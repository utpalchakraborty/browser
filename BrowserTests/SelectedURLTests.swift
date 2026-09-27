import AppKit
import WebKit
import XCTest
@testable import Browser

@MainActor
final class SelectedURLTests: XCTestCase {
    func testNativeSelectionMenuOpensForegroundTabAndPreservesSourceAndClipboard() async throws {
        let controller = BrowserWindowController()
        defer { controller.window?.close() }
        controller.installWebViews(
            profile: BrowserProfile(dataStoreIdentifier: UUID()), viewCount: 1,
            initialURL: Phase1Fixture.url("/phase2/page-a")
        )
        let source = try XCTUnwrap(controller.webView as? BrowserWebView)
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        controller.window?.makeFirstResponder(source)
        try await wait { source.url == Phase1Fixture.url("/phase2/page-a").absoluteURL && !source.isLoading }
        let sourceTabID = controller.selectedTabID
        let clipboardChangeCount = NSPasteboard.general.changeCount
        _ = try await source.evaluateJavaScript("""
            document.body.innerHTML = '<p id="selected">http://127.0.0.1:18765/<b>phase2/page-b</b></p>';
            const range = document.createRange();
            range.selectNodeContents(document.getElementById('selected'));
            window.getSelection().removeAllRanges();
            window.getSelection().addRange(range);
            """)
        let menu = try await selectionMenu(in: source)
        menu.update()
        let item = try XCTUnwrap(menu.items.first)
        XCTAssertTrue(item.isEnabled)
        XCTAssertEqual(item.title, "Open Selected URL in New Tab")
        XCTAssertEqual(item.representedObject as? URL, Phase1Fixture.url("/phase2/page-b").absoluteURL)
        XCTAssertEqual(NSPasteboard.general.changeCount, clipboardChangeCount)
        XCTAssertEqual(controller.tabCount, 1, "Showing the menu must not open a tab")

        // Changing the DOM after the menu opens must not replace its captured URL.
        _ = try await source.evaluateJavaScript("window.getSelection().removeAllRanges()")
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(item.action), to: item.target, from: item))
        XCTAssertEqual(controller.tabCount, 2)
        XCTAssertNotEqual(controller.selectedTabID, sourceTabID)
        let destination = try XCTUnwrap(controller.webView)
        try await wait { destination.url == Phase1Fixture.url("/phase2/page-b").absoluteURL && !destination.isLoading }
        XCTAssertEqual(source.url, Phase1Fixture.url("/phase2/page-a").absoluteURL)
        XCTAssertTrue(source.configuration.websiteDataStore === destination.configuration.websiteDataStore)
        XCTAssertEqual(NSPasteboard.general.changeCount, clipboardChangeCount)
        XCTAssertFalse(try XCTUnwrap(controller.window).isVisible)
    }

    func testNativeEditableSelectionAndClosedTabAction() async throws {
        let tab = TabController()
        defer { tab.close() }
        tab.installWebViewFactory(WebViewFactory(websiteDataStore: .nonPersistent()))
        XCTAssertTrue(tab.navigate(to: Phase1Fixture.url("/phase2/page-a")))
        let webView = try XCTUnwrap(tab.webView as? BrowserWebView)
        try await wait { !webView.isLoading && webView.url != nil }
        var openedURLs: [URL] = []
        tab.onOpenTab = { request, _ in
            if let url = request.url { openedURLs.append(url) }
        }
        _ = try await webView.evaluateJavaScript("""
            document.body.innerHTML = '<textarea>example.com/path</textarea>';
            document.querySelector('textarea').focus();
            document.querySelector('textarea').select();
            """)
        let menu = try await selectionMenu(in: webView)
        let item = try XCTUnwrap(menu.items.first)
        XCTAssertEqual(item.representedObject as? URL, URL(string: "https://example.com/path"))
        tab.close()
        _ = NSApp.sendAction(try XCTUnwrap(item.action), to: item.target, from: item)
        XCTAssertTrue(openedURLs.isEmpty)
    }

    func testOrdinaryTextAndNoSelectionLeaveNativeMenuIntact() async throws {
        let webView = WebViewFactory(websiteDataStore: .nonPersistent()).makeWebView()
        webView.onOpenSelectedURL = { _ in XCTFail("Unexpected navigation") }
        try await WebViewNavigationWaiter().load(Phase1Fixture.url("/phase2/page-a"), in: webView)
        for script in [
            "document.body.innerHTML = '<p>ordinary text</p>'; window.getSelection().selectAllChildren(document.body)",
            "window.getSelection().removeAllRanges()",
        ] {
            _ = try await webView.evaluateJavaScript(script)
            let menu = NSMenu()
            let copy = NSMenuItem(title: "Copy", action: nil, keyEquivalent: "")
            menu.addItem(copy)
            webView.willOpenMenu(menu, with: try event())
            XCTAssertEqual(menu.items, [copy])
        }
    }

    private func selectionMenu(in webView: BrowserWebView) async throws -> NSMenu {
        // WebKit updates its native Services selection asynchronously after DOM selection.
        var result: NSMenu?
        let contextEvent = try event()
        try await wait {
            let menu = NSMenu()
            webView.willOpenMenu(menu, with: contextEvent)
            if !menu.items.isEmpty { result = menu }
            return result != nil
        }
        return try XCTUnwrap(result)
    }

    private func event() throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(
            with: .rightMouseDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0,
            clickCount: 1, pressure: 1
        ))
    }

    private func wait(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(condition(), "Timed out waiting for native WebKit selection or navigation")
        if !condition() { throw WebViewTestError.loadDidNotStart }
    }
}
