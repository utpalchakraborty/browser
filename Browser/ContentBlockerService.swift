import CryptoKit
import Foundation
import WebKit

enum ContentBlockerError: Error {
    case compilationReturnedNoRuleList
    case encodingFailed
}

@MainActor
final class ContentBlockerService {
    private let ruleStore: WKContentRuleListStore

    init(ruleStore: WKContentRuleListStore = .default()) {
        self.ruleStore = ruleStore
    }

    func cachedOrCompile(
        namespace: String,
        encodedRules: String
    ) async throws -> WKContentRuleList {
        let identifier = Self.versionedIdentifier(
            namespace: namespace,
            encodedRules: encodedRules
        )
        if let cached = try? await ruleStore.contentRuleList(
            forIdentifier: identifier
        ) {
            return cached
        }

        guard let compiled = try await ruleStore.compileContentRuleList(
            forIdentifier: identifier,
            encodedContentRuleList: encodedRules
        ) else {
            throw ContentBlockerError.compilationReturnedNoRuleList
        }

        return compiled
    }

    func removeCachedRuleList(identifier: String) async throws {
        try await ruleStore.removeContentRuleList(forIdentifier: identifier)
    }

    func replace(
        _ previousRuleList: WKContentRuleList?,
        with newRuleList: WKContentRuleList,
        on contentController: WKUserContentController
    ) {
        if let previousRuleList {
            contentController.remove(previousRuleList)
        }
        contentController.add(newRuleList)
    }

    func remove(
        _ ruleList: WKContentRuleList,
        from contentController: WKUserContentController
    ) {
        contentController.remove(ruleList)
    }

    static func probeRules(
        blockedURLFilter: String,
        exceptionTopURLFilters: [String]
    ) throws -> String {
        var rules = [
            EncodedRule(
                trigger: Trigger(
                    urlFilter: blockedURLFilter,
                    resourceTypes: ["script"],
                    ifTopURLs: nil
                ),
                action: Action(type: "block")
            )
        ]

        if !exceptionTopURLFilters.isEmpty {
            rules.append(
                EncodedRule(
                    trigger: Trigger(
                        urlFilter: ".*",
                        resourceTypes: nil,
                        ifTopURLs: exceptionTopURLFilters
                    ),
                    action: Action(type: "ignore-previous-rules")
                )
            )
        }

        let data = try JSONEncoder().encode(rules)
        guard let encoded = String(data: data, encoding: .utf8) else {
            throw ContentBlockerError.encodingFailed
        }
        return encoded
    }

    nonisolated static func versionedIdentifier(
        namespace: String,
        encodedRules: String
    ) -> String {
        let digest = SHA256.hash(data: Data(encodedRules.utf8))
        let fingerprint = digest.map { String(format: "%02x", $0) }.joined()
        return "\(namespace)-\(fingerprint)"
    }
}

private struct EncodedRule: Encodable {
    let trigger: Trigger
    let action: Action
}

private struct Trigger: Encodable {
    let urlFilter: String
    let resourceTypes: [String]?
    let ifTopURLs: [String]?

    enum CodingKeys: String, CodingKey {
        case urlFilter = "url-filter"
        case resourceTypes = "resource-type"
        case ifTopURLs = "if-top-url"
    }
}

private struct Action: Encodable {
    let type: String
}
