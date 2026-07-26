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
final class BrowserWindowController: NSWindowController, WKNavigationDelegate {
    private(set) var webViews: [WKWebView] = []
    var webView: WKWebView? { webViews.first }
    private let contentRootView: NSView
    private var firstBlankNavigation: WKNavigation?
    private var firstBlankNavigationState: OSSignpostIntervalState?

    init() {
        contentRootView = NSView(frame: .zero)
        contentRootView.setAccessibilityIdentifier("BrowserNativeShell")

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
        window.backgroundColor = .white
        Self.setAccessibilityIdentifier(
            "BrowserMainWindow",
            on: window
        )
        window.contentView = contentRootView

        super.init(window: window)
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
            WKWebView(
                frame: .zero,
                configuration: profile.makeWebViewConfiguration()
            )
        }

        newWebView.setAccessibilityIdentifier("BrowserInitialWebViewLoading")
        newWebView.navigationDelegate = self
        newWebView.frame = contentRootView.bounds
        newWebView.autoresizingMask = [.width, .height]
        contentRootView.addSubview(newWebView)
        webViews.append(newWebView)
        firstBlankNavigationState =
            BrowserPerformanceSignposts.signposter.beginInterval(
                "FirstBlankNavigation"
            )
        firstBlankNavigation = newWebView.load(
            URLRequest(url: initialURL)
        )

        if firstBlankNavigation == nil {
            finishFirstBlankNavigation(
                accessibilityIdentifier: "BrowserInitialWebViewFailed"
            )
        }

        for _ in 1..<max(1, viewCount) {
            let backgroundWebView = WKWebView(
                frame: .zero,
                configuration: profile.makeWebViewConfiguration()
            )
            backgroundWebView.navigationDelegate = self
            backgroundWebView.frame = contentRootView.bounds
            backgroundWebView.autoresizingMask = [.width, .height]
            backgroundWebView.isHidden = true
            contentRootView.addSubview(
                backgroundWebView,
                positioned: .below,
                relativeTo: newWebView
            )
            webViews.append(backgroundWebView)
            backgroundWebView.load(URLRequest(url: initialURL))
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard navigation === firstBlankNavigation else {
            return
        }
        finishFirstBlankNavigation(accessibilityIdentifier: "BrowserInitialWebViewReady")
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: any Error
    ) {
        guard navigation === firstBlankNavigation else {
            return
        }
        finishFirstBlankNavigation(accessibilityIdentifier: "BrowserInitialWebViewFailed")
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: any Error
    ) {
        guard navigation === firstBlankNavigation else {
            return
        }
        finishFirstBlankNavigation(accessibilityIdentifier: "BrowserInitialWebViewFailed")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard webView === self.webView else {
            return
        }
        finishFirstBlankNavigation(accessibilityIdentifier: "BrowserInitialWebViewFailed")
    }

    private func finishFirstBlankNavigation(
        accessibilityIdentifier: String
    ) {
        guard let state = firstBlankNavigationState else {
            return
        }

        BrowserPerformanceSignposts.signposter.endInterval(
            "FirstBlankNavigation",
            state
        )
        firstBlankNavigation = nil
        firstBlankNavigationState = nil
        webView?.setAccessibilityIdentifier(accessibilityIdentifier)
    }

    private static func setAccessibilityIdentifier(
        _ identifier: String,
        on window: NSWindow
    ) {
        window.identifier = NSUserInterfaceItemIdentifier(identifier)
        window.setAccessibilityIdentifier(identifier)
    }
}
