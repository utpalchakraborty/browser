import AppKit
import os
import WebKit

nonisolated struct BrowserTabErrorState: Equatable, Sendable {
    let title: String
    let message: String
    let recoveryActionTitle: String?
}

nonisolated struct FailedDocumentRecovery: Equatable, Sendable {
    let id = UUID()
    let url: URL
}

nonisolated struct BrowserTabPresentation: Equatable, Sendable {
    let id: UUID
    let title: String
    let isSelected: Bool
}

@MainActor
final class TabController: NSObject, WKNavigationDelegate, WKUIDelegate {
    let id: UUID

    private(set) var webView: WKWebView?
    private(set) var observedURL: URL?
    private(set) var observedTitle: String?
    private(set) var observedProgress = 0.0
    private(set) var observedIsLoading = false
    private(set) var observedCanGoBack = false
    private(set) var observedCanGoForward = false
    private(set) var errorState: BrowserTabErrorState?
    private(set) var failedDocumentRecovery: FailedDocumentRecovery?

    private(set) var pendingNavigationURL: URL?
    private(set) var retryURL: URL?
    private(set) var committedURL: URL?
    private(set) var currentDocumentURL: URL?
    private(set) var isClosed = false

    var onStateChange: ((TabController) -> Void)?
    var onOpenTab: ((URLRequest, NewTabNavigationDisposition) -> Void)?
    var onOpenExternalURL: ((URL) -> Bool)?

    private let contentBlockingCoordinator: ContentBlockingCoordinator?
    private var webViewFactory: WebViewFactory?
    private var observations: [NSKeyValueObservation] = []
    private var contentBlockingNavigationState =
        ContentBlockingNavigationState<WKNavigation>()
    private var localFileAuthorizations: [LocalFileAuthorization] = []
    private var approvedLocalFileURL: URL?
    private var navigationActionGeneration: UInt64 = 0

    private var firstBlankNavigation: WKNavigation?
    private var firstBlankNavigationState: OSSignpostIntervalState?
    private var submittedNavigation: WKNavigation?
    private var submittedNavigationState: OSSignpostIntervalState?

    init(
        id: UUID = UUID(),
        contentBlockingCoordinator: ContentBlockingCoordinator? = nil
    ) {
        self.id = id
        self.contentBlockingCoordinator = contentBlockingCoordinator
        super.init()
    }

    var displayTitle: String {
        if let title = Self.sanitizedTitle(observedTitle), !title.isEmpty {
            return title
        }
        if let host = observedURL?.host ?? pendingNavigationURL?.host,
           let title = Self.sanitizedTitle(host),
           !title.isEmpty
        {
            return title
        }
        return "New Tab"
    }

    var currentContentBlockingURL: URL? {
        committedURL ?? pendingNavigationURL ?? observedURL ?? webView?.url
    }

    var hasActiveNavigation: Bool {
        contentBlockingNavigationState.hasActiveNavigation
    }

    var hasVisibleError: Bool {
        errorState != nil
    }

    var allowsRetry: Bool {
        errorState?.recoveryActionTitle != nil
    }

    func installWebViewFactory(_ factory: WebViewFactory) {
        guard !isClosed else {
            return
        }
        webViewFactory = factory
    }

    @discardableResult
    func realizeInitialWebView(for url: URL) -> Bool {
        realizeWebViewIfNeeded(
            for: url,
            measureInitialConstruction: true
        ) != nil
    }

    @discardableResult
    func loadInitial(
        _ request: URLRequest,
        measureFirstBlankNavigation: Bool
    ) -> Bool {
        load(
            request,
            purpose: measureFirstBlankNavigation ? .firstBlank : .background
        )
    }

    @discardableResult
    func loadInBackground(_ request: URLRequest) -> Bool {
        load(request, purpose: .background)
    }

    @discardableResult
    func navigate(to url: URL) -> Bool {
        load(URLRequest(url: url), purpose: .submitted)
    }

