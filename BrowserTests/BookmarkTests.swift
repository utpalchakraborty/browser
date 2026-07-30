import Foundation
import XCTest
@testable import Browser

final class BookmarkTests: XCTestCase {
    func testCanonicalURLNormalizesOnlyUnambiguousHTTPDetails() throws {
        let bookmark = try Bookmark(
            url: XCTUnwrap(
                URL(string: "HTTPS://Example.COM:443/path?q=One#Section")
            ),
            title: "  Example  ",
            createdAt: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(
            bookmark.url.absoluteString,
            "https://example.com/path?q=One#Section"
        )
        XCTAssertEqual(bookmark.title, "Example")
    }

    func testCanonicalURLAddsRootPathAndRemovesDefaultHTTPPort() throws {
        let bookmark = try Bookmark(
            url: XCTUnwrap(URL(string: "http://EXAMPLE.com:80")),
            title: ""
        )

        XCTAssertEqual(bookmark.url.absoluteString, "http://example.com/")
        XCTAssertEqual(bookmark.title, "example.com")
        XCTAssertEqual(
            try Bookmark.canonicalURLString(
                for: XCTUnwrap(URL(string: "HTTP://EXAMPLE.COM:80"))
            ),
            bookmark.url.absoluteString
        )
    }

    func testCanonicalURLKeepsMeaningfulURLDistinctions() throws {
        let first = try Bookmark(
            url: XCTUnwrap(URL(string: "https://example.com/Path?a=1#one")),
            title: "One"
        )
        let second = try Bookmark(
            url: XCTUnwrap(URL(string: "https://example.com/path?a=1#two")),
            title: "Two"
        )

        XCTAssertNotEqual(first.url, second.url)
    }

    func testCanonicalLocalHTMLBookmarkPreservesComponentsAndUsesFileNameTitle() throws {
        let bookmark = try Bookmark(
            url: XCTUnwrap(
                URL(
                    string: "file://localhost/tmp/site/../My%20Pages/index.HTML?mode=one#intro"
                )
            ),
            title: "   "
        )

        XCTAssertEqual(
            bookmark.url.absoluteString,
            "file:///tmp/My%20Pages/index.HTML?mode=one#intro"
        )
        XCTAssertEqual(bookmark.title, "index.HTML")
        XCTAssertEqual(
            try Bookmark.canonicalURL(
                fromAddress: "/tmp/My Pages/local page.htm"
            ).absoluteString,
            "file:///tmp/My%20Pages/local%20page.htm"
        )
        XCTAssertEqual(
            try Bookmark.canonicalURL(
                for: XCTUnwrap(URL(string: "file:///tmp/page.html?#"))
            ).absoluteString,
            "file:///tmp/page.html"
        )
    }

    func testLocalBookmarkIdentityResolvesSymlinksButPreservesPageComponents() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let siteURL = rootURL.appendingPathComponent("site", isDirectory: true)
        let aliasURL = rootURL.appendingPathComponent("alias", isDirectory: true)
        try FileManager.default.createDirectory(
            at: siteURL,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try FileManager.default.createSymbolicLink(
            at: aliasURL,
            withDestinationURL: siteURL
        )

        let realURL = siteURL.appendingPathComponent("index.html")
        let aliasedURL = aliasURL.appendingPathComponent("index.html")
        try Data("<title>Alias</title>".utf8).write(to: realURL)
        let realSectionURL = try XCTUnwrap(
            URL(string: "?view=grid#saved", relativeTo: realURL)
        ).absoluteURL
        let aliasSectionURL = try XCTUnwrap(
            URL(string: "?view=grid#saved", relativeTo: aliasedURL)
        ).absoluteURL
        let otherSectionURL = try XCTUnwrap(
            URL(string: "?view=grid#other", relativeTo: realURL)
        ).absoluteURL

        XCTAssertTrue(
            Bookmark.refersToSamePage(aliasSectionURL, realSectionURL)
        )
        XCTAssertFalse(
            Bookmark.refersToSamePage(aliasSectionURL, otherSectionURL)
        )
        XCTAssertEqual(
            LocalFileAccessPolicy.resolvedNavigationURL(aliasSectionURL),
            realSectionURL
        )
    }

    func testBookmarkRejectsInvalidLocalMissingHostAndCredentialURLs() throws {
        XCTAssertThrowsError(
            try Bookmark(
                url: XCTUnwrap(URL(string: "file:///tmp/page.txt")),
                title: "Text file"
            )
        ) { error in
            XCTAssertEqual(
                error as? BookmarkURLValidationError,
                .unsupportedLocalFileType
            )
        }

        XCTAssertThrowsError(
            try Bookmark(
                url: XCTUnwrap(
                    URL(string: "file://remote.example/tmp/page.html")
                ),
                title: "Remote file"
            )
        ) { error in
            XCTAssertEqual(
                error as? BookmarkURLValidationError,
                .invalidLocalFileURL
            )
        }

        XCTAssertThrowsError(
            try Bookmark(
                url: XCTUnwrap(URL(string: "file:page.html")),
                title: "Relative file"
            )
        ) { error in
            XCTAssertEqual(
                error as? BookmarkURLValidationError,
                .invalidLocalFileURL
            )
        }

        XCTAssertThrowsError(
            try Bookmark(
                url: XCTUnwrap(URL(string: "file:///tmp/page.html/")),
                title: "Directory"
            )
        ) { error in
            XCTAssertEqual(
                error as? BookmarkURLValidationError,
                .unsupportedLocalFileType
            )
        }

        XCTAssertThrowsError(
            try Bookmark(
                url: XCTUnwrap(URL(string: "https:///path")),
                title: "Missing host"
            )
        ) { error in
            XCTAssertEqual(error as? BookmarkURLValidationError, .missingHost)
        }

        XCTAssertThrowsError(
            try Bookmark(
                url: XCTUnwrap(URL(string: "https://user:password@example.com/")),
                title: "Credentials"
            )
        ) { error in
            XCTAssertEqual(
                error as? BookmarkURLValidationError,
                .credentialsNotAllowed
            )
        }
    }

    func testVersionedFileRoundTrips() throws {
        let bookmarks = try [
            Bookmark(
                id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
                url: XCTUnwrap(URL(string: "https://example.com/")),
                title: "Example",
                createdAt: Date(timeIntervalSince1970: 1_000),
                updatedAt: Date(timeIntervalSince1970: 2_000)
            ),
            Bookmark(
                id: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!,
                url: XCTUnwrap(URL(string: "file:///tmp/saved/index.html")),
                title: "Saved locally",
                createdAt: Date(timeIntervalSince1970: 2_000),
                updatedAt: Date(timeIntervalSince1970: 3_000)
            ),
        ]
        let file = BookmarkFile(bookmarks: bookmarks)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(file)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(BookmarkFile.self, from: encoded)

        XCTAssertEqual(decoded, file)
        XCTAssertEqual(decoded.schemaVersion, BookmarkFile.currentSchemaVersion)
    }
}
