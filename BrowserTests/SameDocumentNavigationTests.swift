import AppKit
import WebKit
import XCTest
@testable import Browser

/// Same-document navigations produce no provisional or commit callbacks. They
/// must not leave a tab "navigating", which would disable the site toggle.
@MainActor
final class SameDocumentNavigationTests: XCTestCase {
    private static let anchorPage = """
        document.body.innerHTML = '<a id="toc" href="#section">Section</a>'
            + '<div style="height: 3000px"></div><h2 id="section">Section</h2>';
        true
        """

    func testRepeatedClickOnTheSameAnchorSettles() async throws {
        let tab = try await loadedTab()
        defer { tab.close() }
        let webView = try XCTUnwrap(tab.webView)
        _ = try await webView.evaluateJavaScript(Self.anchorPage)

        for click in 1...2 {
            _ = try await webView.evaluateJavaScript("document.getElementById('toc').click(); true")
            try await waitForWebKit { webView.url?.fragment == "section" }
            try await settle()
            XCTAssertFalse(tab.hasActiveNavigation, "Anchor click \(click) left the tab navigating.")
        }
    }

    func testHistoryAPIEntriesSettleForAnchorsBackAndForward() async throws {
        let tab = try await loadedTab()
        defer { tab.close() }
        let webView = try XCTUnwrap(tab.webView)
        _ = try await webView.evaluateJavaScript(Self.anchorPage)
        _ = try await webView.evaluateJavaScript("history.pushState({}, '', '/phase2/spa-route'); true")
        try await waitForWebKit { webView.url?.path == "/phase2/spa-route" }
        try await settle()
        XCTAssertFalse(tab.hasActiveNavigation)

        _ = try await webView.evaluateJavaScript("document.getElementById('toc').click(); true")
        try await waitForWebKit { webView.url?.fragment == "section" }
        try await settle()
        XCTAssertFalse(tab.hasActiveNavigation, "An anchor after pushState left the tab navigating.")

        for (step, expectedPath, move) in [
            ("first Back", "/phase2/spa-route", { tab.goBack() }),
            ("second Back", "/phase2/page-a", { tab.goBack() }),
            ("Forward", "/phase2/spa-route", { tab.goForward() }),
        ] as [(String, String, () -> Void)] {
            move()
            try await waitForWebKit { webView.url?.path == expectedPath && webView.url?.fragment == nil }
            try await settle()
            XCTAssertFalse(tab.hasActiveNavigation, "\(step) between history entries left the tab navigating.")
        }

        // A real navigation afterward still commits and resolves normally.
        let destination = Phase1Fixture.url("/phase2/page-b").absoluteURL
        XCTAssertTrue(tab.navigate(to: destination))
        try await waitForWebKit { tab.committedURL == destination && !webView.isLoading }
        try await settle()
        XCTAssertFalse(tab.hasActiveNavigation)
    }

    func testSiteToggleStaysAvailableAfterHistoryNavigationOnAPushStatePage() async throws {
        let page = Phase1Fixture.url("/phase2/page-a")
        let browser = try await HiddenBlockingBrowser.make(initialURL: page)
        defer { browser.cleanUp() }
        try await browser.waitForIdlePage(page)
        let webView = try XCTUnwrap(browser.controller.webView)
        let toggle = NSMenuItem(
            title: "",
            action: #selector(BrowserWindowController.toggleContentBlockingForCurrentSiteAndReload(_:)),
            keyEquivalent: ""
        )
        XCTAssertTrue(browser.controller.validateMenuItem(toggle))

        _ = try await webView.evaluateJavaScript("history.pushState({}, '', '/phase2/spa-route'); true")
        try await waitForWebKit { webView.url?.path == "/phase2/spa-route" }
        browser.tab?.goBack()
        try await waitForWebKit { webView.url?.path == "/phase2/page-a" }
        try await settle()

        XCTAssertEqual(browser.tab?.hasActiveNavigation, false)
        XCTAssertTrue(browser.controller.validateMenuItem(toggle))
        XCTAssertEqual(toggle.title, "Disable Blocking for 127.0.0.1 and Reload")
        XCTAssertFalse(try XCTUnwrap(browser.controller.window).isVisible)
    }

    private func loadedTab() async throws -> TabController {
        let tab = TabController()
        tab.installWebViewFactory(WebViewFactory(websiteDataStore: .nonPersistent()))
        let page = Phase1Fixture.url("/phase2/page-a").absoluteURL
        XCTAssertTrue(tab.navigate(to: page))
        try await waitForWebKit {
            tab.committedURL == page && tab.webView?.isLoading == false && !tab.hasActiveNavigation
        }
        return tab
    }

    /// Let queued KVO tasks and any late WebKit callbacks run.
    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(150))
    }
}