    @discardableResult
    func navigate(toLocalFile authorization: LocalFileAuthorization) -> Bool {
        guard
            !isClosed,
            LocalFileAccessPolicy.isSupportedHTMLFile(authorization.fileURL),
            LocalFileAccessPolicy.contains(
                authorization.fileURL,
                in: authorization.readAccessURL
            )
        else {
            authorization.securityScopedURL
                .stopAccessingSecurityScopedResource()
            return false
        }

        let alreadyAuthorized = localFileAuthorizations.contains {
            LocalFileAccessPolicy.refersToSameFile(
                $0.readAccessURL,
                authorization.readAccessURL
            )
        }
        if alreadyAuthorized {
            authorization.securityScopedURL
                .stopAccessingSecurityScopedResource()
        } else {
            localFileAuthorizations.append(authorization)
        }
        approvedLocalFileURL = authorization.fileURL
        let didStart = load(
            URLRequest(url: authorization.fileURL),
            purpose: .submitted
        )
        if !didStart {
            approvedLocalFileURL = nil
            if !alreadyAuthorized {
                removeLocalFileAuthorization(
                    readAccessURL: authorization.readAccessURL
                )
            }
        }
        return didStart
    }

    func hasLocalFileAccess(to fileURL: URL) -> Bool {
        guard
            LocalFileAccessPolicy.isSupportedHTMLFile(fileURL),
            localFileAuthorization(containing: fileURL) != nil
        else {
            return false
        }
        return true
    }

    @discardableResult
    func navigateToPreviouslyAuthorizedLocalFile(_ fileURL: URL) -> Bool {
        guard
            !isClosed,
            let navigationURL = LocalFileAccessPolicy
                .resolvedNavigationURL(fileURL),
            LocalFileAccessPolicy.isSupportedHTMLFile(navigationURL),
            localFileAuthorization(containing: navigationURL) != nil
        else {
            return false
        }

        approvedLocalFileURL = navigationURL
        let didStart = load(
            URLRequest(url: navigationURL),
            purpose: .submitted
        )
        if !didStart {
            approvedLocalFileURL = nil
        }
        return didStart
    }

    func goBack() {
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
    }

    func goForward() {
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
    }

