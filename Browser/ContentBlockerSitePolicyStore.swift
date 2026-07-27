import Foundation

private struct ContentBlockerSitePolicyState: Codable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let exceptionHosts: [String]
}

@MainActor
final class ContentBlockerSitePolicyStore {
    private static let defaultKey = "contentBlocker.siteExceptions"

    private let defaults: UserDefaults
    private let key: String

    init(
        defaults: UserDefaults = .standard,
        key: String = ContentBlockerSitePolicyStore.defaultKey
    ) {
        self.defaults = defaults
        self.key = key
    }

    func isException(_ site: ContentBlockerSite) -> Bool {
        allExceptionHosts().contains(site.host)
    }

    func setException(
        _ isException: Bool,
        for site: ContentBlockerSite
    ) {
        var hosts = Set(allExceptionHosts())
        if isException {
            hosts.insert(site.host)
        } else {
            hosts.remove(site.host)
        }
        persist(hosts.sorted())
    }

    func allExceptionHosts() -> [String] {
        guard
            let data = defaults.data(forKey: key),
            let state = try? JSONDecoder().decode(
                ContentBlockerSitePolicyState.self,
                from: data
            ),
            state.schemaVersion
                == ContentBlockerSitePolicyState.currentSchemaVersion,
            Set(state.exceptionHosts).count == state.exceptionHosts.count,
            state.exceptionHosts.allSatisfy({ host in
                ContentBlockerSite(host: host)?.host == host
            })
        else {
            return []
        }
        return state.exceptionHosts.sorted()
    }

    func reset() {
        defaults.removeObject(forKey: key)
    }

    private func persist(_ hosts: [String]) {
        guard !hosts.isEmpty else {
            reset()
            return
        }

        let state = ContentBlockerSitePolicyState(
            schemaVersion: ContentBlockerSitePolicyState.currentSchemaVersion,
            exceptionHosts: hosts
        )
        guard let data = try? JSONEncoder().encode(state) else {
            return
        }
        defaults.set(data, forKey: key)
    }
}
