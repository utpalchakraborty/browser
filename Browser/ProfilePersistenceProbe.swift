#if DEBUG
import Foundation
import WebKit

@MainActor
final class ProfilePersistenceProbe {
    static let modeArgument = "--profile-persistence-probe"

    struct Configuration {
        let phase: Phase
        let fixtureOrigin: URL
    }

    enum Phase: String {
        case write
        case readDelete = "read-delete"
        case verifyDeleted = "verify-deleted"
    }

    struct Result {
        let phase: Phase
        let succeeded: Bool
        let cookieSurvived: Bool?
        let failureCode: String?
    }

    fileprivate enum Failure: String, Error {
        case loadDidNotStart = "load-did-not-start"
        case navigationAlreadyInProgress = "navigation-already-in-progress"
        case navigationFailed = "navigation-failed"
        case persistentStoreMismatch = "persistent-store-mismatch"
        case ephemeralStoreMismatch = "ephemeral-store-mismatch"
        case cookieStateMismatch = "cookie-state-mismatch"
        case storageStateMismatch = "storage-state-mismatch"
        case missingPersistentCookie = "missing-persistent-cookie"
        case unexpected = "unexpected"
    }

    private static let dataStoreIdentifier = UUID(
        uuidString: "B2396C63-1E67-4783-84A8-F88DFF98C801"
    )!
    private static let storageKey = "phase1-actual-app-profile-probe"
    private static let storageValue = "persisted"
    private static let cookieName = "phase1"
    private static let cookieValue = "persisted"

    private let configuration: Configuration

    init(configuration: Configuration) {
        self.configuration = configuration
    }

    static func isRequested(arguments: [String]) -> Bool {
        arguments.contains(modeArgument)
    }

    static func configuration(arguments: [String]) -> Configuration? {
        guard
            isRequested(arguments: arguments),
            let phaseValue = optionValue(
                after: "--profile-probe-phase",
                arguments: arguments
            ),
            let phase = Phase(rawValue: phaseValue),
            let fixtureValue = optionValue(
                after: "--profile-probe-fixture-origin",
                arguments: arguments
            ),
            let fixtureOrigin = URL(string: fixtureValue),
            fixtureOrigin.scheme == "http",
            let host = fixtureOrigin.host?.lowercased(),
            ["127.0.0.1", "localhost"].contains(host),
            fixtureOrigin.user == nil,
            fixtureOrigin.password == nil,
            fixtureOrigin.query == nil,
            fixtureOrigin.fragment == nil,
            ["", "/"].contains(fixtureOrigin.path)
        else {
            return nil
        }

        return Configuration(
            phase: phase,
            fixtureOrigin: fixtureOrigin
        )
    }

    func run() async -> Result {
        do {
            let cookieSurvived: Bool?
            switch configuration.phase {
            case .write:
                try await writePersistentAndEphemeralState()
                cookieSurvived = nil
            case .readDelete:
                cookieSurvived = try await readStateAndDeletePersistentData()
            case .verifyDeleted:
                try await verifyPersistentDataIsDeleted()
                cookieSurvived = nil
            }
            return Result(
                phase: configuration.phase,
                succeeded: true,
                cookieSurvived: cookieSurvived,
                failureCode: nil
            )
        } catch let failure as Failure {
            return Result(
                phase: configuration.phase,
                succeeded: false,
                cookieSurvived: nil,
                failureCode: failure.rawValue
            )
        } catch {
            return Result(
                phase: configuration.phase,
                succeeded: false,
                cookieSurvived: nil,
                failureCode: Failure.unexpected.rawValue
            )
        }
    }

    static func emit(_ result: Result) {
        var fields = [
            "BROWSER_PROFILE_PROBE",
            "phase=\(result.phase.rawValue)",
            "pid=\(ProcessInfo.processInfo.processIdentifier)",
            "status=\(result.succeeded ? "passed" : "failed")",
        ]
        if let cookieSurvived = result.cookieSurvived {
            fields.append("cookie-survived=\(cookieSurvived)")
        }
        if let failureCode = result.failureCode {
            fields.append("failure=\(failureCode)")
        }
        writeOutput(fields.joined(separator: " "))
    }

