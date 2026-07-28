import WebKit
import XCTest
@testable import Browser

@MainActor
final class WebsiteDataControllerTests: XCTestCase {
    func testCookiesPersistAcrossWebViewsAndCanBeDeleted() async throws {
        let identifier = UUID(uuidString: "A1000000-0000-4000-8000-000000000001")!
        let profile = BrowserProfile(dataStoreIdentifier: identifier)
        let dataController = WebsiteDataController(
            websiteDataStore: profile.websiteDataStore
        )
        await dataController.clearAllWebsiteData()

        var firstWebView: WKWebView? = profile.webViewFactory.makeWebView()
        try await WebViewNavigationWaiter().load(
            Phase1Fixture.url("/cookie/set"),
            in: try XCTUnwrap(firstWebView)
        )

        let cookies = await dataController.cookies()
        let persistentCookie = try XCTUnwrap(
            cookies.first(where: { $0.name == "phase1" })
        )
        XCTAssertEqual(persistentCookie.value, "persisted")
        XCTAssertNotNil(persistentCookie.expiresDate)
        XCTAssertTrue(persistentCookie.isHTTPOnly)

        let sessionCookie = try XCTUnwrap(
            cookies.first(where: { $0.name == "phase1session" })
        )
        XCTAssertEqual(sessionCookie.value, "transient")
        XCTAssertNil(sessionCookie.expiresDate)

        let simultaneousWebView = profile.webViewFactory.makeWebView()
        try await WebViewNavigationWaiter().load(
            Phase1Fixture.url("/cookie/echo"),
            in: simultaneousWebView
        )
        let simultaneousCookieResult = try await simultaneousWebView
            .evaluateJavaScript("document.body.textContent")
        let simultaneousCookies = try XCTUnwrap(
            simultaneousCookieResult as? String
        )
        XCTAssertTrue(simultaneousCookies.contains("phase1=persisted"))
        XCTAssertTrue(simultaneousCookies.contains("phase1session=transient"))

        firstWebView = nil

        let reconstructedProfile = BrowserProfile(dataStoreIdentifier: identifier)
        let secondWebView = reconstructedProfile.webViewFactory.makeWebView()
        try await WebViewNavigationWaiter().load(
            Phase1Fixture.url("/cookie/echo"),
            in: secondWebView
        )
        let echoedCookieResult = try await secondWebView.evaluateJavaScript(
            "document.body.textContent"
        )
        let echoedCookies = try XCTUnwrap(
            echoedCookieResult as? String
        )
        XCTAssertTrue(echoedCookies.contains("phase1=persisted"))
        XCTAssertTrue(echoedCookies.contains("phase1session=transient"))

        await dataController.deleteCookie(persistentCookie)
        let remainingAfterIndividualDelete = await dataController.cookies()
        XCTAssertFalse(
            remainingAfterIndividualDelete.contains(where: { $0.name == "phase1" })
        )
        XCTAssertTrue(
            remainingAfterIndividualDelete.contains(where: {
                $0.name == "phase1session"
            })
        )

        await dataController.deleteCookies(applicableToHost: "127.0.0.1")
        let cookiesAfterDomainDelete = await dataController.cookies()
        XCTAssertTrue(cookiesAfterDomainDelete.isEmpty)

        try await WebViewNavigationWaiter().load(
            Phase1Fixture.url("/cookie/set"),
            in: secondWebView
        )
        let cookiesBeforeGlobalCookieDelete = await dataController.cookies()
        XCTAssertFalse(cookiesBeforeGlobalCookieDelete.isEmpty)
        let storageBeforeCookieDelete = try await secondWebView
            .evaluateJavaScript(
                "localStorage.setItem('phase1-cookie-delete-retained', "
                    + "'present'); "
                    + "localStorage.getItem('phase1-cookie-delete-retained')"
            )
        XCTAssertEqual(storageBeforeCookieDelete as? String, "present")
        await dataController.clearAllCookies()
        let cookiesAfterGlobalCookieDelete = await dataController.cookies()
        XCTAssertTrue(cookiesAfterGlobalCookieDelete.isEmpty)
        let storageAfterCookieDelete = try await secondWebView.evaluateJavaScript(
            "localStorage.getItem('phase1-cookie-delete-retained')"
        )
        XCTAssertEqual(storageAfterCookieDelete as? String, "present")

        try await WebViewNavigationWaiter().load(
            Phase1Fixture.url("/cookie/set"),
            in: secondWebView
        )
        await dataController.clearAllWebsiteData()
        let cookiesAfterClearAll = await dataController.cookies()
        XCTAssertTrue(cookiesAfterClearAll.isEmpty)
    }

