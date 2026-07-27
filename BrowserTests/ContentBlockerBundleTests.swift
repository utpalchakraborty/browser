import Dispatch
import Foundation
import WebKit
import XCTest
@testable import Browser

final class ContentBlockerBundleTests: XCTestCase {
    func testProductionManifestBuildsOrderedPinnedSources() throws {
        let package = try ContentBlockerBundle.loadProductionPackage()

        XCTAssertEqual(package.manifest.schemaVersion, 1)
        XCTAssertEqual(
            package.manifest.ruleSets.map(\.displayName),
            ["AdGuard Base", "AdGuard Tracking Protection"]
        )
        XCTAssertEqual(
            package.ruleSources.map(\.identifier),
            package.manifest.ruleSets.map(\.identifier)
        )
        XCTAssertEqual(
            package.manifest.ruleSets.map(\.ruleCount),
            [36_356, 83_156]
        )
        XCTAssertEqual(package.manifest.converter.version, "4.3.0")
        XCTAssertEqual(package.manifest.sourceProject.license, "GPL-3.0-only")
    }

    func testBundledRuleBytesMatchPinnedIdentifiers() async throws {
        let package = try ContentBlockerBundle.loadProductionPackage()

        for source in package.ruleSources {
            let rules = try await source.encodedRules()
            XCTAssertEqual(
                ContentBlockerService.versionedIdentifier(
                    namespace: source.namespace,
                    encodedRules: rules
                ),
                source.identifier
            )
        }
    }

    @MainActor
    func testProductionPackageCompilesAsCurrentRuleSetInManifestOrder() async throws {
        let package = try ContentBlockerBundle.loadProductionPackage()
        let expectedIdentifiers = package.manifest.ruleSets.map(\.identifier)
        let ruleStoreDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "BrowserProductionBlockerCompilationTests.\(UUID().uuidString)",
                isDirectory: true
            )
        let ruleStore = try XCTUnwrap(
            WKContentRuleListStore(url: ruleStoreDirectory)
        )
        let defaultsSuiteName =
            "BrowserProductionBlockerCompilationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: defaultsSuiteName)
        )
        defer {
            defaults.removePersistentDomain(forName: defaultsSuiteName)
            try? FileManager.default.removeItem(at: ruleStoreDirectory)
        }

        let service = ContentBlockerService(ruleStore: ruleStore)
        let stateStore = ContentBlockerStateStore(defaults: defaults)
        let resolver = ContentBlockerRuleSetResolver(
            service: service,
            stateStore: stateStore
        )

        XCTAssertEqual(expectedIdentifiers.count, 2)
        for identifier in expectedIdentifiers {
            let cached = try await service.cachedRuleList(
                identifier: identifier
            )
            XCTAssertNil(cached)
        }

        let start = DispatchTime.now().uptimeNanoseconds
        let prepared = try await resolver.prepare(
            currentSources: package.ruleSources
        )
        let elapsedMilliseconds = Double(
            DispatchTime.now().uptimeNanoseconds - start
        ) / 1_000_000

        XCTAssertEqual(prepared.origin, .current)
        XCTAssertEqual(prepared.identifiers, expectedIdentifiers)
        XCTAssertEqual(
            prepared.ruleLists.map(\.identifier),
            expectedIdentifiers
        )
        XCTAssertEqual(
            stateStore.lastValidIdentifiers(),
            expectedIdentifiers
        )
        print(
            String(
                format: "BROWSER_PRODUCTION_BLOCKER_COMPILE_MS=%.1f",
                elapsedMilliseconds
            )
        )

        let contentController = WKUserContentController()
        prepared.ruleLists.forEach { contentController.add($0) }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController = contentController
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let waiter = WebViewNavigationWaiter()

        try await waiter.load(
            Phase1Fixture.url("/privacy/production-blocking/"),
            in: webView
        )
        let completeResult = try await webView.evaluateJavaScript(
            "Boolean(window.productionBlockingFixtureComplete)"
        )
        let allowedResult = try await webView.evaluateJavaScript(
            "Boolean(window.productionAllowedLoaded)"
        )
        let blockedResult = try await webView.evaluateJavaScript(
            "Boolean(window.productionAdLoaded)"
        )
        XCTAssertEqual(
            completeResult as? Bool,
            true
        )
        XCTAssertEqual(
            allowedResult as? Bool,
            true,
            "The production rules blocked an ordinary first-party script."
        )
        XCTAssertEqual(
            blockedResult as? Bool,
            false,
            "The production AdGuard package did not block its advertising probe."
        )

        prepared.ruleLists.forEach { contentController.remove($0) }
        try await waiter.reload(webView)
        let unblockedResult = try await webView.evaluateJavaScript(
            "Boolean(window.productionAdLoaded)"
        )
        XCTAssertEqual(
            unblockedResult as? Bool,
            true,
            "The advertising probe was unavailable independently of blocking."
        )
    }
}
