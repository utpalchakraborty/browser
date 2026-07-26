import XCTest
@testable import Browser

@MainActor
final class BrowserProfileTests: XCTestCase {
    func testFactoryWebViewsShareNamedPersistentDataStore() {
        let identifier = UUID(
            uuidString: "A1000000-0000-4000-8000-000000000000"
        )!
        let profile = BrowserProfile(dataStoreIdentifier: identifier)

        let firstWebView = profile.webViewFactory.makeWebView()
        let secondWebView = profile.webViewFactory.makeWebView()

        XCTAssertTrue(
            firstWebView.configuration.websiteDataStore
                === secondWebView.configuration.websiteDataStore
        )
        XCTAssertTrue(firstWebView.configuration.websiteDataStore.isPersistent)
        XCTAssertEqual(
            firstWebView.configuration.websiteDataStore.identifier,
            identifier
        )
    }

    func testHostedUnitTestsUseAnIsolatedProfile() {
        let identifier = BrowserProfile.applicationDataStoreIdentifier(
            environment: ["XCTestConfigurationFilePath": "/tmp/test.xctestconfiguration"]
        )

        XCTAssertEqual(identifier, BrowserProfile.testHostDataStoreIdentifier)
        XCTAssertNotEqual(identifier, BrowserProfile.normalDataStoreIdentifier)
    }

    func testUITestLaunchMarkerUsesAnIsolatedProfile() {
        let identifier = BrowserProfile.applicationDataStoreIdentifier(
            environment: [:],
            arguments: ["Browser", "--ui-test-profile"]
        )

        XCTAssertEqual(identifier, BrowserProfile.testHostDataStoreIdentifier)
        XCTAssertNotEqual(identifier, BrowserProfile.normalDataStoreIdentifier)
    }

    func testNormalApplicationUsesTheNormalProfile() {
        XCTAssertEqual(
            BrowserProfile.applicationDataStoreIdentifier(environment: [:]),
            BrowserProfile.normalDataStoreIdentifier
        )
    }

    func testPerformanceRunsUseAnIsolatedProfileInReleaseAndDebug() {
        XCTAssertEqual(
            BrowserProfile.applicationDataStoreIdentifier(
                environment: [:],
                arguments: ["Browser", "--performance-test"]
            ),
            BrowserProfile.performanceDataStoreIdentifier
        )
    }
}
