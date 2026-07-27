import Foundation

private struct ContentBlockerLastValidState: Codable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let identifiers: [String]
}

@MainActor
final class ContentBlockerStateStore {
    private static let defaultKey = "contentBlocker.lastValidRuleSet"

    private let defaults: UserDefaults
    private let key: String

    init(
        defaults: UserDefaults = .standard,
        key: String = ContentBlockerStateStore.defaultKey
    ) {
        self.defaults = defaults
        self.key = key
    }

    func lastValidIdentifiers() -> [String]? {
        guard
            let data = defaults.data(forKey: key),
            let state = try? JSONDecoder().decode(
                ContentBlockerLastValidState.self,
                from: data
            ),
            state.schemaVersion
                == ContentBlockerLastValidState.currentSchemaVersion,
            Self.identifiersAreValid(state.identifiers)
        else {
            return nil
        }
        return state.identifiers
    }

    func recordLastValidIdentifiers(_ identifiers: [String]) {
        guard Self.identifiersAreValid(identifiers) else {
            return
        }
        let state = ContentBlockerLastValidState(
            schemaVersion: ContentBlockerLastValidState.currentSchemaVersion,
            identifiers: identifiers
        )
        guard let encoded = try? JSONEncoder().encode(state) else {
            return
        }
        defaults.set(encoded, forKey: key)
    }

    func reset() {
        defaults.removeObject(forKey: key)
    }

    private nonisolated static func identifiersAreValid(
        _ identifiers: [String]
    ) -> Bool {
        !identifiers.isEmpty
            && identifiers.allSatisfy { !$0.isEmpty }
            && Set(identifiers).count == identifiers.count
    }
}
