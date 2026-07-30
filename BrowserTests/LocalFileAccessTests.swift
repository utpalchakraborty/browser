import Foundation
import XCTest
@testable import Browser

@MainActor
final class LocalFileAccessTests: XCTestCase {
    func testAuthorizationRequiresExactContainingDirectoryAndRegularHTML() throws {
        let containerURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: containerURL) }

        let siteURL = containerURL.appendingPathComponent(
            "site",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: siteURL,
            withIntermediateDirectories: false
        )
        let fileURL = siteURL.appendingPathComponent("index.html")
        try Data("<title>Local</title>".utf8).write(to: fileURL)

        let authorization = try XCTUnwrap(
            LocalFileAccessPolicy.authorization(
                for: fileURL,
                selectedDirectoryURL: siteURL
            )
        )
        XCTAssertEqual(
            authorization.fileURL,
            fileURL.resolvingSymlinksInPath()
        )
        XCTAssertEqual(
            authorization.readAccessURL,
            siteURL.resolvingSymlinksInPath()
        )
        XCTAssertNil(
            LocalFileAccessPolicy.authorization(
                for: fileURL,
                selectedDirectoryURL: containerURL
            )
        )

        let textURL = siteURL.appendingPathComponent("notes.txt")
        try Data("private".utf8).write(to: textURL)
        XCTAssertNil(
            LocalFileAccessPolicy.authorization(
                for: textURL,
                selectedDirectoryURL: siteURL
            )
        )
    }

    func testNavigationAllowsApprovedLocalSiteButNotRemoteOrOutsideRequests() {
        let rootURL = URL(fileURLWithPath: "/tmp/local-site", isDirectory: true)
        let approvedURL = rootURL.appendingPathComponent("index.html")
        let siblingURL = rootURL.appendingPathComponent("pages/next.html")
        let outsideURL = URL(fileURLWithPath: "/tmp/local-site-copy/index.html")

        XCTAssertTrue(
            LocalFileNavigationPolicy.allows(
                targetURL: approvedURL,
                sourceURL: URL(string: "about:blank"),
                readAccessURL: rootURL,
                approvedURL: approvedURL,
                isMainFrame: true,
                isBackForwardNavigation: false
            )
        )
        XCTAssertTrue(
            LocalFileNavigationPolicy.allows(
                targetURL: siblingURL,
                sourceURL: approvedURL,
                readAccessURL: rootURL,
                approvedURL: nil,
                isMainFrame: true,
                isBackForwardNavigation: false
            )
        )
        XCTAssertTrue(
            LocalFileNavigationPolicy.allows(
                targetURL: approvedURL,
                sourceURL: URL(string: "https://example.com"),
                readAccessURL: rootURL,
                approvedURL: nil,
                isMainFrame: true,
                isBackForwardNavigation: true
            )
        )
        XCTAssertFalse(
            LocalFileNavigationPolicy.allows(
                targetURL: approvedURL,
                sourceURL: URL(string: "https://example.com"),
                readAccessURL: rootURL,
                approvedURL: nil,
                isMainFrame: true,
                isBackForwardNavigation: false
            )
        )
        XCTAssertFalse(
            LocalFileNavigationPolicy.allows(
                targetURL: outsideURL,
                sourceURL: approvedURL,
                readAccessURL: rootURL,
                approvedURL: outsideURL,
                isMainFrame: true,
                isBackForwardNavigation: false
            )
        )
        XCTAssertFalse(
            LocalFileNavigationPolicy.allows(
                targetURL: approvedURL,
                sourceURL: URL(string: "https://example.com/frame"),
                readAccessURL: rootURL,
                approvedURL: approvedURL,
                isMainFrame: false,
                isBackForwardNavigation: false
            )
        )
    }

    func testResolvedContainmentRejectsSymlinkEscape() throws {
        let containerURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: containerURL) }

        let rootURL = containerURL.appendingPathComponent(
            "site",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: false
        )
        let outsideURL = containerURL.appendingPathComponent("outside.html")
        try Data("outside".utf8).write(to: outsideURL)
        let escapeURL = rootURL.appendingPathComponent("escape.html")
        try FileManager.default.createSymbolicLink(
            at: escapeURL,
            withDestinationURL: outsideURL
        )

        XCTAssertFalse(
            LocalFileAccessPolicy.contains(escapeURL, in: rootURL)
        )
        XCTAssertFalse(
            LocalFileNavigationPolicy.allows(
                targetURL: escapeURL,
                sourceURL: rootURL.appendingPathComponent("index.html"),
                readAccessURL: rootURL,
                approvedURL: escapeURL,
                isMainFrame: true,
                isBackForwardNavigation: false
            )
        )
    }

    func testTabLoadsAssetsAndNavigatesWithinApprovedDirectory() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let secondRootURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: secondRootURL) }

        let scriptURL = rootURL.appendingPathComponent("local.js")
        try Data("window.localAssetLoaded = 'ready';".utf8).write(
            to: scriptURL
        )
        let siblingURL = rootURL.appendingPathComponent("next.html")
        try Data(
            "<html><head><title>Sibling Fixture</title></head><body>Next</body></html>".utf8
        ).write(to: siblingURL)
        let fileURL = rootURL.appendingPathComponent("index.html")
        try Data(
            "<html><head><title>Local Fixture</title><script src=\"local.js\"></script></head><body><a id=\"next\" href=\"next.html\">Next</a></body></html>".utf8
        ).write(to: fileURL)
        let authorization = try XCTUnwrap(
            LocalFileAccessPolicy.authorization(
                for: fileURL,
                selectedDirectoryURL: rootURL
            )
        )

        let tab = TabController()
        defer { tab.close() }
        tab.installWebViewFactory(
            BrowserProfile(dataStoreIdentifier: UUID()).webViewFactory
        )
        let loaded = expectation(description: "local HTML finished loading")
        var fulfilled = false
        tab.onStateChange = { changedTab in
            guard
                !fulfilled,
                LocalFileAccessPolicy.refersToSameFile(
                    changedTab.committedURL,
                    authorization.fileURL
                ),
                changedTab.webView?.isLoading == false
            else {
                return
            }
            fulfilled = true
            loaded.fulfill()
        }

        XCTAssertTrue(tab.navigate(toLocalFile: authorization))
        await fulfillment(of: [loaded], timeout: 5)

        let webView = try XCTUnwrap(tab.webView)
        let assetResult = try await webView.evaluateJavaScript(
            "window.localAssetLoaded"
        )
        XCTAssertEqual(assetResult as? String, "ready")
        XCTAssertEqual(tab.observedTitle, "Local Fixture")

        let siblingLoaded = expectation(
            description: "sibling local HTML finished loading"
        )
        var siblingFulfilled = false
        tab.onStateChange = { changedTab in
            guard
                !siblingFulfilled,
                LocalFileAccessPolicy.refersToSameFile(
                    changedTab.committedURL,
                    siblingURL
                ),
                changedTab.webView?.isLoading == false
            else {
                return
            }
            siblingFulfilled = true
            siblingLoaded.fulfill()
        }
        _ = try await webView.evaluateJavaScript(
            "document.getElementById('next').click()"
        )
        await fulfillment(of: [siblingLoaded], timeout: 5)
        XCTAssertEqual(tab.observedTitle, "Sibling Fixture")

        let returnedToInitialPage = expectation(
            description: "back navigation returned to initial local HTML"
        )
        var backFulfilled = false
        tab.onStateChange = { changedTab in
            guard
                !backFulfilled,
                LocalFileAccessPolicy.refersToSameFile(
                    changedTab.committedURL,
                    fileURL
                ),
                changedTab.webView?.isLoading == false
            else {
                return
            }
            backFulfilled = true
            returnedToInitialPage.fulfill()
        }
        tab.goBack()
        await fulfillment(of: [returnedToInitialPage], timeout: 5)
        XCTAssertEqual(tab.observedTitle, "Local Fixture")

        let secondFileURL = secondRootURL.appendingPathComponent("index.html")
        try Data(
            "<html><head><title>Second Folder</title></head><body>Second</body></html>".utf8
        ).write(to: secondFileURL)
        let secondAuthorization = try XCTUnwrap(
            LocalFileAccessPolicy.authorization(
                for: secondFileURL,
                selectedDirectoryURL: secondRootURL
            )
        )
        let secondFolderLoaded = expectation(
            description: "HTML from second approved folder loaded"
        )
        var secondFolderFulfilled = false
        tab.onStateChange = { changedTab in
            guard
                !secondFolderFulfilled,
                LocalFileAccessPolicy.refersToSameFile(
                    changedTab.committedURL,
                    secondFileURL
                ),
                changedTab.webView?.isLoading == false
            else {
                return
            }
            secondFolderFulfilled = true
            secondFolderLoaded.fulfill()
        }
        XCTAssertTrue(tab.navigate(toLocalFile: secondAuthorization))
        await fulfillment(of: [secondFolderLoaded], timeout: 5)
        XCTAssertEqual(tab.observedTitle, "Second Folder")

        let crossFolderBackLoaded = expectation(
            description: "back navigation retained the first folder grant"
        )
        var crossFolderBackFulfilled = false
        tab.onStateChange = { changedTab in
            guard
                !crossFolderBackFulfilled,
                LocalFileAccessPolicy.refersToSameFile(
                    changedTab.committedURL,
                    fileURL
                ),
                changedTab.webView?.isLoading == false
            else {
                return
            }
            crossFolderBackFulfilled = true
            crossFolderBackLoaded.fulfill()
        }
        tab.goBack()
        await fulfillment(of: [crossFolderBackLoaded], timeout: 5)
        XCTAssertEqual(tab.observedTitle, "Local Fixture")
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: false
        )
        return url
    }
}
