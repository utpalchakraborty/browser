import AppKit
import WebKit
import XCTest
@testable import Browser

@MainActor
final class WebsiteDataPrivacyWindowControllerTests: XCTestCase {
    func testWindowExposesWebsiteDataAndBlockingResetControls() throws {
        let controller = makeController()
        let window = try XCTUnwrap(controller.window)
        let contentView = try XCTUnwrap(window.contentView)

        XCTAssertEqual(window.identifier?.rawValue, "BrowserPrivacyWindow")
        XCTAssertEqual(
            window.accessibilityIdentifier(),
            "BrowserPrivacyWindow"
        )
        XCTAssertFalse(window.isRestorable)
        XCTAssertGreaterThanOrEqual(window.contentMinSize.height, 720)
        XCTAssertNotNil(
            view(
                identified: "BrowserPrivacyExplanation",
                as: NSTextField.self,
                in: contentView
            )
        )
        XCTAssertNotNil(
            view(
                identified: "BrowserPrivacyDataList",
                as: NSTableView.self,
                in: contentView
            )
        )

        let resetExceptions = try XCTUnwrap(
            view(
                identified: "BrowserPrivacyResetSiteExceptionsButton",
                as: NSButton.self,
                in: contentView
            )
        )
        let deleteRules = try XCTUnwrap(
            view(
                identified: "BrowserPrivacyDeleteCompiledRulesButton",
                as: NSButton.self,
                in: contentView
            )
        )
        XCTAssertFalse(resetExceptions.isHidden)
        XCTAssertFalse(deleteRules.isHidden)
        XCTAssertFalse(resetExceptions.isEnabled)
        XCTAssertFalse(deleteRules.isEnabled)

        controller.onResetAllSiteExceptions = {}
        controller.onDeleteCompiledBlockingRules = {}
        controller.updateBlockingResetState(
            exceptionCount: 2,
            canResetCompiledArtifacts: true,
            isBusy: false,
            statusMessage: "Blocking reset is ready."
        )

        XCTAssertTrue(resetExceptions.isEnabled)
        XCTAssertTrue(deleteRules.isEnabled)
        let result = try XCTUnwrap(
            view(
                identified: "BrowserPrivacyBlockingResetResult",
                as: NSTextField.self,
                in: contentView
            )
        )
        XCTAssertEqual(result.stringValue, "Blocking reset is ready.")
        XCTAssertFalse(result.isHidden)

        controller.updateBlockingResetState(
            exceptionCount: 2,
            canResetCompiledArtifacts: true,
            isBusy: true,
            statusMessage: nil
        )
        XCTAssertFalse(resetExceptions.isEnabled)
        XCTAssertFalse(deleteRules.isEnabled)
        XCTAssertTrue(result.isHidden)
    }

    func testCookieValueRemainsMaskedAndUnsearchableUntilExplicitReveal() async throws {
        let dataStore = WKWebsiteDataStore.nonPersistent()
        let secret = "private-cookie-value"
        let cookie = try XCTUnwrap(
            HTTPCookie.cookies(
                withResponseHeaderFields: [
                    "Set-Cookie": "privacy-cookie=\(secret); Domain=.example.com; Path=/account; Max-Age=3600; HttpOnly; SameSite=Strict"
                ],
                for: try XCTUnwrap(
                    URL(string: "https://example.com/account")
                )
            ).first
        )
        await dataStore.httpCookieStore.setCookie(cookie)

        let controller = WebsiteDataPrivacyWindowController(
            dataController: WebsiteDataController(
                websiteDataStore: dataStore
            )
        )
        let contentView = try XCTUnwrap(controller.window?.contentView)
        let table = try XCTUnwrap(
            view(
                identified: "BrowserPrivacyDataList",
                as: NSTableView.self,
                in: contentView
            )
        )
        let status = try XCTUnwrap(
            view(
                identified: "BrowserPrivacyStatus",
                as: NSTextField.self,
                in: contentView
            )
        )

        controller.refresh()
        let snapshotDidLoad = await waitUntil {
            status.stringValue.contains("1 cookie")
                && table.numberOfRows == 2
        }
        XCTAssertTrue(
            snapshotDidLoad,
            "The privacy snapshot did not finish loading."
        )

        table.selectRowIndexes(
            IndexSet(integer: 1),
            byExtendingSelection: false
        )
        controller.tableViewSelectionDidChange(
            Notification(
                name: NSTableView.selectionDidChangeNotification,
                object: table
            )
        )

        let valueLabel = try XCTUnwrap(
            view(
                identified: "BrowserPrivacyCookieValue",
                as: NSTextField.self,
                in: contentView
            )
        )
        let revealButton = try XCTUnwrap(
            view(
                identified: "BrowserPrivacyRevealCookieButton",
                as: NSButton.self,
                in: contentView
            )
        )
        XCTAssertEqual(
            valueLabel.stringValue,
            WebsiteCookieSnapshot.maskedValue
        )
        XCTAssertNotEqual(valueLabel.accessibilityValue() as? String, secret)
        XCTAssertFalse(
            textFields(in: contentView).contains {
                $0.stringValue.contains(secret)
            }
        )

        revealButton.performClick(nil)
        XCTAssertEqual(valueLabel.stringValue, secret)
        XCTAssertEqual(valueLabel.accessibilityValue() as? String, secret)
        XCTAssertTrue(valueLabel.isSelectable)

        table.selectRowIndexes(
            IndexSet(integer: 0),
            byExtendingSelection: false
        )
        controller.tableViewSelectionDidChange(
            Notification(
                name: NSTableView.selectionDidChangeNotification,
                object: table
            )
        )
        XCTAssertEqual(
            valueLabel.stringValue,
            WebsiteCookieSnapshot.maskedValue
        )
        XCTAssertFalse(valueLabel.isSelectable)
        XCTAssertFalse(
            textFields(in: contentView).contains {
                $0.stringValue.contains(secret)
            }
        )

        table.selectRowIndexes(
            IndexSet(integer: 1),
            byExtendingSelection: false
        )
        controller.tableViewSelectionDidChange(
            Notification(
                name: NSTableView.selectionDidChangeNotification,
                object: table
            )
        )
        revealButton.performClick(nil)
        XCTAssertEqual(valueLabel.stringValue, secret)
        controller.windowWillClose(
            Notification(name: NSWindow.willCloseNotification)
        )
        XCTAssertEqual(
            valueLabel.stringValue,
            WebsiteCookieSnapshot.maskedValue
        )
        XCTAssertNotEqual(valueLabel.accessibilityValue() as? String, secret)

        let searchField = try XCTUnwrap(
            view(
                identified: "BrowserPrivacySearchField",
                as: NSSearchField.self,
                in: contentView
            )
        )
        searchField.stringValue = secret
        XCTAssertTrue(searchField.sendAction(searchField.action, to: searchField.target))
        XCTAssertEqual(table.numberOfRows, 0)
    }

