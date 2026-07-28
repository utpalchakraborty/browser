import Foundation
import WebKit
import XCTest
@testable import Browser

@MainActor
final class WebsiteDataSnapshotTests: XCTestCase {
    func testCookieSnapshotIncludesMetadataAndUsesFixedMask() throws {
        let url = try XCTUnwrap(URL(string: "https://account.example.com/"))
        let cookie = try XCTUnwrap(
            HTTPCookie.cookies(
                withResponseHeaderFields: [
                    "Set-Cookie": "token=private-value; Domain=.example.com; Path=/account; Max-Age=3600; Secure; HttpOnly; SameSite=Strict"
                ],
                for: url
            ).first
        )

        let snapshot = WebsiteCookieSnapshot(cookie: cookie)

        XCTAssertEqual(snapshot.name, "token")
        XCTAssertEqual(snapshot.domain, ".example.com")
        XCTAssertEqual(snapshot.path, "/account")
        XCTAssertEqual(snapshot.value, "private-value")
        XCTAssertNotNil(snapshot.expiresDate)
        XCTAssertFalse(snapshot.isSessionOnly)
        XCTAssertTrue(snapshot.isSecure)
        XCTAssertTrue(snapshot.isHTTPOnly)
        XCTAssertEqual(snapshot.sameSitePolicy, "Strict")
        XCTAssertEqual(WebsiteCookieSnapshot.maskedValue, "••••••••")
        XCTAssertEqual(WebsiteCookieSnapshot.maskedValue.count, 8)
    }

    func testCookieIDNormalizesDomainButKeepsNameAndPathBoundaries() {
        let canonical = WebsiteCookieID(
            domain: ".EXAMPLE.com",
            path: "/account",
            name: "session"
        )

        XCTAssertEqual(
            canonical,
            WebsiteCookieID(
                domain: "example.COM.",
                path: "/account",
                name: "session"
            )
        )
        XCTAssertNotEqual(
            canonical,
            WebsiteCookieID(
                domain: "example.com",
                path: "/",
                name: "session"
            )
        )
        XCTAssertNotEqual(
            canonical,
            WebsiteCookieID(
                domain: "example.com",
                path: "/account",
                name: "Session"
            )
        )
        XCTAssertFalse(canonical.accessibilityToken.isEmpty)
    }

    func testCookieDomainsAreGroupedExactlyAndSorted() throws {
        let cookies = try [
            makeCookie(
                header: "zeta=1; Domain=.example.com; Path=/",
                url: "https://example.com/"
            ),
            makeCookie(
                header: "alpha=2; Domain=.EXAMPLE.com; Path=/account",
                url: "https://example.com/account"
            ),
            makeCookie(
                header: "child=3; Domain=sub.example.com; Path=/",
                url: "https://sub.example.com/"
            ),
        ]

        let snapshot = WebsiteDataSnapshot(cookies: cookies, records: [])

        XCTAssertEqual(
            snapshot.cookieDomains.map(\.domain),
            ["example.com", "sub.example.com"]
        )
        XCTAssertEqual(
            snapshot.cookieDomains[0].cookies.map(\.name),
            ["alpha", "zeta"]
        )
        XCTAssertEqual(snapshot.cookieCount, 3)
    }

    func testWebsiteDataCategoriesHaveReadableNamesAndSafeFallback() {
        XCTAssertEqual(
            WebsiteDataCategory(
                rawType: WKWebsiteDataTypeIndexedDBDatabases
            ).displayName,
            "IndexedDB Databases"
        )
        XCTAssertEqual(
            WebsiteDataCategory(
                rawType: WKWebsiteDataTypeServiceWorkerRegistrations
            ).displayName,
            "Service Workers"
        )
        XCTAssertEqual(
            WebsiteDataCategory(rawType: "FutureWebKitStorage").displayName,
            "Other Website Data"
        )
    }

    private func makeCookie(header: String, url: String) throws -> HTTPCookie {
        let parsedURL = try XCTUnwrap(URL(string: url))
        return try XCTUnwrap(
            HTTPCookie.cookies(
                withResponseHeaderFields: ["Set-Cookie": header],
                for: parsedURL
            ).first
        )
    }
}
