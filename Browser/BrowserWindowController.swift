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
    NSTextFieldDelegate,
    WKNavigationDelegate,
    WKUIDelegate
{
    static let mainWindowFrameAutosaveName: NSWindow.FrameAutosaveName =
        "BrowserMainWindow"
    static let uiTestWindowFrameAutosaveName: NSWindow.FrameAutosaveName =
        "BrowserMainWindow.UITests"

    private(set) var webViews: [WKWebView] = []
    var webView: WKWebView? { webViews.first }

    private let chromeView: BrowserChromeView
    private let contentBlockingCoordinator: ContentBlockingCoordinator?
    private var addressInterpreter: AddressInterpreter
    private var searchProvider: SearchProvider
    private var observations: [NSKeyValueObservation] = []
    private var bookmarkCoordinator: BookmarkCoordinator?
    private var bookmarkManagerWindowController: BookmarkManagerWindowController?
    private var bookmarkEditorSheetController: BookmarkEditorSheetController?
    private var websiteDataController: WebsiteDataController?
    private var websiteDataPrivacyWindowController:
        WebsiteDataPrivacyWindowController?
    private var compiledBlockerResetTask: Task<Void, Never>?
    private var compiledBlockerArtifactsWereReset = false

    private var observedURL: URL?
    private var observedTitle: String?
    private var observedProgress = 0.0
    private var observedIsLoading = false
    private var observedCanGoBack = false
    private var observedCanGoForward = false
    private var isEditingAddress = false
    private var retryURL: URL?
    private var errorAllowsRetry = false
    private var pendingNavigationURL: URL?
    private var committedURL: URL?
    private var currentDocumentURL: URL?
    private var contentBlockingNavigationState =
        ContentBlockingNavigationState<WKNavigation>()

    private var firstBlankNavigation: WKNavigation?
    private var firstBlankNavigationState: OSSignpostIntervalState?
    private var submittedNavigation: WKNavigation?
    private var submittedNavigationState: OSSignpostIntervalState?

    init(
        searchProvider: SearchProvider = .defaultProvider,
        frameAutosaveName: NSWindow.FrameAutosaveName? = nil,
        contentBlockingCoordinator: ContentBlockingCoordinator? = nil
    ) {
        self.searchProvider = searchProvider
        self.contentBlockingCoordinator = contentBlockingCoordinator
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
        window.initialFirstResponder = chromeView.addressField

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
        guard webViews.isEmpty, window?.isVisible == true else {
            return
        }

        let requestedInitialURL = pendingNavigationURL ?? initialURL
        let constructedWebView = BrowserPerformanceSignposts.signposter
            .withIntervalSignpost("InitialWebViewConstruction") {
                makeWebView(
                    profile: profile,
                    applyingContentBlockingFor: requestedInitialURL
                )
            }
        guard let newWebView = constructedWebView else {
            contentBlockingPreparationDidFail()
            return
        }
        pendingNavigationURL = nil

        configurePrimaryWebView(newWebView)
        webViews.append(newWebView)

        firstBlankNavigationState = BrowserPerformanceSignposts.signposter.beginInterval(
            "FirstBlankNavigation"
        )
        beginContentBlockingNavigationRequest()
        let initialNavigation = newWebView.load(
            URLRequest(url: requestedInitialURL)
        )
        firstBlankNavigation = initialNavigation
        bindContentBlockingNavigation(initialNavigation)
        if firstBlankNavigation == nil {
            finishFirstBlankNavigation(accessibilityValue: "Failed")
        }

        for _ in 1..<max(1, viewCount) {
            guard let backgroundWebView = makeWebView(
                profile: profile,
                applyingContentBlockingFor: requestedInitialURL
            ) else {
                break
            }
            backgroundWebView.navigationDelegate = self
            backgroundWebView.isHidden = true
            install(
                backgroundWebView,
                positioned: .below,
                relativeTo: newWebView
            )
            webViews.append(backgroundWebView)
            backgroundWebView.load(URLRequest(url: requestedInitialURL))
        }
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
            url: observedURL,
            title: observedTitle,
            isLoading: observedIsLoading,
            hasVisibleError: !chromeView.errorView.isHidden
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
    func submitAddress(_ sender: Any?) {
        switch addressInterpreter.interpret(chromeView.addressField.stringValue) {
        case let .navigate(url):
            navigate(to: url)
        case let .failure(error):
            presentAddressError(error)
            focusAddressField()
        }
    }

    @objc
    func goBack(_ sender: Any?) {
        guard let webView, webView.canGoBack else {
            return
        }
        hideError()
        beginContentBlockingNavigationRequest()
        let navigation = BrowserPerformanceSignposts.signposter.withIntervalSignpost(
            "BrowserCommand"
        ) {
            webView.goBack()
        }
        bindContentBlockingNavigation(navigation)
        window?.makeFirstResponder(webView)
    }

    @objc
    func goForward(_ sender: Any?) {
        guard let webView, webView.canGoForward else {
            return
        }
        hideError()
        beginContentBlockingNavigationRequest()
        let navigation = BrowserPerformanceSignposts.signposter.withIntervalSignpost(
            "BrowserCommand"
        ) {
            webView.goForward()
        }
        bindContentBlockingNavigation(navigation)
        window?.makeFirstResponder(webView)
    }

    @objc
    func reloadOrStop(_ sender: Any?) {
        if webView?.isLoading == true {
            stopLoading(sender)
        } else {
            reloadPage(sender)
        }
    }

    @objc
    func reloadPage(_ sender: Any?) {
        guard let webView, !webView.isLoading else {
            return
        }
        if !chromeView.errorView.isHidden, errorAllowsRetry {
            retryNavigation(sender)
            return
        }
        let reloadURL = committedURL ?? webView.url ?? observedURL
        guard prepareContentBlockingPolicyForNavigation(to: reloadURL) else {
            presentContentBlockingUnavailable()
            return
        }
        hideError()
        beginContentBlockingNavigationRequest()
        let navigation = BrowserPerformanceSignposts.signposter.withIntervalSignpost(
            "BrowserCommand"
        ) {
            webView.reload()
        }
        bindContentBlockingNavigation(navigation)
        window?.makeFirstResponder(webView)
    }

    @objc
    func stopLoading(_ sender: Any?) {
        guard let webView, webView.isLoading else {
            return
        }
        BrowserPerformanceSignposts.signposter.withIntervalSignpost(
            "BrowserCommand"
        ) {
            webView.stopLoading()
        }
        applyContentBlockingPolicyForCommittedPage(
            in: webView,
            mode: contentBlockingNavigationState.cancelLatest()
        )
    }

    @objc
    func retryNavigation(_ sender: Any?) {
        if let retryURL {
            navigate(to: retryURL)
        } else if let webView, webView.url != nil {
            let reloadURL = committedURL ?? webView.url
            guard prepareContentBlockingPolicyForNavigation(to: reloadURL) else {
                presentContentBlockingUnavailable()
                return
            }
            hideError()
            beginContentBlockingNavigationRequest()
            let navigation = webView.reload()
            bindContentBlockingNavigation(navigation)
            window?.makeFirstResponder(webView)
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
        guard
            let contentBlockingCoordinator,
            let webView,
            !contentBlockingNavigationState.hasActiveNavigation,
            let url = committedURL,
            contentBlockingCoordinator.toggleException(for: url) != nil
        else {
            NSSound.beep()
            return
        }
        // This explicit user action is intentionally stronger than ordinary
        // navigation preparation. Apply the selected exact-host policy before
        // reloading so an exception can recover even when a production rule
        // blocks the main document itself.
        guard applyContentBlockingPolicy(
            for: url,
            in: webView,
            mode: .exact
        ) else {
            _ = contentBlockingCoordinator.toggleException(for: url)
            _ = applyContentBlockingPolicy(
                for: url,
                in: webView,
                mode: .exact
            )
            NSSound.beep()
            return
        }
        hideError()
        beginContentBlockingNavigationRequest()
        guard let navigation = webView.reload() else {
            _ = contentBlockingCoordinator.toggleException(for: url)
            applyContentBlockingPolicyForCommittedPage(
                in: webView,
                mode: contentBlockingNavigationState.cancelLatest()
            )
            NSSound.beep()
            return
        }
        bindContentBlockingNavigation(navigation)
        window?.makeFirstResponder(webView)
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
        finishFirstBlankNavigation(accessibilityValue: "Cancelled")
        finishSubmittedNavigation(accessibilityValue: "Cancelled")
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
        observations.forEach { $0.invalidate() }
        observations.removeAll()
        for webView in webViews {
            contentBlockingCoordinator?.forget(
                webView.configuration.userContentController
            )
            webView.navigationDelegate = nil
            webView.uiDelegate = nil
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        // A nil target frame is a request for a new browsing context. It must
        // not change the content-blocking policy of the committed page before
        // the UI delegate denies or deliberately routes that request.
        let isMainFrame = navigationAction.targetFrame?.isMainFrame == true
        switch NavigationPolicy.decision(
            for: navigationAction.request.url,
            isMainFrame: isMainFrame
        ) {
        case .allow:
            if isMainFrame {
                if ContentBlockingNavigationURL.isFragmentOnlyNavigation(
                    from: currentDocumentURL
                        ?? navigationAction.sourceFrame.request.url
                        ?? webView.url,
                    to: navigationAction.request.url
                ) {
                    if webView === self.webView {
                        currentDocumentURL = navigationAction.request.url
                        applyContentBlockingPolicyForCommittedPage(
                            in: webView,
                            mode: contentBlockingNavigationState
                                .resolveSameDocumentAction()
                        )
                        retryURL = navigationAction.request.url
                    }
                    decisionHandler(.allow)
                    return
                }
                guard prepareContentBlockingPolicyForNavigation(
                    to: navigationAction.request.url,
                    in: webView
                ) else {
                    decisionHandler(.cancel)
                    if webView === self.webView {
                        _ = contentBlockingNavigationState.cancelAwaitingRequest()
                    }
                    presentContentBlockingUnavailable()
                    return
                }
                if webView === self.webView {
                    _ = contentBlockingNavigationState.approveAction()
                }
                retryURL = navigationAction.request.url
            }
            decisionHandler(.allow)
        case .cancel:
            decisionHandler(.cancel)
            if isMainFrame, webView === self.webView {
                applyContentBlockingPolicyForCommittedPage(
                    in: webView,
                    mode: contentBlockingNavigationState.cancelAwaitingRequest()
                )
                presentUnsupportedNavigation(url: navigationAction.request.url)
            }
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void
    ) {
        guard navigationResponse.canShowMIMEType else {
            decisionHandler(.cancel)
            if navigationResponse.isForMainFrame, webView === self.webView {
                applyContentBlockingPolicyForCommittedPage(
                    in: webView,
                    mode: contentBlockingNavigationState.cancelLatest()
                )
                finishFirstBlankNavigation(accessibilityValue: "Failed")
                finishSubmittedNavigation(accessibilityValue: "Failed")
                presentError(
                    title: "Download Not Available",
                    message: "File downloads will be added during browser hardening.",
                    recoveryActionTitle: nil
                )
            }
            return
        }
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard navigationAction.targetFrame == nil else {
            return nil
        }
        // WebKit reports both a physical anchor click and JavaScript's
        // anchor.click() as linkActivated. Route only an unmodified primary-
        // button click on an HTTP(S) anchor. Scripted, keyboard, modified,
        // middle-button, and non-web-scheme requests remain denied.
        guard NewContextNavigationPolicy.shouldRouteInCurrentPage(
            url: navigationAction.request.url,
            isLinkActivation: navigationAction.navigationType == .linkActivated,
            buttonNumber: navigationAction.buttonNumber,
            modifierFlags: navigationAction.modifierFlags
        ) else {
            return nil
        }

        if let url = navigationAction.request.url {
            navigate(to: url)
        }
        return nil
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard webView === self.webView else {
            return
        }
        bindContentBlockingNavigation(navigation)
        hideError()
        synchronizeObservedState(from: webView, includeURL: false)
        webView.setAccessibilityValue("Loading")
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard webView === self.webView else {
            return
        }
        committedURL = webView.url
        currentDocumentURL = webView.url
        applyContentBlockingPolicyForCommittedPage(
            in: webView,
            mode: contentBlockingNavigationState.commit(
                navigation
            )
        )
        synchronizeObservedState(from: webView)
    }

    func webView(
        _ webView: WKWebView,
        didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!
    ) {
        guard webView === self.webView else {
            return
        }
        bindContentBlockingRedirect(navigation)
        retryURL = webView.url
        guard prepareContentBlockingPolicyForNavigation(
            to: webView.url,
            in: webView
        ) else {
            webView.stopLoading()
            presentContentBlockingUnavailable()
            return
        }
        synchronizeObservedState(from: webView)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === self.webView else {
            return
        }

        synchronizeObservedState(from: webView)
        webView.setAccessibilityValue("Ready")
        finishFirstNavigationIfNeeded(navigation)
        finishSubmittedNavigationIfNeeded(navigation)
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: any Error
    ) {
        handleNavigationFailure(webView: webView, navigation: navigation, error: error)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: any Error
    ) {
        handleNavigationFailure(webView: webView, navigation: navigation, error: error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard webView === self.webView else {
            return
        }
        applyContentBlockingPolicyForCommittedPage(
            in: webView,
            mode: contentBlockingNavigationState.cancelLatest()
        )
        finishFirstBlankNavigation(accessibilityValue: "Failed")
        finishSubmittedNavigation(accessibilityValue: "Failed")
        show(
            BrowserErrorPresentation.from(
                error: BrowserPageError.webContentProcessTerminated,
                attemptedURL: retryURL ?? webView.url
            )
        )
    }

    private func configurePrimaryWebView(_ webView: WKWebView) {
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.setAccessibilityIdentifier("BrowserWebView")
        webView.setAccessibilityLabel("Web page")
        webView.setAccessibilityValue("Loading")
        install(webView, positioned: .below, relativeTo: chromeView.errorView)
        beginObserving(webView)
    }

    private func makeWebView(
        profile: BrowserProfile,
        applyingContentBlockingFor url: URL
    ) -> WKWebView? {
        guard let contentBlockingCoordinator else {
            return profile.webViewFactory.makeWebView()
        }
        let contentController = WKUserContentController()
        guard contentBlockingCoordinator.applyPolicy(
            to: contentController,
            for: url
        ) else {
            return nil
        }
        return profile.webViewFactory.makeWebView(
            userContentController: contentController
        )
    }

    private func install(
        _ webView: WKWebView,
        positioned placement: NSWindow.OrderingMode,
        relativeTo otherView: NSView
    ) {
        webView.translatesAutoresizingMaskIntoConstraints = false
        chromeView.pageContainer.addSubview(
            webView,
            positioned: placement,
            relativeTo: otherView
        )
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: chromeView.pageContainer.topAnchor),
            webView.leadingAnchor.constraint(equalTo: chromeView.pageContainer.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: chromeView.pageContainer.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: chromeView.pageContainer.bottomAnchor),
        ])
    }

    private func beginObserving(_ webView: WKWebView) {
        observations = [
            webView.observe(\.url, options: [.initial, .new]) {
                [weak self, weak observed = webView] _, _ in
                Task { @MainActor [weak self, weak observed] in
                    self?.observedURL = observed?.url
                    self?.renderDisplayedURL()
                    self?.renderBookmarkState()
                }
            },
            webView.observe(\.title, options: [.initial, .new]) {
                [weak self, weak observed = webView] _, _ in
                Task { @MainActor [weak self, weak observed] in
                    self?.observedTitle = observed?.title
                    self?.renderWindowTitle()
                    self?.renderBookmarkState()
                }
            },
            webView.observe(\.estimatedProgress, options: [.initial, .new]) {
                [weak self, weak observed = webView] _, _ in
                Task { @MainActor [weak self, weak observed] in
                    self?.observedProgress = observed?.estimatedProgress ?? 0
                    self?.renderProgress()
                }
            },
            webView.observe(\.isLoading, options: [.initial, .new]) {
                [weak self, weak observed = webView] _, _ in
                Task { @MainActor [weak self, weak observed] in
                    self?.observedIsLoading = observed?.isLoading ?? false
                    self?.renderLoadingState()
                    self?.renderBookmarkState()
                }
            },
            webView.observe(\.canGoBack, options: [.initial, .new]) {
                [weak self, weak observed = webView] _, _ in
                Task { @MainActor [weak self, weak observed] in
                    self?.observedCanGoBack = observed?.canGoBack ?? false
                    self?.renderNavigationState()
                }
            },
            webView.observe(\.canGoForward, options: [.initial, .new]) {
                [weak self, weak observed = webView] _, _ in
                Task { @MainActor [weak self, weak observed] in
                    self?.observedCanGoForward = observed?.canGoForward ?? false
                    self?.renderNavigationState()
                }
            },
        ]
    }

    private func navigate(to url: URL) {
        guard let webView else {
            if contentBlockingCoordinator?.availability == .preparing {
                pendingNavigationURL = url
                retryURL = url
                isEditingAddress = false
                observedURL = url
                renderDisplayedURL()
                hideError()
                return
            }
            if contentBlockingCoordinator?.availability == .unavailable {
                pendingNavigationURL = url
                retryURL = url
                presentContentBlockingUnavailable()
                return
            }
            presentError(
                title: "Browser Isn’t Ready",
                message: "Wait a moment and try again.",
                recoveryActionTitle: nil
            )
            return
        }

        guard prepareContentBlockingPolicyForNavigation(to: url) else {
            presentContentBlockingUnavailable()
            return
        }

        finishSubmittedNavigation(accessibilityValue: "Cancelled")
        retryURL = url
        isEditingAddress = false
        observedURL = url
        renderDisplayedURL()
        hideError()
        submittedNavigationState = BrowserPerformanceSignposts.signposter.beginInterval(
            "LocalFixtureNavigation"
        )
        beginContentBlockingNavigationRequest()
        let navigation = BrowserPerformanceSignposts.signposter.withIntervalSignpost(
            "AddressSubmission"
        ) {
            webView.load(URLRequest(url: url))
        }
        submittedNavigation = navigation
        bindContentBlockingNavigation(navigation)
        if submittedNavigation == nil {
            finishSubmittedNavigation(accessibilityValue: "Failed")
        }
        window?.makeFirstResponder(webView)
    }

    private func applyContentBlockingPolicy(
        for url: URL?,
        in targetWebView: WKWebView? = nil,
        mode: ContentBlockingPolicyApplicationMode = .exact
    ) -> Bool {
        guard let contentBlockingCoordinator else {
            return true
        }
        guard let targetWebView = targetWebView ?? webView else {
            return false
        }
        return contentBlockingCoordinator.applyPolicy(
            to: targetWebView.configuration.userContentController,
            for: url,
            mode: mode
        )
    }

    private func prepareContentBlockingPolicyForNavigation(
        to url: URL?,
        in targetWebView: WKWebView? = nil
    ) -> Bool {
        applyContentBlockingPolicy(
            for: url,
            in: targetWebView,
            mode: .strengthenOnly
        )
    }

    private func applyContentBlockingPolicyForCommittedPage(
        in targetWebView: WKWebView,
        mode: ContentBlockingPolicyApplicationMode
    ) {
        guard mode != .none else {
            return
        }
        guard applyContentBlockingPolicy(
            for: committedURL,
            in: targetWebView,
            mode: mode
        ) else {
            presentContentBlockingUnavailable()
            return
        }
    }

    private func beginContentBlockingNavigationRequest() {
        _ = contentBlockingNavigationState.beginRequest()
    }

    private func bindContentBlockingNavigation(_ navigation: WKNavigation?) {
        guard let navigation else {
            guard let webView else {
                _ = contentBlockingNavigationState.cancelLatest()
                return
            }
            applyContentBlockingPolicyForCommittedPage(
                in: webView,
                mode: contentBlockingNavigationState.cancelLatest()
            )
            return
        }
        _ = contentBlockingNavigationState.bind(navigation)
    }

    private func bindContentBlockingRedirect(_ navigation: WKNavigation?) {
        guard let navigation else {
            return
        }
        _ = contentBlockingNavigationState.bindRedirect(navigation)
    }

    private var currentContentBlockingURL: URL? {
        committedURL ?? pendingNavigationURL ?? observedURL ?? webView?.url
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
                committedURL != nil,
                webView != nil,
                !contentBlockingNavigationState.hasActiveNavigation
            else {
                return ("No Website Selected", false)
            }
            let verb = snapshot.isException ? "Enable" : "Disable"
            return ("\(verb) Blocking for \(site.host) and Reload", true)
        }
    }

    private func presentContentBlockingUnavailable() {
        presentError(
            title: "Privacy Protection Unavailable",
            message: "Browser could not load a valid ad and tracker blocking ruleset. Navigation remains paused to avoid loading a page without the expected protection.",
            recoveryActionTitle: nil
        )
    }

    private func renderDisplayedURL() {
        guard !isEditingAddress else {
            return
        }
        guard let observedURL, observedURL.absoluteString != "about:blank" else {
            chromeView.addressField.stringValue = ""
            return
        }
        chromeView.addressField.stringValue = observedURL.absoluteString
    }

    private func renderWindowTitle() {
        guard let observedTitle, !observedTitle.isEmpty else {
            window?.title = "Browser"
            return
        }
        window?.title = "\(observedTitle) — Browser"
    }

    private func renderProgress() {
        chromeView.progressIndicator.doubleValue = observedProgress
    }

    private func renderLoadingState() {
        chromeView.progressIndicator.isHidden = !observedIsLoading
        chromeView.updateReloadStopButton(isLoading: observedIsLoading)
    }

    private func renderNavigationState() {
        chromeView.backButton.isEnabled = observedCanGoBack
        chromeView.forwardButton.isEnabled = observedCanGoForward
        chromeView.reloadStopButton.isEnabled = webView != nil
    }

    private func synchronizeObservedState(
        from webView: WKWebView,
        includeURL: Bool = true
    ) {
        if includeURL {
            observedURL = webView.url
        }
        observedTitle = webView.title
        observedProgress = webView.estimatedProgress
        observedIsLoading = webView.isLoading
        observedCanGoBack = webView.canGoBack
        observedCanGoForward = webView.canGoForward
        renderDisplayedURL()
        renderWindowTitle()
        renderProgress()
        renderLoadingState()
        renderNavigationState()
        renderBookmarkState()
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

        let currentWasExcepted = contentBlockingCoordinator.snapshot(
            for: committedURL
        ).isException
        if currentWasExcepted,
           (contentBlockingNavigationState.hasActiveNavigation
                || webView == nil
                || committedURL == nil)
        {
            updatePrivacyBlockingResetState(
                isBusy: false,
                statusMessage: "Wait for the current navigation to finish, then reset the exceptions."
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
        if currentWasExcepted,
           let webView,
           let committedURL
        {
            guard applyContentBlockingPolicy(
                for: committedURL,
                in: webView,
                mode: .exact
            ) else {
                presentContentBlockingUnavailable()
                updatePrivacyBlockingResetState(
                    isBusy: false,
                    statusMessage: "The exceptions were reset, but protection could not be attached to the current page."
                )
                return
            }
            hideError()
            beginContentBlockingNavigationRequest()
            let navigation = webView.reload()
            bindContentBlockingNavigation(navigation)
            if navigation == nil {
                statusMessage += " Protection is attached; reload the current page manually."
            } else {
                statusMessage += " The current page is reloading with protection enabled."
            }
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

    private func handleNavigationFailure(
        webView: WKWebView,
        navigation: WKNavigation?,
        error: any Error
    ) {
        guard webView === self.webView else {
            return
        }

        let disposition = contentBlockingNavigationState.fail(navigation)
        guard case let .current(mode) = disposition else {
            finishFirstNavigationIfNeeded(
                navigation,
                accessibilityValue: nil
            )
            finishSubmittedNavigationIfNeeded(
                navigation,
                accessibilityValue: nil
            )
            return
        }
        applyContentBlockingPolicyForCommittedPage(in: webView, mode: mode)
        synchronizeObservedState(from: webView)
        finishFirstNavigationIfNeeded(
            navigation,
            accessibilityValue: "Failed"
        )
        finishSubmittedNavigationIfNeeded(navigation, accessibilityValue: "Failed")
        show(
            BrowserErrorPresentation.from(
                error: error,
                attemptedURL: retryURL ?? webView.url
            )
        )
    }

    private func finishFirstNavigationIfNeeded(
        _ navigation: WKNavigation?,
        accessibilityValue: String? = "Ready"
    ) {
        guard navigation === firstBlankNavigation else {
            return
        }
        finishFirstBlankNavigation(accessibilityValue: accessibilityValue)
    }

    private func finishFirstBlankNavigation(accessibilityValue: String?) {
        guard let state = firstBlankNavigationState else {
            return
        }
        BrowserPerformanceSignposts.signposter.endInterval(
            "FirstBlankNavigation",
            state
        )
        firstBlankNavigation = nil
        firstBlankNavigationState = nil
        if let accessibilityValue {
            webView?.setAccessibilityValue(accessibilityValue)
        }
    }

    private func finishSubmittedNavigationIfNeeded(
        _ navigation: WKNavigation?,
        accessibilityValue: String? = "Ready"
    ) {
        guard navigation === submittedNavigation else {
            return
        }
        finishSubmittedNavigation(accessibilityValue: accessibilityValue)
    }

    private func finishSubmittedNavigation(accessibilityValue: String?) {
        guard let state = submittedNavigationState else {
            return
        }
        BrowserPerformanceSignposts.signposter.endInterval(
            "LocalFixtureNavigation",
            state
        )
        submittedNavigation = nil
        submittedNavigationState = nil
        if let accessibilityValue {
            webView?.setAccessibilityValue(accessibilityValue)
        }
    }

    private func presentAddressError(_ error: AddressInterpretationError) {
        retryURL = nil
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

    private func presentUnsupportedNavigation(url: URL?) {
        let scheme = url?.scheme?.lowercased()
        presentError(
            title: "Unsupported Address",
            message: scheme.map {
                "Browser blocked the \($0) scheme. Only HTTP and HTTPS navigation is supported."
            } ?? "Browser blocked a navigation without a valid HTTP or HTTPS address.",
            recoveryActionTitle: nil
        )
    }

    private func show(_ presentation: BrowserErrorPresentation?) {
        guard let presentation else {
            return
        }
        presentError(
            title: presentation.title,
            message: presentation.message,
            recoveryActionTitle: presentation.recoveryActionTitle
        )
    }

    private func presentError(
        title: String,
        message: String,
        recoveryActionTitle: String?
    ) {
        errorAllowsRetry = recoveryActionTitle != nil
        chromeView.errorView.update(
            title: title,
            message: message,
            host: nil,
            recoveryActionTitle: recoveryActionTitle
        )
        chromeView.errorView.isHidden = false
        chromeView.pageContainer.addSubview(
            chromeView.errorView,
            positioned: .above,
            relativeTo: webView
        )
        webView?.setAccessibilityValue("Failed")
        renderBookmarkState()
    }

    private func hideError() {
        chromeView.errorView.isHidden = true
        errorAllowsRetry = false
        renderBookmarkState()
    }

    private static func setAccessibilityIdentifier(
        _ identifier: String,
        on window: NSWindow
    ) {
        window.identifier = NSUserInterfaceItemIdentifier(identifier)
        window.setAccessibilityIdentifier(identifier)
    }
}
