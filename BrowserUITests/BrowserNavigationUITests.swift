import Foundation
import XCTest

@MainActor
final class BrowserNavigationUITests: XCTestCase {
    private static let fixtureOrigin = "http://127.0.0.1:18765"
    private static let recoveryOrigin = "http://127.0.0.1:18769"

    private var application: XCUIApplication!

    func testLaunchFocusAndAddressSubmission() throws {
        launchApplication()
        defer { application.terminate() }
        try assertAddressFieldIsFocused()
        assertCriticalControlsExist()

        navigate(to: "/phase2/page-a")

        XCTAssertTrue(
            pageText("Phase 2 Page A").waitForExistence(timeout: 5),
            "Submitting a local HTTP URL did not render Page A."
        )
        waitForAddress(fixtureURL("/phase2/page-a"))
    }

    func testRedirectDisplaysFinalURL() {
        launchApplication()
        defer { application.terminate() }
        submit(fixtureURL("/phase2/redirect"))

        XCTAssertTrue(
            pageText("Phase 2 Page B").waitForExistence(timeout: 5),
            "The redirect did not render its destination."
        )
        waitForAddress(fixtureURL("/phase2/page-b"))
    }

    func testTitleOpenLocationShortcutAndUnsupportedSchemePolicy() {
        launchApplication()
        defer { application.terminate() }
        navigate(to: "/phase2/page-a")
        XCTAssertTrue(pageText("Phase 2 Page A").waitForExistence(timeout: 5))
        waitForWindowTitle("Page A — Browser")

        application.typeKey("l", modifierFlags: .command)
        let unsupportedAddress = "mailto:user@example.com"
        addressField.typeText(unsupportedAddress)
        XCTAssertEqual(addressField.value as? String, unsupportedAddress)
        addressField.typeKey(.return, modifierFlags: [])

        XCTAssertTrue(
            errorView.waitForExistence(timeout: 5),
            "An unsupported top-level scheme did not fail visibly."
        )
        XCTAssertTrue(pageText("Unsupported Address").exists)
    }

    func testBackAndForwardFollowWebKitState() {
        launchApplication()
        defer { application.terminate() }
        navigate(to: "/phase2/page-a")
        XCTAssertTrue(pageText("Phase 2 Page A").waitForExistence(timeout: 5))
        navigate(to: "/phase2/page-b")
        XCTAssertTrue(pageText("Phase 2 Page B").waitForExistence(timeout: 5))

        waitUntilEnabled(backButton)
        backButton.click()
        XCTAssertTrue(pageText("Phase 2 Page A").waitForExistence(timeout: 5))
        waitForAddress(fixtureURL("/phase2/page-a"))

        waitUntilEnabled(forwardButton)
        forwardButton.click()
        XCTAssertTrue(pageText("Phase 2 Page B").waitForExistence(timeout: 5))
        waitForAddress(fixtureURL("/phase2/page-b"))

        application.typeKey("[", modifierFlags: .command)
        XCTAssertTrue(pageText("Phase 2 Page A").waitForExistence(timeout: 5))
        application.typeKey("]", modifierFlags: .command)
        XCTAssertTrue(pageText("Phase 2 Page B").waitForExistence(timeout: 5))
    }

    func testReloadRequestsThePageAgain() throws {
        launchApplication()
        defer { application.terminate() }
        try requestFixture("/phase2/reload-reset")
        navigate(to: "/phase2/reload-count")
        XCTAssertTrue(pageText("Reload count 1").waitForExistence(timeout: 5))

        waitForButtonLabel(reloadStopButton, containing: "Reload")
        reloadStopButton.click()

        XCTAssertTrue(
            pageText("Reload count 2").waitForExistence(timeout: 5),
            "Reload did not issue a second request to the fixture."
        )

        application.typeKey("r", modifierFlags: .command)
        XCTAssertTrue(
            pageText("Reload count 3").waitForExistence(timeout: 5),
            "Command-R did not reload the page."
        )
    }

    func testProgressAndStopCancelSlowNavigation() {
        launchApplication()
        defer { application.terminate() }
        submit(fixtureURL("/phase2/slow-response"))

        XCTAssertTrue(
            progressIndicator.waitForExistence(timeout: 3),
            "A bounded slow load never exposed progress."
        )
        waitForButtonLabel(reloadStopButton, containing: "Stop")
        application.typeKey(".", modifierFlags: .command)

        waitForButtonLabel(reloadStopButton, containing: "Reload")
        XCTAssertTrue(
            progressIndicator.waitForNonExistence(timeout: 3),
            "Progress remained visible after stopping navigation."
        )
        XCTAssertFalse(
            pageText("Slow response complete").waitForExistence(timeout: 4.5),
            "The page completed even though Stop was invoked."
        )
    }

    func testVisibleConnectionErrorCanRetry() throws {
        launchApplication()
        defer { application.terminate() }
        submit(Self.recoveryOrigin + "/recovered")

        XCTAssertTrue(
            errorView.waitForExistence(timeout: 5),
            "A local connection failure did not present a visible error."
        )
        XCTAssertTrue(
            errorReloadButton.waitForExistence(timeout: 2),
            "The connection error did not offer a retry action."
        )

        try requestFixture("/phase2/recovery-enable")
        errorReloadButton.click()

        XCTAssertTrue(
            pageText("Recovered after retry").waitForExistence(timeout: 5),
            "Retry did not reload the formerly unavailable local page."
        )
        XCTAssertTrue(
            errorView.waitForNonExistence(timeout: 2),
            "The error remained visible after a successful retry."
        )
    }

