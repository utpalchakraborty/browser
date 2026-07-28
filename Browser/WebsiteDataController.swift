import Foundation
import WebKit

@MainActor
final class WebsiteDataController {
    let websiteDataStore: WKWebsiteDataStore

    init(websiteDataStore: WKWebsiteDataStore) {
        self.websiteDataStore = websiteDataStore
    }

    func cookies() async -> [HTTPCookie] {
        await websiteDataStore.httpCookieStore.allCookies()
    }

    func snapshot() async -> WebsiteDataSnapshot {
        // WebKit does not expose an atomic cookie-and-record snapshot. Keep both
        // reads on its UI actor and present the freshly reconciled result as one
        // best-effort view of the profile.
        let currentCookies = await cookies()
        let currentRecords = await records()
        return WebsiteDataSnapshot(
            cookies: currentCookies,
            records: currentRecords
        )
    }

    func deleteCookie(_ cookie: HTTPCookie) async {
        await websiteDataStore.httpCookieStore.deleteCookie(cookie)
    }

    func deleteCookie(
        withID identifier: WebsiteCookieID
    ) async -> WebsiteDataMutationResult {
        let matchingCookies = await cookies().filter {
            WebsiteCookieID(cookie: $0) == identifier
        }
        for cookie in matchingCookies {
            await deleteCookie(cookie)
        }

        let refreshed = await snapshot()
        if refreshed.containsCookie(id: identifier) {
            return WebsiteDataMutationResult(
                snapshot: refreshed,
                didRemoveRequestedData: false,
                message: "The cookie is still present. An open page may have recreated it."
            )
        }
        return WebsiteDataMutationResult(
            snapshot: refreshed,
            didRemoveRequestedData: true,
            message: matchingCookies.isEmpty
                ? "The cookie was already gone. Website data was refreshed."
                : "Cookie deleted."
        )
    }

    func deleteCookies(applicableToHost host: String) async {
        let allCookies = await cookies()
        let matchingCookies = allCookies.filter {
            Self.cookieDomain($0.domain, isApplicableToHost: host)
        }

        for cookie in matchingCookies {
            await deleteCookie(cookie)
        }
    }

    func deleteCookies(
        exactDomain domain: String
    ) async -> WebsiteDataMutationResult {
        let normalizedDomain = WebsiteCookieID.normalizedDomain(domain)
        guard !normalizedDomain.isEmpty else {
            return WebsiteDataMutationResult(
                snapshot: await snapshot(),
                didRemoveRequestedData: false,
                message: "No valid cookie domain was selected."
            )
        }

        let matchingCookies = await cookies().filter {
            WebsiteCookieID(cookie: $0).domain == normalizedDomain
        }
        for cookie in matchingCookies {
            await deleteCookie(cookie)
        }

        let refreshed = await snapshot()
        if refreshed.containsCookies(exactDomain: normalizedDomain) {
            return WebsiteDataMutationResult(
                snapshot: refreshed,
                didRemoveRequestedData: false,
                message: "Some cookies for \(normalizedDomain) are still present. An open page may have recreated them."
            )
        }
        return WebsiteDataMutationResult(
            snapshot: refreshed,
            didRemoveRequestedData: true,
            message: matchingCookies.isEmpty
                ? "Cookies for \(normalizedDomain) were already gone. Website data was refreshed."
                : "Cookies for \(normalizedDomain) deleted. Other website data was left intact."
        )
    }

    func clearAllCookies() async {
        await websiteDataStore.removeData(
            ofTypes: [WKWebsiteDataTypeCookies],
            modifiedSince: .distantPast
        )
    }

    func clearAllCookiesAndVerify() async -> WebsiteDataMutationResult {
        await clearAllCookies()
        let refreshed = await snapshot()
        guard refreshed.cookieCount == 0 else {
            return WebsiteDataMutationResult(
                snapshot: refreshed,
                didRemoveRequestedData: false,
                message: "Some cookies are still present. An open page may have recreated them."
            )
        }
        return WebsiteDataMutationResult(
            snapshot: refreshed,
            didRemoveRequestedData: true,
            message: "All cookies deleted. Other website data was left intact."
        )
    }

    func records(
        ofTypes dataTypes: Set<String> = WKWebsiteDataStore.allWebsiteDataTypes()
    ) async -> [WKWebsiteDataRecord] {
        await websiteDataStore.dataRecords(ofTypes: dataTypes)
    }

    func delete(
        records: [WKWebsiteDataRecord],
        dataTypes: Set<String>
    ) async {
        await websiteDataStore.removeData(
            ofTypes: dataTypes,
            for: records
        )
    }

    func deleteWebsiteData(
        for identifier: WebsiteDataRecordID
    ) async -> WebsiteDataMutationResult {
        let currentRecords = await records()
        let matchingRecords = currentRecords.filter {
            WebsiteDataRecordID(displayName: $0.displayName) == identifier
        }
        let matchingTypes = matchingRecords.reduce(into: Set<String>()) {
            partialResult, record in
            partialResult.formUnion(record.dataTypes)
        }
        if !matchingRecords.isEmpty, !matchingTypes.isEmpty {
            await delete(records: matchingRecords, dataTypes: matchingTypes)
        }

        let refreshed = await snapshot()
        if refreshed.containsRecord(id: identifier) {
            return WebsiteDataMutationResult(
                snapshot: refreshed,
                didRemoveRequestedData: false,
                message: "Some website data is still present. An open page may have recreated it."
            )
        }
        return WebsiteDataMutationResult(
            snapshot: refreshed,
            didRemoveRequestedData: true,
            message: matchingRecords.isEmpty
                ? "That website data was already gone. Website data was refreshed."
                : "Website data deleted. This full-data action may also remove cookies and sign-ins for that record."
        )
    }

    func clearAllWebsiteData() async {
        await websiteDataStore.removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        )
    }

    func clearAllWebsiteDataAndVerify() async -> WebsiteDataMutationResult {
        await clearAllWebsiteData()
        let refreshed = await snapshot()
        guard refreshed.cookieCount == 0, refreshed.records.isEmpty else {
            return WebsiteDataMutationResult(
                snapshot: refreshed,
                didRemoveRequestedData: false,
                message: "Some website data is still present. An open page may have recreated it."
            )
        }
        return WebsiteDataMutationResult(
            snapshot: refreshed,
            didRemoveRequestedData: true,
            message: "All WebKit website data deleted, including cookies."
        )
    }

    nonisolated static func cookieDomain(
        _ cookieDomain: String,
        isApplicableToHost host: String
    ) -> Bool {
        let cookie = cookieDomain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let requestedHost = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))

        guard !cookie.isEmpty, !requestedHost.isEmpty else {
            return false
        }
        return requestedHost == cookie || requestedHost.hasSuffix("." + cookie)
    }
}
