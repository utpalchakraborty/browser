import AppKit
import WebKit
import XCTest
@testable import Browser

@MainActor
final class BrowserCloseCommandTests: XCTestCase {
    func testCommandWClosesSelectedTabAndRetainsNeighborStateFromAddressAndContent() throws {
        let browser = BrowserWindowController()
        defer { browser.close() }
        let window = try XCTUnwrap(browser.window)
        let chrome = try XCTUnwrap(window.contentView as? BrowserChromeView)
        let command = BrowserCloseCommand(browser: browser, keyWindow: { window })
        let menu = NSMenu(title: "File")
        let item = command.makeMenuItem()
        menu.addItem(item)
        chrome.addressField.stringValue = "https://retained.example/"
        browser.submitAddress(nil)
        let retained = browser.selectedTabID
        browser.newTab(nil)
        chrome.addressField.stringValue = "https://closed.example/"
        browser.submitAddress(nil)
        window.makeFirstResponder(chrome.addressField)
        menu.update()
        XCTAssertTrue(item.isEnabled)
        XCTAssertEqual(item.title, "Close Tab")
        XCTAssertTrue(try menu.performKeyEquivalent(with: commandW()))
        XCTAssertEqual(browser.tabIDs, [retained])
        XCTAssertEqual(browser.pendingNavigationURL?.absoluteString, "https://retained.example/")
        let content = CloseFixtureContentView()
        chrome.addSubview(content)
        XCTAssertTrue(window.makeFirstResponder(content))
        XCTAssertTrue(try menu.performKeyEquivalent(with: commandW()))
        XCTAssertEqual(browser.tabCount, 1)
        XCTAssertNotEqual(browser.selectedTabID, retained)
        XCTAssertNil(browser.pendingNavigationURL)
        XCTAssertFalse(window.isVisible)
    }

    func testCommandWClosesActualAuxiliaryWindowsWithoutTouchingBrowserTabs() throws {
        let browser = BrowserWindowController()
        defer { browser.close() }
        let chrome = try XCTUnwrap(browser.window?.contentView as? BrowserChromeView)
        chrome.addressField.stringValue = "https://retained.example/"
        browser.submitAddress(nil)
        browser.newTab(nil)
        chrome.addressField.stringValue = "https://selected.example/"
        browser.submitAddress(nil)
        let ids = browser.tabIDs
        let selected = browser.selectedTabID
        let bookmarks = BookmarkManagerWindowController()
        let privacy = WebsiteDataPrivacyWindowController(dataController: WebsiteDataController(websiteDataStore: .nonPersistent()))
        var active: NSWindow? = browser.window
        let command = BrowserCloseCommand(browser: browser, keyWindow: { active })
        let menu = NSMenu(title: "File")
        let item = command.makeMenuItem()
        menu.addItem(item)
        for controller in [bookmarks as NSWindowController, privacy] {
            let window = try XCTUnwrap(controller.window)
            let recorder = CloseFixtureDelegate()
            let originalDelegate = window.delegate
            window.delegate = recorder
            defer { window.delegate = originalDelegate; controller.close() }
            active = window
            menu.update()
            XCTAssertTrue(item.isEnabled)
            XCTAssertEqual(item.title, "Close Window")
            XCTAssertTrue(try menu.performKeyEquivalent(with: commandW()))
            XCTAssertEqual(recorder.closeRequests, 1)
            XCTAssertEqual(browser.tabIDs, ids)
            XCTAssertEqual(browser.selectedTabID, selected)
            XCTAssertEqual(browser.pendingNavigationURL?.absoluteString, "https://selected.example/")
            XCTAssertFalse(window.isVisible)
        }
        active = nil
        menu.update()
        XCTAssertFalse(item.isEnabled)
        _ = try menu.performKeyEquivalent(with: commandW()) // AppKit can consume a disabled key equivalent.
        XCTAssertEqual(browser.tabIDs, ids)
    }

    func testSheetsDisableMenuAndGuardAlreadyDispatchedActions() throws {
        let browser = BrowserWindowController()
        defer { browser.close() }
        browser.newTab(nil)
        let ids = browser.tabIDs
        let parent = CloseFixtureSheetWindow()
        let sheet = CloseFixtureSheetWindow()
        defer { parent.close(); sheet.close() }
        parent.fixtureAttachedSheet = sheet
        sheet.fixtureSheetParent = parent
        var active: NSWindow? = parent
        let command = BrowserCloseCommand(browser: browser, keyWindow: { active })
        let menu = NSMenu(title: "File")
        let item = command.makeMenuItem()
        menu.addItem(item)
        for window in [parent, sheet] {
            active = window
            menu.update()
            XCTAssertFalse(item.isEnabled)
            _ = try menu.performKeyEquivalent(with: commandW()) // AppKit can consume a disabled key equivalent.
            command.closeCurrentContent(nil)
            XCTAssertEqual(window.closeRequests, 0)
            XCTAssertEqual(browser.tabIDs, ids)
        }
        // A window's own cancellation/delegate remains authoritative.
        parent.fixtureAttachedSheet = nil
        active = parent
        let delegate = CloseFixtureDelegate()
        delegate.allowsClose = false
        parent.delegate = delegate
        menu.update()
        XCTAssertTrue(try menu.performKeyEquivalent(with: commandW()))
        XCTAssertEqual(delegate.closeRequests, 1)
        XCTAssertEqual(browser.tabIDs, ids)
        XCTAssertFalse(NSApp.windows.contains(where: \.isVisible))
    }

    private func commandW() throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: 0, windowNumber: 0, context: nil, characters: "w",
            charactersIgnoringModifiers: "w", isARepeat: false, keyCode: 13))
    }
}

@MainActor
private final class CloseFixtureContentView: NSView {
    override var acceptsFirstResponder: Bool { true }
}

@MainActor
private final class CloseFixtureDelegate: NSObject, NSWindowDelegate {
    var closeRequests = 0
    var allowsClose = true
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        closeRequests += 1
        return allowsClose
    }
}

@MainActor
private final class CloseFixtureSheetWindow: NSWindow {
    var fixtureAttachedSheet: NSWindow?
    weak var fixtureSheetParent: NSWindow?
    var closeRequests = 0
    override var attachedSheet: NSWindow? { fixtureAttachedSheet }
    override var sheetParent: NSWindow? { fixtureSheetParent }
    override func performClose(_ sender: Any?) { closeRequests += 1; super.performClose(sender) }
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                   styleMask: [.titled, .closable], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
    }
}