    func testWebsiteDataCanBeEnumeratedAndDeleted() async throws {
        let identifier = UUID(uuidString: "A1000000-0000-4000-8000-000000000002")!
        let profile = BrowserProfile(dataStoreIdentifier: identifier)
        let dataController = WebsiteDataController(
            websiteDataStore: profile.websiteDataStore
        )
        await dataController.clearAllWebsiteData()

        var webView: WKWebView? = profile.webViewFactory.makeWebView()
        try await WebViewNavigationWaiter().load(
            Phase1Fixture.url("/storage"),
            in: try XCTUnwrap(webView)
        )
        _ = try await webView?.callAsyncJavaScript(
            "return await window.storageReady;",
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        let localStorageResult = try await webView?.evaluateJavaScript(
            "localStorage.getItem('phase1-local-storage')"
        )
        let localStorageValue = try XCTUnwrap(
            localStorageResult as? String
        )
        XCTAssertEqual(localStorageValue, "present")
        webView = nil

        let relevantTypes: Set<String> = [
            WKWebsiteDataTypeLocalStorage,
            WKWebsiteDataTypeIndexedDBDatabases,
            WKWebsiteDataTypeFetchCache,
            WKWebsiteDataTypeServiceWorkerRegistrations,
        ]
        let records = await dataController.records(ofTypes: relevantTypes)
        let fixtureRecords = records.filter {
            $0.displayName.contains("127.0.0.1")
        }
        XCTAssertFalse(fixtureRecords.isEmpty)
        let observedTypes = fixtureRecords.reduce(into: Set<String>()) {
            observed, record in
            observed.formUnion(record.dataTypes)
        }
        XCTAssertTrue(
            observedTypes.isSuperset(of: relevantTypes),
            "Missing storage categories: \(relevantTypes.subtracting(observedTypes))"
        )

        await dataController.delete(
            records: fixtureRecords,
            dataTypes: relevantTypes
        )
        let recordsAfterDelete = await dataController.records(ofTypes: relevantTypes)
        XCTAssertFalse(
            recordsAfterDelete.contains(where: {
                $0.displayName.contains("127.0.0.1")
            })
        )

        webView = profile.webViewFactory.makeWebView()
        try await WebViewNavigationWaiter().load(
            Phase1Fixture.url("/storage"),
            in: try XCTUnwrap(webView)
        )
        _ = try await webView?.callAsyncJavaScript(
            "return await window.storageReady;",
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        webView = nil
        await dataController.clearAllWebsiteData()
        let recordsAfterClearAll = await dataController.records(
            ofTypes: relevantTypes
        )
        XCTAssertFalse(
            recordsAfterClearAll.contains(where: {
                $0.displayName.contains("127.0.0.1")
            })
        )
    }

    func testVerifiedCookieDeletionUsesStableIdentity() async throws {
        let dataStore = WKWebsiteDataStore.nonPersistent()
        let dataController = WebsiteDataController(
            websiteDataStore: dataStore
        )
        let cookie = try makeCookie(
            header: "stable-id=secret; Domain=.example.com; Path=/account; Max-Age=3600; HttpOnly; SameSite=Lax",
            url: "https://example.com/account"
        )
        await dataStore.httpCookieStore.setCookie(cookie)

        let before = await dataController.snapshot()
        let identifier = WebsiteCookieID(cookie: cookie)
        XCTAssertTrue(before.containsCookie(id: identifier))

        let result = await dataController.deleteCookie(withID: identifier)

        XCTAssertTrue(result.didRemoveRequestedData)
        XCTAssertFalse(result.snapshot.containsCookie(id: identifier))
        XCTAssertFalse(result.message.contains(cookie.value))
    }

    func testVerifiedWebsiteRecordAndGlobalDeletionRefreshSnapshots() async throws {
        let identifier = UUID(
            uuidString: "A1000000-0000-4000-8000-000000000003"
        )!
        let profile = BrowserProfile(dataStoreIdentifier: identifier)
        let dataController = WebsiteDataController(
            websiteDataStore: profile.websiteDataStore
        )
        await dataController.clearAllWebsiteData()

        var webView: WKWebView? = profile.webViewFactory.makeWebView()
        try await WebViewNavigationWaiter().load(
            Phase1Fixture.url("/storage"),
            in: try XCTUnwrap(webView)
        )
        _ = try await webView?.callAsyncJavaScript(
            "return await window.storageReady;",
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        webView = nil

        let before = await dataController.snapshot()
        let fixtureRecord = try XCTUnwrap(
            before.records.first {
                $0.displayName.contains("127.0.0.1")
            }
        )
        XCTAssertFalse(fixtureRecord.categories.isEmpty)

        let domainResult = await dataController.deleteWebsiteData(
            for: fixtureRecord.id
        )
        XCTAssertTrue(domainResult.didRemoveRequestedData)
        XCTAssertFalse(domainResult.snapshot.containsRecord(id: fixtureRecord.id))

        webView = profile.webViewFactory.makeWebView()
        try await WebViewNavigationWaiter().load(
            Phase1Fixture.url("/cookie/set"),
            in: try XCTUnwrap(webView)
        )
        webView = nil
        let recreatedSnapshot = await dataController.snapshot()
        XCTAssertGreaterThan(recreatedSnapshot.cookieCount, 0)

        let globalResult = await dataController.clearAllWebsiteDataAndVerify()
        XCTAssertTrue(globalResult.didRemoveRequestedData)
        XCTAssertEqual(globalResult.snapshot, .empty)
    }

    func testExactCookieDomainDeletionDoesNotDeleteSubdomainCookies() async throws {
        let dataStore = WKWebsiteDataStore.nonPersistent()
        let dataController = WebsiteDataController(
            websiteDataStore: dataStore
        )
        let parentCookie = try makeCookie(
            header: "parent=one; Domain=.example.com; Path=/; Max-Age=3600",
            url: "https://example.com/"
        )
        let childCookie = try makeCookie(
            header: "child=two; Domain=sub.example.com; Path=/; Max-Age=3600",
            url: "https://sub.example.com/"
        )
        await dataStore.httpCookieStore.setCookie(parentCookie)
        await dataStore.httpCookieStore.setCookie(childCookie)

        let result = await dataController.deleteCookies(
            exactDomain: "EXAMPLE.com."
        )

        XCTAssertTrue(result.didRemoveRequestedData)
        XCTAssertFalse(result.snapshot.containsCookies(exactDomain: "example.com"))
        XCTAssertTrue(
            result.snapshot.containsCookie(
                id: WebsiteCookieID(cookie: childCookie)
            )
        )
        XCTAssertTrue(result.message.contains("Other website data was left intact"))
    }

    func testCookieDomainMatchingDoesNotCrossDomainBoundaries() {
        XCTAssertTrue(
            WebsiteDataController.cookieDomain(
                ".example.com",
                isApplicableToHost: "example.com"
            )
        )
        XCTAssertTrue(
            WebsiteDataController.cookieDomain(
                ".example.com",
                isApplicableToHost: "ACCOUNT.EXAMPLE.COM"
            )
        )
        XCTAssertFalse(
            WebsiteDataController.cookieDomain(
                "notexample.com",
                isApplicableToHost: "example.com"
            )
        )
        XCTAssertFalse(
            WebsiteDataController.cookieDomain(
                ".account.example.com",
                isApplicableToHost: "www.example.com"
            )
        )
        XCTAssertTrue(
            WebsiteDataController.cookieDomain(
                "127.0.0.1",
                isApplicableToHost: "127.0.0.1"
            )
        )
        XCTAssertFalse(
            WebsiteDataController.cookieDomain(
                "",
                isApplicableToHost: ""
            )
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
