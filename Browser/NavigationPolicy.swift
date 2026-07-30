import AppKit
import Foundation

nonisolated enum NavigationPolicyDecision: Equatable, Sendable {
    case allow
    case cancel
}

nonisolated enum ExternalNavigationDisposition: Equatable, Sendable {
    case open(URL)
    case none
}

nonisolated enum ExternalNavigationPolicy {
    private static let browserIntentModifiers: NSEvent.ModifierFlags = [
        .command,
        .control,
        .option,
        .shift,
    ]

    static func disposition(
        for url: URL?,
        isLinkActivation: Bool,
        buttonNumber: Int,
        modifierFlags: NSEvent.ModifierFlags,
        targetsTopLevelContext: Bool
    ) -> ExternalNavigationDisposition {
        guard
            let url,
            url.scheme?.lowercased() == "magnet",
            isLinkActivation,
            buttonNumber == 1,
            targetsTopLevelContext,
            modifierFlags.intersection(browserIntentModifiers).isEmpty
        else {
            return .none
        }

        return .open(url)
    }
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

nonisolated enum NewTabNavigationDisposition: Equatable, Sendable {
    case continueInCurrentFrame
    case foregroundTab
    case backgroundTab
    case deny
}

nonisolated enum NewContextNavigationPolicy {
    private static let browserIntentModifiers: NSEvent.ModifierFlags = [
        .command,
        .control,
        .option,
        .shift,
    ]

    static func disposition(
        url: URL?,
        isLinkActivation: Bool,
        buttonNumber: Int,
        modifierFlags: NSEvent.ModifierFlags,
        requestsNewContext: Bool
    ) -> NewTabNavigationDisposition {
        let intentModifiers = modifierFlags.intersection(
            browserIntentModifiers
        )
        let scheme = url?.scheme?.lowercased()
        let isWebURL = scheme == "http" || scheme == "https"
        let isDirectPrimaryLink = isLinkActivation
            && buttonNumber == 1
            && isWebURL

        if isDirectPrimaryLink, intentModifiers == [.command] {
            return .backgroundTab
        }

        if requestsNewContext {
            return isDirectPrimaryLink && intentModifiers.isEmpty
                ? .foregroundTab
                : .deny
        }

        return .continueInCurrentFrame
    }
}
