import Foundation
import WebKit
import XCTest
@testable import Browser

@MainActor
final class ContentBlockingCoordinatorTests: XCTestCase {
    func testSnapshotMovesFromPreparingToActiveAndUsesExactHostExceptions() async throws {
        let fixture = try makeFixture()
        defer { cleanUp(fixture) }
        let accountURL = try XCTUnwrap(
            URL(string: "https://Account.Example.com:443/settings")
        )
        let accountSite = try XCTUnwrap(
            ContentBlockerSite(host: "account.example.com")
        )

        XCTAssertFalse(fixture.coordinator.isReady)
        XCTAssertEqual(
            fixture.coordinator.snapshot(for: accountURL),
            ContentBlockingSnapshot(
                availability: .preparing,
                site: accountSite,
                isException: false
            )
        )
        XCTAssertFalse(
            fixture.coordinator.applyPolicy(
                to: WKUserContentController(),
                for: accountURL
            )
        )

        let rules = try ContentBlockerService.probeRules(
            blockedURLFilter: ".*/coordinator-active[.]js",
            exceptionTopURLFilters: []
        )
        await fixture.coordinator.prepare(
            currentSources: [
                makeSource(
                    namespace: "coordinator-active",
                    rules: rules
                )
            ]
        )

        XCTAssertTrue(fixture.coordinator.isReady)
        XCTAssertEqual(
            fixture.coordinator.snapshot(for: accountURL),
            ContentBlockingSnapshot(
                availability: .active,
                site: accountSite,
                isException: false
            )
        )
        XCTAssertEqual(
            fixture.coordinator.toggleException(for: accountURL),
            accountSite
        )
        XCTAssertEqual(
            fixture.coordinator.siteExceptionHosts,
            ["account.example.com"]
        )
        XCTAssertEqual(fixture.coordinator.siteExceptionCount, 1)
        XCTAssertTrue(
            fixture.coordinator.snapshot(
                for: URL(string: "http://ACCOUNT.EXAMPLE.COM./another-path")
            ).isException
        )
        XCTAssertFalse(
            fixture.coordinator.snapshot(
                for: URL(string: "https://example.com/")
            ).isException,
            "An exact subdomain exception must not broaden to its parent host"
        )
        XCTAssertFalse(
            fixture.coordinator.snapshot(
                for: URL(string: "https://www.account.example.com/")
            ).isException,
            "An exact-host exception must not broaden to child hosts"
        )
    }

    func testSnapshotReportsLastValidRulesWhenCurrentPreparationFails() async throws {
        let fixture = try makeFixture()
        defer { cleanUp(fixture) }
        let fallbackRules = try ContentBlockerService.probeRules(
            blockedURLFilter: ".*/coordinator-fallback[.]js",
            exceptionTopURLFilters: []
        )
        let fallbackIdentifier = ContentBlockerService.versionedIdentifier(
            namespace: "coordinator-fallback",
            encodedRules: fallbackRules
        )
        _ = try await fixture.service.compileRuleList(
            identifier: fallbackIdentifier,
            encodedRules: fallbackRules
        )
        fixture.stateStore.recordLastValidIdentifiers([fallbackIdentifier])

        let invalidRules = try ContentBlockerService.probeRules(
            blockedURLFilter: "(",
            exceptionTopURLFilters: []
        )
        await fixture.coordinator.prepare(
            currentSources: [
                makeSource(
                    namespace: "coordinator-invalid-current",
                    rules: invalidRules
                )
            ]
        )

        XCTAssertTrue(fixture.coordinator.isReady)
        XCTAssertEqual(
            fixture.coordinator.snapshot(for: URL(string: "https://example.com/")),
            ContentBlockingSnapshot(
                availability: .activeLastValidRules,
                site: ContentBlockerSite(host: "example.com"),
                isException: false
            )
        )
    }

    func testSnapshotReportsUnavailableAndPolicyFailsClosedWithoutRules() async throws {
        let fixture = try makeFixture()
        defer { cleanUp(fixture) }
        let url = try XCTUnwrap(URL(string: "https://example.com/"))

        await fixture.coordinator.prepare(currentSources: [])

        XCTAssertFalse(fixture.coordinator.isReady)
        XCTAssertEqual(
            fixture.coordinator.snapshot(for: url),
            ContentBlockingSnapshot(
                availability: .unavailable,
                site: ContentBlockerSite(host: "example.com"),
                isException: false
            )
        )
        XCTAssertFalse(
            fixture.coordinator.applyPolicy(
                to: WKUserContentController(),
                for: url
            ),
            "Navigation must remain paused when no valid rules are prepared"
        )
    }

