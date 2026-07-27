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

@MainActor
final class ContentBlockerRuleSetResolver {
    private let service: ContentBlockerService
    private let stateStore: ContentBlockerStateStore

    init(
        service: ContentBlockerService,
        stateStore: ContentBlockerStateStore
    ) {
        self.service = service
        self.stateStore = stateStore
    }

    func prepare(
        currentSources: [ContentBlockerRuleSource]
    ) async throws -> PreparedContentBlockerRuleSet {
        do {
            let prepared = try await prepareCurrent(currentSources)
            stateStore.recordLastValidIdentifiers(prepared.identifiers)
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

    private func prepareCurrent(
        _ sources: [ContentBlockerRuleSource]
    ) async throws -> PreparedContentBlockerRuleSet {
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
        }

        return PreparedContentBlockerRuleSet(
            origin: .current,
            identifiers: sources.map(\.identifier),
            ruleLists: ruleLists
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
