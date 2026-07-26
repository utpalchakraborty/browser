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

    func testBookmarkRejectsUnsupportedMissingHostAndCredentialURLs() throws {
        XCTAssertThrowsError(
            try Bookmark(
                url: XCTUnwrap(URL(string: "file:///tmp/page.html")),
                title: "File"
            )
        ) { error in
            XCTAssertEqual(
                error as? BookmarkURLValidationError,
                .unsupportedScheme("file")
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
        let bookmark = try Bookmark(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
            url: XCTUnwrap(URL(string: "https://example.com/")),
            title: "Example",
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 2_000)
        )
        let file = BookmarkFile(bookmarks: [bookmark])
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
