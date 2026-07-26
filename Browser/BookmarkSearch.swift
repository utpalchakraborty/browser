import Foundation

nonisolated enum BookmarkSearch {
    static func filteredBookmarks(
        in bookmarks: [Bookmark],
        matching query: String
    ) -> [Bookmark] {
        let normalizedQuery = query.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalizedQuery.isEmpty else {
            return bookmarks
        }

        return bookmarks.filter {
            $0.title.localizedCaseInsensitiveContains(normalizedQuery)
                || $0.url.absoluteString.localizedCaseInsensitiveContains(
                    normalizedQuery
                )
        }
    }
}
