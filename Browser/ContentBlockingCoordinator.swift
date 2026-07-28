import Foundation
import WebKit

nonisolated enum ContentBlockingAvailability: Equatable, Sendable {
    case preparing
    case active
    case activeLastValidRules
    case unavailable
}

nonisolated struct ContentBlockingSnapshot: Equatable, Sendable {
    let availability: ContentBlockingAvailability
    let site: ContentBlockerSite?
    let isException: Bool
}

@MainActor
final class ContentBlockingCoordinator {
    private let resolver: ContentBlockerRuleSetResolver
    private let sitePolicyStore: ContentBlockerSitePolicyStore
    private var preparedRuleSet: PreparedContentBlockerRuleSet?
    private var attachedStateByController = [ObjectIdentifier: Bool]()
    private var isResettingCompiledArtifacts = false

    private(set) var availability: ContentBlockingAvailability = .preparing

    init(
        resolver: ContentBlockerRuleSetResolver,
        sitePolicyStore: ContentBlockerSitePolicyStore
    ) {
        self.resolver = resolver
        self.sitePolicyStore = sitePolicyStore
    }

    var isReady: Bool {
        preparedRuleSet != nil
    }

    var siteExceptionHosts: [String] {
        sitePolicyStore.allExceptionHosts()
    }

    var siteExceptionCount: Int {
        siteExceptionHosts.count
    }

    var canResetCompiledArtifacts: Bool {
        availability != .preparing && !isResettingCompiledArtifacts
    }

    func prepare(currentSources: [ContentBlockerRuleSource]) async {
        availability = .preparing
        do {
            let prepared = try await resolver.prepare(
                currentSources: currentSources
            )
            preparedRuleSet = prepared
            availability = prepared.origin == .current
                ? .active
                : .activeLastValidRules
        } catch {
            preparedRuleSet = nil
            attachedStateByController.removeAll()
            availability = .unavailable
        }
    }

    func snapshot(for url: URL?) -> ContentBlockingSnapshot {
        let site = url.flatMap(ContentBlockerSite.init(url:))
        return ContentBlockingSnapshot(
            availability: availability,
            site: site,
            isException: site.map(sitePolicyStore.isException) ?? false
        )
    }

    @discardableResult
    func applyPolicy(
        to contentController: WKUserContentController,
        for url: URL?,
        mode: ContentBlockingPolicyApplicationMode = .exact
    ) -> Bool {
        guard let preparedRuleSet else {
            return false
        }

        let site = url.flatMap(ContentBlockerSite.init(url:))
        let shouldAttach = site.map {
            !sitePolicyStore.isException($0)
        } ?? true
        if mode == .none || (mode == .strengthenOnly && !shouldAttach) {
            return true
        }
        let controllerIdentifier = ObjectIdentifier(contentController)
        if attachedStateByController[controllerIdentifier] == shouldAttach {
            return true
        }

        if shouldAttach {
            for ruleList in preparedRuleSet.ruleLists {
                contentController.add(ruleList)
            }
        } else {
            for ruleList in preparedRuleSet.ruleLists {
                contentController.remove(ruleList)
            }
        }
        attachedStateByController[controllerIdentifier] = shouldAttach
        return true
    }

    @discardableResult
    func toggleException(for url: URL?) -> ContentBlockerSite? {
        guard let site = url.flatMap(ContentBlockerSite.init(url:)) else {
            return nil
        }
        sitePolicyStore.setException(
            !sitePolicyStore.isException(site),
            for: site
        )
        return site
    }

    func resetSiteExceptions() {
        sitePolicyStore.reset()
    }

    func resetCompiledArtifacts() async throws
        -> ContentBlockerArtifactResetResult
    {
        guard availability != .preparing else {
            throw ContentBlockerArtifactResetError.preparationInProgress
        }
        guard !isResettingCompiledArtifacts else {
            throw ContentBlockerArtifactResetError.resetInProgress
        }

        isResettingCompiledArtifacts = true
        defer {
            isResettingCompiledArtifacts = false
        }
        return try await resolver.resetCompiledArtifacts()
    }

    func forget(_ contentController: WKUserContentController) {
        attachedStateByController.removeValue(
            forKey: ObjectIdentifier(contentController)
        )
    }
}
