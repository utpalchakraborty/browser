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

    func deleteCookie(_ cookie: HTTPCookie) async {
        await websiteDataStore.httpCookieStore.deleteCookie(cookie)
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

    func clearAllCookies() async {
        await websiteDataStore.removeData(
            ofTypes: [WKWebsiteDataTypeCookies],
            modifiedSince: .distantPast
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

    func clearAllWebsiteData() async {
        await websiteDataStore.removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        )
    }

    nonisolated static func cookieDomain(
        _ cookieDomain: String,
        isApplicableToHost host: String
    ) -> Bool {
        let cookie = cookieDomain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let requestedHost = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))

        return requestedHost == cookie || requestedHost.hasSuffix("." + cookie)
    }
}
