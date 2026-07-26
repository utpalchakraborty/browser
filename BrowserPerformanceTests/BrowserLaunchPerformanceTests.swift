import os
import XCTest

@MainActor
final class BrowserLaunchPerformanceTests: XCTestCase {
    private static let subsystem = "com.utpalchakraborty.browser"
    private static let category = OSLog.Category.pointsOfInterest.rawValue

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testScaffoldLaunch() {
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
            XCTAssertTrue(
                application.windows["BrowserMainWindow"]
                    .waitForExistence(timeout: 5),
                "The browser process launched but did not present a window."
            )
            XCTAssertTrue(
                application.descendants(matching: .any)[
                    "BrowserInitialWebViewReady"
                ]
                    .waitForExistence(timeout: 5),
                "The browser window appeared, but its initial about:blank navigation did not become ready."
            )
        }
    }
}
