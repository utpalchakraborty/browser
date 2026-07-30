import AppKit
import XCTest
@testable import Browser

final class NavigationPolicyTests: XCTestCase {
    func testDirectPrimaryMagnetLinkRequestsExternalOpen() throws {
        let urls = try [
            XCTUnwrap(
                URL(
                    string: "magnet:?xt=urn:btih:0123456789ABCDEF&dn=Example%20File&tr=udp%3A%2F%2Ftracker.example%3A80&tr=udp%3A%2F%2Fbackup.example%3A1337"
                )
            ),
            XCTUnwrap(URL(string: "MAGNET:?xt=urn:btih:ABCDEF")),
        ]

        for url in urls {
            XCTAssertEqual(
                ExternalNavigationPolicy.disposition(
                    for: url,
                    isLinkActivation: true,
                    buttonNumber: 1,
                    modifierFlags: [],
                    targetsTopLevelContext: true
                ),
                .open(url)
            )
        }
    }

    func testMagnetHandoffRequiresDirectUnmodifiedPrimaryTopLevelLink() {
        let url = URL(string: "magnet:?xt=urn:btih:ABCDEF")

        XCTAssertEqual(
            ExternalNavigationPolicy.disposition(
                for: url,
                isLinkActivation: false,
                buttonNumber: 1,
                modifierFlags: [],
                targetsTopLevelContext: true
            ),
            .none
        )
        for buttonNumber in [0, 2, 3] {
            XCTAssertEqual(
                ExternalNavigationPolicy.disposition(
                    for: url,
                    isLinkActivation: true,
                    buttonNumber: buttonNumber,
                    modifierFlags: [],
                    targetsTopLevelContext: true
                ),
                .none
            )
        }
        for modifier: NSEvent.ModifierFlags in [
            .command,
            .control,
            .option,
            .shift,
        ] {
            XCTAssertEqual(
                ExternalNavigationPolicy.disposition(
                    for: url,
                    isLinkActivation: true,
                    buttonNumber: 1,
                    modifierFlags: modifier,
                    targetsTopLevelContext: true
                ),
                .none
            )
        }
        XCTAssertEqual(
            ExternalNavigationPolicy.disposition(
                for: url,
                isLinkActivation: true,
                buttonNumber: 1,
                modifierFlags: [],
                targetsTopLevelContext: false
            ),
            .none
        )
    }

    func testExternalNavigationPolicyDoesNotBroadenOtherSchemes() {
        let cases: [URL?] = [
            URL(string: "https://example.com"),
            URL(string: "mailto:user@example.com"),
            URL(string: "file:///tmp/private"),
            URL(string: "custom-scheme://host/path"),
            nil,
        ]

        for url in cases {
            XCTAssertEqual(
                ExternalNavigationPolicy.disposition(
                    for: url,
                    isLinkActivation: true,
                    buttonNumber: 1,
                    modifierFlags: [],
                    targetsTopLevelContext: true
                ),
                .none,
                String(describing: url)
            )
        }
    }

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
            URL(string: "magnet:?xt=urn:btih:ABCDEF"),
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

    func testUnmodifiedPrimaryWebLinkTargetsForegroundTabOnlyForNewContext() {
        for url in [
            URL(string: "http://example.com/path"),
            URL(string: "HTTPS://example.com/path"),
        ] {
            XCTAssertEqual(
                NewContextNavigationPolicy.disposition(
                    url: url,
                    isLinkActivation: true,
                    buttonNumber: 1,
                    modifierFlags: [],
                    requestsNewContext: true
                ),
                .foregroundTab
            )
            XCTAssertEqual(
                NewContextNavigationPolicy.disposition(
                    url: url,
                    isLinkActivation: true,
                    buttonNumber: 1,
                    modifierFlags: [],
                    requestsNewContext: false
                ),
                .continueInCurrentFrame
            )
        }
    }

    func testExactCommandPrimaryWebLinkTargetsBackgroundTab() {
        let url = URL(string: "https://example.com/path")
        for requestsNewContext in [false, true] {
            XCTAssertEqual(
                NewContextNavigationPolicy.disposition(
                    url: url,
                    isLinkActivation: true,
                    buttonNumber: 1,
                    modifierFlags: [.command],
                    requestsNewContext: requestsNewContext
                ),
                .backgroundTab
            )
            XCTAssertEqual(
                NewContextNavigationPolicy.disposition(
                    url: url,
                    isLinkActivation: true,
                    buttonNumber: 1,
                    modifierFlags: [.command, .capsLock],
                    requestsNewContext: requestsNewContext
                ),
                .backgroundTab
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
            XCTAssertEqual(
                NewContextNavigationPolicy.disposition(
                    url: url,
                    isLinkActivation: true,
                    buttonNumber: 1,
                    modifierFlags: [],
                    requestsNewContext: true
                ),
                .deny,
                String(describing: url)
            )
        }
    }

    func testNewContextPolicyDeniesSyntheticModifiedAndAlternateClicks() {
        let url = URL(string: "https://example.com/path")

        XCTAssertEqual(
            NewContextNavigationPolicy.disposition(
                url: url,
                isLinkActivation: false,
                buttonNumber: 1,
                modifierFlags: [],
                requestsNewContext: true
            ),
            .deny
        )
        for buttonNumber in [0, 2, 3, 4] {
            XCTAssertEqual(
                NewContextNavigationPolicy.disposition(
                    url: url,
                    isLinkActivation: true,
                    buttonNumber: buttonNumber,
                    modifierFlags: [],
                    requestsNewContext: true
                ),
                .deny
            )
        }
        for modifier: NSEvent.ModifierFlags in [
            .control,
            .option,
            .shift,
            [.command, .control],
            [.command, .option],
            [.command, .shift],
        ] {
            XCTAssertEqual(
                NewContextNavigationPolicy.disposition(
                    url: url,
                    isLinkActivation: true,
                    buttonNumber: 1,
                    modifierFlags: modifier,
                    requestsNewContext: true
                ),
                .deny
            )
        }
    }
}
