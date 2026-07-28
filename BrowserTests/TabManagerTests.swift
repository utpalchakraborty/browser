import XCTest
@testable import Browser

@MainActor
final class TabManagerTests: XCTestCase {
    func testManagerStartsWithSelectedInitialTab() {
        let initial = TabController()
        let manager = TabManager(initialTab: initial)

        XCTAssertEqual(manager.tabs.map(\.id), [initial.id])
        XCTAssertEqual(manager.selectedTabID, initial.id)
        XCTAssertTrue(manager.selectedTab === initial)
        XCTAssertEqual(manager.presentations.map(\.title), ["New Tab"])
    }

    func testBackgroundAppendPreservesSelectionAndForegroundAppendSelects() {
        let initial = TabController()
        let manager = TabManager(initialTab: initial)
        let background = TabController()
        manager.append(background, select: false)

        XCTAssertEqual(manager.selectedTabID, initial.id)

        let foreground = TabController()
        manager.append(foreground, select: true)

        XCTAssertEqual(manager.selectedTabID, foreground.id)
        XCTAssertEqual(manager.tabs.map(\.id), [
            initial.id,
            background.id,
            foreground.id,
        ])
    }

    func testClosingSelectedTabChoosesRightNeighborThenLeft() {
        let first = TabController()
        let manager = TabManager(initialTab: first)
        let middle = TabController()
        let last = TabController()
        manager.append(middle, select: false)
        manager.append(last, select: false)

        XCTAssertTrue(manager.select(id: middle.id))
        XCTAssertTrue(manager.remove(id: middle.id) === middle)
        XCTAssertEqual(manager.selectedTabID, last.id)

        XCTAssertTrue(manager.remove(id: last.id) === last)
        XCTAssertEqual(manager.selectedTabID, first.id)
    }

    func testClosingBackgroundTabPreservesSelectedTab() {
        let first = TabController()
        let manager = TabManager(initialTab: first)
        let second = TabController()
        let third = TabController()
        manager.append(second, select: true)
        manager.append(third, select: false)

        XCTAssertTrue(manager.remove(id: first.id) === first)
        XCTAssertEqual(manager.selectedTabID, second.id)
        XCTAssertEqual(manager.tabs.map(\.id), [second.id, third.id])
    }

    func testSoleTabMustBeReplacedWithFreshIdentity() {
        let initial = TabController()
        let manager = TabManager(initialTab: initial)
        let replacement = TabController()

        XCTAssertNil(manager.remove(id: initial.id))
        XCTAssertTrue(manager.replaceSoleTab(with: replacement) === initial)
        XCTAssertEqual(manager.tabs.map(\.id), [replacement.id])
        XCTAssertEqual(manager.selectedTabID, replacement.id)
        XCTAssertNotEqual(initial.id, replacement.id)
    }

    func testClosedTabClearsQueuedURL() throws {
        let tab = TabController()
        let url = try XCTUnwrap(URL(string: "https://example.com/closed"))

        XCTAssertTrue(tab.navigate(to: url))
        XCTAssertEqual(tab.pendingNavigationURL, url)

        tab.close()

        XCTAssertTrue(tab.isClosed)
        XCTAssertNil(tab.pendingNavigationURL)
        XCTAssertNil(tab.currentContentBlockingURL)
    }

    func testClosingResidentTabClearsTransientNavigationState() throws {
        let tab = TabController()
        tab.installWebViewFactory(
            BrowserProfile(dataStoreIdentifier: UUID()).webViewFactory
        )
        let url = try XCTUnwrap(URL(string: "about:blank"))

        XCTAssertTrue(tab.navigate(to: url))
        XCTAssertTrue(tab.hasActiveNavigation)
        XCTAssertNotNil(tab.webView)

        tab.close()

        XCTAssertTrue(tab.isClosed)
        XCTAssertFalse(tab.hasActiveNavigation)
        XCTAssertNil(tab.webView)
        XCTAssertNil(tab.observedURL)
        XCTAssertNil(tab.observedTitle)
        XCTAssertEqual(tab.observedProgress, 0)
        XCTAssertFalse(tab.observedIsLoading)
        XCTAssertFalse(tab.observedCanGoBack)
        XCTAssertFalse(tab.observedCanGoForward)
        XCTAssertNil(tab.errorState)
    }

    func testHundredSoleTabReplacementCyclesKeepFreshIdentity() {
        var current = TabController()
        let manager = TabManager(initialTab: current)
        var seenIDs: Set<UUID> = [current.id]

        for _ in 0..<100 {
            let replacement = TabController()
            let removed = manager.replaceSoleTab(with: replacement)
            removed.close()

            XCTAssertTrue(seenIDs.insert(replacement.id).inserted)
            XCTAssertTrue(removed.isClosed)
            XCTAssertEqual(manager.tabs.count, 1)
            XCTAssertTrue(manager.selectedTab === replacement)
            current = replacement
        }

        XCTAssertEqual(seenIDs.count, 101)
        XCTAssertTrue(manager.selectedTab === current)
    }
}
