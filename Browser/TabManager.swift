import Foundation
import WebKit

@MainActor
final class TabManager {
    private(set) var tabs: [TabController]
    private(set) var selectedTabID: UUID

    init(initialTab: TabController) {
        tabs = [initialTab]
        selectedTabID = initialTab.id
    }

    var selectedTab: TabController {
        guard let tab = tabs.first(where: { $0.id == selectedTabID }) else {
            preconditionFailure("TabManager must always have a selected tab")
        }
        return tab
    }

    var residentWebViews: [WKWebView] {
        tabs.compactMap(\.webView)
    }

    var presentations: [BrowserTabPresentation] {
        tabs.map {
            BrowserTabPresentation(
                id: $0.id,
                title: $0.displayTitle,
                isSelected: $0.id == selectedTabID
            )
        }
    }

    func tab(id: UUID) -> TabController? {
        tabs.first { $0.id == id }
    }

    func append(_ tab: TabController, select: Bool) {
        tabs.append(tab)
        if select {
            selectedTabID = tab.id
        }
    }

    @discardableResult
    func select(id: UUID) -> Bool {
        guard tabs.contains(where: { $0.id == id }) else {
            return false
        }
        selectedTabID = id
        return true
    }

    @discardableResult
    func remove(id: UUID) -> TabController? {
        guard
            tabs.count > 1,
            let index = tabs.firstIndex(where: { $0.id == id })
        else {
            return nil
        }

        let removed = tabs.remove(at: index)
        if selectedTabID == id {
            selectedTabID = tabs[min(index, tabs.count - 1)].id
        }
        return removed
    }

    func replaceSoleTab(with replacement: TabController) -> TabController {
        precondition(tabs.count == 1)
        let removed = tabs[0]
        tabs = [replacement]
        selectedTabID = replacement.id
        return removed
    }

    func closeAll() -> [TabController] {
        let removed = tabs
        // Keep the selection invariant valid until the owning window
        // controller is released. Every returned tab is immediately closed,
        // so this retained controller contains no WebView or browsing state.
        tabs = [selectedTab]
        return removed
    }
}
