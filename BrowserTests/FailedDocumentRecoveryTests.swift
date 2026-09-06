import AppKit
import WebKit
import XCTest

@testable import Browser

@MainActor
final class FailedDocumentRecoveryTests: XCTestCase {
    func testFirstBlockedDocumentOffersExactHostAndLoadsAfterExplicitMenuAction() async throws {
        let fixture = try await makeFixture(initialURL: url("/normal/"))
        defer { fixture.cleanUp() }
        try await wait { fixture.tab.failedDocumentRecovery != nil }
        XCTAssertNil(fixture.tab.committedURL)
        XCTAssertFalse(fixture.coordinator.snapshot(for: url("/normal/")).isException)
        let menu = menuItem()
        XCTAssertTrue(fixture.controller.validateMenuItem(menu))
        XCTAssertEqual(menu.title, "Disable Blocking for 127.0.0.1 and Retry Failed Page")
        XCTAssertFalse(fixture.controller.window!.isVisible)
        fixture.controller.toggleContentBlockingForCurrentSiteAndReload(menu)
        try await wait {
            fixture.tab.committedURL == self.url("/normal/") && !fixture.tab.observedIsLoading
        }
        XCTAssertTrue(fixture.coordinator.snapshot(for: url("/normal/")).isException)
        XCTAssertNil(fixture.tab.failedDocumentRecovery)
        XCTAssertEqual(fixture.tab.webView?.title, "blocking fixture")
    }

    func testFailureAfterAnotherHostRetriesDestinationAndSynchronizesBackgroundTab() async throws {
        let fixture = try await makeFixture(initialURL: url("/phase2/page-a"), viewCount: 2)
        defer { fixture.cleanUp() }
        let background = try XCTUnwrap(
            fixture.controller.webViews.last?.navigationDelegate as? TabController)
        try await wait {
            fixture.tab.committedURL != nil && background.committedURL != nil
                && !background.observedIsLoading
        }
        XCTAssertTrue(fixture.tab.navigate(to: url("/phase2/page-a", host: "localhost")))
        try await wait {
            fixture.tab.committedURL?.host == "localhost" && !fixture.tab.observedIsLoading
        }
        XCTAssertTrue(fixture.tab.navigate(to: url("/normal/")))
        try await wait { fixture.tab.failedDocumentRecovery != nil }
        let menu = menuItem()
        XCTAssertTrue(fixture.controller.validateMenuItem(menu))
        XCTAssertTrue(menu.title.contains("127.0.0.1"))
        fixture.controller.toggleContentBlockingForCurrentSiteAndReload(menu)
        XCTAssertTrue(
            background.hasActiveNavigation,
            "Same-host resident tab must reload under the explicit policy")
        try await wait {
            fixture.tab.committedURL == self.url("/normal/") && !fixture.tab.observedIsLoading
                && !background.hasActiveNavigation
        }
        XCTAssertFalse(
            fixture.coordinator.snapshot(for: url("/phase2/page-a", host: "localhost")).isException)
        XCTAssertEqual(background.committedURL, url("/phase2/page-a"))
    }

    func testRedirectFailureUsesFinalHostAndURL() async throws {
        let fixture = try await makeFixture(initialURL: url("/g05/redirect", host: "localhost"))
        defer { fixture.cleanUp() }
        try await wait { fixture.tab.failedDocumentRecovery != nil }
        XCTAssertEqual(fixture.tab.failedDocumentRecovery?.url, url("/normal/"))
        let menu = menuItem()
        XCTAssertTrue(fixture.controller.validateMenuItem(menu))
        XCTAssertTrue(menu.title.contains("127.0.0.1"))
        fixture.controller.toggleContentBlockingForCurrentSiteAndReload(menu)
        try await wait {
            fixture.tab.committedURL == self.url("/normal/") && !fixture.tab.observedIsLoading
        }
        XCTAssertFalse(
            fixture.coordinator.snapshot(for: url("/g05/redirect", host: "localhost")).isException)
    }

    func testSupersededFailureAndCapturedMenuCannotChangeNewAttemptPolicy() async throws {
        let fixture = try await makeFixture(initialURL: url("/normal/"))
        defer { fixture.cleanUp() }
        try await wait { fixture.tab.failedDocumentRecovery != nil }
        let recovery = try XCTUnwrap(fixture.tab.failedDocumentRecovery)
        let menu = menuItem()
        XCTAssertTrue(fixture.controller.validateMenuItem(menu))
        XCTAssertTrue(fixture.tab.navigate(to: url("/phase2/slow-response")))
        XCTAssertNil(fixture.tab.failedDocumentRecovery)
        XCTAssertFalse(fixture.tab.retryFailedDocument(recovery))
        fixture.controller.toggleContentBlockingForCurrentSiteAndReload(menu)
        XCTAssertFalse(fixture.coordinator.snapshot(for: recovery.url).isException)
        try await wait { !fixture.tab.hasActiveNavigation }
        fixture.controller.toggleContentBlockingForCurrentSiteAndReload(menu)
        XCTAssertFalse(fixture.coordinator.snapshot(for: recovery.url).isException)

        let webView = try XCTUnwrap(fixture.tab.webView)
        let oldNavigation = try XCTUnwrap(webView.load(URLRequest(url: url("/normal/"))))
        fixture.tab.webView(webView, didStartProvisionalNavigation: oldNavigation)
        XCTAssertTrue(fixture.tab.navigate(to: url("/phase2/page-a")))
        fixture.tab.webView(
            webView, didFailProvisionalNavigation: oldNavigation,
            withError: NSError(domain: "WebKitErrorDomain", code: 104))
        XCTAssertNil(fixture.tab.failedDocumentRecovery)
        try await wait {
            fixture.tab.committedURL == self.url("/phase2/page-a") && !fixture.tab.observedIsLoading
        }
    }

