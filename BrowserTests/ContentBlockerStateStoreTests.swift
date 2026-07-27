import Foundation
import XCTest
@testable import Browser

@MainActor
final class ContentBlockerStateStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "ContentBlockerStateStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testRoundTripPreservesIdentifierOrderAndResetRemovesState() {
        let store = ContentBlockerStateStore(defaults: defaults)

        store.recordLastValidIdentifiers(["base", "tracking"])

        XCTAssertEqual(
            store.lastValidIdentifiers(),
            ["base", "tracking"]
        )
        store.reset()
        XCTAssertNil(store.lastValidIdentifiers())
    }

    func testInvalidReplacementDoesNotDestroyLastValidState() {
        let store = ContentBlockerStateStore(defaults: defaults)
        store.recordLastValidIdentifiers(["base", "tracking"])

        store.recordLastValidIdentifiers(["duplicate", "duplicate"])

        XCTAssertEqual(
            store.lastValidIdentifiers(),
            ["base", "tracking"]
        )
    }
}
