import XCTest
@testable import Browser

final class NavigationPolicyTests: XCTestCase {
    func testTopLevelHTTPAndHTTPSNavigationIsAllowed() {
        XCTAssertEqual(
            NavigationPolicy.decision(
                for: URL(string: "http://example.com"),
                isMainFrame: true
            ),
            .allow
        )
        XCTAssertEqual(
            NavigationPolicy.decision(
                for: URL(string: "HTTPS://example.com"),
                isMainFrame: true
            ),
            .allow
        )
    }

    func testTopLevelAboutBlankIsAllowedOnlyForTheExactInternalPage() {
        XCTAssertEqual(
            NavigationPolicy.decision(
                for: URL(string: "about:blank"),
                isMainFrame: true
            ),
            .allow
        )
        XCTAssertEqual(
            NavigationPolicy.decision(
                for: URL(string: "about:config"),
                isMainFrame: true
            ),
            .cancel
        )
    }

    func testWebContentSchemesRequiredBySubframesAreAllowed() {
        let cases: [URL] = [
            URL(string: "data:text/html,frame"),
            URL(string: "blob:https://example.com/id"),
            URL(string: "javascript:void(0)"),
            URL(string: "about:srcdoc"),
        ].compactMap { $0 }

        for url in cases {
            XCTAssertEqual(
                NavigationPolicy.decision(for: url, isMainFrame: false),
                .allow
            )
        }
    }

    func testUnsupportedOrMissingSubframeSchemesFailClosed() {
        let cases: [URL?] = [
            URL(string: "file:///tmp/private"),
            URL(string: "mailto:user@example.com"),
            URL(string: "custom-scheme://host/path"),
            URL(string: "relative/path"),
            nil,
        ]

        for url in cases {
            XCTAssertEqual(
                NavigationPolicy.decision(for: url, isMainFrame: false),
                .cancel,
                String(describing: url)
            )
        }
    }

    func testTopLevelUnsupportedOrMissingSchemesFailClosed() {
        let cases: [URL?] = [
            URL(string: "file:///tmp/private"),
            URL(string: "mailto:user@example.com"),
            URL(string: "javascript:alert(1)"),
            URL(string: "data:text/html,page"),
            URL(string: "custom-scheme://host/path"),
            URL(string: "relative/path"),
            nil,
        ]

        for url in cases {
            XCTAssertEqual(
                NavigationPolicy.decision(for: url, isMainFrame: true),
                .cancel,
                String(describing: url)
            )
        }
    }
}
