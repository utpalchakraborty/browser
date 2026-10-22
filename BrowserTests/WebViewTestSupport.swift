import AppKit
import Foundation
import WebKit
@testable import Browser

enum WebViewTestError: Error {
    case loadDidNotStart
    case navigationAlreadyInProgress
}

@MainActor
final class WebViewNavigationWaiter: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, any Error>?
    private let credential: URLCredential?

    private(set) var authenticationChallengeCount = 0

    init(credential: URLCredential? = nil) {
        self.credential = credential
    }

    func load(_ url: URL, in webView: WKWebView) async throws {
        guard continuation == nil else {
            throw WebViewTestError.navigationAlreadyInProgress
        }

        webView.navigationDelegate = self
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            guard webView.load(URLRequest(url: url)) != nil else {
                finish(with: WebViewTestError.loadDidNotStart, webView: webView)
                return
            }
        }
    }

    func reload(_ webView: WKWebView) async throws {
        guard continuation == nil else {
            throw WebViewTestError.navigationAlreadyInProgress
        }

        webView.navigationDelegate = self
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            guard webView.reload() != nil else {
                finish(with: WebViewTestError.loadDidNotStart, webView: webView)
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
        finish(with: error, webView: webView)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: any Error
    ) {
        finish(with: error, webView: webView)
    }

    func webView(
        _ webView: WKWebView,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @MainActor (
            URLSession.AuthChallengeDisposition,
            URLCredential?
        ) -> Void
    ) {
        authenticationChallengeCount += 1
        if let credential,
           challenge.protectionSpace.authenticationMethod
               == NSURLAuthenticationMethodHTTPBasic
        {
            completionHandler(.useCredential, credential)
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    private func finish(with error: (any Error)?, webView: WKWebView) {
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

@MainActor
final class PopupProbe: NSObject, WKUIDelegate, WKNavigationDelegate {
    var onCreate: ((WKNavigationAction, WKWebView) -> Void)?
    var onFinish: ((WKWebView) -> Void)?
    private(set) var popupWebView: WKWebView?

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        let popup = WKWebView(frame: .zero, configuration: configuration)
        popup.navigationDelegate = self
        popupWebView = popup
        onCreate?(navigationAction, popup)
        return popup
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onFinish?(webView)
    }
}

@MainActor
final class DownloadProbe: NSObject, WKNavigationDelegate, WKDownloadDelegate {
    var onDownloadCreated: ((WKDownload) -> Void)?
    var onDestinationRequested: ((URLResponse, String) -> Void)?
    private(set) var download: WKDownload?

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void
    ) {
        decisionHandler(
            navigationResponse.canShowMIMEType ? .allow : .download
        )
    }

    func webView(
        _ webView: WKWebView,
        navigationResponse: WKNavigationResponse,
        didBecome download: WKDownload
    ) {
        self.download = download
        download.delegate = self
        onDownloadCreated?(download)
    }

    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping @MainActor (URL?) -> Void
    ) {
        onDestinationRequested?(response, suggestedFilename)
        completionHandler(nil)
    }
}

enum Phase1Fixture {
    static let origin = URL(string: "http://127.0.0.1:18765")!

    static func url(_ path: String) -> URL {
        URL(string: path, relativeTo: origin)!
    }
}

/// Polls on the main actor; WebKit delivers state through KVO and async callbacks.
@MainActor
func waitForWebKit(
    timeout: TimeInterval = 10,
    _ condition: () -> Bool
) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition(), Date() < deadline {
        try await Task.sleep(for: .milliseconds(20))
    }
    if !condition() { throw WebViewTestError.loadDidNotStart }
}

/// A hidden browser window with a prepared, isolated content-blocking
/// coordinator, rule store, and preferences suite.
@MainActor
struct HiddenBlockingBrowser {
    let controller: BrowserWindowController
    let coordinator: ContentBlockingCoordinator
    let defaults: UserDefaults
    private let suite: String
    private let ruleDirectory: URL

    var tab: TabController? {
        controller.webView?.navigationDelegate as? TabController
    }

    static func make(
        initialURL: URL,
        keyWindow: @escaping () -> NSWindow? = { nil }
    ) async throws -> HiddenBlockingBrowser {
        let ruleDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HiddenBlockingBrowser.\(UUID())")
        let suite = "HiddenBlockingBrowser.\(UUID())"
        guard
            let store = WKContentRuleListStore(url: ruleDirectory),
            let defaults = UserDefaults(suiteName: suite)
        else {
            throw WebViewTestError.loadDidNotStart
        }
        let rules = try ContentBlockerService.probeRules(
            blockedURLFilter: ".*/privacy/blocked[.]js", exceptionTopURLFilters: []
        )
        let namespace = "browser-hidden-fixture-\(UUID())"
        let coordinator = ContentBlockingCoordinator(
            resolver: ContentBlockerRuleSetResolver(
                service: ContentBlockerService(ruleStore: store),
                stateStore: ContentBlockerStateStore(defaults: defaults)
            ),
            sitePolicyStore: ContentBlockerSitePolicyStore(defaults: defaults)
        )
        await coordinator.prepare(currentSources: [
            ContentBlockerRuleSource(
                namespace: namespace,
                identifier: ContentBlockerService.versionedIdentifier(
                    namespace: namespace, encodedRules: rules
                ),
                encodedRulesLoader: { rules }
            )
        ])
        let controller = BrowserWindowController(
            contentBlockingCoordinator: coordinator,
            preferences: defaults,
            keyWindow: keyWindow
        )
        controller.installWebViews(
            profile: BrowserProfile(dataStoreIdentifier: UUID()),
            viewCount: 1,
            initialURL: initialURL
        )
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        return HiddenBlockingBrowser(
            controller: controller,
            coordinator: coordinator,
            defaults: defaults,
            suite: suite,
            ruleDirectory: ruleDirectory
        )
    }

    func waitForIdlePage(_ url: URL) async throws {
        try await waitForWebKit {
            tab?.committedURL == url.absoluteURL
                && controller.webView?.isLoading == false
                && tab?.hasActiveNavigation == false
        }
    }

    func cleanUp() {
        controller.window?.close()
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: ruleDirectory)
    }
}