    func reload() {
        guard let webView, !webView.isLoading else {
            return
        }
        if hasVisibleError, allowsRetry {
            retry()
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
    }

    func stopLoading() {
        guard let webView, webView.isLoading else {
            return
        }
        BrowserPerformanceSignposts.signposter.withIntervalSignpost(
            "BrowserCommand"
        ) {
            webView.stopLoading()
        }
        applyContentBlockingPolicyForCommittedPage(
            mode: contentBlockingNavigationState.cancelLatest()
        )
        synchronizeObservedState()
    }

    func retry() {
        if let retryURL {
            if
                retryURL.isFileURL,
                localFileAuthorization(containing: retryURL) != nil
            {
                approvedLocalFileURL = retryURL
            }
            _ = navigate(to: retryURL)
            return
        }
        guard let webView, webView.url != nil else {
            onStateChange?(self)
            return
        }
        let reloadURL = committedURL ?? webView.url
        guard prepareContentBlockingPolicyForNavigation(to: reloadURL) else {
            presentContentBlockingUnavailable()
            return
        }
        hideError()
        beginContentBlockingNavigationRequest()
        let navigation = webView.reload()
        bindContentBlockingNavigation(navigation)
    }

    func presentError(
        title: String,
        message: String,
        recoveryActionTitle: String?
    ) {
        failedDocumentRecovery = nil
        errorState = BrowserTabErrorState(
            title: title,
            message: message,
            recoveryActionTitle: recoveryActionTitle
        )
        webView?.setAccessibilityValue("Failed")
        notifyStateChange()
    }

    func clearRetryURL() {
        retryURL = nil
    }

    func retryFailedDocument(_ recovery: FailedDocumentRecovery) -> Bool {
        guard
            !isClosed,
            failedDocumentRecovery == recovery,
            !hasActiveNavigation,
            webView != nil,
            ContentBlockerSite(url: recovery.url) != nil,
            applyContentBlockingPolicy(for: recovery.url, mode: .exact)
        else {
            return false
        }
        return navigate(to: recovery.url)
    }

    func applyExactPolicyAndReload() -> Bool {
        guard
            let webView,
            let committedURL,
            !contentBlockingNavigationState.hasActiveNavigation,
            applyContentBlockingPolicy(
                for: committedURL,
                mode: .exact
            )
        else {
            return false
        }

        hideError()
        beginContentBlockingNavigationRequest()
        guard let navigation = webView.reload() else {
            applyContentBlockingPolicyForCommittedPage(
                mode: contentBlockingNavigationState.cancelLatest()
            )
            return false
        }
        bindContentBlockingNavigation(navigation)
        return true
    }

    func strengthenPolicy(for url: URL?) -> Bool {
        guard applyContentBlockingPolicy(for: url, mode: .strengthenOnly) else {
            webView?.stopLoading()
            presentContentBlockingUnavailable()
            return false
        }
        return true
    }

    func strengthenProtection() -> Bool {
        strengthenPolicy(for: nil)
    }

    func restoreExactPolicyForCommittedPage() -> Bool {
        applyContentBlockingPolicy(for: committedURL, mode: .exact)
    }

    func setSelectedAccessibility(_ isSelected: Bool) {
        guard let webView else {
            return
        }
        webView.setAccessibilityIdentifier(
            isSelected ? "BrowserWebView" : "BrowserBackgroundWebView.\(id.uuidString)"
        )
        webView.setAccessibilityHidden(!isSelected)
    }

    func close() {
        guard !isClosed else {
            return
        }
        isClosed = true
        finishFirstBlankNavigation(accessibilityValue: "Cancelled")
        finishSubmittedNavigation(accessibilityValue: "Cancelled")
        observations.forEach { $0.invalidate() }
        observations.removeAll()
        if let webView {
            webView.navigationDelegate = nil
            webView.uiDelegate = nil
            webView.stopLoading()
            contentBlockingCoordinator?.forget(
                webView.configuration.userContentController
            )
            webView.removeFromSuperview()
        }
        webView = nil
        webViewFactory = nil
        observedURL = nil
        observedTitle = nil
        observedProgress = 0
        observedIsLoading = false
        observedCanGoBack = false
        observedCanGoForward = false
        pendingNavigationURL = nil
        retryURL = nil
        committedURL = nil
        currentDocumentURL = nil
        failedDocumentRecovery = nil
        errorState = nil
        contentBlockingNavigationState =
            ContentBlockingNavigationState<WKNavigation>()
        releaseLocalFileAccess()
        onStateChange = nil
        onOpenTab = nil
        onOpenExternalURL = nil
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        guard acceptsDelegateCallback(from: webView) else {
            decisionHandler(.cancel)
            return
        }
        let isMainFrame = navigationAction.targetFrame?.isMainFrame == true
        let externalDisposition = ExternalNavigationPolicy.disposition(
            for: navigationAction.request.url,
            isLinkActivation: navigationAction.navigationType == .linkActivated,
            buttonNumber: navigationAction.buttonNumber,
            modifierFlags: navigationAction.modifierFlags,
            targetsTopLevelContext:
                navigationAction.targetFrame?.isMainFrame ?? true
        )
        if case let .open(url) = externalDisposition {
            decisionHandler(.cancel)
            if isMainFrame {
                applyContentBlockingPolicyForCommittedPage(
                    mode: contentBlockingNavigationState.cancelAwaitingRequest()
                )
            }
            openExternalURL(url)
            return
        }

        let newTabDisposition = NewContextNavigationPolicy.disposition(
            url: navigationAction.request.url,
            isLinkActivation: navigationAction.navigationType == .linkActivated,
            buttonNumber: navigationAction.buttonNumber,
            modifierFlags: navigationAction.modifierFlags,
            requestsNewContext: navigationAction.targetFrame == nil
        )
        switch newTabDisposition {
        case .foregroundTab, .backgroundTab:
            decisionHandler(.cancel)
            onOpenTab?(navigationAction.request, newTabDisposition)
            return
        case .deny:
            decisionHandler(.cancel)
            return
        case .continueInCurrentFrame:
            break
        }

        let localFileAuthorization = localFileAuthorization(
            containing: navigationAction.request.url
        )
        let isAuthorizedLocalFile = LocalFileNavigationPolicy.allows(
            targetURL: navigationAction.request.url,
            sourceURL: navigationAction.sourceFrame.request.url,
            readAccessURL: localFileAuthorization?.readAccessURL,
            approvedURL: approvedLocalFileURL,
            isMainFrame: isMainFrame,
            isBackForwardNavigation:
                navigationAction.navigationType == .backForward
        )
        if
            isAuthorizedLocalFile,
            isMainFrame,
            LocalFileAccessPolicy.refersToSameFile(
                navigationAction.request.url,
                approvedLocalFileURL
            )
        {
            approvedLocalFileURL = nil
        }
        let navigationDecision: NavigationPolicyDecision = isAuthorizedLocalFile
            ? .allow
            : NavigationPolicy.decision(
                for: navigationAction.request.url,
                isMainFrame: isMainFrame
            )
        switch navigationDecision {
        case .allow:
            if isMainFrame {
                if ContentBlockingNavigationURL.isFragmentOnlyNavigation(
                    from: currentDocumentURL
                        ?? navigationAction.sourceFrame.request.url
                        ?? webView.url,
                    to: navigationAction.request.url
                ) {
                    currentDocumentURL = navigationAction.request.url
                    applyContentBlockingPolicyForCommittedPage(
                        mode: contentBlockingNavigationState
                            .resolveSameDocumentAction()
                    )
                    retryURL = navigationAction.request.url
                    decisionHandler(.allow)
                    return
                }
                guard prepareContentBlockingPolicyForNavigation(
                    to: navigationAction.request.url
                ) else {
                    decisionHandler(.cancel)
                    _ = contentBlockingNavigationState.cancelAwaitingRequest()
                    presentContentBlockingUnavailable()
                    return
                }
                navigationActionGeneration &+= 1
                hideError()
                _ = contentBlockingNavigationState.approveAction()
                retryURL = navigationAction.request.url
            }
            decisionHandler(.allow)
        case .cancel:
            decisionHandler(.cancel)
            if isMainFrame {
                applyContentBlockingPolicyForCommittedPage(
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
        guard acceptsDelegateCallback(from: webView) else {
            decisionHandler(.cancel)
            return
        }
        guard navigationResponse.canShowMIMEType else {
            decisionHandler(.cancel)
            if navigationResponse.isForMainFrame {
                applyContentBlockingPolicyForCommittedPage(
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
        guard acceptsDelegateCallback(from: webView) else {
            return nil
        }
        let externalDisposition = ExternalNavigationPolicy.disposition(
            for: navigationAction.request.url,
            isLinkActivation: navigationAction.navigationType == .linkActivated,
            buttonNumber: navigationAction.buttonNumber,
            modifierFlags: navigationAction.modifierFlags,
            targetsTopLevelContext:
                navigationAction.targetFrame?.isMainFrame ?? true
        )
        if case let .open(url) = externalDisposition {
            openExternalURL(url)
            return nil
        }

        let disposition = NewContextNavigationPolicy.disposition(
            url: navigationAction.request.url,
            isLinkActivation: navigationAction.navigationType == .linkActivated,
            buttonNumber: navigationAction.buttonNumber,
            modifierFlags: navigationAction.modifierFlags,
            requestsNewContext: navigationAction.targetFrame == nil
        )
        if disposition == .foregroundTab || disposition == .backgroundTab {
            onOpenTab?(navigationAction.request, disposition)
        }
        return nil
    }

    func webView(
        _ webView: WKWebView,
        didStartProvisionalNavigation navigation: WKNavigation!
    ) {
        guard acceptsDelegateCallback(from: webView) else {
            return
        }
        bindContentBlockingNavigation(navigation)
        hideError()
        synchronizeObservedState(includeURL: false)
        webView.setAccessibilityValue("Loading")
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard acceptsDelegateCallback(from: webView) else {
            return
        }
        failedDocumentRecovery = nil
        committedURL = webView.url
        currentDocumentURL = webView.url
        if LocalFileAccessPolicy.refersToSameFile(
            webView.url,
            approvedLocalFileURL
        ) {
            approvedLocalFileURL = nil
        }
        applyContentBlockingPolicyForCommittedPage(
            mode: contentBlockingNavigationState.commit(navigation)
        )
        synchronizeObservedState()
    }

    func webView(
        _ webView: WKWebView,
        didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!
    ) {
        guard acceptsDelegateCallback(from: webView) else {
            return
        }
        bindContentBlockingRedirect(navigation)
        retryURL = webView.url
        guard prepareContentBlockingPolicyForNavigation(to: webView.url) else {
            webView.stopLoading()
            presentContentBlockingUnavailable()
            return
        }
        synchronizeObservedState()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard acceptsDelegateCallback(from: webView) else {
            return
        }
        synchronizeObservedState()
        webView.setAccessibilityValue("Ready")
        finishFirstNavigationIfNeeded(navigation)
        finishSubmittedNavigationIfNeeded(navigation)
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: any Error
    ) {
        guard acceptsDelegateCallback(from: webView) else {
            return
        }
        handleNavigationFailure(navigation: navigation, error: error, isProvisional: false)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: any Error
    ) {
        guard acceptsDelegateCallback(from: webView) else {
            return
        }
        handleNavigationFailure(navigation: navigation, error: error, isProvisional: true)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard acceptsDelegateCallback(from: webView) else {
            return
        }
        applyContentBlockingPolicyForCommittedPage(
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

    private func acceptsDelegateCallback(from webView: WKWebView) -> Bool {
        !isClosed && webView === self.webView
    }

    private enum LoadPurpose: Equatable {
        case firstBlank
        case submitted
        case background
    }

    @discardableResult
    private func load(
        _ request: URLRequest,
        purpose: LoadPurpose
    ) -> Bool {
        guard !isClosed, let url = request.url else {
            return false
        }

        if
            let approvedLocalFileURL,
            !LocalFileAccessPolicy.refersToSameFile(
                url,
                approvedLocalFileURL
            )
        {
            self.approvedLocalFileURL = nil
        }
        let localFileReadAccessURL: URL?
        if url.isFileURL {
            guard
                let authorization = localFileAuthorization(containing: url),
                LocalFileNavigationPolicy.allows(
                    targetURL: url,
                    sourceURL: currentDocumentURL,
                    readAccessURL: authorization.readAccessURL,
                    approvedURL: approvedLocalFileURL,
                    isMainFrame: true,
                    isBackForwardNavigation: false
                )
            else {
                return false
            }
            localFileReadAccessURL = authorization.readAccessURL
        } else {
            localFileReadAccessURL = nil
        }

        pendingNavigationURL = url
        retryURL = url
        observedURL = url
        hideError()

        guard let webView = realizeWebViewIfNeeded(for: url) else {
            if webViewFactory == nil {
                notifyStateChange()
                return true
            }
            presentContentBlockingUnavailable()
            return false
        }
        guard prepareContentBlockingPolicyForNavigation(to: url) else {
            presentContentBlockingUnavailable()
            return false
        }

        pendingNavigationURL = nil
        if purpose == .submitted {
            finishSubmittedNavigation(accessibilityValue: "Cancelled")
            submittedNavigationState = BrowserPerformanceSignposts.signposter
                .beginInterval("LocalFixtureNavigation")
        } else if purpose == .firstBlank {
            firstBlankNavigationState = BrowserPerformanceSignposts.signposter
                .beginInterval("FirstBlankNavigation")
        }

        beginContentBlockingNavigationRequest()
        let navigation: WKNavigation?
        if purpose == .submitted {
            navigation = BrowserPerformanceSignposts.signposter.withIntervalSignpost(
                "AddressSubmission"
            ) {
                if let localFileReadAccessURL {
                    webView.loadFileURL(
                        url,
                        allowingReadAccessTo: localFileReadAccessURL
                    )
                } else {
                    webView.load(request)
                }
            }
            submittedNavigation = navigation
        } else {
            if let localFileReadAccessURL {
                navigation = webView.loadFileURL(
                    url,
                    allowingReadAccessTo: localFileReadAccessURL
                )
            } else {
                navigation = webView.load(request)
            }
            if purpose == .firstBlank {
                firstBlankNavigation = navigation
            }
        }
        bindContentBlockingNavigation(navigation)
        if purpose == .submitted, navigation == nil {
            finishSubmittedNavigation(accessibilityValue: "Failed")
        } else if purpose == .firstBlank, navigation == nil {
            finishFirstBlankNavigation(accessibilityValue: "Failed")
        }
        notifyStateChange()
        return navigation != nil
    }

    private func realizeWebViewIfNeeded(
        for url: URL,
        measureInitialConstruction: Bool = false
    ) -> WKWebView? {
        if let webView {
            return webView
        }
        guard let webViewFactory else {
            return nil
        }

        let constructWebView = { [self] () -> WKWebView? in
            self.makeWebView(factory: webViewFactory, for: url)
        }
        let constructedWebView = measureInitialConstruction
            ? BrowserPerformanceSignposts.signposter.withIntervalSignpost(
                "InitialWebViewConstruction",
                around: constructWebView
            )
            : constructWebView()
        guard let newWebView = constructedWebView else {
            return nil
        }

        newWebView.translatesAutoresizingMaskIntoConstraints = false
        newWebView.navigationDelegate = self
        newWebView.uiDelegate = self
        newWebView.setAccessibilityLabel("Web page")
        newWebView.setAccessibilityValue("Loading")
        webView = newWebView
        beginObserving(newWebView)
        notifyStateChange()
        return newWebView
    }

    private func makeWebView(
        factory: WebViewFactory,
        for url: URL
    ) -> WKWebView? {
        if let contentBlockingCoordinator {
            let contentController = WKUserContentController()
            guard contentBlockingCoordinator.applyPolicy(
                to: contentController,
                for: url
            ) else {
                return nil
            }
            return factory.makeWebView(
                userContentController: contentController
            )
        }
        return factory.makeWebView()
    }

    private func beginObserving(_ webView: WKWebView) {
        observations = [
            webView.observe(\.url, options: [.initial, .new]) {
                [weak self, weak observed = webView] _, _ in
                Task { @MainActor [weak self, weak observed] in
                    guard let self, self.webView === observed else {
                        return
                    }
                    self.synchronizeObservedState()
                }
            },
            webView.observe(\.title, options: [.initial, .new]) {
                [weak self, weak observed = webView] _, _ in
                Task { @MainActor [weak self, weak observed] in
                    guard let self, self.webView === observed else {
                        return
                    }
                    self.synchronizeObservedState()
                }
            },
            webView.observe(\.estimatedProgress, options: [.initial, .new]) {
                [weak self, weak observed = webView] _, _ in
                Task { @MainActor [weak self, weak observed] in
                    guard let self, self.webView === observed else {
                        return
                    }
                    self.synchronizeObservedState()
                }
            },
            webView.observe(\.isLoading, options: [.initial, .new]) {
                [weak self, weak observed = webView] _, _ in
                Task { @MainActor [weak self, weak observed] in
                    guard let self, self.webView === observed else {
                        return
                    }
                    self.synchronizeObservedState()
                }
            },
            webView.observe(\.canGoBack, options: [.initial, .new]) {
                [weak self, weak observed = webView] _, _ in
                Task { @MainActor [weak self, weak observed] in
                    guard let self, self.webView === observed else {
                        return
                    }
                    self.synchronizeObservedState()
                }
            },
            webView.observe(\.canGoForward, options: [.initial, .new]) {
                [weak self, weak observed = webView] _, _ in
                Task { @MainActor [weak self, weak observed] in
                    guard let self, self.webView === observed else {
                        return
                    }
                    self.synchronizeObservedState()
                }
            },
        ]
    }

    private func synchronizeObservedState(includeURL: Bool = true) {
        guard let webView else {
            return
        }
        if includeURL {
            observedURL = webView.url
        }
        observedTitle = webView.title
        observedProgress = webView.estimatedProgress
        observedIsLoading = webView.isLoading
        observedCanGoBack = webView.canGoBack
        observedCanGoForward = webView.canGoForward
        notifyStateChange()
    }

    private func notifyStateChange() {
        guard !isClosed else {
            return
        }
        onStateChange?(self)
    }

    private func applyContentBlockingPolicy(
        for url: URL?,
        mode: ContentBlockingPolicyApplicationMode = .exact
    ) -> Bool {
        guard let contentBlockingCoordinator else {
            return true
        }
        guard let webView else {
            return false
        }
        return contentBlockingCoordinator.applyPolicy(
            to: webView.configuration.userContentController,
            for: url,
            mode: mode
        )
    }

    private func prepareContentBlockingPolicyForNavigation(to url: URL?) -> Bool {
        applyContentBlockingPolicy(for: url, mode: .strengthenOnly)
    }

    private func applyContentBlockingPolicyForCommittedPage(
        mode: ContentBlockingPolicyApplicationMode
    ) {
        guard mode != .none else {
            return
        }
        guard applyContentBlockingPolicy(for: committedURL, mode: mode) else {
            presentContentBlockingUnavailable()
            return
        }
    }

    private func beginContentBlockingNavigationRequest() {
        navigationActionGeneration &+= 1
        _ = contentBlockingNavigationState.beginRequest()
    }

    private func bindContentBlockingNavigation(_ navigation: WKNavigation?) {
        guard let navigation else {
            applyContentBlockingPolicyForCommittedPage(
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

    private func handleNavigationFailure(
        navigation: WKNavigation?,
        error: any Error,
        isProvisional: Bool
    ) {
        // A document rule can block a redirect before WebKit sends its
        // redirect callback. Its error then carries the original navigation
        // token and URL, while the final approved action is still unbound.
        // Keep protection intact and resolve only after WebKit becomes idle.
        let canSettleBlockedAction = isProvisional
            && (error as NSError).domain == "WebKitErrorDomain"
            && (error as NSError).code == 104
            && navigation.map {
                contentBlockingNavigationState.canSettleUnboundAction(after: $0)
            } == true
        let disposition = contentBlockingNavigationState.fail(navigation)
        guard case let .current(mode) = disposition else {
            if canSettleBlockedAction, let destination = retryURL {
                settleBlockedAction(destination: destination, error: error)
            }
            finishFirstNavigationIfNeeded(navigation, accessibilityValue: nil)
            finishSubmittedNavigationIfNeeded(navigation, accessibilityValue: nil)
            return
        }
        applyContentBlockingPolicyForCommittedPage(mode: mode)
        synchronizeObservedState()
        finishFirstNavigationIfNeeded(navigation, accessibilityValue: "Failed")
        finishSubmittedNavigationIfNeeded(navigation, accessibilityValue: "Failed")
        let nsError = error as NSError
        let failingURL = (nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL)
            ?? retryURL
        let presentation = BrowserErrorPresentation.from(
            error: error,
            attemptedURL: failingURL ?? webView?.url
        )
        show(presentation)
        if isProvisional, mode == .exact,
           let presentation, presentation.kind != .tlsFailure,
           let failingURL, ContentBlockerSite(url: failingURL) != nil
        {
            retryURL = failingURL
            failedDocumentRecovery = FailedDocumentRecovery(url: failingURL)
            notifyStateChange()
        }
    }

    private func settleBlockedAction(destination: URL, error: any Error) {
        let generation = navigationActionGeneration
        Task { @MainActor [weak self] in
            // Let queued navigation-start and loading-state callbacks run.
            await Task.yield()
            guard let self, !isClosed,
                  navigationActionGeneration == generation,
                  webView?.isLoading == false,
                  contentBlockingNavigationState.hasUnboundApprovedAction,
                  retryURL == destination,
                  ContentBlockerSite(url: destination) != nil
            else {
                return
            }
            applyContentBlockingPolicyForCommittedPage(
                mode: contentBlockingNavigationState.cancelLatest()
            )
            show(BrowserErrorPresentation.from(error: error, attemptedURL: destination))
            failedDocumentRecovery = FailedDocumentRecovery(url: destination)
            notifyStateChange()
        }
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

    private func presentContentBlockingUnavailable() {
        presentError(
            title: "Privacy Protection Unavailable",
            message: "Browser could not load a valid ad and tracker blocking ruleset. Navigation remains paused to avoid loading a page without the expected protection.",
            recoveryActionTitle: nil
        )
    }

    private func presentUnsupportedNavigation(url: URL?) {
        let scheme = url?.scheme?.lowercased()
        if scheme == "file" {
            presentError(
                title: "Local File Blocked",
                message: "Open local HTML from the address field or a bookmark, then approve its containing folder.",
                recoveryActionTitle: nil
            )
            return
        }
        presentError(
            title: "Unsupported Address",
            message: scheme.map {
                "Browser blocked the \($0) scheme. Only HTTP and HTTPS navigation is supported."
            } ?? "Browser blocked a navigation without a valid HTTP or HTTPS address.",
            recoveryActionTitle: nil
        )
    }

    private func openExternalURL(_ url: URL) {
        guard onOpenExternalURL?(url) == true else {
            presentError(
                title: "Magnet Link Not Opened",
                message: "Browser couldn’t open this magnet link. Make sure an application that handles magnet links is installed.",
                recoveryActionTitle: nil
            )
            return
        }
    }

    private func releaseLocalFileAccess() {
        for authorization in localFileAuthorizations {
            authorization.securityScopedURL
                .stopAccessingSecurityScopedResource()
        }
        localFileAuthorizations.removeAll()
        approvedLocalFileURL = nil
    }

    private func localFileAuthorization(
        containing fileURL: URL?
    ) -> LocalFileAuthorization? {
        guard let fileURL else {
            return nil
        }
        return localFileAuthorizations
            .filter {
                LocalFileAccessPolicy.contains(
                    fileURL,
                    in: $0.readAccessURL
                )
            }
            .max {
                $0.readAccessURL.pathComponents.count
                    < $1.readAccessURL.pathComponents.count
            }
    }

    private func removeLocalFileAuthorization(readAccessURL: URL) {
        guard let index = localFileAuthorizations.firstIndex(where: {
            LocalFileAccessPolicy.refersToSameFile(
                $0.readAccessURL,
                readAccessURL
            )
        }) else {
            return
        }
        let authorization = localFileAuthorizations.remove(at: index)
        authorization.securityScopedURL.stopAccessingSecurityScopedResource()
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

    private func hideError() {
        guard errorState != nil else {
            return
        }
        failedDocumentRecovery = nil
        errorState = nil
        notifyStateChange()
    }

    private static func sanitizedTitle(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let sanitized = String(
            value.unicodeScalars.filter {
                !CharacterSet.controlCharacters.contains($0)
            }
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        return String(sanitized.prefix(200))
    }
}
