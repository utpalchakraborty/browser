import Foundation
import WebKit

nonisolated struct ContentBlockerRuleSource: Sendable {
    let namespace: String
    let identifier: String
    private let encodedRulesLoader: @Sendable () async throws -> String

    init(
        namespace: String,
        identifier: String,
        encodedRulesLoader: @escaping @Sendable () async throws -> String
    ) {
        self.namespace = namespace
        self.identifier = identifier
        self.encodedRulesLoader = encodedRulesLoader
    }

    func encodedRules() async throws -> String {
        try await encodedRulesLoader()
    }
}

// Compiled rule lists are immutable. Retain this value for the profile's
// lifetime and reuse its ordered lists when configuring content controllers.
struct PreparedContentBlockerRuleSet {
    enum Origin: Equatable, Sendable {
        case current
        case lastValidFallback
    }

    let origin: Origin
    let identifiers: [String]
    let ruleLists: [WKContentRuleList]
}

enum ContentBlockerRuleSetResolverError: Error, Equatable {
    case noCurrentRuleSources
    case invalidRuleSource
    case duplicateIdentifier(String)
    case sourceIdentifierMismatch(expected: String, actual: String)
    case currentAndLastValidRuleSetsUnavailable
}

nonisolated struct ContentBlockerArtifactResetResult: Equatable, Sendable {
    let removedIdentifiers: [String]
}

nonisolated enum ContentBlockerArtifactResetScope: Equatable, Sendable {
    case all
    case identifierPrefix(String)

    func includes(identifier: String) -> Bool {
        switch self {
        case .all:
            return true
        case let .identifierPrefix(prefix):
            return !prefix.isEmpty && identifier.hasPrefix(prefix)
        }
    }
}

nonisolated enum ContentBlockerArtifactResetError: Error, Equatable, Sendable {
    case preparationInProgress
    case resetInProgress
    case cachedIdentifiersRemain([String])
}

@MainActor
final class ContentBlockerRuleSetResolver {
    private let service: ContentBlockerService
    private let stateStore: ContentBlockerStateStore
    private let artifactResetScope: ContentBlockerArtifactResetScope

    init(
        service: ContentBlockerService,
        stateStore: ContentBlockerStateStore,
        artifactResetScope: ContentBlockerArtifactResetScope = .all
    ) {
        self.service = service
        self.stateStore = stateStore
        self.artifactResetScope = artifactResetScope
    }

    func prepare(
        currentSources: [ContentBlockerRuleSource]
    ) async throws -> PreparedContentBlockerRuleSet {
        do {
            let (prepared, didCompile) = try await prepareCurrent(currentSources)
            stateStore.recordLastValidIdentifiers(prepared.identifiers)
            if didCompile {
                await removeSupersededArtifacts(keeping: currentSources)
            }
            return prepared
        } catch {
            guard
                let fallbackIdentifiers = stateStore.lastValidIdentifiers(),
                fallbackIdentifiers != currentSources.map(\.identifier)
            else {
                throw error
            }

            do {
                return try await prepareFallback(
                    identifiers: fallbackIdentifiers
                )
            } catch {
                throw ContentBlockerRuleSetResolverError
                    .currentAndLastValidRuleSetsUnavailable
            }
        }
    }

    func resetCompiledArtifacts() async throws
        -> ContentBlockerArtifactResetResult
    {
        // The persisted identifiers are recovery bookkeeping for the compiled
        // artifacts. Clear them even if WebKit cannot remove every cached list
        // so a later launch never follows a stale fallback pointer.
        defer {
            stateStore.reset()
        }

        let identifiers = await service.availableCachedRuleListIdentifiers()
            .filter(artifactResetScope.includes(identifier:))
        for identifier in identifiers {
            // Continue after an individual failure, then ask WebKit for the
            // authoritative remaining set before reporting the result.
            try? await service.removeCachedRuleList(identifier: identifier)
        }

        let remainingIdentifiers = await service
            .availableCachedRuleListIdentifiers()
            .filter(artifactResetScope.includes(identifier:))
        guard remainingIdentifiers.isEmpty else {
            throw ContentBlockerArtifactResetError.cachedIdentifiersRemain(
                remainingIdentifiers
            )
        }

        return ContentBlockerArtifactResetResult(
            removedIdentifiers: identifiers
        )
    }

