import AppKit
import WebKit
import XCTest
@testable import Browser

@MainActor
final class BrowserCommandRoutingTests: XCTestCase {
    func testPageShortcutsDoNothingWhileAnAuxiliaryWindowIsKey() async throws {
        let auxiliary = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.titled, .closable], backing: .buffered, defer: true
        )
        auxiliary.isReleasedWhenClosed = false
        defer { auxiliary.close() }
        var keyWindow: NSWindow? = auxiliary
        let page = Phase1Fixture.url("/phase2/page-a")
        let browser = try await HiddenBlockingBrowser.make(initialURL: page) { keyWindow }
        defer { browser.cleanUp() }
        try await browser.waitForIdlePage(page)
        let webView = try XCTUnwrap(browser.controller.webView)
        let tab = try XCTUnwrap(browser.tab)
        webView.pageZoom = 1.25

        let menu = NSMenu(title: "Commands")
        let reload = menu.addItem(withTitle: "Reload", action: #selector(BrowserWindowController.reloadPage(_:)), keyEquivalent: "r")
        let zoomIn = menu.addItem(withTitle: "Zoom In", action: #selector(BrowserWindowController.zoomIn(_:)), keyEquivalent: "+")
        let actualSize = menu.addItem(withTitle: "Actual Size", action: #selector(BrowserWindowController.resetPageZoom(_:)), keyEquivalent: "0")
        let location = menu.addItem(withTitle: "Open Location", action: #selector(BrowserWindowController.focusAddressField(_:)), keyEquivalent: "l")
        let websiteData = menu.addItem(withTitle: "Manage Website Data", action: #selector(BrowserWindowController.showWebsiteData(_:)), keyEquivalent: "")
        for item in menu.items { item.target = browser.controller }

        for item in [reload, zoomIn, actualSize, location] {
            XCTAssertFalse(browser.controller.validateMenuItem(item), item.title)
        }
        _ = menu.performKeyEquivalent(with: try commandKey("r", keyCode: 15))
        _ = menu.performKeyEquivalent(with: try commandKey("0", keyCode: 29))
        XCTAssertFalse(tab.hasActiveNavigation, "Command-R reloaded a page behind the key window.")
        XCTAssertEqual(webView.pageZoom, 1.25, "Command-0 zoomed a page behind the key window.")
        // Commands that open other windows are unaffected by this gate.
        browser.controller.startWebsiteDataManagement(
            controller: WebsiteDataController(websiteDataStore: .nonPersistent())
        )
        XCTAssertTrue(browser.controller.validateMenuItem(websiteData))

        for owner in [browser.controller.window, nil] {
            keyWindow = owner
            for item in [reload, zoomIn, actualSize, location] {
                XCTAssertTrue(browser.controller.validateMenuItem(item), item.title)
            }
        }
        keyWindow = browser.controller.window
        XCTAssertTrue(menu.performKeyEquivalent(with: try commandKey("r", keyCode: 15)))
        XCTAssertTrue(tab.hasActiveNavigation, "Command-R must reload when the browser window is key.")
        XCTAssertFalse(try XCTUnwrap(browser.controller.window).isVisible)
    }

    func testSiteToggleKeepsPrivacyBusyWhileCompiledRulesAreDeleted() async throws {
        let page = Phase1Fixture.url("/phase2/page-a")
        let browser = try await HiddenBlockingBrowser.make(initialURL: page)
        defer { browser.cleanUp() }
        try await browser.waitForIdlePage(page)
        browser.controller.startWebsiteDataManagement(
            controller: WebsiteDataController(websiteDataStore: .nonPersistent())
        )
        let privacy = browser.controller.websiteDataPrivacyManager()
        let content = try XCTUnwrap(privacy.window?.contentView)
        let refresh = try XCTUnwrap(control("BrowserPrivacyRefreshButton", as: NSButton.self, in: content))
        let resetExceptions = try XCTUnwrap(
            control("BrowserPrivacyResetSiteExceptionsButton", as: NSButton.self, in: content)
        )
        let result = try XCTUnwrap(control("BrowserPrivacyBlockingResetResult", as: NSTextField.self, in: content))

        // The reset task starts on the next main-actor turn, so the toggle below
        // runs while it is in flight.
        privacy.onDeleteCompiledBlockingRules?()
        XCTAssertFalse(refresh.isEnabled)
        browser.controller.toggleContentBlockingForCurrentSiteAndReload(nil)
        XCTAssertTrue(browser.coordinator.snapshot(for: page).isException)
        XCTAssertFalse(refresh.isEnabled, "A site toggle re-enabled Privacy controls mid-reset.")
        XCTAssertFalse(resetExceptions.isEnabled)
        XCTAssertEqual(result.stringValue, "Deleting compiled blocking rules…")

        try await waitForWebKit { result.stringValue.contains("deleted") && refresh.isEnabled }
        XCTAssertTrue(refresh.isEnabled)
        XCTAssertTrue(resetExceptions.isEnabled)
        XCTAssertFalse(try XCTUnwrap(privacy.window).isVisible)
    }

    private func commandKey(_ character: String, keyCode: UInt16) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
            windowNumber: 0, context: nil, characters: character,
            charactersIgnoringModifiers: character, isARepeat: false, keyCode: keyCode
        ))
    }

    private func control<T: NSView>(_ identifier: String, as type: T.Type, in view: NSView) -> T? {
        if view.accessibilityIdentifier() == identifier, let match = view as? T {
            return match
        }
        for subview in view.subviews {
            if let match = control(identifier, as: type, in: subview) {
                return match
            }
        }
        return nil
    }
}
