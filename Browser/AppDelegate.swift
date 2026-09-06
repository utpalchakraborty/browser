import AppKit

nonisolated struct BookmarkLaunchConfiguration: Equatable, Sendable {
    let directoryURL: URL
    let resetOnLaunch: Bool
}

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let maximumPerformanceViewCount = 10
    private static let initialWebViewDeferralMilliseconds = 100

    private let launchConfiguration = BrowserLaunchConfiguration.current
    private lazy var profile = BrowserProfile(
        dataStoreIdentifier: launchConfiguration.dataStoreIdentifier
    )
    private var browserWindowController: BrowserWindowController?
    private var contentBlockingCoordinator: ContentBlockingCoordinator?
#if DEBUG
    private var profilePersistenceProbe: ProfilePersistenceProbe?
#endif

    static func main() {
        let application = NSApplication.shared
        if !BrowserLaunchConfiguration.current.allowsActivation {
            application.setActivationPolicy(.prohibited)
        } else {
            installApplicationIcon(on: application)
        }
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) {
            application.run()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard launchConfiguration.startsApplication else {
            NSApp.setActivationPolicy(launchConfiguration.allowsActivation ? .regular : .prohibited)
            return
        }
#if DEBUG
        if startProfilePersistenceProbeIfRequested() {
            return
        }
#endif

        NSApp.setActivationPolicy(.regular)
        NSApp.disableRelaunchOnLogin()

        let contentBlockingCoordinator = Self.makeContentBlockingCoordinator(
            configuration: launchConfiguration
        )
        self.contentBlockingCoordinator = contentBlockingCoordinator

        let presentationState = BrowserPerformanceSignposts.signposter.beginInterval(
            "InitialWindowPresentation"
        )
        let controller = BrowserWindowController(
            searchProvider: BrowserPreferences.searchProvider(),
            frameAutosaveName: launchConfiguration.frameAutosaveName,
            contentBlockingCoordinator: contentBlockingCoordinator
        )
        browserWindowController = controller
        installMainMenu(navigationTarget: controller)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
        let focusState = BrowserPerformanceSignposts.signposter.beginInterval(
            "InitialAddressFieldFocus"
        )
        controller.ensureInitialAddressFieldFocus()
        controller.window?.displayIfNeeded()
        BrowserPerformanceSignposts.signposter.endInterval(
            "InitialAddressFieldFocus",
            focusState
        )
        BrowserPerformanceSignposts.signposter.endInterval(
            "InitialWindowPresentation",
            presentationState
        )

        DispatchQueue.main.async { [weak controller] in
            controller?.ensureInitialAddressFieldFocus()
        }

        DispatchQueue.main.async { [weak controller, launchConfiguration] in
            guard
                let controller,
                let applicationSupportDirectory = FileManager.default.urls(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask
                ).first,
                let configuration = launchConfiguration.bookmarkConfiguration(
                    applicationSupportDirectory: applicationSupportDirectory
                )
            else {
                return
            }
            controller.startBookmarks(
                repository: BookmarkRepository(
                    directoryURL: configuration.directoryURL
                ),
                resetOnLaunch: configuration.resetOnLaunch
            )
        }

        // Keep WebKit's heavier process and data-store setup out of the native
        // chrome's first-frame path. The delay is measured as part of the
        // initial WebView readiness proxy rather than hidden from the budget.
        let deferralState = BrowserPerformanceSignposts.signposter.beginInterval(
            "InitialWebViewDeferral"
        )
        DispatchQueue.main.asyncAfter(
            deadline: .now()
                + .milliseconds(Self.initialWebViewDeferralMilliseconds)
        ) { [weak self, weak controller, weak contentBlockingCoordinator] in
            BrowserPerformanceSignposts.signposter.endInterval(
                "InitialWebViewDeferral",
                deferralState
            )
            guard
                let self,
                let controller,
                let contentBlockingCoordinator,
                self.browserWindowController === controller,
                controller.window?.isVisible == true
            else {
                return
            }
            Task { [weak self, weak controller, weak contentBlockingCoordinator] in
                guard
                    let self,
                    let controller,
                    let contentBlockingCoordinator,
                    self.browserWindowController === controller
                else {
                    return
                }
                let ruleSources = (
                    try? Self.contentBlockerRuleSources(
                        arguments: ProcessInfo.processInfo.arguments
                    )
                ) ?? []
                await contentBlockingCoordinator.prepare(
                    currentSources: ruleSources
                )
                guard
                    self.browserWindowController === controller,
                    controller.window?.isVisible == true
                else {
                    return
                }
                // Preserve the approved first-frame path: opening the named
                // WebKit store happens only after blocker preparation. The
                // privacy controller is still installed before the readiness
                // check so website-data controls remain usable if preparation
                // fails closed.
                let profile = self.profile
                let websiteDataController = WebsiteDataController(
                    websiteDataStore: profile.websiteDataStore
                )
                if self.launchConfiguration.shouldResetWebsiteData {
                    await websiteDataController.clearAllWebsiteData()
                    guard
                        self.browserWindowController === controller,
                        controller.window?.isVisible == true
                    else {
                        return
                    }
                }
                controller.startWebsiteDataManagement(
                    controller: websiteDataController
                )
                controller.contentBlockingPreparationDidFinish()
                guard contentBlockingCoordinator.isReady else {
                    controller.contentBlockingPreparationDidFail()
                    return
                }
                controller.startWebViews(
                    profile: profile,
                    viewCount: Self.performanceViewCount(
                        arguments: ProcessInfo.processInfo.arguments
                    ),
                    initialURL: Self.performanceFixtureURL(
                        arguments: ProcessInfo.processInfo.arguments
                    ) ?? URL(string: "about:blank")!
                )
                DispatchQueue.main.async { [weak self, weak controller] in
                    guard self?.browserWindowController === controller else {
                        return
                    }
                    controller?.ensureInitialAddressFieldFocus()
                }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        launchConfiguration.startsApplication
    }

    func applicationShouldSaveApplicationState(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldRestoreApplicationState(_ sender: NSApplication) -> Bool {
        false
    }

    private static func installApplicationIcon(on application: NSApplication) {
        guard
            let iconURL = Bundle.main.url(
                forResource: "AppIcon",
                withExtension: "icns"
            ),
            let icon = NSImage(contentsOf: iconURL)
        else {
            return
        }

        application.applicationIconImage = icon
    }

    static func windowFrameAutosaveName(
        arguments: [String]
    ) -> NSWindow.FrameAutosaveName? {
        BrowserLaunchConfiguration(arguments: arguments).frameAutosaveName
    }

    static func bookmarkLaunchConfiguration(
        arguments: [String],
        applicationSupportDirectory: URL
    ) -> BookmarkLaunchConfiguration? {
        BrowserLaunchConfiguration(arguments: arguments)
            .bookmarkConfiguration(applicationSupportDirectory: applicationSupportDirectory)
    }

    static func performanceViewCount(arguments: [String]) -> Int {
        guard
            arguments.contains("--performance-test"),
            let optionIndex = arguments.firstIndex(
                of: "--performance-view-count"
            ),
            arguments.indices.contains(optionIndex + 1),
            let count = Int(arguments[optionIndex + 1]),
            (1...maximumPerformanceViewCount).contains(count)
        else {
            return 1
        }
        return count
    }

    static func performanceFixtureURL(arguments: [String]) -> URL? {
        guard
            arguments.contains("--performance-test"),
            let optionIndex = arguments.firstIndex(
                of: "--performance-fixture-url"
            ),
            arguments.indices.contains(optionIndex + 1),
            let url = URL(string: arguments[optionIndex + 1]),
            url.scheme == "http",
            let host = url.host?.lowercased(),
            ["127.0.0.1", "localhost"].contains(host),
            url.user == nil,
            url.password == nil
        else {
            return nil
        }
        return url
    }

    static func contentBlockerRuleSources(
        arguments: [String],
        bundle: Bundle = .main
    ) throws -> [ContentBlockerRuleSource] {
        if arguments.contains("--ui-test-profile") {
            let namespace = "browser-ui-test-content-blocking-v1"
            let rules = try ContentBlockerService.probeRules(
                blockedURLFilter: ".*/privacy/blocked[.]js",
                exceptionTopURLFilters: []
            )
            return [
                ContentBlockerRuleSource(
                    namespace: namespace,
                    identifier: ContentBlockerService.versionedIdentifier(
                        namespace: namespace,
                        encodedRules: rules
                    ),
                    encodedRulesLoader: { rules }
                )
            ]
        }
        return try ContentBlockerBundle.loadProductionPackage(
            from: bundle
        ).ruleSources
    }

    static func contentBlockerStateKey(arguments: [String]) -> String {
        BrowserLaunchConfiguration(arguments: arguments).contentBlockerStateKey
    }

    static func contentBlockerSitePolicyKey(arguments: [String]) -> String {
        BrowserLaunchConfiguration(arguments: arguments).contentBlockerSitePolicyKey
    }

    static func shouldResetWebsiteData(arguments: [String]) -> Bool {
        BrowserLaunchConfiguration(arguments: arguments).shouldResetWebsiteData
    }

    static func contentBlockerArtifactResetScope(arguments: [String]) -> ContentBlockerArtifactResetScope {
        BrowserLaunchConfiguration(arguments: arguments).artifactResetScope
    }

    private static func makeContentBlockingCoordinator(
        configuration: BrowserLaunchConfiguration
    ) -> ContentBlockingCoordinator {
        let stateStore = ContentBlockerStateStore(
            defaults: configuration.defaults,
            key: configuration.contentBlockerStateKey
        )
        let sitePolicyStore = ContentBlockerSitePolicyStore(
            defaults: configuration.defaults,
            key: configuration.contentBlockerSitePolicyKey
        )
        if configuration.shouldResetSitePolicy { sitePolicyStore.reset() }
        return ContentBlockingCoordinator(
            resolver: ContentBlockerRuleSetResolver(
                service: ContentBlockerService(ruleStore: configuration.makeContentRuleListStore()),
                stateStore: stateStore,
                artifactResetScope: configuration.artifactResetScope
            ),
            sitePolicyStore: sitePolicyStore
        )
    }

#if DEBUG
    private func startProfilePersistenceProbeIfRequested() -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard ProfilePersistenceProbe.isRequested(arguments: arguments) else {
            return false
        }
        guard let configuration = ProfilePersistenceProbe.configuration(
            arguments: arguments
        ) else {
            ProfilePersistenceProbe.emitInvalidConfiguration()
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
            return true
        }

        let probe = ProfilePersistenceProbe(configuration: configuration)
        profilePersistenceProbe = probe
        Task { [weak self, probe] in
            let result = await probe.run()
            ProfilePersistenceProbe.emit(result)
            self?.profilePersistenceProbe = nil
            NSApp.terminate(nil)
        }
        return true
    }
#endif

    private func installMainMenu(navigationTarget: BrowserWindowController) {
        let mainMenu = NSMenu()

        let applicationMenu = NSMenu(title: "Browser")
        applicationMenu.addItem(
            withTitle: "About Browser",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(
            withTitle: "Hide Browser",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        let hideOthers = applicationMenu.addItem(
            withTitle: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        applicationMenu.addItem(
            withTitle: "Show All",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(
            withTitle: "Quit Browser",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        addMenu(applicationMenu, to: mainMenu)

        let fileMenu = NSMenu(title: "File")
        let newTabItem = fileMenu.addItem(
            withTitle: "New Tab",
            action: #selector(BrowserWindowController.newTab(_:)),
            keyEquivalent: "t"
        )
        newTabItem.target = navigationTarget
        let closeTabItem = fileMenu.addItem(
            withTitle: "Close Tab",
            action: #selector(BrowserWindowController.closeSelectedTab(_:)),
            keyEquivalent: "w"
        )
        closeTabItem.target = navigationTarget
        fileMenu.addItem(.separator())
        let closeWindowItem = fileMenu.addItem(
            withTitle: "Close Window",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        closeWindowItem.keyEquivalentModifierMask = [.command, .shift]
        addMenu(fileMenu, to: mainMenu)

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(
            withTitle: "Undo",
            action: Selector(("undo:")),
            keyEquivalent: "z"
        )
        let redoItem = editMenu.addItem(
            withTitle: "Redo",
            action: Selector(("redo:")),
            keyEquivalent: "z"
        )
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(
            withTitle: "Cut",
            action: #selector(NSText.cut(_:)),
            keyEquivalent: "x"
        )
        editMenu.addItem(
            withTitle: "Copy",
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c"
        )
        editMenu.addItem(
            withTitle: "Paste",
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v"
        )
        editMenu.addItem(
            withTitle: "Select All",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )
        addMenu(editMenu, to: mainMenu)

        let viewMenu = NSMenu(title: "View")
        let zoomInItem = viewMenu.addItem(
            withTitle: "Zoom In",
            action: #selector(BrowserWindowController.zoomIn(_:)),
            keyEquivalent: "+"
        )
        zoomInItem.target = navigationTarget
        let zoomOutItem = viewMenu.addItem(
            withTitle: "Zoom Out",
            action: #selector(BrowserWindowController.zoomOut(_:)),
            keyEquivalent: "-"
        )
        zoomOutItem.target = navigationTarget
        let actualSizeItem = viewMenu.addItem(
            withTitle: "Actual Size",
            action: #selector(BrowserWindowController.resetPageZoom(_:)),
            keyEquivalent: "0"
        )
        actualSizeItem.target = navigationTarget
        addMenu(viewMenu, to: mainMenu)

        let navigationMenu = NSMenu(title: "Navigate")
        let openLocationItem = navigationMenu.addItem(
            withTitle: "Open Location",
            action: #selector(BrowserWindowController.focusAddressField(_:)),
            keyEquivalent: "l"
        )
        openLocationItem.target = navigationTarget
        navigationMenu.addItem(.separator())
        let backItem = navigationMenu.addItem(
            withTitle: "Back",
            action: #selector(BrowserWindowController.goBack(_:)),
            keyEquivalent: "["
        )
        backItem.target = navigationTarget
        let forwardItem = navigationMenu.addItem(
            withTitle: "Forward",
            action: #selector(BrowserWindowController.goForward(_:)),
            keyEquivalent: "]"
        )
        forwardItem.target = navigationTarget
        navigationMenu.addItem(.separator())
        let reloadItem = navigationMenu.addItem(
            withTitle: "Reload Page",
            action: #selector(BrowserWindowController.reloadPage(_:)),
            keyEquivalent: "r"
        )
        reloadItem.target = navigationTarget
        let stopItem = navigationMenu.addItem(
            withTitle: "Stop Loading",
            action: #selector(BrowserWindowController.stopLoading(_:)),
            keyEquivalent: "."
        )
        stopItem.target = navigationTarget

        let searchProviderItem = NSMenuItem(title: "Search Provider", action: nil, keyEquivalent: "")
        let searchProviderMenu = NSMenu(title: "Search Provider")
        for provider in SearchProvider.allCases {
            let item = searchProviderMenu.addItem(
                withTitle: provider.displayName,
                action: #selector(BrowserWindowController.selectSearchProvider(_:)),
                keyEquivalent: ""
            )
            item.representedObject = provider.rawValue
            item.target = navigationTarget
        }
        searchProviderItem.submenu = searchProviderMenu
        navigationMenu.addItem(.separator())
        navigationMenu.addItem(searchProviderItem)
        addMenu(navigationMenu, to: mainMenu)

        let bookmarksMenu = NSMenu(title: "Bookmarks")
        let addBookmarkItem = bookmarksMenu.addItem(
            withTitle: "Add Bookmark…",
            action: #selector(BrowserWindowController.bookmarkCurrentPage(_:)),
            keyEquivalent: "d"
        )
        addBookmarkItem.target = navigationTarget
        let showBookmarksItem = bookmarksMenu.addItem(
            withTitle: "Show Bookmarks",
            action: #selector(BrowserWindowController.showBookmarks(_:)),
            keyEquivalent: "b"
        )
        showBookmarksItem.keyEquivalentModifierMask = [.command, .option]
        showBookmarksItem.target = navigationTarget
        addMenu(bookmarksMenu, to: mainMenu)

        let privacyMenu = NSMenu(title: "Privacy")
        let manageWebsiteDataItem = privacyMenu.addItem(
            withTitle: "Manage Website Data…",
            action: #selector(BrowserWindowController.showWebsiteData(_:)),
            keyEquivalent: "y"
        )
        manageWebsiteDataItem.keyEquivalentModifierMask = [.command, .option]
        manageWebsiteDataItem.target = navigationTarget
        privacyMenu.addItem(.separator())
        let blockingStatusItem = privacyMenu.addItem(
            withTitle: "Ad & Tracker Blocking: Preparing…",
            action: #selector(BrowserWindowController.contentBlockingStatus(_:)),
            keyEquivalent: ""
        )
        blockingStatusItem.target = navigationTarget
        privacyMenu.addItem(.separator())
        let siteBlockingItem = privacyMenu.addItem(
            withTitle: "Blocking Is Not Ready",
            action: #selector(
                BrowserWindowController
                    .toggleContentBlockingForCurrentSiteAndReload(_:)
            ),
            keyEquivalent: "p"
        )
        siteBlockingItem.keyEquivalentModifierMask = [.command, .option]
        siteBlockingItem.target = navigationTarget
        addMenu(privacyMenu, to: mainMenu)

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(
            withTitle: "Minimize",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )
        windowMenu.addItem(
            withTitle: "Zoom",
            action: #selector(NSWindow.performZoom(_:)),
            keyEquivalent: ""
        )
        addMenu(windowMenu, to: mainMenu)
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    private func addMenu(_ menu: NSMenu, to mainMenu: NSMenu) {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        mainMenu.addItem(item)
    }
}