    /// A compiled rule update leaves earlier lists of the same namespaces
    /// unreferenced, because the last-valid pointer now names the current set.
    /// Cached launches skip this, so the common launch path does no extra work.
    private func removeSupersededArtifacts(
        keeping sources: [ContentBlockerRuleSource]
    ) async {
        let current = Set(sources.map(\.identifier))
        let namespacePrefixes = Set(sources.map { "\($0.namespace)-" })
        for identifier in await service.availableCachedRuleListIdentifiers()
        where !current.contains(identifier)
            && artifactResetScope.includes(identifier: identifier)
            && namespacePrefixes.contains(where: {
                Self.isVersionedIdentifier(identifier, withPrefix: $0)
            })
        {
            try? await service.removeCachedRuleList(identifier: identifier)
        }
    }

    /// Matches `versionedIdentifier(namespace:encodedRules:)` exactly, so a
    /// longer namespace that shares this prefix is never treated as a sibling.
    private static func isVersionedIdentifier(
        _ identifier: String,
        withPrefix prefix: String
    ) -> Bool {
        guard identifier.hasPrefix(prefix) else {
            return false
        }
        let fingerprint = identifier.dropFirst(prefix.count)
        return fingerprint.count == 64
            && fingerprint.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }

    private func prepareCurrent(
        _ sources: [ContentBlockerRuleSource]
    ) async throws -> (prepared: PreparedContentBlockerRuleSet, didCompile: Bool) {
        guard !sources.isEmpty else {
            throw ContentBlockerRuleSetResolverError.noCurrentRuleSources
        }

        var seenIdentifiers = Set<String>()
        for source in sources {
            guard
                !source.namespace.isEmpty,
                !source.identifier.isEmpty
            else {
                throw ContentBlockerRuleSetResolverError.invalidRuleSource
            }
            guard seenIdentifiers.insert(source.identifier).inserted else {
                throw ContentBlockerRuleSetResolverError.duplicateIdentifier(
                    source.identifier
                )
            }
        }

        var ruleLists = [WKContentRuleList]()
        ruleLists.reserveCapacity(sources.count)
        var didCompile = false
        for source in sources {
            if let cached = try await service.cachedRuleList(
                identifier: source.identifier
            ) {
                ruleLists.append(cached)
                continue
            }

            let encodedRules = try await source.encodedRules()
            let namespace = source.namespace
            let actualIdentifier = await Task.detached(priority: .utility) {
                ContentBlockerService.versionedIdentifier(
                    namespace: namespace,
                    encodedRules: encodedRules
                )
            }.value
            guard actualIdentifier == source.identifier else {
                throw ContentBlockerRuleSetResolverError
                    .sourceIdentifierMismatch(
                        expected: source.identifier,
                        actual: actualIdentifier
                    )
            }
            ruleLists.append(
                try await service.compileRuleList(
                    identifier: source.identifier,
                    encodedRules: encodedRules
                )
            )
            didCompile = true
        }

        return (
            PreparedContentBlockerRuleSet(
                origin: .current,
                identifiers: sources.map(\.identifier),
                ruleLists: ruleLists
            ),
            didCompile
        )
    }

    private func prepareFallback(
        identifiers: [String]
    ) async throws -> PreparedContentBlockerRuleSet {
        var ruleLists = [WKContentRuleList]()
        ruleLists.reserveCapacity(identifiers.count)
        for identifier in identifiers {
            guard
                let cached = try await service.cachedRuleList(
                    identifier: identifier
                )
            else {
                throw ContentBlockerError.cachedRuleListNotFound(
                    identifier: identifier
                )
            }
            ruleLists.append(cached)
        }

        return PreparedContentBlockerRuleSet(
            origin: .lastValidFallback,
            identifiers: identifiers,
            ruleLists: ruleLists
        )
    }
}
