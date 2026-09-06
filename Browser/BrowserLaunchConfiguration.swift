import AppKit
import WebKit

/// One policy for startup and persistent state; unit hosts never start app services.
@MainActor
struct BrowserLaunchConfiguration {
    enum Mode: Equatable { case production, backgroundTests, uiTests, performance }

    static let testBundleIdentifier = "com.utpalchakraborty.browser.testhost"
    static let current = BrowserLaunchConfiguration(
        environment: ProcessInfo.processInfo.environment,
        arguments: ProcessInfo.processInfo.arguments,
        isTestBuild: isTestBuild
    )
    private static var isTestBuild: Bool {
#if BROWSER_TEST_HOST
        true
#else
        false
#endif
    }

    let mode: Mode
    let arguments: [String]

    init(environment: [String: String] = [:], arguments: [String] = [], isTestBuild: Bool = false) {
        self.arguments = arguments
        if arguments.contains("--performance-test") {
            mode = .performance
        } else if arguments.contains("--ui-test-profile") {
            mode = .uiTests
        } else if isTestBuild || environment["XCTestConfigurationFilePath"] != nil {
            mode = .backgroundTests
        } else {
            mode = .production
        }
    }

    var isIsolated: Bool { mode != .production }
    var allowsActivation: Bool { startsApplication || arguments.contains("--interactive-test-host") }
    var startsApplication: Bool { mode != .backgroundTests }
    var defaultsSuiteName: String? {
        isIsolated ? Self.testBundleIdentifier + ".preferences" : nil
    }
    var defaults: UserDefaults {
        defaultsSuiteName.map { UserDefaults(suiteName: $0)! } ?? .standard
    }
    var dataStoreIdentifier: UUID {
        switch mode {
        case .production: BrowserProfile.normalDataStoreIdentifier
        case .performance: BrowserProfile.performanceDataStoreIdentifier
        case .backgroundTests, .uiTests: BrowserProfile.testHostDataStoreIdentifier
        }
    }
    var frameAutosaveName: NSWindow.FrameAutosaveName? {
        if mode == .uiTests { return BrowserWindowController.uiTestWindowFrameAutosaveName }
        if isIsolated || arguments.contains("-ApplePersistenceIgnoreState") { return nil }
        return BrowserWindowController.mainWindowFrameAutosaveName
    }
    func bookmarkConfiguration(applicationSupportDirectory: URL) -> BookmarkLaunchConfiguration? {
        guard mode != .backgroundTests, mode != .performance else { return nil }
        let root = applicationSupportDirectory.appendingPathComponent(
            isIsolated ? Self.testBundleIdentifier : "com.utpalchakraborty.browser",
            isDirectory: true
        )
        return BookmarkLaunchConfiguration(
            directoryURL: mode == .uiTests
                ? root.appendingPathComponent("UITests", isDirectory: true) : root,
            resetOnLaunch: mode == .uiTests && arguments.contains("--reset-ui-test-bookmarks")
        )
    }
    func ruleStoreDirectory(applicationSupportDirectory: URL) -> URL? {
        guard isIsolated else { return nil }
        return applicationSupportDirectory.appendingPathComponent(
            Self.testBundleIdentifier + "/ContentRules", isDirectory: true
        )
    }
    func makeContentRuleListStore() -> WKContentRuleListStore {
        guard isIsolated else { return .default() }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        // A failure must never fall back to the production rule store.
        return WKContentRuleListStore(url: ruleStoreDirectory(applicationSupportDirectory: support)!)!
    }
    var contentBlockerStateKey: String {
        mode == .uiTests ? "contentBlocker.uiTests.lastValidRuleSet" : "contentBlocker.lastValidRuleSet"
    }
    var contentBlockerSitePolicyKey: String {
        mode == .uiTests ? "contentBlocker.uiTests.sitePolicy" : "contentBlocker.sitePolicy"
    }
    var shouldResetWebsiteData: Bool {
        mode == .uiTests && arguments.contains("--reset-ui-test-website-data")
    }
    var shouldResetSitePolicy: Bool {
        mode == .uiTests && arguments.contains("--reset-ui-test-content-blocking")
    }
    var artifactResetScope: ContentBlockerArtifactResetScope {
        mode == .uiTests ? .identifierPrefix("browser-ui-test-") : .all
    }
}
