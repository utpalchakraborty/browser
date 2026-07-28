import Foundation
import WebKit

nonisolated struct WebsiteCookieID: Hashable, Sendable {
    let domain: String
    let path: String
    let name: String

    init(domain: String, path: String, name: String) {
        self.domain = Self.normalizedDomain(domain)
        self.path = path.isEmpty ? "/" : path
        self.name = name
    }

    init(cookie: HTTPCookie) {
        self.init(
            domain: cookie.domain,
            path: cookie.path,
            name: cookie.name
        )
    }

    var accessibilityToken: String {
        Data("\(domain)\u{0}\(path)\u{0}\(name)".utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
    }

    static func normalizedDomain(_ domain: String) -> String {
        domain
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
    }
}

nonisolated struct WebsiteCookieSnapshot: Equatable, Sendable, Identifiable {
    static let maskedValue = "••••••••"

    let id: WebsiteCookieID
    let name: String
    let domain: String
    let path: String
    let value: String
    let expiresDate: Date?
    let isSessionOnly: Bool
    let isSecure: Bool
    let isHTTPOnly: Bool
    let sameSitePolicy: String?

    init(cookie: HTTPCookie) {
        id = WebsiteCookieID(cookie: cookie)
        name = cookie.name
        domain = cookie.domain
        path = cookie.path
        value = cookie.value
        expiresDate = cookie.expiresDate
        isSessionOnly = cookie.isSessionOnly
        isSecure = cookie.isSecure
        isHTTPOnly = cookie.isHTTPOnly
        sameSitePolicy = Self.displaySameSitePolicy(
            cookie.sameSitePolicy?.rawValue
        )
    }

    init(
        id: WebsiteCookieID,
        name: String,
        domain: String,
        path: String,
        value: String,
        expiresDate: Date?,
        isSecure: Bool,
        isHTTPOnly: Bool,
        sameSitePolicy: String?
    ) {
        self.id = id
        self.name = name
        self.domain = domain
        self.path = path
        self.value = value
        self.expiresDate = expiresDate
        isSessionOnly = expiresDate == nil
        self.isSecure = isSecure
        self.isHTTPOnly = isHTTPOnly
        self.sameSitePolicy = sameSitePolicy
    }

    private static func displaySameSitePolicy(_ rawValue: String?) -> String? {
        guard let rawValue else {
            return nil
        }
        switch rawValue.lowercased() {
        case "lax":
            return "Lax"
        case "strict":
            return "Strict"
        case "none":
            return "None"
        default:
            return rawValue
        }
    }
}

nonisolated struct WebsiteCookieDomainSnapshot: Equatable, Sendable, Identifiable {
    var id: String { domain }

    let domain: String
    let cookies: [WebsiteCookieSnapshot]
}

nonisolated struct WebsiteDataCategory: Equatable, Hashable, Sendable,
    Identifiable
{
    var id: String { rawType }

    let rawType: String
    let displayName: String

    init(rawType: String) {
        self.rawType = rawType
        displayName = Self.displayName(for: rawType)
    }

    static func displayName(for rawType: String) -> String {
        switch rawType {
        case WKWebsiteDataTypeCookies:
            return "Cookies"
        case WKWebsiteDataTypeDiskCache:
            return "Disk Cache"
        case WKWebsiteDataTypeMemoryCache:
            return "Memory Cache"
        case WKWebsiteDataTypeOfflineWebApplicationCache:
            return "Offline Web App Cache"
        case WKWebsiteDataTypeSessionStorage:
            return "Session Storage"
        case WKWebsiteDataTypeLocalStorage:
            return "Local Storage"
        case WKWebsiteDataTypeWebSQLDatabases:
            return "WebSQL Databases"
        case WKWebsiteDataTypeIndexedDBDatabases:
            return "IndexedDB Databases"
        case WKWebsiteDataTypeFetchCache:
            return "Fetch Cache"
        case WKWebsiteDataTypeServiceWorkerRegistrations:
            return "Service Workers"
        case WKWebsiteDataTypeFileSystem:
            return "File System Storage"
        case WKWebsiteDataTypeSearchFieldRecentSearches:
            return "Recent Searches"
        case WKWebsiteDataTypeMediaKeys:
            return "Media Keys"
        case WKWebsiteDataTypeHashSalt:
            return "Device Identifier Salt"
        case WKWebsiteDataTypeScreenTime:
            return "Screen Time Data"
        default:
            return "Other Website Data"
        }
    }
}

nonisolated struct WebsiteDataRecordID: Hashable, Sendable {
    let displayName: String

    init(displayName: String) {
        self.displayName = Self.normalizedDisplayName(displayName)
    }

    var accessibilityToken: String {
        Data(displayName.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
    }

    static func normalizedDisplayName(_ displayName: String) -> String {
        displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

nonisolated struct WebsiteDataRecordSnapshot: Equatable, Sendable, Identifiable {
    let id: WebsiteDataRecordID
    let displayName: String
    let categories: [WebsiteDataCategory]
}

nonisolated struct WebsiteDataSnapshot: Equatable, Sendable {
    static let empty = WebsiteDataSnapshot(cookieDomains: [], records: [])

    let cookieDomains: [WebsiteCookieDomainSnapshot]
    let records: [WebsiteDataRecordSnapshot]

    var cookieCount: Int {
        cookieDomains.reduce(0) { $0 + $1.cookies.count }
    }

    init(
        cookieDomains: [WebsiteCookieDomainSnapshot],
        records: [WebsiteDataRecordSnapshot]
    ) {
        self.cookieDomains = cookieDomains
        self.records = records
    }

    @MainActor
    init(cookies: [HTTPCookie], records: [WKWebsiteDataRecord]) {
        let cookieSnapshots = cookies.map(WebsiteCookieSnapshot.init(cookie:))
        let groupedCookies = Dictionary(grouping: cookieSnapshots) { cookie in
            cookie.id.domain
        }
        cookieDomains = groupedCookies.map { domain, cookies in
            WebsiteCookieDomainSnapshot(
                domain: domain,
                cookies: cookies.sorted(by: Self.cookieSort)
            )
        }.sorted(by: Self.cookieDomainSort)

        let groupedRecords = Dictionary(grouping: records) { record in
            WebsiteDataRecordID(displayName: record.displayName)
        }
        self.records = groupedRecords.map { identifier, matchingRecords in
            let displayName = matchingRecords
                .map { $0.displayName }
                .sorted(by: Self.textSort)
                .first ?? identifier.displayName
            let rawTypes = matchingRecords.reduce(into: Set<String>()) {
                partialResult, record in
                partialResult.formUnion(record.dataTypes)
            }
            return WebsiteDataRecordSnapshot(
                id: identifier,
                displayName: displayName,
                categories: rawTypes
                    .map(WebsiteDataCategory.init(rawType:))
                    .sorted(by: Self.categorySort)
            )
        }.sorted(by: Self.recordSort)
    }

    func cookie(id: WebsiteCookieID) -> WebsiteCookieSnapshot? {
        cookieDomains.lazy
            .flatMap(\.cookies)
            .first { $0.id == id }
    }

    func containsCookie(id: WebsiteCookieID) -> Bool {
        cookie(id: id) != nil
    }

    func containsCookies(exactDomain domain: String) -> Bool {
        let normalized = WebsiteCookieID.normalizedDomain(domain)
        return cookieDomains.contains { $0.domain == normalized }
    }

    func containsRecord(id: WebsiteDataRecordID) -> Bool {
        records.contains { $0.id == id }
    }

    private static func cookieSort(
        _ left: WebsiteCookieSnapshot,
        _ right: WebsiteCookieSnapshot
    ) -> Bool {
        if left.name != right.name {
            return textSort(left.name, right.name)
        }
        if left.path != right.path {
            return textSort(left.path, right.path)
        }
        return textSort(left.domain, right.domain)
    }

    private static func cookieDomainSort(
        _ left: WebsiteCookieDomainSnapshot,
        _ right: WebsiteCookieDomainSnapshot
    ) -> Bool {
        textSort(left.domain, right.domain)
    }

    private static func recordSort(
        _ left: WebsiteDataRecordSnapshot,
        _ right: WebsiteDataRecordSnapshot
    ) -> Bool {
        textSort(left.displayName, right.displayName)
    }

    private static func categorySort(
        _ left: WebsiteDataCategory,
        _ right: WebsiteDataCategory
    ) -> Bool {
        if left.displayName != right.displayName {
            return textSort(left.displayName, right.displayName)
        }
        return textSort(left.rawType, right.rawType)
    }

    private static func textSort(_ left: String, _ right: String) -> Bool {
        left.localizedCaseInsensitiveCompare(right) == .orderedAscending
    }
}

nonisolated struct WebsiteDataMutationResult: Equatable, Sendable {
    let snapshot: WebsiteDataSnapshot
    let didRemoveRequestedData: Bool
    let message: String
}
