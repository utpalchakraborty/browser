import Foundation

@MainActor
enum BrowserPreferences {
    private static let searchProviderKey = "searchProvider"

    static func searchProvider(in defaults: UserDefaults = .standard) -> SearchProvider {
        guard
            let rawValue = defaults.string(forKey: searchProviderKey),
            let provider = SearchProvider(rawValue: rawValue)
        else {
            return .defaultProvider
        }
        return provider
    }

    static func setSearchProvider(
        _ provider: SearchProvider,
        in defaults: UserDefaults = .standard
    ) {
        defaults.set(provider.rawValue, forKey: searchProviderKey)
    }
}
