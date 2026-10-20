import Foundation

@MainActor
enum BrowserPreferences {
    private static let searchProviderKey = "searchProvider"
    private static let bookmarkSidebarVisibleKey = "bookmarkSidebarVisible"

    static func bookmarkSidebarVisible(
        in defaults: UserDefaults = BrowserLaunchConfiguration.current.defaults
    ) -> Bool {
        guard defaults.object(forKey: bookmarkSidebarVisibleKey) != nil else {
            return true
        }
        return defaults.bool(forKey: bookmarkSidebarVisibleKey)
    }

    static func setBookmarkSidebarVisible(
        _ visible: Bool,
        in defaults: UserDefaults = BrowserLaunchConfiguration.current.defaults
    ) {
        defaults.set(visible, forKey: bookmarkSidebarVisibleKey)
    }

    static func searchProvider(in defaults: UserDefaults = BrowserLaunchConfiguration.current.defaults) -> SearchProvider {
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
        in defaults: UserDefaults = BrowserLaunchConfiguration.current.defaults
    ) {
        defaults.set(provider.rawValue, forKey: searchProviderKey)
    }
}
