import Foundation

nonisolated struct ContentBlockerPackageManifest: Decodable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let ruleSets: [RuleSet]
    let sourceProject: SourceProject
    let converter: Converter

    struct RuleSet: Decodable, Sendable {
        let displayName: String
        let namespace: String
        let identifier: String
        let resource: String
        let fileExtension: String
        let sha256: String
        let ruleCount: Int
        let source: Source
    }

    struct Source: Decodable, Sendable {
        let title: String
        let url: URL
        let repository: URL
        let commit: String
        let path: String
        let version: String
        let updatedAt: String
        let sha256: String
    }

    struct SourceProject: Decodable, Sendable {
        let name: String
        let repository: URL
        let license: String
    }

    struct Converter: Decodable, Sendable {
        let name: String
        let repository: URL
        let version: String
        let commit: String
        let binarySha256: String
        let arguments: [String]
        let publicSuffixListVersion: String
        let publicSuffixListCommit: String
    }
}

nonisolated struct ContentBlockerPackage: Sendable {
    let manifest: ContentBlockerPackageManifest
    let ruleSources: [ContentBlockerRuleSource]
}

nonisolated enum ContentBlockerBundleError: Error, Equatable, Sendable {
    case manifestMissing
    case unsupportedSchemaVersion(Int)
    case noRuleSets
    case invalidRuleSet(String)
    case duplicateIdentifier(String)
    case resourceMissing(String)
    case resourceIsNotUTF8(String)
}

extension ContentBlockerBundleError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .manifestMissing:
            "The bundled content-blocker manifest is missing."
        case let .unsupportedSchemaVersion(version):
            "Content-blocker manifest version \(version) is unsupported."
        case .noRuleSets:
            "The content-blocker manifest contains no rule sets."
        case let .invalidRuleSet(name):
            "The bundled content-blocker rule set \(name) is invalid."
        case let .duplicateIdentifier(identifier):
            "The content-blocker identifier \(identifier) is duplicated."
        case let .resourceMissing(resource):
            "The bundled content-blocker resource \(resource) is missing."
        case let .resourceIsNotUTF8(resource):
            "The bundled content-blocker resource \(resource) is not UTF-8."
        }
    }
}

nonisolated enum ContentBlockerBundle {
    private static let resourceSubdirectory = "ContentBlockerRules"

    static func loadProductionPackage(
        from bundle: Bundle = .main
    ) throws -> ContentBlockerPackage {
        guard let manifestURL = resourceURL(
            named: "ContentBlockerManifest",
            extension: "json",
            in: bundle
        ) else {
            throw ContentBlockerBundleError.manifestMissing
        }

        let manifestData = try Data(
            contentsOf: manifestURL,
            options: .mappedIfSafe
        )
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let manifest = try decoder.decode(
            ContentBlockerPackageManifest.self,
            from: manifestData
        )
        guard manifest.schemaVersion
            == ContentBlockerPackageManifest.currentSchemaVersion
        else {
            throw ContentBlockerBundleError.unsupportedSchemaVersion(
                manifest.schemaVersion
            )
        }
        guard !manifest.ruleSets.isEmpty else {
            throw ContentBlockerBundleError.noRuleSets
        }

        var identifiers = Set<String>()
        var sources = [ContentBlockerRuleSource]()
        sources.reserveCapacity(manifest.ruleSets.count)
        for ruleSet in manifest.ruleSets {
            guard
                !ruleSet.displayName.isEmpty,
                !ruleSet.namespace.isEmpty,
                !ruleSet.resource.isEmpty,
                !ruleSet.fileExtension.isEmpty,
                ruleSet.ruleCount > 0,
                isSHA256(ruleSet.sha256),
                isSHA256(ruleSet.source.sha256),
                ruleSet.identifier
                    == "\(ruleSet.namespace)-\(ruleSet.sha256)"
            else {
                throw ContentBlockerBundleError.invalidRuleSet(
                    ruleSet.displayName
                )
            }
            guard identifiers.insert(ruleSet.identifier).inserted else {
                throw ContentBlockerBundleError.duplicateIdentifier(
                    ruleSet.identifier
                )
            }
            guard let rulesURL = resourceURL(
                named: ruleSet.resource,
                extension: ruleSet.fileExtension,
                in: bundle
            ) else {
                throw ContentBlockerBundleError.resourceMissing(
                    ruleSet.resource
                )
            }

            let resourceName = ruleSet.resource
            sources.append(
                ContentBlockerRuleSource(
                    namespace: ruleSet.namespace,
                    identifier: ruleSet.identifier,
                    encodedRulesLoader: {
                        let data = try await Task.detached(priority: .utility) {
                            try Data(contentsOf: rulesURL, options: .mappedIfSafe)
                        }.value
                        guard let encodedRules = String(
                            data: data,
                            encoding: .utf8
                        ) else {
                            throw ContentBlockerBundleError.resourceIsNotUTF8(
                                resourceName
                            )
                        }
                        return encodedRules
                    }
                )
            )
        }

        return ContentBlockerPackage(
            manifest: manifest,
            ruleSources: sources
        )
    }

    private static func resourceURL(
        named name: String,
        extension fileExtension: String,
        in bundle: Bundle
    ) -> URL? {
        bundle.url(
            forResource: name,
            withExtension: fileExtension,
            subdirectory: resourceSubdirectory
        ) ?? bundle.url(forResource: name, withExtension: fileExtension)
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.count == 64
            && value.unicodeScalars.allSatisfy {
                (UnicodeScalar("0")...UnicodeScalar("9")).contains($0)
                    || (UnicodeScalar("a")...UnicodeScalar("f")).contains($0)
            }
    }
}
