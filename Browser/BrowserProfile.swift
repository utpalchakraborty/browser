import Foundation
import WebKit

@MainActor
final class BrowserProfile {
    static let normalDataStoreIdentifier = UUID(
        uuidString: "5D1F8E17-6A12-4C9C-9B1D-B9E17A4C7110"
    )!
    static let testHostDataStoreIdentifier = UUID(
        uuidString: "7B92BEE3-7745-444A-A312-D787CB93DB6E"
    )!
    static let performanceDataStoreIdentifier = UUID(
        uuidString: "2272E2F6-C1D7-4F1E-B69C-E8E0325FB03C"
    )!

    let websiteDataStore: WKWebsiteDataStore
    let webViewFactory: WebViewFactory

    init(dataStoreIdentifier: UUID = normalDataStoreIdentifier) {
        let websiteDataStore = WKWebsiteDataStore(
            forIdentifier: dataStoreIdentifier
        )
        self.websiteDataStore = websiteDataStore
        webViewFactory = WebViewFactory(websiteDataStore: websiteDataStore)
    }

    static func applicationDataStoreIdentifier(
        environment: [String: String],
        arguments: [String] = []
    ) -> UUID {
        if arguments.contains("--performance-test") {
            return performanceDataStoreIdentifier
        }
        if arguments.contains("--ui-test-profile") {
            return testHostDataStoreIdentifier
        }
        if environment["XCTestConfigurationFilePath"] != nil {
            return testHostDataStoreIdentifier
        }
        return normalDataStoreIdentifier
    }
}
