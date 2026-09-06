import AppKit
import XCTest
@testable import Browser

@MainActor
final class AddressSubmissionTests: XCTestCase {
    func testPastedMagnetShowsErrorWithoutLoadingOrOpeningExternally() throws {
        for provider in SearchProvider.allCases {
            for input in ["magnet:?xt=urn:btih:private&dn=private&tr=https%3A%2F%2Ftracker.example", " \nMaGnEt:?xt=urn:btih:private\t"] {
                var openedURLs: [URL] = []
                let controller = BrowserWindowController(searchProvider: provider, externalURLOpener: {
                    openedURLs.append($0)
                    return true
                })
                let window = try XCTUnwrap(controller.window)
                defer { window.close() }
                let chrome = try XCTUnwrap(window.contentView as? BrowserChromeView)
                chrome.addressField.stringValue = input
                controller.submitAddress(nil)
                XCTAssertFalse(chrome.errorView.isHidden)
                XCTAssertEqual(chrome.errorView.accessibilityLabel(), "Unsupported Address")
                XCTAssertNil(controller.pendingNavigationURL)
                XCTAssertNil(controller.webView)
                XCTAssertTrue(openedURLs.isEmpty)
                XCTAssertFalse(window.isVisible)
                // A subsequent ordinary address proves this fixture observes queued loads.
                chrome.addressField.stringValue = "example.com"
                controller.submitAddress(nil)
                XCTAssertEqual(controller.pendingNavigationURL?.absoluteString, "https://example.com")
            }
        }
    }
}