    func testWebsiteDataAndBlockingOperationsDisableEachOther() async throws {
        let controller = makeController()
        let contentView = try XCTUnwrap(controller.window?.contentView)
        let refreshButton = try XCTUnwrap(
            view(
                identified: "BrowserPrivacyRefreshButton",
                as: NSButton.self,
                in: contentView
            )
        )
        let resetExceptions = try XCTUnwrap(
            view(
                identified: "BrowserPrivacyResetSiteExceptionsButton",
                as: NSButton.self,
                in: contentView
            )
        )
        let deleteRules = try XCTUnwrap(
            view(
                identified: "BrowserPrivacyDeleteCompiledRulesButton",
                as: NSButton.self,
                in: contentView
            )
        )

        controller.onResetAllSiteExceptions = {}
        controller.onDeleteCompiledBlockingRules = {}
        controller.updateBlockingResetState(
            exceptionCount: 1,
            canResetCompiledArtifacts: true,
            isBusy: false,
            statusMessage: nil
        )
        XCTAssertTrue(resetExceptions.isEnabled)
        XCTAssertTrue(deleteRules.isEnabled)

        controller.refresh()
        XCTAssertFalse(resetExceptions.isEnabled)
        XCTAssertFalse(deleteRules.isEnabled)
        let refreshDidFinish = await waitUntil { refreshButton.isEnabled }
        XCTAssertTrue(refreshDidFinish)
        XCTAssertTrue(resetExceptions.isEnabled)
        XCTAssertTrue(deleteRules.isEnabled)

        controller.updateBlockingResetState(
            exceptionCount: 1,
            canResetCompiledArtifacts: true,
            isBusy: true,
            statusMessage: nil
        )
        XCTAssertFalse(refreshButton.isEnabled)
        XCTAssertFalse(resetExceptions.isEnabled)
        XCTAssertFalse(deleteRules.isEnabled)
    }

    func testBlockingResetCallbacksRunOnlyAfterConfirmation() async throws {
        _ = NSApplication.shared
        let controller = makeController()
        let window = try XCTUnwrap(controller.window)
        let contentView = try XCTUnwrap(window.contentView)
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }

        var resetWasRequested = false
        controller.onResetAllSiteExceptions = {
            resetWasRequested = true
        }
        controller.updateBlockingResetState(
            exceptionCount: 1,
            canResetCompiledArtifacts: false,
            isBusy: false,
            statusMessage: nil
        )
        let resetButton = try XCTUnwrap(
            view(
                identified: "BrowserPrivacyResetSiteExceptionsButton",
                as: NSButton.self,
                in: contentView
            )
        )

        resetButton.performClick(nil)
        XCTAssertFalse(resetWasRequested)
        let confirmationDidAppear = await waitUntil {
            !window.sheets.isEmpty
        }
        XCTAssertTrue(
            confirmationDidAppear,
            "The destructive action did not present a confirmation sheet."
        )
        let sheet = try XCTUnwrap(window.sheets.first)
        let confirmButton = try XCTUnwrap(
            buttons(in: sheet.contentView).first {
                $0.title == "Reset Site Exceptions"
            }
        )
        confirmButton.performClick(nil)

        let callbackWasInvoked = await waitUntil { resetWasRequested }
        XCTAssertTrue(
            callbackWasInvoked,
            "The confirmed reset callback was not invoked."
        )
    }

    private func makeController() -> WebsiteDataPrivacyWindowController {
        WebsiteDataPrivacyWindowController(
            dataController: WebsiteDataController(
                websiteDataStore: .nonPersistent()
            )
        )
    }

    private func view<T: NSView>(
        identified identifier: String,
        as type: T.Type,
        in root: NSView
    ) -> T? {
        if root.accessibilityIdentifier() == identifier,
           let match = root as? T
        {
            return match
        }
        for subview in root.subviews {
            if let match = view(
                identified: identifier,
                as: type,
                in: subview
            ) {
                return match
            }
        }
        return nil
    }

    private func textFields(in root: NSView) -> [NSTextField] {
        var fields = root is NSTextField ? [root as! NSTextField] : []
        for subview in root.subviews {
            fields.append(contentsOf: textFields(in: subview))
        }
        return fields
    }

    private func buttons(in root: NSView?) -> [NSButton] {
        guard let root else {
            return []
        }
        var matches = root is NSButton ? [root as! NSButton] : []
        for subview in root.subviews {
            matches.append(contentsOf: buttons(in: subview))
        }
        return matches
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        for _ in 0..<100 {
            if condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }
}
