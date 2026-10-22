import Foundation
import WebKit
import XCTest
@testable import Browser

@MainActor
final class ContentBlockerRuleSetResolverTests: XCTestCase {
    func testCacheLookupAndCompilationAreSeparateOperations() async throws {
        let fixture = try makeFixture()
        defer { cleanUp(fixture) }
        let rules = try ContentBlockerService.probeRules(
            blockedURLFilter: ".*/separate[.]js",
            exceptionTopURLFilters: []
        )
        let identifier = ContentBlockerService.versionedIdentifier(
            namespace: "separate-operations",
            encodedRules: rules
        )

        let missing = try await fixture.service.cachedRuleList(
            identifier: identifier
        )
        XCTAssertNil(missing)

        let compiled = try await fixture.service.compileRuleList(
            identifier: identifier,
            encodedRules: rules
        )
        XCTAssertEqual(compiled.identifier, identifier)

        let cached = try await fixture.service.cachedRuleList(
            identifier: identifier
        )
        XCTAssertEqual(cached?.identifier, identifier)
    }

    func testCachedCurrentRuleSetDoesNotLoadBundledJSON() async throws {
        let fixture = try makeFixture()
        defer { cleanUp(fixture) }
        let rules = try ContentBlockerService.probeRules(
            blockedURLFilter: ".*/cached[.]js",
            exceptionTopURLFilters: []
        )
        let identifier = ContentBlockerService.versionedIdentifier(
            namespace: "cached-current",
            encodedRules: rules
        )
        _ = try await fixture.service.compileRuleList(
            identifier: identifier,
            encodedRules: rules
        )
        let loader = RuleLoaderProbe(
            encodedRules: rules,
            failsIfCalled: true
        )
        let cachedSource = makeSource(
            namespace: "cached-current",
            rules: rules,
            loader: loader
        )

        let prepared = try await fixture.resolver.prepare(
            currentSources: [cachedSource]
        )

        XCTAssertEqual(prepared.origin, .current)
        XCTAssertEqual(prepared.identifiers, [cachedSource.identifier])
        XCTAssertEqual(
            prepared.ruleLists.map(\.identifier),
            [cachedSource.identifier]
        )
        let loaderCallCount = await loader.numberOfCalls()
        XCTAssertEqual(loaderCallCount, 0)
        XCTAssertEqual(
            fixture.stateStore.lastValidIdentifiers(),
            [cachedSource.identifier]
        )
    }

    func testCacheMissLoadsCompilesAndRecordsCurrentRuleSet() async throws {
        let fixture = try makeFixture()
        defer { cleanUp(fixture) }
        let rules = try ContentBlockerService.probeRules(
            blockedURLFilter: ".*/compile-on-miss[.]js",
            exceptionTopURLFilters: []
        )
        let loader = RuleLoaderProbe(encodedRules: rules)
        let source = makeSource(
            namespace: "compile-on-miss",
            rules: rules,
            loader: loader
        )

        let prepared = try await fixture.resolver.prepare(
            currentSources: [source]
        )

        XCTAssertEqual(prepared.origin, .current)
        XCTAssertEqual(prepared.identifiers, [source.identifier])
        let loaderCallCount = await loader.numberOfCalls()
        XCTAssertEqual(loaderCallCount, 1)
        XCTAssertEqual(
            fixture.stateStore.lastValidIdentifiers(),
            [source.identifier]
        )
        let cached = try await fixture.service.cachedRuleList(
            identifier: source.identifier
        )
        XCTAssertEqual(cached?.identifier, source.identifier)
    }

