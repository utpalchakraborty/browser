import WebKit
import XCTest
@testable import Browser

@MainActor
final class WebKitEdgeCaseTests: XCTestCase {
    func testTargetBlankProvidesAReusableWebViewConfiguration() async throws {
        let profile = BrowserProfile(
            dataStoreIdentifier: UUID(
                uuidString: "A1000000-0000-4000-8000-000000000004"
            )!
        )
        let sourceWebView = profile.webViewFactory.makeWebView()
        try await WebViewNavigationWaiter().load(
            Phase1Fixture.url("/popup"),
            in: sourceWebView
        )

        let popupCreated = expectation(description: "popup web view created")
        let popupFinished = expectation(description: "popup navigation finished")
        let probe = PopupProbe()
        probe.onCreate = { navigationAction, popup in
            XCTAssertNil(navigationAction.targetFrame)
            XCTAssertEqual(
                navigationAction.buttonNumber,
                0,
                "JavaScript anchor.click() must not look pointer-activated."
            )
            XCTAssertTrue(
                popup.configuration.websiteDataStore === profile.websiteDataStore
            )
            popupCreated.fulfill()
        }
        probe.onFinish = { popup in
            XCTAssertEqual(popup.url?.path, "/popup-target")
            popupFinished.fulfill()
        }
        sourceWebView.uiDelegate = probe

        _ = try await sourceWebView.evaluateJavaScript(
            "document.getElementById('popup').click()"
        )
        await fulfillment(
            of: [popupCreated, popupFinished],
            timeout: 3,
            enforceOrder: true
        )
        XCTAssertNotNil(probe.popupWebView)
    }

    func testWindowOpenProvidesAReusableWebViewConfiguration() async throws {
        let profile = BrowserProfile(
            dataStoreIdentifier: UUID(
                uuidString: "A1000000-0000-4000-8000-000000000008"
            )!
        )
        let sourceWebView = profile.webViewFactory.makeWebView()
        try await WebViewNavigationWaiter().load(
            Phase1Fixture.url("/window-open"),
            in: sourceWebView
        )

        let popupCreated = expectation(description: "window.open web view created")
        let popupFinished = expectation(description: "window.open navigation finished")
        let probe = PopupProbe()
        probe.onCreate = { navigationAction, popup in
            XCTAssertNil(navigationAction.targetFrame)
            XCTAssertTrue(
                popup.configuration.websiteDataStore === profile.websiteDataStore
            )
            popupCreated.fulfill()
        }
        probe.onFinish = { popup in
            XCTAssertEqual(popup.url?.path, "/popup-target")
            popupFinished.fulfill()
        }
        sourceWebView.uiDelegate = probe

        _ = try await sourceWebView.evaluateJavaScript(
            "document.getElementById('window-open').click()"
        )
        await fulfillment(
            of: [popupCreated, popupFinished],
            timeout: 3,
            enforceOrder: true
        )
        XCTAssertNotNil(probe.popupWebView)
    }

    func testHTTPBasicAuthenticationChallengeCanBeAnswered() async throws {
        let profile = BrowserProfile(
            dataStoreIdentifier: UUID(
                uuidString: "A1000000-0000-4000-8000-000000000005"
            )!
        )
        let webView = profile.webViewFactory.makeWebView()
        let waiter = WebViewNavigationWaiter(
            credential: URLCredential(
                user: "phase1",
                password: "browser",
                persistence: .none
            )
        )

        try await waiter.load(Phase1Fixture.url("/auth"), in: webView)
        let bodyResult = try await webView.evaluateJavaScript(
            "document.body.textContent"
        )
        XCTAssertEqual(bodyResult as? String, "authenticated")
        XCTAssertEqual(waiter.authenticationChallengeCount, 1)
    }

    func testUnsupportedResponseBecomesCancellableDownload() async throws {
        let profile = BrowserProfile(
            dataStoreIdentifier: UUID(
                uuidString: "A1000000-0000-4000-8000-000000000006"
            )!
        )
        let webView = profile.webViewFactory.makeWebView()
        let downloadCreated = expectation(description: "download created")
        let destinationRequested = expectation(
            description: "download destination requested"
        )
        let probe = DownloadProbe()
        probe.onDownloadCreated = { _ in
            downloadCreated.fulfill()
        }
        probe.onDestinationRequested = { response, suggestedFilename in
            XCTAssertEqual(response.mimeType, "application/octet-stream")
            XCTAssertEqual(suggestedFilename, "phase1.bin")
            destinationRequested.fulfill()
        }
        webView.navigationDelegate = probe

        XCTAssertNotNil(webView.load(URLRequest(url: Phase1Fixture.url("/download"))))
        await fulfillment(
            of: [downloadCreated, destinationRequested],
            timeout: 3,
            enforceOrder: true
        )
        XCTAssertNotNil(probe.download)
    }

    func testRedirectLoopReportsAProvisionalNavigationFailure() async {
        let profile = BrowserProfile(
            dataStoreIdentifier: UUID(
                uuidString: "A1000000-0000-4000-8000-000000000007"
            )!
        )
        let webView = profile.webViewFactory.makeWebView()

        do {
            try await WebViewNavigationWaiter().load(
                Phase1Fixture.url("/redirect-loop"),
                in: webView
            )
            XCTFail("Redirect loop unexpectedly loaded")
        } catch {
            XCTAssertEqual((error as NSError).domain, NSURLErrorDomain)
            XCTAssertEqual(
                (error as NSError).code,
                NSURLErrorHTTPTooManyRedirects
            )
        }
    }
}
