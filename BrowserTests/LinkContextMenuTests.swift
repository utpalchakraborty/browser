import AppKit
import WebKit
import XCTest
@testable import Browser

/// Drives `willOpenMenu` with WebKit's stock identifiers; a real context menu
/// cannot be opened from a background test.
@MainActor
final class LinkContextMenuTests: XCTestCase {
    private static let stockItems = [
        ("Open Link in New Window", "WKMenuItemIdentifierOpenLinkInNewWindow"),
        ("Download Linked File", "WKMenuItemIdentifierDownloadLinkedFile"),
        ("Copy Link", "WKMenuItemIdentifierCopyLink"),
        ("", "separator"),
        ("Open Image in New Window", "WKMenuItemIdentifierOpenImageInNewWindow"),
        ("Download Image", "WKMenuItemIdentifierDownloadImage"),
        ("", "separator"),
        ("Copy Image", "WKMenuItemIdentifierCopyImage"),
    ]

    func testLinkItemOpensBackgroundTabAndDeadStockItemsAreRemoved() async throws {
        let fixture = try await makePage()
        defer { fixture.controller.window?.close() }
        let destination = Phase1Fixture.url("/phase2/page-b").absoluteURL

        for zoom in [1.0, 1.5] {
            fixture.webView.pageZoom = zoom
            let menu = stockMenu()
            fixture.webView.willOpenMenu(menu, with: try await event(over: "real", in: fixture.webView))
            XCTAssertEqual(
                menu.items.map { $0.identifier?.rawValue ?? ($0.isSeparatorItem ? "separator" : $0.title) },
                [BrowserWebView.openLinkInNewTabIdentifier.rawValue,
                 "WKMenuItemIdentifierCopyLink", "separator", "WKMenuItemIdentifierCopyImage"],
                "zoom \(zoom)"
            )
            let item = try XCTUnwrap(menu.items.first)
            XCTAssertEqual(item.title, "Open Link in New Tab")
            try await waitForWebKit { item.representedObject as? URL == destination }
        }

        let menu = stockMenu()
        fixture.webView.willOpenMenu(menu, with: try await event(over: "real", in: fixture.webView))
        let item = try XCTUnwrap(menu.items.first)
        try await waitForWebKit { item.representedObject as? URL == destination }
        let source = fixture.controller.selectedTabID
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(item.action), to: item.target, from: item))
        XCTAssertEqual(fixture.controller.tabCount, 2)
        XCTAssertEqual(fixture.controller.selectedTabID, source, "Open Link in New Tab must not switch tabs.")
        let opened = try XCTUnwrap(fixture.controller.webViews.last)
        try await waitForWebKit { opened.url == destination && !opened.isLoading }
        XCTAssertFalse(try XCTUnwrap(fixture.controller.window).isVisible)
    }

    func testPageScriptsCannotRedirectTheResolvedLink() async throws {
        let fixture = try await makePage()
        defer { fixture.controller.window?.close() }
        _ = try await fixture.webView.evaluateJavaScript("""
            const decoy = document.getElementById('decoy');
            document.elementFromPoint = () => decoy;
            Element.prototype.closest = function () { return decoy; };
            true
            """)
        let menu = stockMenu()
        fixture.webView.willOpenMenu(menu, with: try await event(over: "real", in: fixture.webView))
        let item = try XCTUnwrap(menu.items.first)
        try await waitForWebKit { item.representedObject != nil }
        XCTAssertEqual(item.representedObject as? URL, Phase1Fixture.url("/phase2/page-b").absoluteURL)
    }

    func testUnresolvableLinksRemoveTheItemInsteadOfLeavingItDead() async throws {
        let fixture = try await makePage()
        defer { fixture.controller.window?.close() }
        for target in ["script", "blank"] {
            let menu = stockMenu()
            fixture.webView.willOpenMenu(menu, with: try await event(over: target, in: fixture.webView))
            try await waitForWebKit {
                !menu.items.contains { $0.identifier == BrowserWebView.openLinkInNewTabIdentifier }
            }
            XCTAssertEqual(
                menu.items.compactMap(\.identifier?.rawValue),
                ["WKMenuItemIdentifierCopyLink", "WKMenuItemIdentifierCopyImage"],
                target
            )
            XCTAssertFalse(menu.items.first?.isSeparatorItem ?? false)
            XCTAssertFalse(menu.items.last?.isSeparatorItem ?? false)
        }
        XCTAssertEqual(fixture.controller.tabCount, 1)
    }

    private struct Fixture {
        let controller: BrowserWindowController
        let webView: BrowserWebView
    }

    private func makePage() async throws -> Fixture {
        let controller = BrowserWindowController()
        let page = Phase1Fixture.url("/phase2/page-a").absoluteURL
        controller.installWebViews(
            profile: BrowserProfile(dataStoreIdentifier: UUID()), viewCount: 1, initialURL: page
        )
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        let webView = try XCTUnwrap(controller.webView as? BrowserWebView)
        try await waitForWebKit { webView.url == page && !webView.isLoading }
        _ = try await webView.evaluateJavaScript("""
            document.body.style.margin = '0';
            document.body.innerHTML =
                '<a id="real" href="/phase2/page-b" style="position:absolute;left:20px;top:20px;width:160px;height:30px">Real</a>'
                + '<a id="decoy" href="http://127.0.0.1:18765/phase2/redirect" style="position:absolute;left:20px;top:80px">Decoy</a>'
                + '<a id="script" href="javascript:void(0)" style="position:absolute;left:20px;top:140px;width:160px;height:30px">Script</a>'
                + '<p id="blank" style="position:absolute;left:20px;top:200px;width:160px;height:30px">Text</p>';
            true
            """)
        return Fixture(controller: controller, webView: webView)
    }

    private func stockMenu() -> NSMenu {
        let menu = NSMenu()
        for (title, identifier) in Self.stockItems {
            if identifier == "separator" {
                menu.addItem(.separator())
            } else {
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.identifier = NSUserInterfaceItemIdentifier(identifier)
                menu.addItem(item)
            }
        }
        return menu
    }

    /// A secondary click at the center of an element, in window coordinates.
    private func event(over elementID: String, in webView: BrowserWebView) async throws -> NSEvent {
        let center = try await webView.evaluateJavaScript("""
            (() => {
                const r = document.getElementById('\(elementID)').getBoundingClientRect();
                return [r.left + r.width / 2, r.top + r.height / 2];
            })()
            """)
        let rect = try XCTUnwrap(center as? [Double])
        let zoom = webView.pageZoom
        let viewPoint = NSPoint(
            x: rect[0] * zoom,
            y: webView.isFlipped ? rect[1] * zoom : webView.bounds.height - rect[1] * zoom
        )
        return try XCTUnwrap(NSEvent.mouseEvent(
            with: .rightMouseDown, location: webView.convert(viewPoint, to: nil),
            modifierFlags: [], timestamp: 0, windowNumber: webView.window?.windowNumber ?? 0,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
    }
}
