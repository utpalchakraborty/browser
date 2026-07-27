import AppKit
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

    func testNewContextPolicyRoutesOnlyUnmodifiedPrimaryHTTPLinks() {
        for url in [
            URL(string: "http://example.com/path"),
            URL(string: "HTTPS://example.com/path"),
        ] {
            XCTAssertTrue(
                NewContextNavigationPolicy.shouldRouteInCurrentPage(
                    url: url,
                    isLinkActivation: true,
                    buttonNumber: 1,
                    modifierFlags: []
                )
            )
        }
    }

    func testNewContextPolicyDeniesNonWebSchemesAndMissingURLs() {
        let cases: [URL?] = [
            URL(string: "about:blank"),
            URL(string: "javascript:alert(1)"),
            URL(string: "data:text/html,page"),
            URL(string: "file:///tmp/private"),
            URL(string: "mailto:user@example.com"),
            nil,
        ]

        for url in cases {
            XCTAssertFalse(
                NewContextNavigationPolicy.shouldRouteInCurrentPage(
                    url: url,
                    isLinkActivation: true,
                    buttonNumber: 1,
                    modifierFlags: []
                ),
                String(describing: url)
            )
        }
    }

    func testNewContextPolicyDeniesSyntheticModifiedAndAlternateClicks() {
        let url = URL(string: "https://example.com/path")

        XCTAssertFalse(
            NewContextNavigationPolicy.shouldRouteInCurrentPage(
                url: url,
                isLinkActivation: false,
                buttonNumber: 1,
                modifierFlags: []
            )
        )
        for buttonNumber in [0, 2, 4] {
            XCTAssertFalse(
                NewContextNavigationPolicy.shouldRouteInCurrentPage(
                    url: url,
                    isLinkActivation: true,
                    buttonNumber: buttonNumber,
                    modifierFlags: []
                )
            )
        }
        for modifier: NSEvent.ModifierFlags in [
            .command,
            .control,
            .option,
            .shift,
        ] {
            XCTAssertFalse(
                NewContextNavigationPolicy.shouldRouteInCurrentPage(
                    url: url,
                    isLinkActivation: true,
                    buttonNumber: 1,
                    modifierFlags: modifier
                )
            )
        }
    }
}
