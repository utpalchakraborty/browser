import WebKit

@MainActor
final class WebViewFactory {
    private let websiteDataStore: WKWebsiteDataStore

    init(websiteDataStore: WKWebsiteDataStore) {
        self.websiteDataStore = websiteDataStore
    }

    func makeWebView(
        frame: CGRect = .zero,
        contentRuleLists: [WKContentRuleList] = [],
        userContentController: WKUserContentController? = nil
    ) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = websiteDataStore
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false

        if let userContentController {
            configuration.userContentController = userContentController
        }
        for ruleList in contentRuleLists {
            configuration.userContentController.add(ruleList)
        }

        return WKWebView(frame: frame, configuration: configuration)
    }
}
