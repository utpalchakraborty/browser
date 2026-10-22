import AppKit
import WebKit
import XCTest
@testable import Browser

@MainActor
final class WebKitConnectionResetTests: XCTestCase {
    func testMenuIsDisabledWithoutAProfileAndAfterWindowCloses() {
        let controller = BrowserWindowController()
        let item = controller.makeConnectionResetMenuItem()
        XCTAssertFalse(controller.validateMenuItem(item))
        XCTAssertTrue(item.target === controller)
        XCTAssertEqual(item.keyEquivalent, "")

        controller.installWebViews(
            profile: BrowserProfile(dataStoreIdentifier: UUID()), viewCount: 1,
            initialURL: URL(string: "about:blank")!
        )
        XCTAssertTrue(controller.validateMenuItem(item))
        controller.window?.close()
        XCTAssertFalse(controller.validateMenuItem(item))
    }

    func testResetReplacesNetworkProcessPreservingTabsHistoryAndPersistentData() async throws {
        let profile = BrowserProfile(dataStoreIdentifier: UUID())
        let controller = BrowserWindowController()
        defer { controller.window?.close() }
        controller.installWebViews(
            profile: profile, viewCount: 1, initialURL: url("/cookie/set")
        )
        let first = try XCTUnwrap(controller.webView)
        try await wait { first.url == self.url("/cookie/set") && !first.isLoading }
        _ = try await first.evaluateJavaScript("""
            localStorage.setItem('network-reset', 'retained');
            sessionStorage.setItem('network-reset', 'retained');
            document.body.innerHTML += '<input id="draft">';
            document.getElementById('draft').value = 'unsent text';
            """)
        let cookiesBefore = await profile.websiteDataStore.httpCookieStore.allCookies()
        XCTAssertEqual(cookiesBefore.first { $0.name == "phase1" }?.value, "persisted")
        XCTAssertEqual(cookiesBefore.first { $0.name == "phase1session" }?.value, "transient")

        controller.newTab(nil)
        try submit("/phase2/page-a", in: controller)
        let second = try XCTUnwrap(controller.webView)
        try await wait { second.url == self.url("/phase2/page-a") && !second.isLoading }
        try submit("/phase2/page-b", in: controller)
        try await wait { second.url == self.url("/phase2/page-b") && !second.isLoading }
        _ = try await second.evaluateJavaScript("window.resetSentinel = 'retained'")
        second.pageZoom = 1.25
        let tabIDs = controller.tabIDs
        let selectedID = controller.selectedTabID
        let backList = second.backForwardList.backList.map(\.url)
        XCTAssertFalse(backList.isEmpty)
        let oldPID = try networkProcessIdentifier(in: profile.websiteDataStore)
        XCTAssertGreaterThan(oldPID, 0)

        let item = controller.makeConnectionResetMenuItem()
        XCTAssertTrue(controller.validateMenuItem(item))
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(item.action), to: item.target, from: item))
        try await wait {
            guard let pid = try? self.networkProcessIdentifier(in: profile.websiteDataStore) else { return false }
            return pid > 0 && pid != oldPID
        }
        let newPID = try networkProcessIdentifier(in: profile.websiteDataStore)
        print("BROWSER_NETWORK_RESET old_pid=\(oldPID) new_pid=\(newPID)")
        XCTAssertEqual(controller.tabIDs, tabIDs)
        XCTAssertEqual(controller.selectedTabID, selectedID)
        XCTAssertTrue(controller.webView === second)
        XCTAssertEqual(second.backForwardList.backList.map(\.url), backList)
        XCTAssertEqual(second.pageZoom, 1.25)
        let sentinel = try await second.evaluateJavaScript("window.resetSentinel")
        XCTAssertEqual(sentinel as? String, "retained", "Reset must not reload loaded tabs")
        let draft = try await first.evaluateJavaScript("document.getElementById('draft').value")
        XCTAssertEqual(draft as? String, "unsent text")
        let sessionValue = try await first.evaluateJavaScript("sessionStorage.getItem('network-reset')")
        // WebKit may lose process-local sessions. Record that diagnostic, but
        // do not require the loss if a future WebKit version preserves them.
        print("BROWSER_NETWORK_RESET session_storage_survived=\(sessionValue as? String == "retained")")

        // An actual request in a new tab proves recovery, and exercises cookies
        // at the server rather than only checking the cookie-store API.
        controller.newTab(nil)
        try submit("/cookie/echo", in: controller)
        let third = try XCTUnwrap(controller.webView)
        try await wait { third.url == self.url("/cookie/echo") && !third.isLoading }
        let echoedCookies = try await third.evaluateJavaScript("document.body.textContent") as? String
        XCTAssertTrue(echoedCookies?.contains("phase1=persisted") == true)
        print("BROWSER_NETWORK_RESET session_cookie_survived=\(echoedCookies?.contains("phase1session=transient") == true)")
        let localValue = try await third.evaluateJavaScript("localStorage.getItem('network-reset')")
        XCTAssertEqual(localValue as? String, "retained")
        XCTAssertFalse(try XCTUnwrap(controller.window).isVisible)
    }

    func testResetDuringNewTabStartupAllowsQueuedLoadsAndReload() async throws {
        let controller = BrowserWindowController()
        defer { controller.window?.close() }
        controller.installWebViews(
            profile: BrowserProfile(dataStoreIdentifier: UUID()), viewCount: 2,
            initialURL: url("/phase2/page-a")
        )
        let views = controller.webViews
        XCTAssertEqual(views.count, 2)
        for view in views {
            XCTAssertTrue(view.isLoading)
            XCTAssertNil((view.navigationDelegate as? TabController)?.committedURL)
        }

        // Do not yield before reset: these initial requests are still queued.
        // Preceding the reset with stopLoading strands them indefinitely.
        controller.resetWebKitConnections(nil)
        try await wait { views.allSatisfy { $0.title == "Page A" && !$0.isLoading } }
        let selected = try XCTUnwrap(controller.webView)
        _ = try await selected.evaluateJavaScript("window.beforeReload = true")
        let reloadItem = NSMenuItem(
            title: "Reload", action: #selector(BrowserWindowController.reloadPage(_:)),
            keyEquivalent: "r"
        )
        XCTAssertTrue(controller.validateMenuItem(reloadItem))
        controller.reloadPage(nil)
        XCTAssertTrue(selected.isLoading)
        try await wait { !selected.isLoading }
        let wasReloaded = try await selected.evaluateJavaScript("window.beforeReload === undefined")
        XCTAssertEqual(wasReloaded as? Bool, true)
        XCTAssertEqual(selected.title, "Page A")
        XCTAssertFalse(try XCTUnwrap(controller.window).isVisible)
    }

    func testResetDuringNewTabStartupAllowsImmediateExplicitNavigation() async throws {
        let controller = BrowserWindowController()
        defer { controller.window?.close() }
        controller.installWebViews(
            profile: BrowserProfile(dataStoreIdentifier: UUID()), viewCount: 2,
            initialURL: url("/phase2/slow-response")
        )
        let first = try XCTUnwrap(controller.webView)
        XCTAssertTrue(first.isLoading)
        controller.resetWebKitConnections(nil)
        // A user can submit a new address without waiting for reset completion.
        try submit("/phase2/page-a", in: controller)
        controller.selectTab(id: controller.tabIDs[1])
        let second = try XCTUnwrap(controller.webView)
        try submit("/phase2/page-b", in: controller)
        try await wait {
            first.title == "Page A" && !first.isLoading
                && second.title == "Page B" && !second.isLoading
        }
        XCTAssertFalse(try XCTUnwrap(controller.window).isVisible)
    }

    func testResetInterruptsActiveResponsesAcrossTabsAndAllowsExplicitRetry() async throws {
        let controller = BrowserWindowController()
        defer { controller.window?.close() }
        controller.installWebViews(
            profile: BrowserProfile(dataStoreIdentifier: UUID()), viewCount: 2,
            initialURL: url("/phase2/slow-response")
        )
        let first = try XCTUnwrap(controller.webViews.first)
        let second = try XCTUnwrap(controller.webViews.last)
        try await wait { first.title == "Slow response" && second.title == "Slow response" }
        XCTAssertTrue(first.isLoading && second.isLoading)

        controller.resetWebKitConnections(nil)
        try await wait { !first.isLoading && !second.isLoading }
        for view in [first, second] {
            let body = try await view.evaluateJavaScript("document.body.textContent") as? String
            XCTAssertFalse(body?.contains("Slow response complete") == true)
        }
        try submit("/phase2/page-a", in: controller)
        try await wait { first.title == "Page A" && !first.isLoading }
        controller.selectTab(id: controller.tabIDs[1])
        try submit("/phase2/page-b", in: controller)
        try await wait { second.title == "Page B" && !second.isLoading }
        XCTAssertFalse(try XCTUnwrap(controller.window).isVisible)
    }

    private func url(_ path: String) -> URL {
        Phase1Fixture.url(path).absoluteURL
    }

    private func submit(_ path: String, in controller: BrowserWindowController) throws {
        let chrome = try XCTUnwrap(controller.window?.contentView as? BrowserChromeView)
        chrome.addressField.stringValue = url(path).absoluteString
        controller.submitAddress(nil)
    }

    private func networkProcessIdentifier(in store: WKWebsiteDataStore) throws -> pid_t {
        // Private introspection is confined to this integration test. Checking
        // the PID proves the command did more than reload or clear a cache.
        let selector = NSSelectorFromString("_networkProcessIdentifier")
        XCTAssertTrue(store.responds(to: selector))
        let implementation = try XCTUnwrap(store.method(for: selector))
        typealias Getter = @convention(c) (AnyObject, Selector) -> pid_t
        return unsafeBitCast(implementation, to: Getter.self)(store, selector)
    }

    private func wait(
        file: StaticString = #filePath, line: UInt = #line,
        _ condition: () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(10)
        while !condition(), Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(condition(), "Timed out waiting for network reset or navigation", file: file, line: line)
        if !condition() { throw WebViewTestError.loadDidNotStart }
    }
}
