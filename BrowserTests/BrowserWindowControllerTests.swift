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
    }

    func testHiddenWindowDoesNotConstructWebView() {
        let controller = BrowserWindowController()
        let profile = BrowserProfile(dataStoreIdentifier: UUID())

        controller.startWebView(profile: profile)

        XCTAssertNil(controller.webView)
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