    func testExactHostExceptionDetachesRulesAndResetReattachesThemOnReload() async throws {
        let fixture = try makeFixture()
        defer { cleanUp(fixture) }
        let rules = try ContentBlockerService.probeRules(
            blockedURLFilter: ".*/assets/blocked[.]js",
            exceptionTopURLFilters: []
        )
        await fixture.coordinator.prepare(
            currentSources: [
                makeSource(namespace: "coordinator-policy-reload", rules: rules)
            ]
        )
        let pageURL = Phase1Fixture.url("/normal/")
        let contentController = WKUserContentController()

        XCTAssertTrue(
            fixture.coordinator.applyPolicy(
                to: contentController,
                for: pageURL
            )
        )
        let profile = BrowserProfile(
            dataStoreIdentifier: BrowserProfile.testHostDataStoreIdentifier
        )
        let webView = profile.webViewFactory.makeWebView(
            userContentController: contentController
        )

        try await WebViewNavigationWaiter().load(pageURL, in: webView)
        let loadedWhileProtected = try await blockedScriptLoaded(in: webView)
        XCTAssertFalse(loadedWhileProtected)

        XCTAssertEqual(
            fixture.coordinator.toggleException(for: pageURL)?.host,
            "127.0.0.1"
        )
        XCTAssertTrue(
            fixture.coordinator.applyPolicy(
                to: contentController,
                for: pageURL
            )
        )
        try await WebViewNavigationWaiter().reload(webView)
        let loadedWithException = try await blockedScriptLoaded(in: webView)
        XCTAssertTrue(
            loadedWithException,
            "The exact-host exception must detach the prepared rules before reload"
        )

        fixture.coordinator.resetSiteExceptions()
        XCTAssertFalse(fixture.coordinator.snapshot(for: pageURL).isException)
        XCTAssertTrue(
            fixture.coordinator.applyPolicy(
                to: contentController,
                for: pageURL
            )
        )
        try await WebViewNavigationWaiter().reload(webView)
        let loadedAfterReset = try await blockedScriptLoaded(in: webView)
        XCTAssertFalse(
            loadedAfterReset,
            "Reset must reattach the prepared rules before reload"
        )

        fixture.coordinator.forget(contentController)
    }

    func testCompiledArtifactResetIsRejectedWhilePreparing() async throws {
        let fixture = try makeFixture()
        defer { cleanUp(fixture) }
        let rules = try ContentBlockerService.probeRules(
            blockedURLFilter: ".*/reset-while-preparing[.]js",
            exceptionTopURLFilters: []
        )
        let identifier = ContentBlockerService.versionedIdentifier(
            namespace: "reset-while-preparing",
            encodedRules: rules
        )
        _ = try await fixture.service.compileRuleList(
            identifier: identifier,
            encodedRules: rules
        )
        fixture.stateStore.recordLastValidIdentifiers([identifier])

        XCTAssertFalse(fixture.coordinator.canResetCompiledArtifacts)
        do {
            _ = try await fixture.coordinator.resetCompiledArtifacts()
            XCTFail("A compiled-artifact reset started while preparation was active")
        } catch {
            XCTAssertEqual(
                error as? ContentBlockerArtifactResetError,
                .preparationInProgress
            )
        }

        let identifiersAfterRejection =
            await fixture.service.availableCachedRuleListIdentifiers()
        XCTAssertEqual(identifiersAfterRejection, [identifier])
        XCTAssertEqual(
            fixture.stateStore.lastValidIdentifiers(),
            [identifier]
        )
    }

