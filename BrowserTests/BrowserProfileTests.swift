import XCTest
@testable import Browser

@MainActor
final class BrowserProfileTests: XCTestCase {
    func testConfigurationsShareNamedPersistentDataStore() {
        let identifier = UUID(
            uuidString: "A1000000-0000-4000-8000-000000000000"
        )!
        let profile = BrowserProfile(dataStoreIdentifier: identifier)

        let firstConfiguration = profile.makeWebViewConfiguration()
        let secondConfiguration = profile.makeWebViewConfiguration()

        XCTAssertTrue(
            firstConfiguration.websiteDataStore === secondConfiguration.websiteDataStore
        )
        XCTAssertTrue(firstConfiguration.websiteDataStore.isPersistent)
        XCTAssertEqual(
            firstConfiguration.websiteDataStore.identifier,
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