    func testCompiledUpdateRemovesSupersededListsOnlyInItsNamespaces() async throws {
        let fixture = try makeFixture()
        defer { cleanUp(fixture) }
        let oldRules = try ContentBlockerService.probeRules(
            blockedURLFilter: ".*/old[.]js", exceptionTopURLFilters: []
        )
        let newRules = try ContentBlockerService.probeRules(
            blockedURLFilter: ".*/new[.]js", exceptionTopURLFilters: []
        )
        let oldSource = makeSource(
            namespace: "updated", rules: oldRules,
            loader: RuleLoaderProbe(encodedRules: oldRules)
        )
        _ = try await fixture.resolver.prepare(currentSources: [oldSource])
        var unrelated: Set<String> = []
        for namespace in ["other", "updated-extra"] {
            let identifier = ContentBlockerService.versionedIdentifier(
                namespace: namespace, encodedRules: oldRules
            )
            _ = try await fixture.service.compileRuleList(identifier: identifier, encodedRules: oldRules)
            unrelated.insert(identifier)
        }

        let newSource = makeSource(
            namespace: "updated", rules: newRules,
            loader: RuleLoaderProbe(encodedRules: newRules)
        )
        let prepared = try await fixture.resolver.prepare(currentSources: [newSource])

        XCTAssertEqual(prepared.origin, .current)
        let afterUpdate = await fixture.service.availableCachedRuleListIdentifiers()
        XCTAssertEqual(Set(afterUpdate), unrelated.union([newSource.identifier]))
        XCTAssertEqual(fixture.stateStore.lastValidIdentifiers(), [newSource.identifier])

        // A cached launch does no cleanup work, even if a stale sibling reappears.
        _ = try await fixture.service.compileRuleList(identifier: oldSource.identifier, encodedRules: oldRules)
        _ = try await fixture.resolver.prepare(currentSources: [newSource])
        let afterCachedLaunch = await fixture.service.availableCachedRuleListIdentifiers()
        XCTAssertTrue(afterCachedLaunch.contains(oldSource.identifier))
    }

