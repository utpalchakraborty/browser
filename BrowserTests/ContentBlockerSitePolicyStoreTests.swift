import Foundation
import XCTest
@testable import Browser

@MainActor
final class ContentBlockerSitePolicyStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: ContentBlockerSitePolicyStore!
    private let key = "ContentBlockerSitePolicyStoreTests.state"

    override func setUp() {
        super.setUp()
        suiteName = "ContentBlockerSitePolicyStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = ContentBlockerSitePolicyStore(defaults: defaults, key: key)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        store = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testExceptionsPersistAsSortedExactNormalizedHosts() throws {
        let root = try XCTUnwrap(ContentBlockerSite(host: "example.com"))
        let account = try XCTUnwrap(
            ContentBlockerSite(host: "ACCOUNT.EXAMPLE.COM.")
        )

        store.setException(true, for: root)
        store.setException(true, for: account)

        XCTAssertTrue(store.isException(root))
        XCTAssertTrue(store.isException(account))
        XCTAssertEqual(
            store.allExceptionHosts(),
            ["account.example.com", "example.com"]
        )
        XCTAssertFalse(
            store.isException(
                try XCTUnwrap(ContentBlockerSite(host: "www.example.com"))
            )
        )

        let reconstructed = ContentBlockerSitePolicyStore(
            defaults: defaults,
            key: key
        )
        XCTAssertEqual(
            reconstructed.allExceptionHosts(),
            ["account.example.com", "example.com"]
        )
    }

    func testRemovingAndResettingExceptionsClearPersistence() throws {
        let site = try XCTUnwrap(ContentBlockerSite(host: "example.com"))
        store.setException(true, for: site)
        store.setException(false, for: site)

        XCTAssertFalse(store.isException(site))
        XCTAssertEqual(store.allExceptionHosts(), [])
        XCTAssertNil(defaults.object(forKey: key))

        store.setException(true, for: site)
        store.reset()
        XCTAssertEqual(store.allExceptionHosts(), [])
        XCTAssertNil(defaults.object(forKey: key))
    }

    func testCorruptOrUnsupportedStateFailsClosedToNoExceptions() throws {
        let site = try XCTUnwrap(ContentBlockerSite(host: "example.com"))
        let corruptStates: [Any] = [
            ["schemaVersion": 999, "exceptionHosts": ["example.com"]],
            ["schemaVersion": 1, "exceptionHosts": ["EXAMPLE.COM"]],
            ["schemaVersion": 1, "exceptionHosts": ["example.com", "example.com"]],
            ["schemaVersion": 1, "exceptionHosts": ["example.com", "bad host"]],
        ]

        for corruptState in corruptStates {
            defaults.set(
                try JSONSerialization.data(withJSONObject: corruptState),
                forKey: key
            )
            XCTAssertEqual(store.allExceptionHosts(), [])
            XCTAssertFalse(store.isException(site))
        }

        defaults.set(Data("not-json".utf8), forKey: key)
        XCTAssertEqual(store.allExceptionHosts(), [])
        XCTAssertFalse(store.isException(site))
    }

    func testExplicitSetHealsCorruptStateWithoutRestoringUnknownHosts() throws {
        defaults.set(Data("not-json".utf8), forKey: key)
        let site = try XCTUnwrap(ContentBlockerSite(host: "example.com"))

        store.setException(true, for: site)

        XCTAssertEqual(store.allExceptionHosts(), ["example.com"])
        XCTAssertTrue(store.isException(site))
    }
}