    func testNavigationIsNotRestoredAfterRelaunch() throws {
        launchApplication(ignoringSavedState: false)
        defer { application.terminate() }
        let sentinelURL = fixtureURL(
            "/phase2/page-a?phase2-history-sentinel=7f3d2e"
        )
        submit(sentinelURL)
        XCTAssertTrue(pageText("Phase 2 Page A").waitForExistence(timeout: 5))
        waitForAddress(sentinelURL)
        application.terminate()

        application.launchArguments = ["--ui-test-profile"]
        application.launch()
        XCTAssertTrue(mainWindow.waitForExistence(timeout: 5))
        try assertAddressFieldIsFocused()

        let relaunchedValue = addressField.value as? String ?? ""
        XCTAssertFalse(
            relaunchedValue.contains("phase2-history-sentinel-7f3d2e"),
            "The prior navigation was restored after relaunch."
        )
        XCTAssertFalse(
            pageText("Phase 2 Page A").exists,
            "The prior page remained visible after relaunch."
        )
    }

    private func launchApplication(ignoringSavedState: Bool = true) {
        continueAfterFailure = false
        application = XCUIApplication()
        application.launchArguments = ["--ui-test-profile"]
        if ignoringSavedState {
            application.launchArguments += [
                "-ApplePersistenceIgnoreState",
                "YES",
            ]
        }
        application.launch()
        XCTAssertTrue(
            mainWindow.waitForExistence(timeout: 5),
            "Browser did not present its main window."
        )
    }

    private var mainWindow: XCUIElement {
        application.windows["BrowserMainWindow"]
    }

    private var addressField: XCUIElement {
        application.descendants(matching: .any)["BrowserAddressField"]
    }

    private var backButton: XCUIElement {
        application.buttons["BrowserBackButton"]
    }

    private var forwardButton: XCUIElement {
        application.buttons["BrowserForwardButton"]
    }

    private var reloadStopButton: XCUIElement {
        application.buttons["BrowserReloadStopButton"]
    }

    private var progressIndicator: XCUIElement {
        application.progressIndicators["BrowserLoadProgress"]
    }

    private var errorView: XCUIElement {
        application.descendants(matching: .any)["BrowserErrorView"]
    }

    private var errorReloadButton: XCUIElement {
        application.buttons["BrowserErrorReloadButton"]
    }

    private func assertCriticalControlsExist(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for (name, element) in [
            ("web view", application.descendants(matching: .any)["BrowserWebView"]),
            ("back button", backButton),
            ("forward button", forwardButton),
            ("reload button", reloadStopButton),
        ] {
            XCTAssertTrue(
                element.waitForExistence(timeout: 5),
                "Missing critical \(name) accessibility identifier.",
                file: file,
                line: line
            )
        }
    }

    private func assertAddressFieldIsFocused(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertTrue(
            addressField.waitForExistence(timeout: 5),
            "The address field did not appear.",
            file: file,
            line: line
        )
        XCTAssertTrue(
            addressField.isEnabled,
            "The address field is not interactive.",
            file: file,
            line: line
        )

        let focusProbe = "focus-probe"
        addressField.typeText(focusProbe)
        XCTAssertEqual(
            addressField.value as? String,
            focusProbe,
            "Typing without clicking did not reach the launch-focused address field.",
            file: file,
            line: line
        )
        addressField.typeKey("a", modifierFlags: .command)
        addressField.typeKey(.delete, modifierFlags: [])
    }

    private func navigate(to path: String) {
        let url = fixtureURL(path)
        submit(url)
        waitForAddress(url)
    }

    private func submit(_ text: String) {
        application.activate()
        application.typeKey("l", modifierFlags: .command)
        let field = addressField
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeKey("a", modifierFlags: .command)
        field.typeText(text)
        field.typeKey(.return, modifierFlags: [])
    }

    private func waitForAddress(
        _ expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", expected),
            object: addressField
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 5),
            .completed,
            "Displayed URL did not become \(expected).",
            file: file,
            line: line
        )
    }

    private func waitForWindowTitle(
        _ expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "title == %@", expected),
            object: mainWindow
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 5),
            .completed,
            "Window title did not become \(expected).",
            file: file,
            line: line
        )
    }

    private func waitUntilEnabled(
        _ element: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"),
            object: element
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 5),
            .completed,
            "Control did not become enabled.",
            file: file,
            line: line
        )
    }

    private func waitForButtonLabel(
        _ button: XCUIElement,
        containing expectedText: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format: "label CONTAINS[c] %@",
                expectedText
            ),
            object: button
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 5),
            .completed,
            "Button label did not contain \(expectedText).",
            file: file,
            line: line
        )
    }

    private func pageText(_ text: String) -> XCUIElement {
        application.staticTexts[text]
    }

    private func fixtureURL(_ path: String) -> String {
        Self.fixtureOrigin + path
    }

    @discardableResult
    private func requestFixture(_ path: String) throws -> Data {
        let url = try XCTUnwrap(URL(string: fixtureURL(path)))
        return try Data(contentsOf: url)
    }
}
