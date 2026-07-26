import AppKit
import XCTest
@testable import Browser

@MainActor
final class BrowserWindowControllerTests: XCTestCase {
    func testInitialStateExposesNativeShellWithoutConstructingWebView() {
        let controller = BrowserWindowController()

        XCTAssertNil(controller.webView)
        XCTAssertEqual(
            controller.window?.identifier?.rawValue,
            "BrowserMainWindow"
        )
        XCTAssertEqual(
            controller.window?.accessibilityIdentifier(),
            "BrowserMainWindow"
        )
        XCTAssertEqual(
            controller.window?.contentView?.accessibilityIdentifier(),
            "BrowserNativeShell"
        )
        XCTAssertFalse(controller.window?.isRestorable ?? true)
        XCTAssertEqual(
            controller.window?.contentMinSize,
            NSSize(width: 420, height: 300)
        )
        XCTAssertNotNil(controller.window?.initialFirstResponder)
    }

    func testApplicationStateRestorationIsDisabled() {
        let delegate = AppDelegate()

        XCTAssertFalse(
            delegate.applicationShouldSaveApplicationState(.shared)
        )
        XCTAssertFalse(
            delegate.applicationShouldRestoreApplicationState(.shared)
        )
    }

    func testWindowFrameAutosaveRestoresOnlyGeometry() throws {
        let autosaveName: NSWindow.FrameAutosaveName =
            "BrowserWindowControllerTests.\(UUID().uuidString)"
        var autosaveWindows: [NSWindow] = []
        defer {
            autosaveWindows.forEach {
                _ = $0.setFrameAutosaveName("")
            }
            NSWindow.removeFrame(usingName: autosaveName)
        }

        let firstController = BrowserWindowController(
            frameAutosaveName: autosaveName
        )
        let firstWindow = try XCTUnwrap(firstController.window)
        autosaveWindows.append(firstWindow)
        var savedFrame = firstWindow.frame
        savedFrame.size.width -= 120
        savedFrame.size.height -= 80
        savedFrame.origin.x += 40
        savedFrame.origin.y += 20
        savedFrame = firstWindow.constrainFrameRect(
            savedFrame,
            to: firstWindow.screen
        )
        firstWindow.setFrame(savedFrame, display: false)
        firstWindow.saveFrame(usingName: autosaveName)
        _ = firstWindow.setFrameAutosaveName("")

        let restoredController = BrowserWindowController(
            frameAutosaveName: autosaveName
        )
        let restoredWindow = try XCTUnwrap(restoredController.window)
        autosaveWindows.append(restoredWindow)

        XCTAssertEqual(restoredController.windowFrameAutosaveName, autosaveName)
        XCTAssertEqual(restoredWindow.frameAutosaveName, autosaveName)
        XCTAssertEqual(
            restoredWindow.frame.origin.x,
            savedFrame.origin.x,
            accuracy: 1
        )
        XCTAssertEqual(
            restoredWindow.frame.origin.y,
            savedFrame.origin.y,
            accuracy: 1
        )
        XCTAssertEqual(
            restoredWindow.frame.width,
            savedFrame.width,
            accuracy: 1
        )
        XCTAssertEqual(
            restoredWindow.frame.height,
            savedFrame.height,
            accuracy: 1
        )
        XCTAssertFalse(restoredWindow.isRestorable)
        XCTAssertNil(restoredController.webView)
    }

    func testWindowFrameAutosaveNameIsolatedByLaunchMode() {
        XCTAssertEqual(
            AppDelegate.windowFrameAutosaveName(arguments: ["Browser"]),
            BrowserWindowController.mainWindowFrameAutosaveName
        )
        XCTAssertEqual(
            AppDelegate.windowFrameAutosaveName(
                arguments: [
                    "Browser",
                    "--ui-test-profile",
                    "-ApplePersistenceIgnoreState",
                    "YES",
                ]
            ),
            BrowserWindowController.uiTestWindowFrameAutosaveName
        )
        XCTAssertNil(
            AppDelegate.windowFrameAutosaveName(
                arguments: ["Browser", "--performance-test"]
            )
        )
        XCTAssertNil(
            AppDelegate.windowFrameAutosaveName(
                arguments: [
                    "Browser",
                    "-ApplePersistenceIgnoreState",
                    "YES",
                ]
            )
        )
    }

    func testHiddenWindowDoesNotConstructWebView() {
        let controller = BrowserWindowController()
        let profile = BrowserProfile(dataStoreIdentifier: UUID())

        controller.startWebView(profile: profile)

        XCTAssertNil(controller.webView)
    }

    func testRepeatedInitialFocusDoesNotReselectTypedText() throws {
        let controller = BrowserWindowController()
        let window = try XCTUnwrap(controller.window)
        let chromeView = try XCTUnwrap(
            window.contentView as? BrowserChromeView
        )
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }

        controller.ensureInitialAddressFieldFocus()
        let editor = try XCTUnwrap(chromeView.addressField.currentEditor())
        editor.string = "focus-probe"
        editor.selectedRange = NSRange(location: 1, length: 0)

        controller.ensureInitialAddressFieldFocus()

        XCTAssertEqual(editor.string, "focus-probe")
        XCTAssertEqual(editor.selectedRange, NSRange(location: 1, length: 0))
    }

    func testPerformanceViewCountIsBoundedAndRequiresPerformanceMode() {
        XCTAssertEqual(
            AppDelegate.performanceViewCount(arguments: ["Browser"]),
            1
        )
        XCTAssertEqual(
            AppDelegate.performanceViewCount(
                arguments: [
                    "Browser",
                    "--performance-test",
                    "--performance-view-count",
                    "10",
                ]
            ),
            10
        )
        XCTAssertEqual(
            AppDelegate.performanceViewCount(
                arguments: [
                    "Browser",
                    "--performance-test",
                    "--performance-view-count",
                    "11",
                ]
            ),
            1
        )
    }

    func testPerformanceFixtureURLIsRestrictedToLocalHTTP() {
        let prefix = ["Browser", "--performance-test", "--performance-fixture-url"]

        XCTAssertEqual(
            AppDelegate.performanceFixtureURL(
                arguments: prefix + ["http://127.0.0.1:18765/normal/"]
            )?.absoluteString,
            "http://127.0.0.1:18765/normal/"
        )
        XCTAssertNil(
            AppDelegate.performanceFixtureURL(
                arguments: prefix + ["https://example.com/"]
            )
        )
        XCTAssertNil(
            AppDelegate.performanceFixtureURL(
                arguments: [
                    "Browser",
                    "--performance-fixture-url",
                    "http://127.0.0.1:18765/normal/",
                ]
            )
        )
    }
}
