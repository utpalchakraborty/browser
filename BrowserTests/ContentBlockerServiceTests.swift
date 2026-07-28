import WebKit
import XCTest
@testable import Browser

@MainActor
final class ContentBlockerServiceTests: XCTestCase {
    func testAvailableCachedRuleListIdentifiersReflectsPrivateStore() async throws {
        let ruleStoreDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ContentBlockerServiceTests.\(UUID().uuidString)",
                isDirectory: true
            )
        defer {
            try? FileManager.default.removeItem(at: ruleStoreDirectory)
        }
        let ruleStore = try XCTUnwrap(
            WKContentRuleListStore(url: ruleStoreDirectory)
        )
        let service = ContentBlockerService(ruleStore: ruleStore)
        let firstRules = try ContentBlockerService.probeRules(
            blockedURLFilter: ".*/enumerated-first[.]js",
            exceptionTopURLFilters: []
        )
        let secondRules = try ContentBlockerService.probeRules(
            blockedURLFilter: ".*/enumerated-second[.]js",
            exceptionTopURLFilters: []
        )
        let firstIdentifier = ContentBlockerService.versionedIdentifier(
            namespace: "enumerated-first",
            encodedRules: firstRules
        )
        let secondIdentifier = ContentBlockerService.versionedIdentifier(
            namespace: "enumerated-second",
            encodedRules: secondRules
        )

        let initialIdentifiers =
            await service.availableCachedRuleListIdentifiers()
        XCTAssertEqual(initialIdentifiers, [])
        _ = try await service.compileRuleList(
            identifier: secondIdentifier,
            encodedRules: secondRules
        )
        _ = try await service.compileRuleList(
            identifier: firstIdentifier,
            encodedRules: firstRules
        )

        let compiledIdentifiers =
            await service.availableCachedRuleListIdentifiers()
        XCTAssertEqual(
            compiledIdentifiers,
            [firstIdentifier, secondIdentifier].sorted()
        )