    static func emitInvalidConfiguration() {
        writeOutput(
            "BROWSER_PROFILE_PROBE phase=invalid "
                + "pid=\(ProcessInfo.processInfo.processIdentifier) "
                + "status=failed failure=invalid-configuration"
        )
    }

    private func writePersistentAndEphemeralState() async throws {
        let persistentProfile = makePersistentProfile()
        guard
            persistentProfile.websiteDataStore.isPersistent,
            persistentProfile.websiteDataStore.identifier
                == Self.dataStoreIdentifier
        else {
            throw Failure.persistentStoreMismatch
        }
        let persistentData = WebsiteDataController(
            websiteDataStore: persistentProfile.websiteDataStore
        )
        await persistentData.clearAllWebsiteData()

        let persistentWebView = persistentProfile.webViewFactory.makeWebView()
        try await writeFixtureState(in: persistentWebView)
        try await requireFixtureState(
            exists: true,
            in: persistentWebView,
            dataController: persistentData
        )
        let persistentCookies = await persistentData.cookies()
        guard let persistentCookie = persistentCookies.first(where: {
            $0.name == Self.cookieName
                && $0.value == Self.cookieValue
                && $0.expiresDate != nil
        }) else {
            throw Failure.missingPersistentCookie
        }
        await persistentProfile.websiteDataStore.httpCookieStore.setCookie(
            persistentCookie
        )

        let ephemeralDataStore = WKWebsiteDataStore.nonPersistent()
        guard !ephemeralDataStore.isPersistent else {
            throw Failure.ephemeralStoreMismatch
        }
        let ephemeralData = WebsiteDataController(
            websiteDataStore: ephemeralDataStore
        )
        let ephemeralWebView = makeWebView(dataStore: ephemeralDataStore)
        try await writeFixtureState(in: ephemeralWebView)
        try await requireFixtureState(
            exists: true,
            in: ephemeralWebView,
            dataController: ephemeralData
        )

        // Keep both stores alive while WebKit flushes the named store. This is
        // deliberately bounded so a probe cannot hold the app open forever.
        try await Task.sleep(for: .seconds(2))
        _ = persistentWebView
        _ = ephemeralWebView
    }

    private func readStateAndDeletePersistentData() async throws -> Bool {
        let persistentProfile = makePersistentProfile()
        let persistentData = WebsiteDataController(
            websiteDataStore: persistentProfile.websiteDataStore
        )
        var persistentWebView: WKWebView? = persistentProfile.webViewFactory
            .makeWebView()
        try await loadCookieEcho(in: try unwrap(persistentWebView))

        let persistentView = try unwrap(persistentWebView)
        guard try await storageValue(in: persistentView) == Self.storageValue
        else {
            throw Failure.storageStateMismatch
        }
        let cookieSurvived = try await cookieExists(
            in: persistentView,
            dataController: persistentData
        )
        guard cookieSurvived else {
            throw Failure.missingPersistentCookie
        }

        let ephemeralDataStore = WKWebsiteDataStore.nonPersistent()
        var ephemeralWebView: WKWebView? = makeWebView(
            dataStore: ephemeralDataStore
        )
        try await loadCookieEcho(in: try unwrap(ephemeralWebView))
        try await requireFixtureState(
            exists: false,
            in: try unwrap(ephemeralWebView),
            dataController: WebsiteDataController(
                websiteDataStore: ephemeralDataStore
            )
        )

        persistentWebView = nil
        ephemeralWebView = nil
        await persistentData.clearAllWebsiteData()

        let reloadedWebView = persistentProfile.webViewFactory.makeWebView()
        try await loadCookieEcho(in: reloadedWebView)
        try await requireFixtureState(
            exists: false,
            in: reloadedWebView,
            dataController: persistentData
        )
        try await Task.sleep(for: .milliseconds(500))
        _ = reloadedWebView
        return cookieSurvived
    }

    private func verifyPersistentDataIsDeleted() async throws {
        let persistentProfile = makePersistentProfile()
        let persistentData = WebsiteDataController(
            websiteDataStore: persistentProfile.websiteDataStore
        )
        let persistentWebView = persistentProfile.webViewFactory.makeWebView()
        try await loadCookieEcho(in: persistentWebView)
        try await requireFixtureState(
            exists: false,
            in: persistentWebView,
            dataController: persistentData
        )
        await persistentData.clearAllWebsiteData()
    }

