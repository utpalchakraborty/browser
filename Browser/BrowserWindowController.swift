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
    private(set) var webViews: [WKWebView] = []
    var webView: WKWebView? { webViews.first }

    private let chromeView: BrowserChromeView
    private var addressInterpreter: AddressInterpreter
    private var searchProvider: SearchProvider
    private var observations: [NSKeyValueObservation] = []

    private var observedURL: URL?
    private var observedTitle: String?
    private var observedProgress = 0.0
    private var observedIsLoading = false
    private var observedCanGoBack = false
    private var observedCanGoForward = false
    private var isEditingAddress = false
    private var retryURL: URL?
    private var errorAllowsRetry = false

    private var firstBlankNavigation: WKNavigation?
    private var firstBlankNavigationState: OSSignpostIntervalState?
    private var submittedNavigation: WKNavigation?
    private var submittedNavigationState: OSSignpostIntervalState?

    init(searchProvider: SearchProvider = .defaultProvider) {
        self.searchProvider = searchProvider
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
        window.contentMinSize = NSSize(width: 420, height: 300)
        window.backgroundColor = .windowBackgroundColor
        Self.setAccessibilityIdentifier("BrowserMainWindow", on: window)
        window.contentView = chromeView

        super.init(window: window)

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

        let newWebView = BrowserPerformanceSignposts.signposter.withIntervalSignpost(
            "InitialWebViewConstruction"
        ) {
            profile.webViewFactory.makeWebView()
        }

        configurePrimaryWebView(newWebView)
        webViews.append(newWebView)

        firstBlankNavigationState = BrowserPerformanceSignposts.signposter.beginInterval(
            "FirstBlankNavigation"
        )
        firstBlankNavigation = newWebView.load(URLRequest(url: initialURL))
        if firstBlankNavigation == nil {
            finishFirstBlankNavigation(accessibilityValue: "Failed")
        }

        for _ in 1..<max(1, viewCount) {
            let backgroundWebView = profile.webViewFactory.makeWebView()
            backgroundWebView.navigationDelegate = self
            backgroundWebView.isHidden = true
            install(
                backgroundWebView,
                positioned: .below,
                relativeTo: newWebView
            )
            webViews.append(backgroundWebView)
            backgroundWebView.load(URLRequest(url: initialURL))
        }
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
        _ = BrowserPerformanceSignposts.signposter.withIntervalSignpost(
            "BrowserCommand"
        ) {
            webView.goBack()
        }
        window?.makeFirstResponder(webView)
    }

    @objc
    func goForward(_ sender: Any?) {
        guard let webView, webView.canGoForward else {
            return
        }
        hideError()
        _ = BrowserPerformanceSignposts.signposter.withIntervalSignpost(
            "BrowserCommand"
        ) {
            webView.goForward()
        }
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
        hideError()
        _ = BrowserPerformanceSignposts.signposter.withIntervalSignpost(
            "BrowserCommand"
        ) {
            webView.reload()
        }
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
    }

    @objc
    func retryNavigation(_ sender: Any?) {
        if let retryURL {
            navigate(to: retryURL)
        } else if let webView, webView.url != nil {
            hideError()
            _ = webView.reload()
            window?.makeFirstResponder(webView)
        } else {
            focusAddressField()
        }
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
        observations.forEach { $0.invalidate() }
        observations.removeAll()
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        switch NavigationPolicy.decision(
            for: navigationAction.request.url,
            isMainFrame: isMainFrame
        ) {
        case .allow:
            if isMainFrame {
                retryURL = navigationAction.request.url
            }
            decisionHandler(.allow)
        case .cancel:
            decisionHandler(.cancel)
            if isMainFrame {
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
            if navigationResponse.isForMainFrame {
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
        guard navigationAction.navigationType == .linkActivated else {
            return nil
        }

        switch NavigationPolicy.decision(
            for: navigationAction.request.url,
            isMainFrame: true
        ) {
        case .allow:
            if let url = navigationAction.request.url {
                navigate(to: url)
            }
        case .cancel:
            presentUnsupportedNavigation(url: navigationAction.request.url)
        }
        return nil
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard webView === self.webView else {
            return
        }
        hideError()
        synchronizeObservedState(from: webView, includeURL: false)
        webView.setAccessibilityValue("Loading")
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard webView === self.webView else {
            return
        }
        synchronizeObservedState(from: webView)
    }

    func webView(
        _ webView: WKWebView,
        didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!
    ) {
        guard webView === self.webView else {
            return
        }
        retryURL = webView.url
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
                }
            },
            webView.observe(\.title, options: [.initial, .new]) {
                [weak self, weak observed = webView] _, _ in
                Task { @MainActor [weak self, weak observed] in
                    self?.observedTitle = observed?.title
                    self?.renderWindowTitle()
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
            presentError(
                title: "Browser Isn’t Ready",
                message: "Wait a moment and try again.",
                recoveryActionTitle: nil
            )
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
        submittedNavigation = BrowserPerformanceSignposts.signposter.withIntervalSignpost(
            "AddressSubmission"
        ) {
            webView.load(URLRequest(url: url))
        }
        if submittedNavigation == nil {
            finishSubmittedNavigation(accessibilityValue: "Failed")
        }
        window?.makeFirstResponder(webView)
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
    }

    private func handleNavigationFailure(
        webView: WKWebView,
        navigation: WKNavigation?,
        error: any Error
    ) {
        guard webView === self.webView else {
            return
        }

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
        accessibilityValue: String = "Ready"
    ) {
        guard navigation === firstBlankNavigation else {
            return
        }
        finishFirstBlankNavigation(accessibilityValue: accessibilityValue)
    }

    private func finishFirstBlankNavigation(accessibilityValue: String) {
        guard let state = firstBlankNavigationState else {
            return
        }
        BrowserPerformanceSignposts.signposter.endInterval(
            "FirstBlankNavigation",
            state
        )
        firstBlankNavigation = nil
        firstBlankNavigationState = nil
        webView?.setAccessibilityValue(accessibilityValue)
    }

    private func finishSubmittedNavigationIfNeeded(
        _ navigation: WKNavigation?,
        accessibilityValue: String = "Ready"
    ) {
        guard navigation === submittedNavigation else {
            return
        }
        finishSubmittedNavigation(accessibilityValue: accessibilityValue)
    }

    private func finishSubmittedNavigation(accessibilityValue: String) {
        guard let state = submittedNavigationState else {
            return
        }
        BrowserPerformanceSignposts.signposter.endInterval(
            "LocalFixtureNavigation",
            state
        )
        submittedNavigation = nil
        submittedNavigationState = nil
        webView?.setAccessibilityValue(accessibilityValue)
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
    }

    private func hideError() {
        chromeView.errorView.isHidden = true
        errorAllowsRetry = false
    }

    private static func setAccessibilityIdentifier(
        _ identifier: String,
        on window: NSWindow
    ) {
        window.identifier = NSUserInterfaceItemIdentifier(identifier)
        window.setAccessibilityIdentifier(identifier)
    }
}
