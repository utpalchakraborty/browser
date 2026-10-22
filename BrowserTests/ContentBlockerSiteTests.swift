import Foundation
import XCTest
@testable import Browser

final class ContentBlockerSiteTests: XCTestCase {
    func testURLIdentityUsesAnExactNormalizedHost() throws {
        let site = try XCTUnwrap(
            ContentBlockerSite(
                url: try XCTUnwrap(
                    URL(string: "HTTPS://Account.Example.COM.:8443/path?q=1#fragment")
                )
            )
        )

        XCTAssertEqual(site.host, "account.example.com")
        XCTAssertNotEqual(site, ContentBlockerSite(host: "example.com"))
        XCTAssertEqual(
            site,
            ContentBlockerSite(
                url: try XCTUnwrap(URL(string: "http://account.example.com/other"))
            )
        )
    }

    func testLocalAndInternationalHostsAreCanonicalized() throws {
        XCTAssertEqual(
            ContentBlockerSite(
                url: try XCTUnwrap(URL(string: "http://LOCALHOST:18765/"))
            )?.host,
            "localhost"
        )
        XCTAssertEqual(
            ContentBlockerSite(
                url: try XCTUnwrap(URL(string: "http://127.0.0.1:18765/"))
            )?.host,
            "127.0.0.1"
        )
        XCTAssertEqual(
            ContentBlockerSite(
                url: try XCTUnwrap(URL(string: "http://[0:0:0:0:0:0:0:1]:18765/"))
            )?.host,
            "::1"
        )
        XCTAssertEqual(
            ContentBlockerSite(
                url: try XCTUnwrap(URL(string: "https://bücher.example/"))
            )?.host,
            "xn--bcher-kva.example"
        )
    }

    func testNonWebAndMalformedHostsAreRejected() throws {
        XCTAssertNil(ContentBlockerSite(url: URL(string: "about:blank")!))
        XCTAssertNil(ContentBlockerSite(url: URL(string: "data:text/plain,test")!))
        XCTAssertNil(ContentBlockerSite(host: ""))
        XCTAssertNil(ContentBlockerSite(host: ".example.com"))
        XCTAssertNil(ContentBlockerSite(host: "example..com"))
        XCTAssertNil(ContentBlockerSite(host: "example.com/path"))
        XCTAssertNil(ContentBlockerSite(host: "999.0.0.1"))
        XCTAssertNil(ContentBlockerSite(host: "[::1"))
    }

    // The exception store fails closed when any stored host stops round-tripping,
    // so a normalization change must stay idempotent for every normalized form.
    func testNormalizedHostsRoundTripUnchanged() throws {
        for input in [
            "example.com",
            "ACCOUNT.EXAMPLE.COM.",
            "localhost",
            "127.0.0.1",
            "[0:0:0:0:0:0:0:1]",
            "2001:DB8::1",
            "bücher.example",
            "xn--bcher-kva.example",
            "a-b.example",
        ] {
            let normalized = try XCTUnwrap(ContentBlockerSite(host: input), input).host
            XCTAssertEqual(ContentBlockerSite(host: normalized)?.host, normalized, input)
        }
    }

    func testCodableRequiresTheStoredHostToAlreadyBeNormalized() throws {
        let site = try XCTUnwrap(ContentBlockerSite(host: "EXAMPLE.COM."))
        let encoded = try JSONEncoder().encode(site)
        XCTAssertEqual(try JSONDecoder().decode(ContentBlockerSite.self, from: encoded), site)

        XCTAssertThrowsError(
            try JSONDecoder().decode(
                ContentBlockerSite.self,
                from: Data("\"EXAMPLE.COM\"".utf8)
            )
        )
    }
}
