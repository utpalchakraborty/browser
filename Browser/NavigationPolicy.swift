import Foundation

nonisolated enum NavigationPolicyDecision: Equatable, Sendable {
    case allow
    case cancel
}

nonisolated enum NavigationPolicy {
    static func decision(
        for url: URL?,
        isMainFrame: Bool
    ) -> NavigationPolicyDecision {
        guard let url, let scheme = url.scheme?.lowercased() else {
            return .cancel
        }

        if ["http", "https"].contains(scheme) {
            return .allow
        }

        if url.absoluteString.lowercased() == "about:blank" {
            return .allow
        }

        if !isMainFrame {
            if url.absoluteString.lowercased() == "about:srcdoc" {
                return .allow
            }
            if ["blob", "data", "javascript"].contains(scheme) {
                return .allow
            }
        }

        return .cancel
    }
}
