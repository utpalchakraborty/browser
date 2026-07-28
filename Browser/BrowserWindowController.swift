import AppKit
import os
import WebKit

enum BrowserPerformanceSignposts {
    static let subsystem = "com.utpalchakraborty.browser"
    static let category = OSLog.Category.pointsOfInterest
    static let signposter = OSSignposter(
        subsystem: subsystem,
        category: category
    )
}

@MainActor
final class BrowserWindowController: NSWindowController,
    NSMenuItemValidation,
    NSWindowDelegate,
    NSTextFieldDelegate
{
    static let mainWindowFrameAutosaveName: NSWindow.FrameAutosaveName =
        "BrowserMainWindow"
    static let uiTestWindowFrameAutosaveName: NSWindow.FrameAutosaveName =
        "BrowserMainWindow.UITests"

    private let tabManager: TabManager
    private var profile: BrowserProfile?
    var webViews: [WKWebView] { tabManager.residentWebViews }
    var webView: WKWebView? { tabManager.selectedTab.webView }
    var tabCount: Int { tabManager.tabs.count }
    var tabIDs: [UUID] { tabManager.tabs.map(\.id) }
    var selectedTabID: UUID { tabManager.selectedTabID }

    private let chromeView: BrowserChromeView
    private let contentBlockingCoordinator: ContentBlockingCoordinator?
    private var addressInterpreter: AddressInterpreter
    private var searchProvider: SearchProvider
    private var bookmarkCoordinator: BookmarkCoordinator?
    private var bookmarkManagerWindowController: BookmarkManagerWindowController?
    private var bookmarkEditorSheetController: BookmarkEditorSheetController?
    private var websiteDataController: WebsiteDataController?
    private var websiteDataPrivacyWindowController:
        WebsiteDataPrivacyWindowController?
    private var compiledBlockerResetTask: Task<Void, Never>?
    private var compiledBlockerArtifactsWereReset = false

    private var isEditingAddress = false
    private var renderedTabPresentations: [BrowserTabPresentation] = []

    init(
        searchProvider: SearchProvider = .defaultProvider,
        frameAutosaveName: NSWindow.FrameAutosaveName? = nil,
        contentBlockingCoordinator: ContentBlockingCoordinator? = nil
    ) {
        self.searchProvider = searchProvider
        self.contentBlockingCoordinator = contentBlockingCoordinator
        let initialTab = TabController(
            contentBlockingCoordinator: contentBlockingCoordinator
        )
        tabManager = TabManager(initialTab: initialTab)
        addressInterpreter = AddressInterpreter(searchProvider: searchProvider)
        chromeView = BrowserChromeView(searchProviderName: searchProvider.displayName)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_100, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Browser"
        window.center()
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.contentMinSize = NSSize(width: 460, height: 300)
        window.backgroundColor = .windowBackgroundColor
        Self.setAccessibilityIdentifier("BrowserMainWindow", on: window)
        window.contentView = chromeView

        super.init(window: window)

        if let frameAutosaveName {
            windowFrameAutosaveName = frameAutosaveName
            _ = window.setFrameUsingName(frameAutosaveName)
            _ = window.setFrameAutosaveName(frameAutosaveName)
        }

        window.delegate = self
        chromeView.addressField.delegate = self
        chromeView.addressField.target = self
        chromeView.addressField.action = #selector(submitAddress(_:))
        chromeView.addressField.onCommandReturn = { [weak self] input in
            self?.submitAddress(input, intent: .completeDotCom)
        }

        chromeView.backButton.target = self
        chromeView.backButton.action = #selector(goBack(_:))
        chromeView.forwardButton.target = self
        chromeView.forwardButton.action = #selector(goForward(_:))
        chromeView.reloadStopButton.target = self
        chromeView.reloadStopButton.action = #selector(reloadOrStop(_:))
        chromeView.bookmarkButton.target = self
        chromeView.bookmarkButton.action = #selector(bookmarkCurrentPage(_:))
        chromeView.errorView.retryButton.target = self
        chromeView.errorView.retryButton.action = #selector(retryNavigation(_:))
        chromeView.tabStrip.onNewTab = { [weak self] in
            self?.newTab(nil)
        }
        chromeView.tabStrip.onSelectTab = { [weak self] id in
            self?.selectTab(id: id)
        }
        chromeView.tabStrip.onCloseTab = { [weak self] id in
            self?.closeTab(id: id)
        }
        window.initialFirstResponder = chromeView.addressField

        configureTab(initialTab)
        renderTabs()
        renderNavigationState()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func startWebView(profile: BrowserProfile) {
        startWebViews(
            profile: profile,
            viewCount: 1,
            initialURL: URL(string: "about:blank")!
        )
    }

    func startWebViews(
        profile: BrowserProfile,
        viewCount: Int,
        initialURL: URL
    ) {
        guard self.profile == nil, window?.isVisible == true else {
            return
        }
        self.profile = profile

        for tab in tabManager.tabs {
            tab.installWebViewFactory(profile.webViewFactory)
        }

        let requestedInitialURL = tabManager.selectedTab.pendingNavigationURL
            ?? initialURL
        guard tabManager.selectedTab.realizeInitialWebView(
            for: requestedInitialURL
        ) else {
            contentBlockingPreparationDidFail()
            renderSelectedTab()
            return
        }
        let initialLoadStarted = tabManager.selectedTab.loadInitial(
            URLRequest(url: requestedInitialURL),
            measureFirstBlankNavigation: true
        )
        guard initialLoadStarted else {
            contentBlockingPreparationDidFail()
            renderSelectedTab()
            return
        }

        let selectedTab = tabManager.selectedTab
        let existingBackgroundTabs = tabManager.tabs.filter {
            $0 !== selectedTab
        }
        for tab in existingBackgroundTabs {
            guard
                let pendingURL = tab.pendingNavigationURL,
                pendingURL.absoluteString != "about:blank"
            else {
                continue
            }
            _ = tab.loadInBackground(URLRequest(url: pendingURL))
        }

        let requestedViewCount = max(1, viewCount)
        if tabManager.tabs.count < requestedViewCount {
            for _ in tabManager.tabs.count..<requestedViewCount {
                let backgroundTab = makeTab()
                tabManager.append(backgroundTab, select: false)
                _ = backgroundTab.loadInBackground(
                    URLRequest(url: requestedInitialURL)
                )
            }
        }

        renderTabs()
        renderSelectedTab()
    }

    func contentBlockingPreparationDidFail() {
        presentContentBlockingUnavailable()
        updatePrivacyBlockingResetState(
            isBusy: false,
            statusMessage: "Blocking rules are unavailable. Website-data controls remain available."
        )
    }

    func contentBlockingPreparationDidFinish() {
        updatePrivacyBlockingResetState(
            isBusy: false,
            statusMessage: nil
        )
    }

    func startBookmarks(
        repository: BookmarkRepository,
        resetOnLaunch: Bool = false
    ) {
        guard bookmarkCoordinator == nil else {
            return
        }

        let coordinator = BookmarkCoordinator(repository: repository)
        coordinator.onStateChange = { [weak self] state in
            self?.bookmarkStateDidChange(state)
        }
        bookmarkCoordinator = coordinator
        renderBookmarkState()
        coordinator.start(resetOnLaunch: resetOnLaunch)
    }

    func startWebsiteDataManagement(
        controller: WebsiteDataController
    ) {
        guard websiteDataController == nil else {
            return
        }
        websiteDataController = controller
    }

    var currentBookmarkPageCandidate: BookmarkPageCandidate? {
        BookmarkPageCandidate.currentPage(
            url: tabManager.selectedTab.observedURL,
            title: tabManager.selectedTab.observedTitle,
            isLoading: tabManager.selectedTab.observedIsLoading,
            hasVisibleError: tabManager.selectedTab.hasVisibleError
        )
    }

    func openBookmark(_ url: URL) {
        guard let canonicalURL = try? Bookmark.canonicalURL(for: url) else {
            NSSound.beep()
            return
        }
        navigate(to: canonicalURL)
    }

    @objc
    func focusAddressField(_ sender: Any? = nil) {
        guard let window else {
            return
        }
        window.makeFirstResponder(chromeView.addressField)
        chromeView.addressField.currentEditor()?.selectAll(nil)
    }

    func ensureInitialAddressFieldFocus() {
        guard let window else {
            return
        }
        if let editor = chromeView.addressField.currentEditor(),
           window.firstResponder === editor
        {
            return
        }
        window.makeFirstResponder(chromeView.addressField)
    }

    @objc
    func newTab(_ sender: Any?) {
        BrowserPerformanceSignposts.signposter.withIntervalSignpost(
            "TabCreation"
        ) {
            let tab = makeTab()
            tabManager.append(tab, select: true)
            prepareForSelectedTabChange()
            attachSelectedWebView()
            renderTabs()
            renderSelectedTab()
            focusAddressField()
        }
    }

    @objc
    func closeSelectedTab(_ sender: Any?) {
        closeTab(id: tabManager.selectedTabID)
    }

    func selectTab(id: UUID) {
        guard tabManager.tab(id: id) != nil else {
            return
        }
        guard id != tabManager.selectedTabID else {
            renderTabs()
            return
        }
        BrowserPerformanceSignposts.signposter.withIntervalSignpost(
            "TabSelection"
        ) {
            _ = tabManager.select(id: id)
            prepareForSelectedTabChange()
            attachSelectedWebView()
            renderTabs()
            renderSelectedTab()
            focusSelectedTabContent()
        }
    }

    private func closeTab(id: UUID) {
        if tabManager.tabs.count == 1 {
            guard id == tabManager.selectedTabID else {
                return
            }
            let replacement = makeTab()
            let removed = tabManager.replaceSoleTab(with: replacement)
            removed.close()
            prepareForSelectedTabChange()
            attachSelectedWebView()
            renderTabs()
            renderSelectedTab()
            focusAddressField()
            return
        }

        let selectionChanged = id == tabManager.selectedTabID
        guard let removed = tabManager.remove(id: id) else {
            return
        }
        removed.close()
        if selectionChanged {
            prepareForSelectedTabChange()
            attachSelectedWebView()
        }
        renderTabs()
        renderSelectedTab()
        if selectionChanged {
            focusSelectedTabContent()
        }
    }

    private func makeTab() -> TabController {
        let tab = TabController(
            contentBlockingCoordinator: contentBlockingCoordinator
        )
        configureTab(tab)
        if let profile {
            tab.installWebViewFactory(profile.webViewFactory)
        }
        return tab
    }

    private func configureTab(_ tab: TabController) {
        tab.onStateChange = { [weak self, weak tab] changedTab in
            guard let self, let tab, changedTab === tab else {
                return
            }
            tabStateDidChange(tab)
        }
        tab.onOpenTab = { [weak self] request, disposition in
            self?.openTab(request: request, disposition: disposition)
        }
    }

    private func openTab(
        request: URLRequest,
        disposition: NewTabNavigationDisposition
    ) {
        guard
            disposition == .foregroundTab
                || disposition == .backgroundTab,
            let url = request.url,
            ["http", "https"].contains(url.scheme?.lowercased() ?? "")
        else {
            return
        }

        let selectsNewTab = disposition == .foregroundTab
        let tab = makeTab()
        tabManager.append(tab, select: selectsNewTab)
        _ = tab.loadInBackground(request)
        if selectsNewTab {
            attachSelectedWebView()
            renderSelectedTab()
            focusSelectedTabContent()
        }
        renderTabs()
    }

    private func tabStateDidChange(_ tab: TabController) {
        renderTabs()
        guard tab.id == tabManager.selectedTabID else {
            return
        }
        attachSelectedWebView()
        renderSelectedTab()
    }

    private func attachSelectedWebView() {
        let selectedTab = tabManager.selectedTab
        for tab in tabManager.tabs {
            let isSelected = tab === selectedTab
            tab.setSelectedAccessibility(isSelected)
            guard let residentView = tab.webView else {
                continue
            }
            if isSelected {
                if residentView.superview !== chromeView.pageContainer {
                    chromeView.pageContainer.addSubview(
                        residentView,
                        positioned: .below,
                        relativeTo: chromeView.errorView
                    )
                    NSLayoutConstraint.activate([
                        residentView.topAnchor.constraint(
                            equalTo: chromeView.pageContainer.topAnchor
                        ),
                        residentView.leadingAnchor.constraint(
                            equalTo: chromeView.pageContainer.leadingAnchor
                        ),
                        residentView.trailingAnchor.constraint(
                            equalTo: chromeView.pageContainer.trailingAnchor
                        ),
                        residentView.bottomAnchor.constraint(
                            equalTo: chromeView.pageContainer.bottomAnchor
                        ),
                    ])
                }
            } else if residentView.superview != nil {
                residentView.removeFromSuperview()
            }
        }
    }

    private func focusSelectedTabContent() {
        if let webView = tabManager.selectedTab.webView {
            window?.makeFirstResponder(webView)
        } else {
            focusAddressField()
        }
    }

    private func prepareForSelectedTabChange() {
        isEditingAddress = false
    }

    private func renderTabs() {
        let presentations = tabManager.presentations
        guard presentations != renderedTabPresentations else {
            return
        }
        renderedTabPresentations = presentations
        chromeView.tabStrip.update(presentations)
    }

    @objc
    func submitAddress(_ sender: Any?) {
        submitAddress(
            chromeView.addressField.stringValue,
            intent: .standard
        )
    }

    private func submitAddress(
        _ input: String,
        intent: AddressSubmissionIntent
    ) {
        switch addressInterpreter.interpret(
            input,
            intent: intent
        ) {
        case let .navigate(url):
            navigate(to: url)
        case let .failure(error):
            presentAddressError(error)
            focusAddressField()
        }
    }

    @objc
    func goBack(_ sender: Any?) {
        let tab = tabManager.selectedTab
        guard let webView = tab.webView, webView.canGoBack else {
            return
        }
        tab.goBack()
        window?.makeFirstResponder(webView)
    }

    @objc
    func goForward(_ sender: Any?) {
        let tab = tabManager.selectedTab
        guard let webView = tab.webView, webView.canGoForward else {
            return
        }
        tab.goForward()
        window?.makeFirstResponder(webView)
    }

    @objc
    func reloadOrStop(_ sender: Any?) {
        if tabManager.selectedTab.observedIsLoading {
            stopLoading(sender)
        } else {
            reloadPage(sender)
        }
    }

    @objc
    func reloadPage(_ sender: Any?) {
        let tab = tabManager.selectedTab
        guard let webView = tab.webView, !webView.isLoading else {
            return
        }
        tab.reload()
        window?.makeFirstResponder(webView)
    }

    @objc
    func stopLoading(_ sender: Any?) {
        let tab = tabManager.selectedTab
        guard let webView = tab.webView, webView.isLoading else {
            return
        }
        tab.stopLoading()
    }

    @objc
    func retryNavigation(_ sender: Any?) {
        let tab = tabManager.selectedTab
        if tab.retryURL != nil || tab.webView?.url != nil {
            tab.retry()
            if let webView = tab.webView {
                window?.makeFirstResponder(webView)
            }
        } else {
            focusAddressField()
        }
    }

    @objc
    func bookmarkCurrentPage(_ sender: Any?) {
        guard
            let coordinator = bookmarkCoordinator,
            coordinator.allowsChanges,
            let candidate = currentBookmarkPageCandidate
        else {
            NSSound.beep()
            return
        }

        if let existing = bookmarkedCurrentPage {
            presentBookmarkEditor(editing: existing)
        } else {
            presentBookmarkEditor(adding: candidate)
        }
    }

    @objc
    func showBookmarks(_ sender: Any?) {
        guard bookmarkCoordinator != nil else {
            return
        }
        let manager = bookmarkManager()
        renderBookmarkManager()
        manager.showWindow(sender)
    }

    @objc
    func showWebsiteData(_ sender: Any?) {
        guard websiteDataController != nil else {
            NSSound.beep()
            return
        }
        let manager = websiteDataPrivacyManager()
        let blockingStatusMessage: String?
        switch contentBlockingCoordinator?.availability {
        case .unavailable, nil:
            blockingStatusMessage = "Blocking rules are unavailable. Website-data controls remain available."
        case .preparing:
            blockingStatusMessage = "Blocking rules are still preparing. Website-data controls remain available."
        case .active, .activeLastValidRules:
            blockingStatusMessage = nil
        }
        updatePrivacyBlockingResetState(
            isBusy: compiledBlockerResetTask != nil
                || contentBlockingCoordinator?.availability == .preparing,
            statusMessage: blockingStatusMessage
        )
        manager.showWindow(sender)
    }

    @objc
    func contentBlockingStatus(_ sender: Any?) {}

    @objc
    func toggleContentBlockingForCurrentSiteAndReload(_ sender: Any?) {
        let tab = tabManager.selectedTab
        guard
            let contentBlockingCoordinator,
            tab.webView != nil,
            !tab.hasActiveNavigation,
            let url = tab.committedURL,
            let site = ContentBlockerSite(url: url)
        else {
            NSSound.beep()
            return
        }
        let hasAffectedActiveTab = tabManager.tabs.contains {
            $0.hasActiveNavigation
                && contentBlockingURL(in: $0, matching: site) != nil
        }
        guard !hasAffectedActiveTab else {
            NSSound.beep()
            return
        }
        guard contentBlockingCoordinator.toggleException(for: url) != nil else {
            NSSound.beep()
            return
        }
        // This explicit user action is intentionally stronger than ordinary
        // navigation preparation. Apply the selected exact-host policy before
        // reloading so an exception can recover even when a production rule
        // blocks the main document itself.
        guard tab.applyExactPolicyAndReload() else {
            _ = contentBlockingCoordinator.toggleException(for: url)
            _ = tab.restoreExactPolicyForCommittedPage()
            NSSound.beep()
            return
        }
        for otherTab in tabManager.tabs where otherTab !== tab {
            if otherTab.hasActiveNavigation {
                guard let affectedURL = contentBlockingURL(
                    in: otherTab,
                    matching: site
                ) else {
                    continue
                }
                _ = otherTab.strengthenPolicy(for: affectedURL)
            } else if
                otherTab.committedURL.flatMap(ContentBlockerSite.init(url:))
                    == site,
                !otherTab.applyExactPolicyAndReload()
            {
                _ = otherTab.restoreExactPolicyForCommittedPage()
            }
        }
        window?.makeFirstResponder(tab.webView)
        updatePrivacyBlockingResetState(
            isBusy: false,
            statusMessage: nil
        )
    }

    @objc
    func selectSearchProvider(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let provider = SearchProvider(rawValue: rawValue)
        else {
            return
        }

        searchProvider = provider
        addressInterpreter.searchProvider = provider
        BrowserPreferences.setSearchProvider(provider)
        chromeView.updateSearchProviderName(provider.displayName)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(goBack(_:)):
            return webView?.canGoBack == true
        case #selector(goForward(_:)):
            return webView?.canGoForward == true
        case #selector(reloadOrStop(_:)):
            menuItem.title = webView?.isLoading == true ? "Stop" : "Reload"
            return webView != nil
        case #selector(reloadPage(_:)):
            return webView != nil && webView?.isLoading == false
        case #selector(stopLoading(_:)):
            return webView?.isLoading == true
        case #selector(bookmarkCurrentPage(_:)):
            menuItem.title = bookmarkedCurrentPage == nil
                ? "Add Bookmark…"
                : "Edit Bookmark…"
            return bookmarkCoordinator?.allowsChanges == true
                && currentBookmarkPageCandidate != nil
        case #selector(showBookmarks(_:)):
            return bookmarkCoordinator != nil
        case #selector(showWebsiteData(_:)):
            return websiteDataController != nil
        case #selector(contentBlockingStatus(_:)):
            menuItem.title = contentBlockingStatusTitle
            return false
        case #selector(toggleContentBlockingForCurrentSiteAndReload(_:)):
            let presentation = contentBlockingTogglePresentation
            menuItem.title = presentation.title
            return presentation.isEnabled
        case #selector(selectSearchProvider(_:)):
            menuItem.state = (menuItem.representedObject as? String)
                == searchProvider.rawValue ? .on : .off
            return true
        default:
            return true
        }
    }

    func controlTextDidBeginEditing(_ notification: Notification) {
        isEditingAddress = true
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        isEditingAddress = false
        renderDisplayedURL()
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        guard
            control === chromeView.addressField,
            commandSelector == #selector(NSResponder.insertNewline(_:))
        else {
            return false
        }
        submitAddress(control)
        return true
    }

    func windowWillClose(_ notification: Notification) {
        bookmarkCoordinator?.cancel()
        bookmarkManagerWindowController?.close()
        websiteDataPrivacyWindowController?.close()
        compiledBlockerResetTask?.cancel()
        compiledBlockerResetTask = nil
        if
            let editorWindow = bookmarkEditorSheetController?.window,
            let parentWindow = editorWindow.sheetParent
        {
            parentWindow.endSheet(editorWindow)
        }
        for tab in tabManager.closeAll() {
            tab.close()
        }
        profile = nil
    }

    private func navigate(to url: URL) {
        let tab = tabManager.selectedTab
        if profile == nil,
           contentBlockingCoordinator?.availability == .unavailable
        {
            presentContentBlockingUnavailable()
            return
        }

        isEditingAddress = false
        _ = tab.navigate(to: url)
        renderDisplayedURL()
        if let webView = tab.webView {
            window?.makeFirstResponder(webView)
        }
    }

    private var currentContentBlockingURL: URL? {
        tabManager.selectedTab.currentContentBlockingURL
    }

    private func contentBlockingURL(
        in tab: TabController,
        matching site: ContentBlockerSite
    ) -> URL? {
        contentBlockingURLs(in: tab).first {
            ContentBlockerSite(url: $0) == site
        }
    }

    private func contentBlockingURLs(in tab: TabController) -> [URL] {
        [
            tab.retryURL,
            tab.pendingNavigationURL,
            tab.observedURL,
            tab.committedURL,
            tab.currentDocumentURL,
            tab.webView?.url,
        ].compactMap { $0 }
    }

    private var contentBlockingStatusTitle: String {
        guard let contentBlockingCoordinator else {
            return "Ad & Tracker Blocking: Unavailable"
        }
        let snapshot = contentBlockingCoordinator.snapshot(
            for: currentContentBlockingURL
        )
        switch snapshot.availability {
        case .preparing:
            return "Ad & Tracker Blocking: Preparing…"
        case .active:
            if snapshot.isException, let site = snapshot.site {
                return "Ad & Tracker Blocking: Off for \(site.host)"
            }
            return "Ad & Tracker Blocking: Active"
        case .activeLastValidRules:
            if snapshot.isException, let site = snapshot.site {
                return "Ad & Tracker Blocking: Off for \(site.host)"
            }
            return "Ad & Tracker Blocking: Active (Last Valid Rules)"
        case .unavailable:
            return "Ad & Tracker Blocking: Unavailable"
        }
    }

    private var contentBlockingTogglePresentation: (
        title: String,
        isEnabled: Bool
    ) {
        guard let contentBlockingCoordinator else {
            return ("Blocking Is Unavailable", false)
        }
        let snapshot = contentBlockingCoordinator.snapshot(
            for: currentContentBlockingURL
        )
        switch snapshot.availability {
        case .preparing:
            return ("Blocking Is Not Ready", false)
        case .unavailable:
            return ("Blocking Is Unavailable", false)
        case .active, .activeLastValidRules:
            guard
                let site = snapshot.site,
                tabManager.selectedTab.committedURL != nil,
                tabManager.selectedTab.webView != nil,
                !tabManager.selectedTab.hasActiveNavigation
            else {
                return ("No Website Selected", false)
            }
            let verb = snapshot.isException ? "Enable" : "Disable"
            return ("\(verb) Blocking for \(site.host) and Reload", true)
        }
    }

    private func presentContentBlockingUnavailable() {
        tabManager.selectedTab.presentError(
            title: "Privacy Protection Unavailable",
            message: "Browser could not load a valid ad and tracker blocking ruleset. Navigation remains paused to avoid loading a page without the expected protection.",
            recoveryActionTitle: nil
        )
    }

    private func renderDisplayedURL() {
        guard !isEditingAddress else {
            return
        }
        let observedURL = tabManager.selectedTab.observedURL
            ?? tabManager.selectedTab.pendingNavigationURL
        guard let observedURL, observedURL.absoluteString != "about:blank" else {
            chromeView.addressField.stringValue = ""
            return
        }
        chromeView.addressField.stringValue = observedURL.absoluteString
    }

    private func renderWindowTitle() {
        let observedTitle = tabManager.selectedTab.observedTitle
        guard let observedTitle, !observedTitle.isEmpty else {
            window?.title = "Browser"
            return
        }
        window?.title = "\(observedTitle) — Browser"
    }

    private func renderProgress() {
        chromeView.progressIndicator.doubleValue =
            tabManager.selectedTab.observedProgress
    }

    private func renderLoadingState() {
        let isLoading = tabManager.selectedTab.observedIsLoading
        chromeView.progressIndicator.isHidden = !isLoading
        chromeView.updateReloadStopButton(isLoading: isLoading)
    }

    private func renderNavigationState() {
        chromeView.backButton.isEnabled =
            tabManager.selectedTab.observedCanGoBack
        chromeView.forwardButton.isEnabled =
            tabManager.selectedTab.observedCanGoForward
        chromeView.reloadStopButton.isEnabled = webView != nil
    }

    private func renderSelectedTab() {
        renderDisplayedURL()
        renderWindowTitle()
        renderProgress()
        renderLoadingState()
        renderNavigationState()
        renderSelectedError()
        renderBookmarkState()
    }

    private func renderSelectedError() {
        guard let errorState = tabManager.selectedTab.errorState else {
            chromeView.errorView.isHidden = true
            return
        }
        chromeView.errorView.update(
            title: errorState.title,
            message: errorState.message,
            host: nil,
            recoveryActionTitle: errorState.recoveryActionTitle
        )
        chromeView.errorView.isHidden = false
        chromeView.pageContainer.addSubview(
            chromeView.errorView,
            positioned: .above,
            relativeTo: tabManager.selectedTab.webView
        )
    }

    private var bookmarkedCurrentPage: Bookmark? {
        guard let candidate = currentBookmarkPageCandidate else {
            return nil
        }
        return bookmarkCoordinator?.bookmarks.first {
            $0.url == candidate.url
        }
    }

    private func bookmarkStateDidChange(_ state: BookmarkCoordinator.State) {
        renderBookmarkState()
        renderBookmarkManager()
    }

    private func renderBookmarkState() {
        chromeView.updateBookmarkButton(
            isBookmarked: bookmarkedCurrentPage != nil,
            isEnabled: bookmarkCoordinator?.allowsChanges == true
                && currentBookmarkPageCandidate != nil
        )
        bookmarkManagerWindowController?.refreshCurrentPageAvailability()
    }

    private func websiteDataPrivacyManager()
        -> WebsiteDataPrivacyWindowController
    {
        if let websiteDataPrivacyWindowController {
            return websiteDataPrivacyWindowController
        }
        guard let websiteDataController else {
            preconditionFailure("Website data management was not started")
        }

        let manager = WebsiteDataPrivacyWindowController(
            dataController: websiteDataController
        )
        manager.onResetAllSiteExceptions = { [weak self] in
            self?.resetAllContentBlockingSiteExceptions()
        }
        manager.onDeleteCompiledBlockingRules = { [weak self] in
            self?.deleteCompiledContentBlockingArtifacts()
        }
        websiteDataPrivacyWindowController = manager
        return manager
    }

    private func resetAllContentBlockingSiteExceptions() {
        guard let contentBlockingCoordinator else {
            updatePrivacyBlockingResetState(
                isBusy: false,
                statusMessage: "Blocking data is unavailable in this launch mode."
            )
            return
        }
        let previousCount = contentBlockingCoordinator.siteExceptionCount
        guard previousCount > 0 else {
            updatePrivacyBlockingResetState(
                isBusy: false,
                statusMessage: "There are no site exceptions to reset."
            )
            return
        }

        let affectedTabs = tabManager.tabs.filter {
            $0.committedURL != nil
                && contentBlockingCoordinator.snapshot(
                    for: $0.committedURL
                ).isException
        }
        let hasAffectedActiveTab = tabManager.tabs.contains { tab in
            tab.hasActiveNavigation
                && contentBlockingURLs(in: tab).contains {
                    contentBlockingCoordinator.snapshot(for: $0).isException
                }
        }
        if hasAffectedActiveTab {
            updatePrivacyBlockingResetState(
                isBusy: false,
                statusMessage: "Wait for the affected tab navigation to finish, then reset the exceptions."
            )
            return
        }

        updatePrivacyBlockingResetState(
            isBusy: true,
            statusMessage: "Resetting site exceptions…"
        )
        contentBlockingCoordinator.resetSiteExceptions()

        var statusMessage = previousCount == 1
            ? "The site exception was reset."
            : "All \(previousCount) site exceptions were reset."
        var reloadCount = 0
        var failedCount = 0
        for tab in tabManager.tabs where tab.webView != nil {
            if !tab.strengthenProtection() {
                failedCount += 1
            }
        }
        for tab in affectedTabs {
            if tab.applyExactPolicyAndReload() {
                reloadCount += 1
            } else {
                _ = tab.restoreExactPolicyForCommittedPage()
                failedCount += 1
            }
        }
        if reloadCount == 1 {
            statusMessage += " The affected tab is reloading with protection enabled."
        } else if reloadCount > 1 {
            statusMessage += " \(reloadCount) affected tabs are reloading with protection enabled."
        }
        if failedCount > 0 {
            statusMessage += " Protection is attached to \(failedCount) other affected tab(s); reload them manually."
        }

        updatePrivacyBlockingResetState(
            isBusy: false,
            statusMessage: statusMessage
        )
    }

    private func deleteCompiledContentBlockingArtifacts() {
        guard
            compiledBlockerResetTask == nil,
            !compiledBlockerArtifactsWereReset,
            let contentBlockingCoordinator,
            contentBlockingCoordinator.canResetCompiledArtifacts
        else {
            updatePrivacyBlockingResetState(
                isBusy: false,
                statusMessage: "Compiled blocking rules cannot be reset right now."
            )
            return
        }

        updatePrivacyBlockingResetState(
            isBusy: true,
            statusMessage: "Deleting compiled blocking rules…"
        )
        compiledBlockerResetTask = Task { [weak self] in
            guard let self else {
                return
            }
            do {
                let result = try await contentBlockingCoordinator
                    .resetCompiledArtifacts()
                compiledBlockerArtifactsWereReset = true
                let removedCount = result.removedIdentifiers.count
                let removalDescription = removedCount == 1
                    ? "1 compiled rule list was deleted."
                    : "\(removedCount) compiled rule lists were deleted."
                compiledBlockerResetTask = nil
                updatePrivacyBlockingResetState(
                    isBusy: false,
                    statusMessage: removalDescription
                        + " Current pages remain protected; bundled rules will rebuild locally on the next launch."
                )
            } catch {
                compiledBlockerResetTask = nil
                updatePrivacyBlockingResetState(
                    isBusy: false,
                    statusMessage: Self.compiledBlockerResetFailureMessage(
                        error
                    )
                )
            }
        }
    }

    private func updatePrivacyBlockingResetState(
        isBusy: Bool,
        statusMessage: String?
    ) {
        guard let manager = websiteDataPrivacyWindowController else {
            return
        }
        manager.updateBlockingResetState(
            exceptionCount: contentBlockingCoordinator?.siteExceptionCount ?? 0,
            canResetCompiledArtifacts: contentBlockingCoordinator?
                .canResetCompiledArtifacts == true
                && !compiledBlockerArtifactsWereReset,
            isBusy: isBusy,
            statusMessage: statusMessage
        )
    }

    private static func compiledBlockerResetFailureMessage(
        _ error: Error
    ) -> String {
        switch error as? ContentBlockerArtifactResetError {
        case .preparationInProgress:
            return "Blocking rules are still preparing. Try again when protection is active."
        case .resetInProgress:
            return "Compiled blocking rules are already being deleted."
        case let .cachedIdentifiersRemain(identifiers):
            return "WebKit kept \(identifiers.count) compiled rule lists. Current protection remains active; try again after relaunching Browser."
        case nil:
            return "Compiled blocking rules could not be deleted. Current protection remains active."
        }
    }

    private func bookmarkManager() -> BookmarkManagerWindowController {
        if let bookmarkManagerWindowController {
            return bookmarkManagerWindowController
        }

        let manager = BookmarkManagerWindowController()
        manager.currentPageProvider = { [weak self] in
            self?.currentBookmarkPageCandidate
        }
        manager.onAddCurrentPage = { [weak self] candidate in
            guard let self else {
                return
            }
            if let existing = bookmarkedCurrentPage {
                presentBookmarkEditor(editing: existing)
            } else {
                presentBookmarkEditor(adding: candidate)
            }
        }
        manager.onEdit = { [weak self] bookmark in
            self?.presentBookmarkEditor(editing: bookmark)
        }
        manager.onDelete = { [weak self, weak manager] bookmark in
            manager?.showOperationStatus("Deleting bookmark…")
            self?.bookmarkCoordinator?.delete(id: bookmark.id) { errorMessage in
                if let errorMessage {
                    manager?.showOperationStatus(errorMessage)
                }
            }
        }
        manager.onOpen = { [weak self] bookmark in
            self?.openBookmark(bookmark.url)
            self?.window?.makeKeyAndOrderFront(nil)
        }
        manager.onRestoreBackup = { [weak self, weak manager] in
            manager?.showOperationStatus("Restoring bookmark backup…")
            self?.bookmarkCoordinator?.restoreBackup { errorMessage in
                if let errorMessage {
                    manager?.showOperationStatus(errorMessage)
                }
            }
        }
        manager.onReset = { [weak self, weak manager] in
            manager?.showOperationStatus("Resetting bookmarks…")
            self?.bookmarkCoordinator?.reset { errorMessage in
                if let errorMessage {
                    manager?.showOperationStatus(errorMessage)
                }
            }
        }
        bookmarkManagerWindowController = manager
        return manager
    }

    private func renderBookmarkManager() {
        guard let manager = bookmarkManagerWindowController else {
            return
        }
        guard let coordinator = bookmarkCoordinator else {
            manager.showFailure("Bookmarks are unavailable in this launch mode.", canReset: false)
            return
        }

        switch coordinator.state {
        case .idle, .loading:
            manager.showLoading()
        case let .ready(snapshot):
            let recoveryMessage: String?
            switch snapshot.recovery?.reason {
            case .corruptPrimary:
                recoveryMessage = "A damaged bookmark file was preserved. You can open this read-only backup, then restore it or reset the library."
            case .missingPrimary:
                recoveryMessage = "The primary bookmark file is missing. You can open this read-only backup, then restore it or reset the library."
            case nil:
                recoveryMessage = nil
            }
            manager.update(
                bookmarks: snapshot.bookmarks,
                allowsChanges: coordinator.allowsChanges,
                recoveryMessage: recoveryMessage,
                canRestoreBackup: coordinator.allowsRecoveryActions,
                canReset: snapshot.recovery != nil
                    && !coordinator.operationInProgress
            )
        case let .failed(message):
            manager.showFailure(
                message,
                canReset: !coordinator.operationInProgress
            )
        }
    }

    private func presentBookmarkEditor(adding candidate: BookmarkPageCandidate) {
        let editor = bookmarkEditor()
        guard !editor.activateIfPresented() else {
            NSSound.beep()
            return
        }
        guard let parentWindow = bookmarkEditorParentWindow else {
            return
        }
        editor.beginAdding(candidate, for: parentWindow)
    }

    private func presentBookmarkEditor(editing bookmark: Bookmark) {
        let editor = bookmarkEditor()
        guard !editor.activateIfPresented() else {
            NSSound.beep()
            return
        }
        guard let parentWindow = bookmarkEditorParentWindow else {
            return
        }
        editor.beginEditing(bookmark, for: parentWindow)
    }

    private var bookmarkEditorParentWindow: NSWindow? {
        if bookmarkManagerWindowController?.window?.isKeyWindow == true {
            return bookmarkManagerWindowController?.window
        }
        return window
    }

    private func bookmarkEditor() -> BookmarkEditorSheetController {
        if let bookmarkEditorSheetController {
            return bookmarkEditorSheetController
        }

        let editor = BookmarkEditorSheetController()
        editor.onSave = { [weak self, weak editor] identifier, url, title in
            guard let coordinator = self?.bookmarkCoordinator else {
                editor?.completeSave(errorMessage: "Bookmarks are not ready yet.")
                return
            }
            let completion: BookmarkCoordinator.MutationCompletion = { errorMessage in
                editor?.completeSave(errorMessage: errorMessage)
            }
            if let identifier {
                coordinator.update(
                    id: identifier,
                    url: url,
                    title: title,
                    completion: completion
                )
            } else {
                coordinator.add(
                    url: url,
                    title: title,
                    completion: completion
                )
            }
        }
        editor.onRemove = { [weak self, weak editor] bookmark in
            self?.bookmarkCoordinator?.delete(id: bookmark.id) { errorMessage in
                editor?.completeRemoval(errorMessage: errorMessage)
            }
        }
        bookmarkEditorSheetController = editor
        return editor
    }

    private func presentAddressError(_ error: AddressInterpretationError) {
        tabManager.selectedTab.clearRetryURL()
        switch error {
        case .emptyInput:
            presentError(
                title: "Enter an Address",
                message: error.localizedDescription,
                recoveryActionTitle: nil
            )
        case .malformedURL:
            presentError(
                title: "Invalid Address",
                message: error.localizedDescription,
                recoveryActionTitle: nil
            )
        case let .unsupportedScheme(scheme):
            presentError(
                title: "Unsupported Address",
                message: "Browser can’t open the \(scheme) scheme. Use an HTTP or HTTPS address.",
                recoveryActionTitle: nil
            )
        }
    }

    private func presentError(
        title: String,
        message: String,
        recoveryActionTitle: String?
    ) {
        tabManager.selectedTab.presentError(
            title: title,
            message: message,
            recoveryActionTitle: recoveryActionTitle
        )
    }

    private static func setAccessibilityIdentifier(
        _ identifier: String,
        on window: NSWindow
    ) {
        window.identifier = NSUserInterfaceItemIdentifier(identifier)
        window.setAccessibilityIdentifier(identifier)
    }
}
