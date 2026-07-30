import XCTest
@testable import Browser

final class ContentBlockingNavigationStateTests: XCTestCase {
    func testFragmentOnlyNavigationRequiresOnlyAFragmentDelta() throws {
        let base = try XCTUnwrap(URL(string: "https://example.com/path?q=one"))
        let first = try XCTUnwrap(URL(string: "https://example.com/path?q=one#first"))
        let second = try XCTUnwrap(URL(string: "https://example.com/path?q=one#second"))

        XCTAssertTrue(
            ContentBlockingNavigationURL.isFragmentOnlyNavigation(
                from: base,
                to: first
            )
        )
        XCTAssertTrue(
            ContentBlockingNavigationURL.isFragmentOnlyNavigation(
                from: first,
                to: second
            )
        )
        XCTAssertTrue(
            ContentBlockingNavigationURL.isFragmentOnlyNavigation(
                from: second,
                to: base
            )
        )
        XCTAssertFalse(
            ContentBlockingNavigationURL.isFragmentOnlyNavigation(
                from: first,
                to: first
            )
        )
        XCTAssertFalse(
            ContentBlockingNavigationURL.isFragmentOnlyNavigation(
                from: first,
                to: try XCTUnwrap(URL(string: "https://example.com/other#second"))
            )
        )
        XCTAssertFalse(
            ContentBlockingNavigationURL.isFragmentOnlyNavigation(
                from: first,
                to: try XCTUnwrap(URL(string: "https://example.com/path?q=two#second"))
            )
        )

        let localBase = URL(fileURLWithPath: "/tmp/local/index.html")
        let localFragment = try XCTUnwrap(
            URL(string: "\(localBase.absoluteString)#details")
        )
        XCTAssertTrue(
            ContentBlockingNavigationURL.isFragmentOnlyNavigation(
                from: localBase,
                to: localFragment
            )
        )
    }

    func testNavigationCanOnlyStrengthenUntilItsDocumentCommits() {
        var state = ContentBlockingNavigationState<Int>()

        XCTAssertEqual(state.beginRequest(), .strengthenOnly)
        XCTAssertEqual(state.bind(1), .strengthenOnly)
        XCTAssertEqual(state.approveAction(), .strengthenOnly)
        XCTAssertTrue(state.hasActiveNavigation)
        XCTAssertEqual(state.commit(1), .exact)
        XCTAssertFalse(state.hasActiveNavigation)
    }

    func testStaleCommitCannotWeakenPolicyNeededByNewerNavigation() {
        var state = ContentBlockingNavigationState<Int>()

        _ = state.beginRequest()
        _ = state.bind(1)
        _ = state.approveAction()
        _ = state.approveAction()
        _ = state.bind(2)

        XCTAssertEqual(state.commit(1), .strengthenOnly)
        XCTAssertTrue(state.hasActiveNavigation)
        XCTAssertEqual(state.commit(2), .exact)
    }

    func testUnboundNewActionMakesOlderFailureStaleBeforeDidStart() {
        var state = ContentBlockingNavigationState<Int>()

        _ = state.beginRequest()
        _ = state.bind(1)
        _ = state.approveAction()
        XCTAssertEqual(state.approveAction(), .strengthenOnly)

        XCTAssertEqual(state.fail(1), .stale)
        XCTAssertTrue(state.hasActiveNavigation)
        XCTAssertEqual(state.bind(2), .strengthenOnly)
        XCTAssertEqual(state.commit(2), .exact)
    }

    func testLatestProvisionalFailureCanRestoreExactCommittedPolicy() {
        var state = ContentBlockingNavigationState<Int>()

        _ = state.beginRequest()
        _ = state.bind(1)
        _ = state.approveAction()

        XCTAssertEqual(state.fail(1), .current(.exact))
        XCTAssertFalse(state.hasActiveNavigation)
        XCTAssertEqual(state.fail(1), .stale)
    }

    func testFailureAfterCommitRemainsCurrentWithoutReapplyingPolicy() {
        var state = ContentBlockingNavigationState<Int>()

        _ = state.beginRequest()
        _ = state.bind(1)
        _ = state.approveAction()
        XCTAssertEqual(state.commit(1), .exact)

        XCTAssertEqual(state.fail(1), .current(.none))
    }

    func testPostCommitFailureCannotClaimANewerUnboundAttempt() {
        var state = ContentBlockingNavigationState<Int>()

        _ = state.beginRequest()
        _ = state.bind(1)
        _ = state.approveAction()
        XCTAssertEqual(state.commit(1), .exact)

        XCTAssertEqual(state.approveAction(), .strengthenOnly)
        XCTAssertEqual(state.fail(1), .stale)
        XCTAssertTrue(state.hasActiveNavigation)
        XCTAssertEqual(state.bind(2), .strengthenOnly)
        XCTAssertEqual(state.commit(2), .exact)
        XCTAssertFalse(state.hasActiveNavigation)
    }

    func testRedirectCanBindAReplacementActionToTheSameNavigation() {
        var state = ContentBlockingNavigationState<Int>()

        _ = state.beginRequest()
        _ = state.bind(1)
        _ = state.approveAction()
        _ = state.approveAction()

        XCTAssertEqual(state.bindRedirect(1), .strengthenOnly)
        XCTAssertEqual(state.commit(1), .exact)
    }

    func testUnsupportedActionCancelsOnlyAnAwaitingProgrammaticRequest() {
        var state = ContentBlockingNavigationState<Int>()

        _ = state.beginRequest()
        _ = state.bind(1)
        XCTAssertEqual(state.cancelAwaitingRequest(), .exact)
        XCTAssertFalse(state.hasActiveNavigation)

        _ = state.beginRequest()
        _ = state.bind(2)
        _ = state.approveAction()
        XCTAssertEqual(state.cancelAwaitingRequest(), .none)
        XCTAssertTrue(state.hasActiveNavigation)
    }

    func testSameDocumentActionClearsAwaitingRequestWithoutWeakening() {
        var state = ContentBlockingNavigationState<Int>()

        _ = state.beginRequest()

        XCTAssertEqual(state.resolveSameDocumentAction(), .strengthenOnly)
        XCTAssertFalse(state.hasActiveNavigation)
        XCTAssertEqual(state.resolveSameDocumentAction(), .none)
    }

    func testUnboundCurrentFailureRestoresExactCommittedPolicy() {
        var state = ContentBlockingNavigationState<Int>()

        _ = state.approveAction()

        XCTAssertEqual(state.fail(1), .current(.exact))
        XCTAssertFalse(state.hasActiveNavigation)
    }
}