    func testActiveSameHostTabDisablesRecoveryAndSelectionRejectsCapturedMenu() async throws {
        let fixture = try await makeFixture(initialURL: url("/normal/"), viewCount: 2)
        defer { fixture.cleanUp() }
        let background = try XCTUnwrap(
            fixture.controller.webViews.last?.navigationDelegate as? TabController)
        try await wait {
            fixture.tab.failedDocumentRecovery != nil && background.failedDocumentRecovery != nil
        }
        let menu = menuItem()
        XCTAssertTrue(fixture.controller.validateMenuItem(menu))
        fixture.controller.selectTab(id: background.id)
        fixture.controller.toggleContentBlockingForCurrentSiteAndReload(menu)
        XCTAssertFalse(fixture.coordinator.snapshot(for: url("/normal/")).isException)
        fixture.controller.selectTab(id: fixture.tab.id)
        XCTAssertTrue(background.navigate(to: url("/phase2/slow-response")))
        XCTAssertFalse(fixture.controller.validateMenuItem(menu))
        try await wait { !background.hasActiveNavigation }
        XCTAssertTrue(fixture.controller.validateMenuItem(menu))
    }

    func testTLSCancellationNonWebAndPostCommitFailuresDoNotOfferExceptionRecovery() async throws {
        let fixture = try await makeFixture(initialURL: url("/phase2/page-a"))
        defer { fixture.cleanUp() }
        try await wait { fixture.tab.committedURL != nil && !fixture.tab.observedIsLoading }
        let webView = try XCTUnwrap(fixture.tab.webView)
        for (error, failingURL) in [
            (URLError(.serverCertificateUntrusted), url("/normal/")),
            (URLError(.cancelled), url("/normal/")),
            (URLError(.cannotConnectToHost), URL(string: "file:///tmp/private.html")!),
        ] {
            let navigation = try XCTUnwrap(
                webView.load(URLRequest(url: URL(string: "about:blank")!)))
            fixture.tab.webView(webView, didStartProvisionalNavigation: navigation)
            let failure = NSError(
                domain: NSURLErrorDomain, code: error.errorCode,
                userInfo: [NSURLErrorFailingURLErrorKey: failingURL])
            fixture.tab.webView(
                webView, didFailProvisionalNavigation: navigation, withError: failure)
            XCTAssertNil(fixture.tab.failedDocumentRecovery)
            webView.stopLoading()
        }
        let navigation = try XCTUnwrap(webView.load(URLRequest(url: URL(string: "about:blank")!)))
        fixture.tab.webView(webView, didStartProvisionalNavigation: navigation)
        fixture.tab.webView(webView, didCommit: navigation)
        fixture.tab.webView(webView, didFail: navigation, withError: URLError(.cannotConnectToHost))
        XCTAssertNil(fixture.tab.failedDocumentRecovery)
    }

    private func url(_ path: String, host: String = "127.0.0.1") -> URL {
        URL(string: "http://\(host):18765\(path)")!
    }

    private func menuItem() -> NSMenuItem {
        NSMenuItem(
            title: "",
            action: #selector(
                BrowserWindowController.toggleContentBlockingForCurrentSiteAndReload(_:)),
            keyEquivalent: "")
    }

    private func wait(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(10)
        while !condition(), Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(condition(), "Timed out waiting for hidden WebKit fixture")
        if !condition() { throw WebViewTestError.loadDidNotStart }
    }

    private func makeFixture(initialURL: URL, viewCount: Int = 1) async throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "FailedDocumentRecoveryTests.\(UUID())")
        let store = try XCTUnwrap(WKContentRuleListStore(url: directory))
        let suite = "FailedDocumentRecoveryTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let rules = try ContentBlockerService.probeRules(
            blockedURLFilter: ".*/normal/.*", exceptionTopURLFilters: [],
            resourceTypes: ["document"])
        let namespace = "browser-failed-document-\(UUID())"
        let coordinator = ContentBlockingCoordinator(
            resolver: ContentBlockerRuleSetResolver(
                service: ContentBlockerService(ruleStore: store),
                stateStore: ContentBlockerStateStore(defaults: defaults)),
            sitePolicyStore: ContentBlockerSitePolicyStore(defaults: defaults)
        )
        await coordinator.prepare(currentSources: [
            ContentBlockerRuleSource(
                namespace: namespace,
                identifier: ContentBlockerService.versionedIdentifier(
                    namespace: namespace, encodedRules: rules),
                encodedRulesLoader: { rules }
            )
        ])
        XCTAssertTrue(coordinator.isReady)
        let controller = BrowserWindowController(contentBlockingCoordinator: coordinator)
        controller.installWebViews(
            profile: BrowserProfile(dataStoreIdentifier: UUID()), viewCount: viewCount,
            initialURL: initialURL)
        let tab = try XCTUnwrap(controller.webView?.navigationDelegate as? TabController)
        return Fixture(
            controller: controller, tab: tab, coordinator: coordinator, directory: directory,
            defaults: defaults, suite: suite)
    }

    private struct Fixture {
        let controller: BrowserWindowController
        let tab: TabController
        let coordinator: ContentBlockingCoordinator
        let directory: URL
        let defaults: UserDefaults
        let suite: String

        func cleanUp() {
            XCTAssertFalse(controller.window!.isVisible)
            controller.window?.close()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
    }
}
