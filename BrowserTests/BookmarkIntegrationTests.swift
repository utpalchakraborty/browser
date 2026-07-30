import AppKit
import XCTest
@testable import Browser

@MainActor
final class BookmarkIntegrationTests: XCTestCase {
    func testCurrentPageCandidateUsesObservedHTTPPageState() throws {
        let candidate = try XCTUnwrap(
            BookmarkPageCandidate.currentPage(
                url: URL(string: "HTTPS://Example.COM:443/guide"),
                title: "  Example Guide  ",
                isLoading: false,
                hasVisibleError: false
            )
        )

        XCTAssertEqual(candidate.url.absoluteString, "https://example.com/guide")
        XCTAssertEqual(candidate.suggestedTitle, "Example Guide")
    }

    func testCurrentPageCandidateAcceptsLoadedLocalHTML() throws {
        let titledCandidate = try XCTUnwrap(
            BookmarkPageCandidate.currentPage(
                url: URL(string: "file:///tmp/My%20Pages/index1.html#details"),
                title: "  Local Movies  ",
                isLoading: false,
                hasVisibleError: false
            )
        )
        let untitledCandidate = try XCTUnwrap(
            BookmarkPageCandidate.currentPage(
                url: URL(string: "file:///tmp/My%20Pages/index1.html"),
                title: "   ",
                isLoading: false,
                hasVisibleError: false
            )
        )

        XCTAssertEqual(
            titledCandidate.url.absoluteString,
            "file:///tmp/My%20Pages/index1.html#details"
        )
        XCTAssertEqual(titledCandidate.suggestedTitle, "Local Movies")
        XCTAssertEqual(untitledCandidate.suggestedTitle, "index1.html")
    }

    func testCurrentPageCandidateFallsBackToHostAndRejectsTransientPages() {
        XCTAssertEqual(
            BookmarkPageCandidate.currentPage(
                url: URL(string: "https://example.com/"),
                title: "   ",
                isLoading: false,
                hasVisibleError: false
            )?.suggestedTitle,
            "example.com"
        )
        XCTAssertNil(
            BookmarkPageCandidate.currentPage(
                url: URL(string: "about:blank"),
                title: nil,
                isLoading: false,
                hasVisibleError: false
            )
        )
        XCTAssertNil(
            BookmarkPageCandidate.currentPage(
                url: URL(string: "https://example.com/"),
                title: "Example",
                isLoading: true,
                hasVisibleError: false
            )
        )
        XCTAssertNil(
            BookmarkPageCandidate.currentPage(
                url: URL(string: "https://example.com/"),
                title: "Example",
                isLoading: false,
                hasVisibleError: true
            )
        )
    }

    func testBookmarkLaunchStorageIsIsolatedByLaunchMode() throws {
        let applicationSupport = URL(fileURLWithPath: "/tmp/browser-support")
        let production = try XCTUnwrap(
            AppDelegate.bookmarkLaunchConfiguration(
                arguments: ["Browser"],
                applicationSupportDirectory: applicationSupport
            )
        )
        XCTAssertEqual(
            production.directoryURL.path,
            "/tmp/browser-support/com.utpalchakraborty.browser"
        )
        XCTAssertFalse(production.resetOnLaunch)

        let uiTest = try XCTUnwrap(
            AppDelegate.bookmarkLaunchConfiguration(
                arguments: [
                    "Browser",
                    "--ui-test-profile",
                    "--reset-ui-test-bookmarks",
                ],
                applicationSupportDirectory: applicationSupport
            )
        )
        XCTAssertEqual(
            uiTest.directoryURL.path,
            "/tmp/browser-support/com.utpalchakraborty.browser/UITests"
        )
        XCTAssertTrue(uiTest.resetOnLaunch)

        XCTAssertNil(
            AppDelegate.bookmarkLaunchConfiguration(
                arguments: ["Browser", "--performance-test"],
                applicationSupportDirectory: applicationSupport
            )
        )
    }

    func testBookmarkButtonReflectsAvailabilityAndSavedState() {
        let chromeView = BrowserChromeView(searchProviderName: "DuckDuckGo")

        XCTAssertFalse(chromeView.bookmarkButton.isEnabled)
        chromeView.updateBookmarkButton(isBookmarked: false, isEnabled: true)
        XCTAssertTrue(chromeView.bookmarkButton.isEnabled)
        XCTAssertEqual(chromeView.bookmarkButton.toolTip, "Add Bookmark")

        chromeView.updateBookmarkButton(isBookmarked: true, isEnabled: true)
        XCTAssertEqual(chromeView.bookmarkButton.toolTip, "Edit Bookmark")
        XCTAssertNotNil(chromeView.bookmarkButton.image)
    }

    func testCoordinatorReportsCanonicalDuplicateAsAnError() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "BookmarkCoordinatorTests.\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let repository = BookmarkRepository(directoryURL: directoryURL)
        let result = try await repository.add(
            url: XCTUnwrap(URL(string: "https://example.com/")),
            title: "Original"
        )
        guard case let .added(original) = result else {
            return XCTFail("Expected the first bookmark to be added")
        }

        let coordinator = BookmarkCoordinator(repository: repository)
        let ready = expectation(description: "Bookmark coordinator loaded")
        coordinator.onStateChange = { state in
            if case .ready = state {
                ready.fulfill()
            }
        }
        coordinator.start(resetOnLaunch: false)
        await fulfillment(of: [ready], timeout: 1)
        coordinator.onStateChange = nil

        let completion = expectation(description: "Duplicate was reported")
        var duplicateMessage: String?
        coordinator.add(
            url: try XCTUnwrap(URL(string: "HTTPS://EXAMPLE.COM:443")),
            title: "Duplicate"
        ) { errorMessage in
            duplicateMessage = errorMessage
            completion.fulfill()
        }
        await fulfillment(of: [completion], timeout: 1)

        XCTAssertEqual(
            duplicateMessage,
            BookmarkRepositoryError.duplicateURL(existingID: original.id)
                .localizedDescription
        )
        XCTAssertEqual(coordinator.bookmarks, [original])
    }
}