    func testCompileFailureUsesCompleteLastValidRuleSet() async throws {
        let fixture = try makeFixture()
        defer { cleanUp(fixture) }
        let fallbackRules = try ContentBlockerService.probeRules(
            blockedURLFilter: ".*/fallback[.]js",
            exceptionTopURLFilters: []
        )
        let fallbackIdentifier = ContentBlockerService.versionedIdentifier(
            namespace: "fallback",
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
        let currentSource = makeSource(
            namespace: "invalid-current",
            rules: invalidRules,
            loader: RuleLoaderProbe(encodedRules: invalidRules)
        )

        let prepared = try await fixture.resolver.prepare(
            currentSources: [currentSource]
        )

        XCTAssertEqual(prepared.origin, .lastValidFallback)
        XCTAssertEqual(prepared.identifiers, [fallbackIdentifier])
        XCTAssertEqual(
            prepared.ruleLists.map(\.identifier),
            [fallbackIdentifier]
        )
        XCTAssertEqual(
            fixture.stateStore.lastValidIdentifiers(),
            [fallbackIdentifier]
        )
    }

    func testPartialCurrentCompilationNeverBecomesLastValid() async throws {
        let fixture = try makeFixture()
        defer { cleanUp(fixture) }
        let fallbackRules = try ContentBlockerService.probeRules(
            blockedURLFilter: ".*/transaction-fallback[.]js",
            exceptionTopURLFilters: []
        )
        let fallbackIdentifier = ContentBlockerService.versionedIdentifier(
            namespace: "transaction-fallback",
            encodedRules: fallbackRules
        )
        _ = try await fixture.service.compileRuleList(
            identifier: fallbackIdentifier,
            encodedRules: fallbackRules
        )
        fixture.stateStore.recordLastValidIdentifiers([fallbackIdentifier])

        let validRules = try ContentBlockerService.probeRules(
            blockedURLFilter: ".*/transaction-current[.]js",
            exceptionTopURLFilters: []
        )
        let validSource = makeSource(
            namespace: "transaction-current-valid",
            rules: validRules,
            loader: RuleLoaderProbe(encodedRules: validRules)
        )
        let invalidRules = try ContentBlockerService.probeRules(
            blockedURLFilter: "(",
            exceptionTopURLFilters: []
        )
        let invalidSource = makeSource(
            namespace: "transaction-current-invalid",
            rules: invalidRules,
            loader: RuleLoaderProbe(encodedRules: invalidRules)
        )

        let prepared = try await fixture.resolver.prepare(
            currentSources: [validSource, invalidSource]
        )

        XCTAssertEqual(prepared.origin, .lastValidFallback)
        XCTAssertEqual(prepared.identifiers, [fallbackIdentifier])
        XCTAssertEqual(
            fixture.stateStore.lastValidIdentifiers(),
            [fallbackIdentifier]
        )
        let partiallyCompiled = try await fixture.service.cachedRuleList(
            identifier: validSource.identifier
        )
        XCTAssertEqual(
            partiallyCompiled?.identifier,
            validSource.identifier,
            "A compiled partial update may remain cached but must not activate"
        )
    }

    func testMissingFallbackProducesExplicitUnavailableError() async throws {
        let fixture = try makeFixture()
        defer { cleanUp(fixture) }
        fixture.stateStore.recordLastValidIdentifiers(["missing-fallback"])
        let invalidRules = try ContentBlockerService.probeRules(
            blockedURLFilter: "(",
            exceptionTopURLFilters: []
        )
        let currentSource = makeSource(
            namespace: "missing-fallback-current",
            rules: invalidRules,
            loader: RuleLoaderProbe(encodedRules: invalidRules)
        )

        do {
            _ = try await fixture.resolver.prepare(
                currentSources: [currentSource]
            )
            XCTFail("Unavailable current and fallback rules unexpectedly prepared")
        } catch {
            XCTAssertEqual(
                error as? ContentBlockerRuleSetResolverError,
                .currentAndLastValidRuleSetsUnavailable
            )
        }
    }

    func testSourceIdentifierMismatchFailsBeforeCompilation() async throws {
        let fixture = try makeFixture()
        defer { cleanUp(fixture) }
        let expectedRules = try ContentBlockerService.probeRules(
            blockedURLFilter: ".*/expected[.]js",
            exceptionTopURLFilters: []
        )
        let unexpectedRules = try ContentBlockerService.probeRules(
            blockedURLFilter: ".*/unexpected[.]js",
            exceptionTopURLFilters: []
        )
        let namespace = "integrity-check"
        let expectedIdentifier = ContentBlockerService.versionedIdentifier(
            namespace: namespace,
            encodedRules: expectedRules
        )
        let actualIdentifier = ContentBlockerService.versionedIdentifier(
            namespace: namespace,
            encodedRules: unexpectedRules
        )
        let source = ContentBlockerRuleSource(
            namespace: namespace,
            identifier: expectedIdentifier,
            encodedRulesLoader: { unexpectedRules }
        )

        do {
            _ = try await fixture.resolver.prepare(currentSources: [source])
            XCTFail("Mismatched rule source unexpectedly compiled")
        } catch {
            XCTAssertEqual(
                error as? ContentBlockerRuleSetResolverError,
                .sourceIdentifierMismatch(
                    expected: expectedIdentifier,
                    actual: actualIdentifier
                )
            )
        }
        let cached = try await fixture.service.cachedRuleList(
            identifier: expectedIdentifier
        )
        XCTAssertNil(cached)
    }

    func testResetCompiledArtifactsRemovesEveryCachedIdentifierAndState() async throws {
        let fixture = try makeFixture()
        defer { cleanUp(fixture) }
        let currentRules = try ContentBlockerService.probeRules(
            blockedURLFilter: ".*/reset-current[.]js",
            exceptionTopURLFilters: []
        )
        let orphanRules = try ContentBlockerService.probeRules(
            blockedURLFilter: ".*/reset-orphan[.]js",
            exceptionTopURLFilters: []
        )
        let currentIdentifier = ContentBlockerService.versionedIdentifier(
            namespace: "reset-current",
            encodedRules: currentRules
        )
        let orphanIdentifier = ContentBlockerService.versionedIdentifier(
            namespace: "reset-orphan",
            encodedRules: orphanRules
        )
        _ = try await fixture.service.compileRuleList(
            identifier: currentIdentifier,
            encodedRules: currentRules
        )
        _ = try await fixture.service.compileRuleList(
            identifier: orphanIdentifier,
            encodedRules: orphanRules
        )
        fixture.stateStore.recordLastValidIdentifiers([currentIdentifier])

        let result = try await fixture.resolver.resetCompiledArtifacts()

        XCTAssertEqual(
            result.removedIdentifiers,
            [currentIdentifier, orphanIdentifier].sorted()
        )
        let remainingIdentifiers =
            await fixture.service.availableCachedRuleListIdentifiers()
        XCTAssertEqual(remainingIdentifiers, [])
        XCTAssertNil(fixture.stateStore.lastValidIdentifiers())
        let cachedCurrent = try await fixture.service.cachedRuleList(
            identifier: currentIdentifier
        )
        let cachedOrphan = try await fixture.service.cachedRuleList(
            identifier: orphanIdentifier
        )
        XCTAssertNil(cachedCurrent)
        XCTAssertNil(cachedOrphan)
    }

    func testScopedResetRemovesOnlyUITestIdentifiersAndState() async throws {
        let fixture = try makeFixture()
        defer { cleanUp(fixture) }
        let productionRules = try ContentBlockerService.probeRules(
            blockedURLFilter: ".*/production[.]js",
            exceptionTopURLFilters: []
        )
        let uiTestRules = try ContentBlockerService.probeRules(
            blockedURLFilter: ".*/ui-test[.]js",
            exceptionTopURLFilters: []
        )
        let productionIdentifier = ContentBlockerService.versionedIdentifier(
            namespace: "browser-adguard-base-v1",
            encodedRules: productionRules
        )
        let uiTestIdentifier = ContentBlockerService.versionedIdentifier(
            namespace: "browser-ui-test-content-blocking-v1",
            encodedRules: uiTestRules
        )
        _ = try await fixture.service.compileRuleList(
            identifier: productionIdentifier,
            encodedRules: productionRules
        )
        _ = try await fixture.service.compileRuleList(
            identifier: uiTestIdentifier,
            encodedRules: uiTestRules
        )
        fixture.stateStore.recordLastValidIdentifiers([uiTestIdentifier])
        let resolver = ContentBlockerRuleSetResolver(
            service: fixture.service,
            stateStore: fixture.stateStore,
            artifactResetScope: .identifierPrefix("browser-ui-test-")
        )

        let result = try await resolver.resetCompiledArtifacts()
        let remainingIdentifiers =
            await fixture.service.availableCachedRuleListIdentifiers()
        let cachedProduction = try await fixture.service.cachedRuleList(
            identifier: productionIdentifier
        )
        let cachedUITest = try await fixture.service.cachedRuleList(
            identifier: uiTestIdentifier
        )

        XCTAssertEqual(result.removedIdentifiers, [uiTestIdentifier])
        XCTAssertEqual(remainingIdentifiers, [productionIdentifier])
        XCTAssertNil(fixture.stateStore.lastValidIdentifiers())
        XCTAssertNotNil(cachedProduction)
        XCTAssertNil(cachedUITest)
    }

    private func makeSource(
        namespace: String,
        rules: String,
        loader: RuleLoaderProbe
    ) -> ContentBlockerRuleSource {
        ContentBlockerRuleSource(
            namespace: namespace,
            identifier: ContentBlockerService.versionedIdentifier(
                namespace: namespace,
                encodedRules: rules
            ),
            encodedRulesLoader: {
                try await loader.load()
            }
        )
    }

    private func makeFixture() throws -> Fixture {
        let ruleStoreDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "BrowserContentBlockerResolverTests.\(UUID().uuidString)",
                isDirectory: true
            )
        let ruleStore = try XCTUnwrap(
            WKContentRuleListStore(url: ruleStoreDirectory)
        )
        let suiteName = "ContentBlockerResolverTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let service = ContentBlockerService(ruleStore: ruleStore)
        let stateStore = ContentBlockerStateStore(defaults: defaults)
        return Fixture(
            ruleStoreDirectory: ruleStoreDirectory,
            defaultsSuiteName: suiteName,
            defaults: defaults,
            service: service,
            stateStore: stateStore,
            resolver: ContentBlockerRuleSetResolver(
                service: service,
                stateStore: stateStore
            )
        )
    }

    private func cleanUp(_ fixture: Fixture) {
        fixture.defaults.removePersistentDomain(
            forName: fixture.defaultsSuiteName
        )
        try? FileManager.default.removeItem(
            at: fixture.ruleStoreDirectory
        )
    }
}

private struct Fixture {
    let ruleStoreDirectory: URL
    let defaultsSuiteName: String
    let defaults: UserDefaults
    let service: ContentBlockerService
    let stateStore: ContentBlockerStateStore
    let resolver: ContentBlockerRuleSetResolver
}

private actor RuleLoaderProbe {
    private let encodedRules: String
    private let failsIfCalled: Bool
    private var callCount = 0

    init(encodedRules: String, failsIfCalled: Bool = false) {
        self.encodedRules = encodedRules
        self.failsIfCalled = failsIfCalled
    }

    func load() throws -> String {
        callCount += 1
        if failsIfCalled {
            throw RuleLoaderProbeError.unexpectedLoad
        }
        return encodedRules
    }

    func numberOfCalls() -> Int {
        callCount
    }
}

private enum RuleLoaderProbeError: Error {
    case unexpectedLoad
}
