import Foundation
import os
import XCTest

@MainActor
final class BrowserLaunchPerformanceTests: XCTestCase {
    private static let subsystem = "com.utpalchakraborty.browser"
    private static let category = OSLog.Category.pointsOfInterest.rawValue
    private static let fixtureOrigin = "http://127.0.0.1:18768"

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testFocusedSinglePageBrowserLaunch() {
        let application = XCUIApplication()
        application.launchArguments = [
            "--performance-test",
            "-ApplePersistenceIgnoreState",
            "YES",
        ]

        let options = XCTMeasureOptions()
        options.iterationCount = 20

        measure(
            metrics: [
                XCTApplicationLaunchMetric(waitUntilResponsive: true),
                XCTOSSignpostMetric(
                    subsystem: Self.subsystem,
                    category: Self.category,
                    name: "InitialWindowPresentation"
                ),
                XCTOSSignpostMetric(
                    subsystem: Self.subsystem,
                    category: Self.category,
                    name: "InitialAddressFieldFocus"
                ),
                XCTOSSignpostMetric(
                    subsystem: Self.subsystem,
                    category: Self.category,
                    name: "InitialWebViewDeferral"
                ),
                XCTOSSignpostMetric(
                    subsystem: Self.subsystem,
                    category: Self.category,
                    name: "InitialWebViewConstruction"
                ),
                XCTOSSignpostMetric(
                    subsystem: Self.subsystem,
                    category: Self.category,
                    name: "FirstBlankNavigation"
                ),
            ],
            options: options
        ) {
            application.launch()
            let addressField = application.descendants(matching: .any)[
                "BrowserAddressField"
            ]
            let webView = application.descendants(matching: .any)[
                "BrowserWebView"
            ]
            let reloadStopButton = application.buttons[
                "BrowserReloadStopButton"
            ]
            let progressIndicator = application.progressIndicators[
                "BrowserLoadProgress"
            ]

            XCTAssertTrue(
                application.windows["BrowserMainWindow"]
                    .waitForExistence(timeout: 5),
                "The browser process launched but did not present a window."
            )
            XCTAssertTrue(
                addressField.waitForExistence(timeout: 5),
                "The browser window appeared without its address field."
            )
            XCTAssertTrue(addressField.isEnabled)
            assertFocused(addressField)
            XCTAssertTrue(
                webView.waitForExistence(timeout: 5),
                "The initial web view was not constructed."
            )
            waitForButtonLabel(reloadStopButton, containing: "Reload")
            XCTAssertTrue(
                progressIndicator.waitForNonExistence(timeout: 5),
                "The initial blank web view did not settle."
            )
        }
    }

    func testDeterministicLocalNavigationAndCommandResponse() {
        let application = XCUIApplication()
        application.launchArguments = [
            "--performance-test",
            "-ApplePersistenceIgnoreState",
            "YES",
        ]
        application.launch()

        let addressField = application.descendants(matching: .any)[
            "BrowserAddressField"
        ]
        XCTAssertTrue(addressField.waitForExistence(timeout: 5))
        XCTAssertTrue(
            application.descendants(matching: .any)["BrowserWebView"]
                .waitForExistence(timeout: 5)
        )
        waitForButtonLabel(
            application.buttons["BrowserReloadStopButton"],
            containing: "Reload"
        )

        let destinations = [
            (path: "/phase2/page-a", text: "Phase 2 Page A"),
            (path: "/phase2/page-b", text: "Phase 2 Page B"),
        ]
        var iteration = 0
        let options = XCTMeasureOptions()
        options.iterationCount = 20

        measure(
            metrics: [
                XCTOSSignpostMetric(
                    subsystem: Self.subsystem,
                    category: Self.category,
                    name: "AddressSubmission"
                ),
                XCTOSSignpostMetric(
                    subsystem: Self.subsystem,
                    category: Self.category,
                    name: "LocalFixtureNavigation"
                ),
            ],
            options: options
        ) {
            let destination = destinations[iteration % destinations.count]
            iteration += 1
            let url = Self.fixtureOrigin + destination.path

            application.activate()
            application.typeKey("l", modifierFlags: .command)
            addressField.typeKey("a", modifierFlags: .command)
            addressField.typeText(url)
            addressField.typeKey(.return, modifierFlags: [])

            XCTAssertTrue(
                application.staticTexts[destination.text]
                    .waitForExistence(timeout: 5),
                "The deterministic fixture navigation did not finish."
            )
            waitForValue(addressField, equalTo: url)
        }

        application.terminate()
    }

