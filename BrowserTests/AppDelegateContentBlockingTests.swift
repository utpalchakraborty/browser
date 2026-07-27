import XCTest
@testable import Browser

@MainActor
final class AppDelegateContentBlockingTests: XCTestCase {
    func testContentBlockingPersistenceKeysAreIsolatedByLaunchMode() {
        let productionArguments = ["Browser"]
        let uiTestArguments = ["Browser", "--ui-test-profile"]

        XCTAssertEqual(
            AppDelegate.contentBlockerStateKey(arguments: productionArguments),
            "contentBlocker.lastValidRuleSet"
        )
        XCTAssertEqual(
            AppDelegate.contentBlockerStateKey(arguments: uiTestArguments),
            "contentBlocker.uiTests.lastValidRuleSet"
        )
        XCTAssertEqual(
            AppDelegate.contentBlockerSitePolicyKey(
                arguments: productionArguments
            ),
            "contentBlocker.sitePolicy"
        )
        XCTAssertEqual(
            AppDelegate.contentBlockerSitePolicyKey(
                arguments: uiTestArguments
            ),
            "contentBlocker.uiTests.sitePolicy"
        )
    }

    func testUITestRuleSourceIsDeterministicAndSeparateFromProduction() async throws {
        let uiTestSources = try AppDelegate.contentBlockerRuleSources(
            arguments: ["Browser", "--ui-test-profile"]
        )
        let productionSources = try AppDelegate.contentBlockerRuleSources(
            arguments: ["Browser"]
        )
        let productionPackage = try ContentBlockerBundle.loadProductionPackage()
        let expectedUITestRules = try ContentBlockerService.probeRules(
            blockedURLFilter: ".*/privacy/blocked[.]js",
            exceptionTopURLFilters: []
        )
        let uiTestSource = try XCTUnwrap(uiTestSources.first)
        let uiTestRules = try await uiTestSource.encodedRules()

        XCTAssertEqual(uiTestSources.count, 1)
        XCTAssertEqual(
            uiTestSource.namespace,
            "browser-ui-test-content-blocking-v1"
        )
        XCTAssertEqual(
            uiTestSource.identifier,
            ContentBlockerService.versionedIdentifier(
                namespace: uiTestSource.namespace,
                encodedRules: expectedUITestRules
            )
        )
        XCTAssertEqual(uiTestRules, expectedUITestRules)
        XCTAssertEqual(
            productionSources.map(\.identifier),
            productionPackage.ruleSources.map(\.identifier)
        )
        XCTAssertFalse(
            productionSources.map(\.identifier).contains(uiTestSource.identifier)
        )
    }
}
