import AppKit
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

nonisolated enum NewContextNavigationPolicy {
    static func shouldRouteInCurrentPage(
        url: URL?,
        isLinkActivation: Bool,
        buttonNumber: Int,
        modifierFlags: NSEvent.ModifierFlags
    ) -> Bool {
        guard
            isLinkActivation,
            buttonNumber == 1,
            modifierFlags.intersection([
                .command,
                .control,
                .option,
                .shift,
            ]).isEmpty,
            let scheme = url?.scheme?.lowercased(),
            ["http", "https"].contains(scheme)
        else {
            return false
        }

        return true
    }
}