        try await service.removeCachedRuleList(identifier: firstIdentifier)
        try await service.removeCachedRuleList(identifier: secondIdentifier)
        let remainingIdentifiers =
            await service.availableCachedRuleListIdentifiers()
        XCTAssertEqual(remainingIdentifiers, [])
    }

    func testCompiledRulesBlockNormallyAndAllowSiteException() async throws {
        let blockingRules = try ContentBlockerService.probeRules(
            blockedURLFilter: ".*/blocked[.]js",
            exceptionTopURLFilters: []
        )
        let exceptionRules = try ContentBlockerService.probeRules(
            blockedURLFilter: ".*/blocked[.]js",
            exceptionTopURLFilters: [
                "http://127[.]0[.]0[.]1:[0-9]+/exception/.*"
            ]
        )
        let service = ContentBlockerService()
        let blockingNamespace = "phase1-content-rule-blocking-v2"
        let exceptionNamespace = "phase1-content-rule-exception-v2"
        let blockingIdentifier = ContentBlockerService.versionedIdentifier(
            namespace: blockingNamespace,
            encodedRules: blockingRules
        )
        let exceptionIdentifier = ContentBlockerService.versionedIdentifier(
            namespace: exceptionNamespace,
            encodedRules: exceptionRules
        )
        let compiledBlockingRules = try await service.cachedOrCompile(
            namespace: blockingNamespace,
            encodedRules: blockingRules
        )
        let compiledExceptionRules = try await service.cachedOrCompile(
            namespace: exceptionNamespace,
            encodedRules: exceptionRules
        )
        let cachedExceptionRules = try await service.cachedOrCompile(
            namespace: exceptionNamespace,
            encodedRules: exceptionRules
        )
        XCTAssertEqual(compiledBlockingRules.identifier, blockingIdentifier)
        XCTAssertEqual(compiledExceptionRules.identifier, exceptionIdentifier)
        XCTAssertEqual(cachedExceptionRules.identifier, exceptionIdentifier)

        let profile = BrowserProfile(
            dataStoreIdentifier: UUID(
                uuidString: "A1000000-0000-4000-8000-000000000003"
            )!
        )
        let contentController = WKUserContentController()
        service.replace(nil, with: compiledBlockingRules, on: contentController)
        let webView = profile.webViewFactory.makeWebView(
            userContentController: contentController
        )

        try await WebViewNavigationWaiter().load(
            Phase1Fixture.url("/normal/"),
            in: webView
        )
        let normalPageResult = try await webView.evaluateJavaScript(
            "Boolean(window.blockedLoaded)"
        )
        let blockedOnNormalPage = try XCTUnwrap(
            normalPageResult as? Bool
        )
        XCTAssertFalse(blockedOnNormalPage)

        try await WebViewNavigationWaiter().load(
            Phase1Fixture.url("/exception/"),
            in: webView
        )
        let beforeExceptionResult = try await webView.evaluateJavaScript(
            "Boolean(window.blockedLoaded)"
        )
        let blockedBeforeException = try XCTUnwrap(
            beforeExceptionResult as? Bool
        )
        XCTAssertFalse(blockedBeforeException)

        service.replace(
            compiledBlockingRules,
            with: compiledExceptionRules,
            on: contentController
        )
        try await WebViewNavigationWaiter().reload(webView)
        let exceptionPageResult = try await webView.evaluateJavaScript(
            "Boolean(window.blockedLoaded)"
        )
        let loadedOnExceptionPage = try XCTUnwrap(exceptionPageResult as? Bool)
        XCTAssertTrue(loadedOnExceptionPage)

        service.replace(
            compiledExceptionRules,
            with: compiledBlockingRules,
            on: contentController
        )
        try await WebViewNavigationWaiter().reload(webView)
        let afterExceptionRemovalResult = try await webView.evaluateJavaScript(
            "Boolean(window.blockedLoaded)"
        )
        let blockedAfterExceptionRemoval = try XCTUnwrap(
            afterExceptionRemovalResult as? Bool
        )
        XCTAssertFalse(blockedAfterExceptionRemoval)

        service.remove(compiledBlockingRules, from: contentController)
        try await WebViewNavigationWaiter().reload(webView)
        let afterRemovalResult = try await webView.evaluateJavaScript(
            "Boolean(window.blockedLoaded)"
        )
        let loadedAfterRemoval = try XCTUnwrap(
            afterRemovalResult as? Bool
        )
        XCTAssertTrue(loadedAfterRemoval)
        try await service.removeCachedRuleList(identifier: blockingIdentifier)
        try await service.removeCachedRuleList(identifier: exceptionIdentifier)
    }

    func testProbeRulesRejectInvalidRegularExpressionDuringCompilation() async throws {
        let rules = try ContentBlockerService.probeRules(
            blockedURLFilter: "(",
            exceptionTopURLFilters: []
        )
        let service = ContentBlockerService()

        do {
            _ = try await service.cachedOrCompile(
                namespace: "phase1-invalid-content-rule-probe-v1",
                encodedRules: rules
            )
            XCTFail("Invalid content-rule regular expression unexpectedly compiled")
        } catch {
            XCTAssertNotNil(error as NSError)
        }
    }

    func testRuleIdentifierChangesWhenRulesChange() throws {
        let firstRules = try ContentBlockerService.probeRules(
            blockedURLFilter: ".*/first[.]js",
            exceptionTopURLFilters: []
        )
        let secondRules = try ContentBlockerService.probeRules(
            blockedURLFilter: ".*/second[.]js",
            exceptionTopURLFilters: []
        )

        XCTAssertNotEqual(
            ContentBlockerService.versionedIdentifier(
                namespace: "phase1",
                encodedRules: firstRules
            ),
            ContentBlockerService.versionedIdentifier(
                namespace: "phase1",
                encodedRules: secondRules
            )
        )
    }
}