    private func writeFixtureState(in webView: WKWebView) async throws {
        try await ProbeNavigationWaiter().load(
            fixtureURL("/cookie/set"),
            in: webView
        )
        let storedValue = try await webView.evaluateJavaScript(
            "localStorage.setItem('\(Self.storageKey)', "
                + "'\(Self.storageValue)'); "
                + "localStorage.getItem('\(Self.storageKey)')"
        ) as? String
        guard storedValue == Self.storageValue else {
            throw Failure.storageStateMismatch
        }
        try await loadCookieEcho(in: webView)
    }

    private func loadCookieEcho(in webView: WKWebView) async throws {
        try await ProbeNavigationWaiter().load(
            fixtureURL("/cookie/echo"),
            in: webView
        )
    }

    private func requireFixtureState(
        exists: Bool,
        in webView: WKWebView,
        dataController: WebsiteDataController
    ) async throws {
        guard try await storageValue(in: webView)
            == (exists ? Self.storageValue : "")
        else {
            throw Failure.storageStateMismatch
        }
        guard try await cookieExists(
            in: webView,
            dataController: dataController
        ) == exists else {
            throw Failure.cookieStateMismatch
        }
    }

    private func cookieExists(
        in webView: WKWebView,
        dataController: WebsiteDataController
    ) async throws -> Bool {
        let body = try await webView.evaluateJavaScript(
            "document.body.textContent"
        ) as? String
        let headerContainsCookie = body?.contains(
            "\(Self.cookieName)=\(Self.cookieValue)"
        ) == true
        let cookies = await dataController.cookies()
        let storeContainsCookie = cookies.contains(where: {
            $0.name == Self.cookieName && $0.value == Self.cookieValue
        })
        guard headerContainsCookie == storeContainsCookie else {
            throw Failure.cookieStateMismatch
        }
        return storeContainsCookie
    }

    private func storageValue(in webView: WKWebView) async throws -> String? {
        try await webView.evaluateJavaScript(
            "localStorage.getItem('\(Self.storageKey)') ?? ''"
        ) as? String
    }

    private func fixtureURL(_ path: String) -> URL {
        URL(string: path, relativeTo: configuration.fixtureOrigin)!.absoluteURL
    }

    private func makePersistentProfile() -> BrowserProfile {
        BrowserProfile(dataStoreIdentifier: Self.dataStoreIdentifier)
    }

    private func makeWebView(dataStore: WKWebsiteDataStore) -> WKWebView {
        WebViewFactory(websiteDataStore: dataStore).makeWebView()
    }

    private func unwrap<T>(_ value: T?) throws -> T {
        guard let value else {
            throw Failure.unexpected
        }
        return value
    }

    private static func optionValue(
        after option: String,
        arguments: [String]
    ) -> String? {
        guard
            let optionIndex = arguments.firstIndex(of: option),
            arguments.indices.contains(optionIndex + 1)
        else {
            return nil
        }
        return arguments[optionIndex + 1]
    }

    private static func writeOutput(_ line: String) {
        guard let data = (line + "\n").data(using: .utf8) else {
            return
        }
        FileHandle.standardOutput.write(data)
    }
}

@MainActor
private final class ProbeNavigationWaiter: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, any Error>?

    func load(_ url: URL, in webView: WKWebView) async throws {
        guard continuation == nil else {
            throw ProfilePersistenceProbe.Failure.navigationAlreadyInProgress
        }

        webView.navigationDelegate = self
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            guard webView.load(URLRequest(url: url)) != nil else {
                finish(
                    with: ProfilePersistenceProbe.Failure.loadDidNotStart,
                    webView: webView
                )
                return
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finish(with: nil, webView: webView)
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: any Error
    ) {
        finish(
            with: ProfilePersistenceProbe.Failure.navigationFailed,
            webView: webView
        )
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: any Error
    ) {
        finish(
            with: ProfilePersistenceProbe.Failure.navigationFailed,
            webView: webView
        )
    }

    private func finish(
        with error: (any Error)?,
        webView: WKWebView
    ) {
        guard let continuation else {
            return
        }
        self.continuation = nil
        webView.navigationDelegate = nil
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }
}
#endif