    func testBackAndForwardCommandResponse() {
        let application = XCUIApplication()
        application.launchArguments = [
            "--performance-test",
            "-ApplePersistenceIgnoreState",
            "YES",
        ]
        application.launch()

        let addressField = application.descendants(matching: .any)[
            "BrowserAddressField"
        ]
        XCTAssertTrue(addressField.waitForExistence(timeout: 5))
        XCTAssertTrue(
            application.descendants(matching: .any)["BrowserWebView"]
                .waitForExistence(timeout: 5)
        )
        waitForButtonLabel(
            application.buttons["BrowserReloadStopButton"],
            containing: "Reload"
        )

        let setupDestinations = [
            (path: "/phase2/page-a", text: "Phase 2 Page A"),
            (path: "/phase2/page-b", text: "Phase 2 Page B"),
        ]
        for destination in setupDestinations {
            application.activate()
            application.typeKey("l", modifierFlags: .command)
            addressField.typeKey("a", modifierFlags: .command)
            addressField.typeText(Self.fixtureOrigin + destination.path)
            addressField.typeKey(.return, modifierFlags: [])
            XCTAssertTrue(
                application.staticTexts[destination.text]
                    .waitForExistence(timeout: 5)
            )
            waitForValue(
                addressField,
                equalTo: Self.fixtureOrigin + destination.path
            )
        }

        var goesBack = true
        let options = XCTMeasureOptions()
        options.iterationCount = 20

        measure(
            metrics: [
                XCTOSSignpostMetric(
                    subsystem: Self.subsystem,
                    category: Self.category,
                    name: "BrowserCommand"
                ),
            ],
            options: options
        ) {
            let expectedText = goesBack ? "Phase 2 Page A" : "Phase 2 Page B"
            let key = goesBack ? "[" : "]"
            application.typeKey(key, modifierFlags: .command)
            XCTAssertTrue(
                application.staticTexts[expectedText].waitForExistence(timeout: 5)
            )
            goesBack.toggle()
        }

        application.terminate()
    }

    func testControlledScrollingResponsiveness() {
        let application = XCUIApplication()
        application.launchArguments = [
            "--performance-test",
            "-ApplePersistenceIgnoreState",
            "YES",
        ]
        application.launch()

        let addressField = application.descendants(matching: .any)[
            "BrowserAddressField"
        ]
        let webView = application.descendants(matching: .any)[
            "BrowserWebView"
        ]
        XCTAssertTrue(addressField.waitForExistence(timeout: 5))
        XCTAssertTrue(webView.waitForExistence(timeout: 5))
        waitForButtonLabel(
            application.buttons["BrowserReloadStopButton"],
            containing: "Reload"
        )

        let url = Self.fixtureOrigin + "/performance/scroll"
        application.activate()
        application.typeKey("l", modifierFlags: .command)
        addressField.typeKey("a", modifierFlags: .command)
        addressField.typeText(url)
        addressField.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(
            application.staticTexts["Controlled Scroll Fixture"]
                .waitForExistence(timeout: 5)
        )
        waitForValue(addressField, equalTo: url)

        var scrollsDown = true
        // WKWebView exposes its root accessibility group as a non-hittable
        // element on macOS. A coordinate inside its visible bounds avoids
        // XCUIElement's hit-point lookup while still synthesizing a real
        // scrolling gesture through the web view.
        let scrollCoordinate = webView.coordinate(
            withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)
        )

        // Prove outside the measured block that this coordinate drives the
        // document rather than a no-op accessibility surface. Restore the
        // fixture to its deterministic top state before collecting hitches.
        let topMarker = application.staticTexts["Scroll position top"]
        let movedMarker = application.staticTexts["Scroll position moved"]
        XCTAssertTrue(topMarker.waitForExistence(timeout: 5))
        scrollCoordinate.swipeUp()
        XCTAssertTrue(
            movedMarker.waitForExistence(timeout: 5),
            "The scroll preflight gesture did not move the fixture document."
        )
        for _ in 0 ..< 5 where !topMarker.exists {
            scrollCoordinate.swipeDown()
        }
        XCTAssertTrue(
            topMarker.waitForExistence(timeout: 5),
            "The scroll preflight did not restore the fixture to the top."
        )

        let options = XCTMeasureOptions()
        options.iterationCount = 10
        measure(
            metrics: [
                XCTHitchMetric(application: application),
                XCTOSSignpostMetric.scrollingAndDecelerationMetric,
            ],
            options: options
        ) {
            if scrollsDown {
                scrollCoordinate.swipeUp()
            } else {
                scrollCoordinate.swipeDown()
            }
            scrollsDown.toggle()
        }

        application.terminate()
    }

    private func assertFocused(
        _ element: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let focusProbe = "focus-probe"
        element.typeText(focusProbe)
        XCTAssertEqual(
            element.value as? String,
            focusProbe,
            "Typing without clicking did not reach the launch-focused address field.",
            file: file,
            line: line
        )
        element.typeKey("a", modifierFlags: .command)
        element.typeKey(.delete, modifierFlags: [])
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

    private func waitForValue(
        _ element: XCUIElement,
        equalTo expectedValue: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", expectedValue),
            object: element
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 5),
            .completed,
            "Element value did not become \(expectedValue).",
            file: file,
            line: line
        )
    }
}