    func testCompiledArtifactResetPreservesActiveRulesAndRecompilesOnRestart() async throws {
        let fixture = try makeFixture()
        defer { cleanUp(fixture) }
        let rules = try ContentBlockerService.probeRules(
            blockedURLFilter: ".*/assets/blocked[.]js",
            exceptionTopURLFilters: []
        )
        let namespace = "coordinator-reset-recompile"
        let identifier = ContentBlockerService.versionedIdentifier(
            namespace: namespace,
            encodedRules: rules
        )
        let loader = ContentBlockerRuleSourceLoadProbe(rules: rules)
        let source = ContentBlockerRuleSource(
            namespace: namespace,
            identifier: identifier,
            encodedRulesLoader: {
                await loader.load()
            }
        )
        await fixture.coordinator.prepare(currentSources: [source])
        let initialLoaderCallCount = await loader.numberOfCalls()
        XCTAssertEqual(initialLoaderCallCount, 1)

        let pageURL = Phase1Fixture.url("/normal/")
        let contentController = WKUserContentController()
        XCTAssertTrue(
            fixture.coordinator.applyPolicy(
                to: contentController,
                for: pageURL
            )
        )
        let profile = BrowserProfile(
            dataStoreIdentifier: BrowserProfile.testHostDataStoreIdentifier
        )
        let webView = profile.webViewFactory.makeWebView(
            userContentController: contentController
        )
        try await WebViewNavigationWaiter().load(pageURL, in: webView)
        let loadedBeforeReset = try await blockedScriptLoaded(in: webView)
        XCTAssertFalse(loadedBeforeReset)
        XCTAssertTrue(fixture.coordinator.canResetCompiledArtifacts)

        let result = try await fixture.coordinator.resetCompiledArtifacts()

        XCTAssertEqual(result.removedIdentifiers, [identifier])
        XCTAssertTrue(fixture.coordinator.isReady)
        XCTAssertEqual(fixture.coordinator.availability, .active)
        XCTAssertTrue(fixture.coordinator.canResetCompiledArtifacts)
        let identifiersAfterReset =
            await fixture.service.availableCachedRuleListIdentifiers()
        XCTAssertEqual(identifiersAfterReset, [])
        XCTAssertNil(fixture.stateStore.lastValidIdentifiers())

        try await WebViewNavigationWaiter().reload(webView)
        let loadedAfterReset = try await blockedScriptLoaded(in: webView)
        XCTAssertFalse(
            loadedAfterReset,
            "Deleting the cached copy must not detach the in-memory rules"
        )

        let reconstructedCoordinator = ContentBlockingCoordinator(
            resolver: ContentBlockerRuleSetResolver(
                service: fixture.service,
                stateStore: fixture.stateStore
            ),
            sitePolicyStore: ContentBlockerSitePolicyStore(
                defaults: fixture.defaults
            )
        )
        await reconstructedCoordinator.prepare(currentSources: [source])

        let reconstructedLoaderCallCount = await loader.numberOfCalls()
        XCTAssertEqual(reconstructedLoaderCallCount, 2)
        XCTAssertTrue(reconstructedCoordinator.isReady)
        XCTAssertEqual(reconstructedCoordinator.availability, .active)
        XCTAssertEqual(
            fixture.stateStore.lastValidIdentifiers(),
            [identifier]
        )
        let identifiersAfterReconstruction =
            await fixture.service.availableCachedRuleListIdentifiers()
        XCTAssertEqual(identifiersAfterReconstruction, [identifier])

        fixture.coordinator.forget(contentController)
    }

    private func blockedScriptLoaded(in webView: WKWebView) async throws -> Bool {
        let result = try await webView.evaluateJavaScript(
            "Boolean(window.blockedLoaded)"
        )
        return try XCTUnwrap(result as? Bool)
    }

    private func makeSource(
        namespace: String,
        rules: String
    ) -> ContentBlockerRuleSource {
        ContentBlockerRuleSource(
            namespace: namespace,
            identifier: ContentBlockerService.versionedIdentifier(
                namespace: namespace,
                encodedRules: rules
            ),
            encodedRulesLoader: { rules }
        )
    }

    private func makeFixture() throws -> ContentBlockingCoordinatorFixture {
        let ruleStoreDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ContentBlockingCoordinatorTests.\(UUID().uuidString)",
                isDirectory: true
            )
        let ruleStore = try XCTUnwrap(
            WKContentRuleListStore(url: ruleStoreDirectory)
        )
        let defaultsSuiteName =
            "ContentBlockingCoordinatorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuiteName))
        let service = ContentBlockerService(ruleStore: ruleStore)
        let stateStore = ContentBlockerStateStore(defaults: defaults)
        let sitePolicyStore = ContentBlockerSitePolicyStore(defaults: defaults)
        return ContentBlockingCoordinatorFixture(
            ruleStoreDirectory: ruleStoreDirectory,
            defaultsSuiteName: defaultsSuiteName,
            defaults: defaults,
            service: service,
            stateStore: stateStore,
            coordinator: ContentBlockingCoordinator(
                resolver: ContentBlockerRuleSetResolver(
                    service: service,
                    stateStore: stateStore
                ),
                sitePolicyStore: sitePolicyStore
            )
        )
    }

    private func cleanUp(_ fixture: ContentBlockingCoordinatorFixture) {
        fixture.defaults.removePersistentDomain(
            forName: fixture.defaultsSuiteName
        )
        try? FileManager.default.removeItem(at: fixture.ruleStoreDirectory)
    }
}

private struct ContentBlockingCoordinatorFixture {
    let ruleStoreDirectory: URL
    let defaultsSuiteName: String
    let defaults: UserDefaults
    let service: ContentBlockerService
    let stateStore: ContentBlockerStateStore
    let coordinator: ContentBlockingCoordinator
}

private actor ContentBlockerRuleSourceLoadProbe {
    private let rules: String
    private var callCount = 0

    init(rules: String) {
        self.rules = rules
    }

    func load() -> String {
        callCount += 1
        return rules
    }

    func numberOfCalls() -> Int {
        callCount
    }
}
