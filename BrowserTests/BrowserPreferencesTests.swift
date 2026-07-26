import XCTest
@testable import Browser

@MainActor
final class BrowserPreferencesTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "BrowserPreferencesTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultsToDuckDuckGoWhenNoPreferenceExists() {
        XCTAssertEqual(BrowserPreferences.searchProvider(in: defaults), .duckDuckGo)
    }

    func testSelectedSearchProviderPersists() {
        BrowserPreferences.setSearchProvider(.google, in: defaults)

        XCTAssertEqual(BrowserPreferences.searchProvider(in: defaults), .google)
    }

    func testUnknownStoredProviderFallsBackToDefault() {
        defaults.set("removed-provider", forKey: "searchProvider")

        XCTAssertEqual(BrowserPreferences.searchProvider(in: defaults), .duckDuckGo)
    }
}
