import WebKit
import XCTest
@testable import Browser

/// Hosted tests create uniquely named persistent WebKit stores. Without cleanup
/// the test host's container keeps every one of them across runs.
@MainActor
enum TestWebsiteDataStores {
    static let launchModeIdentifiers: Set<UUID> = [
        BrowserProfile.normalDataStoreIdentifier,
        BrowserProfile.testHostDataStoreIdentifier,
        BrowserProfile.performanceDataStoreIdentifier,
    ]

    /// Only the isolated test host may sweep stores; a production-identity host
    /// owns the user's profile.
    static var canRemoveStores: Bool {
        Bundle.main.bundleIdentifier == BrowserLaunchConfiguration.testBundleIdentifier
    }

    /// Removes every named store except the fixed launch-mode profiles. WebKit
    /// refuses to remove a store that is still in use, so live fixtures are kept.
    @discardableResult
    static func removeUnusedStores() async -> Int {
        guard canRemoveStores else {
            return 0
        }
        var removedCount = 0
        for identifier in await WKWebsiteDataStore.allDataStoreIdentifiers
        where !launchModeIdentifiers.contains(identifier) {
            do {
                try await WKWebsiteDataStore.remove(forIdentifier: identifier)
                removedCount += 1
            } catch {
                continue
            }
        }
        return removedCount
    }
}

/// Sorts last among the background classes, so most of this run's stores have
/// been released; anything still in use is removed by the next run.
@MainActor
final class WebsiteDataStoreHygieneTests: XCTestCase {
    func testRemovesReleasedTestStoresAndKeepsLaunchModeProfiles() async throws {
        try XCTSkipUnless(
            TestWebsiteDataStores.canRemoveStores,
            "Store cleanup runs only in the isolated test host."
        )
        executionTimeAllowance = 120

        let identifier = try await makeReleasedStoreOnDisk()
        let launchModeStore = BrowserProfile(
            dataStoreIdentifier: BrowserProfile.testHostDataStoreIdentifier
        )
        let liveProfile = BrowserProfile(dataStoreIdentifier: UUID())
        let liveIdentifier = try XCTUnwrap(liveProfile.websiteDataStore.identifier)
        await liveProfile.websiteDataStore.httpCookieStore.setCookie(
            try Self.sentinelCookie()
        )

        var removedCount = await TestWebsiteDataStores.removeUnusedStores()
        // A just-released store can stay referenced until the run loop drains.
        for _ in 0..<20 where await WKWebsiteDataStore.allDataStoreIdentifiers.contains(identifier) {
            try await Task.sleep(for: .milliseconds(50))
            removedCount += await TestWebsiteDataStores.removeUnusedStores()
        }
        print("BROWSER_TEST_STORE_HYGIENE removed=\(removedCount)")

        let remaining = await WKWebsiteDataStore.allDataStoreIdentifiers
        XCTAssertFalse(remaining.contains(identifier), "A released test store was not removed.")
        XCTAssertTrue(remaining.contains(liveIdentifier), "A store in use must not be removed.")
        XCTAssertTrue(
            remaining.contains(BrowserProfile.testHostDataStoreIdentifier),
            "The fixed test-host profile must be kept."
        )
        withExtendedLifetime((launchModeStore, liveProfile)) {}
    }

    private func makeReleasedStoreOnDisk() async throws -> UUID {
        let profile = BrowserProfile(dataStoreIdentifier: UUID())
        let identifier = try XCTUnwrap(profile.websiteDataStore.identifier)
        await profile.websiteDataStore.httpCookieStore.setCookie(
            try Self.sentinelCookie()
        )
        let stored = await WKWebsiteDataStore.allDataStoreIdentifiers
        XCTAssertTrue(stored.contains(identifier), "The probe store was not created on disk.")
        return identifier
    }

    private static func sentinelCookie() throws -> HTTPCookie {
        try XCTUnwrap(
            HTTPCookie(properties: [
                .domain: "store-hygiene.invalid",
                .path: "/",
                .name: "hygiene",
                .value: "1",
                .expires: Date().addingTimeInterval(3_600),
            ])
        )
    }
}
