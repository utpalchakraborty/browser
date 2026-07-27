import Foundation

nonisolated enum ContentBlockingPolicyApplicationMode: Equatable, Sendable {
    /// Leave the resident controller unchanged, as required for stale callbacks.
    case none
    /// Attach protection when needed, but never detach it from a live document.
    case strengthenOnly
    /// Match the committed page after the winning navigation resolves.
    case exact
}

nonisolated enum ContentBlockingNavigationFailureDisposition: Equatable, Sendable {
    case stale
    case current(ContentBlockingPolicyApplicationMode)
}

nonisolated enum ContentBlockingNavigationURL {
    static func isFragmentOnlyNavigation(from sourceURL: URL?, to targetURL: URL?) -> Bool {
        guard
            let sourceURL,
            let targetURL,
            let sourceScheme = sourceURL.scheme?.lowercased(),
            let targetScheme = targetURL.scheme?.lowercased(),
            [sourceScheme, targetScheme].allSatisfy({ $0 == "http" || $0 == "https" }),
            var sourceComponents = URLComponents(
                url: sourceURL,
                resolvingAgainstBaseURL: false
            ),
            var targetComponents = URLComponents(
                url: targetURL,
                resolvingAgainstBaseURL: false
            )
        else {
            return false
        }

        let sourceFragment = sourceComponents.percentEncodedFragment
        let targetFragment = targetComponents.percentEncodedFragment
        sourceComponents.percentEncodedFragment = nil
        targetComponents.percentEncodedFragment = nil
        return sourceFragment != targetFragment
            && sourceComponents.string == targetComponents.string
    }
}

nonisolated struct ContentBlockingNavigationState<NavigationID: Hashable> {
    private var nextAttemptID: UInt64 = 0
    private var latestAttemptID: UInt64?
    private var latestAttemptAwaitingAction = false
    private var latestAttemptIsUnbound = false
    private var attemptByNavigationID = [NavigationID: UInt64]()
    private var committedNavigationID: NavigationID?

    var hasActiveNavigation: Bool {
        latestAttemptID != nil
    }

    @discardableResult
    mutating func beginRequest() -> ContentBlockingPolicyApplicationMode {
        _ = startAttempt(awaitingAction: true)
        return .strengthenOnly
    }

    @discardableResult
    mutating func approveAction() -> ContentBlockingPolicyApplicationMode {
        if latestAttemptID != nil, latestAttemptAwaitingAction {
            latestAttemptAwaitingAction = false
        } else {
            _ = startAttempt(awaitingAction: false)
        }
        return .strengthenOnly
    }

    @discardableResult
    mutating func bind(
        _ navigationID: NavigationID
    ) -> ContentBlockingPolicyApplicationMode {
        if attemptByNavigationID[navigationID] != nil {
            return .strengthenOnly
        }
        if let latestAttemptID, latestAttemptIsUnbound {
            attemptByNavigationID[navigationID] = latestAttemptID
            latestAttemptIsUnbound = false
            return .strengthenOnly
        }

        let attemptID = startAttempt(awaitingAction: false)
        attemptByNavigationID[navigationID] = attemptID
        latestAttemptIsUnbound = false
        return .strengthenOnly
    }

    @discardableResult
    mutating func bindRedirect(
        _ navigationID: NavigationID
    ) -> ContentBlockingPolicyApplicationMode {
        if let latestAttemptID, latestAttemptIsUnbound {
            attemptByNavigationID[navigationID] = latestAttemptID
            latestAttemptIsUnbound = false
            return .strengthenOnly
        }
        return bind(navigationID)
    }

    mutating func commit(
        _ navigationID: NavigationID?
    ) -> ContentBlockingPolicyApplicationMode {
        guard let navigationID else {
            return latestAttemptID == nil ? .exact : .strengthenOnly
        }

        let attemptID = resolveAttempt(for: navigationID)
        attemptByNavigationID.removeValue(forKey: navigationID)
        committedNavigationID = navigationID
        guard let latestAttemptID else {
            return .exact
        }
        guard attemptID == latestAttemptID else {
            return .strengthenOnly
        }

        clearLatestAttempt(latestAttemptID)
        return .exact
    }

    mutating func fail(
        _ navigationID: NavigationID?
    ) -> ContentBlockingNavigationFailureDisposition {
        guard let navigationID else {
            return .stale
        }

        // A committed navigation can still fail while a newer action is
        // waiting for WebKit to provide its navigation token. Do not let the
        // older callback claim that unbound attempt and restore a weaker
        // committed-page policy over it.
        if navigationID == committedNavigationID {
            return latestAttemptID == nil ? .current(.none) : .stale
        }

        let attemptID = resolveAttempt(for: navigationID)
        attemptByNavigationID.removeValue(forKey: navigationID)
        if let latestAttemptID, attemptID == latestAttemptID {
            clearLatestAttempt(latestAttemptID)
            return .current(.exact)
        }
        if latestAttemptID != nil {
            return .stale
        }
        return .stale
    }

    mutating func cancelLatest() -> ContentBlockingPolicyApplicationMode {
        if let latestAttemptID {
            clearLatestAttempt(latestAttemptID)
        }
        return .exact
    }

    mutating func cancelAwaitingRequest() -> ContentBlockingPolicyApplicationMode {
        guard
            let latestAttemptID,
            latestAttemptAwaitingAction
        else {
            return .none
        }
        clearLatestAttempt(latestAttemptID)
        return .exact
    }

    mutating func resolveSameDocumentAction() -> ContentBlockingPolicyApplicationMode {
        guard
            let latestAttemptID,
            latestAttemptAwaitingAction
        else {
            return .none
        }
        clearLatestAttempt(latestAttemptID)
        return .strengthenOnly
    }

    private mutating func startAttempt(awaitingAction: Bool) -> UInt64 {
        nextAttemptID &+= 1
        latestAttemptID = nextAttemptID
        latestAttemptAwaitingAction = awaitingAction
        latestAttemptIsUnbound = true
        return nextAttemptID
    }

    private mutating func resolveAttempt(
        for navigationID: NavigationID
    ) -> UInt64? {
        if let attemptID = attemptByNavigationID[navigationID] {
            return attemptID
        }
        guard let latestAttemptID, latestAttemptIsUnbound else {
            return nil
        }
        latestAttemptIsUnbound = false
        return latestAttemptID
    }

    private mutating func clearLatestAttempt(_ attemptID: UInt64) {
        guard latestAttemptID == attemptID else {
            return
        }
        latestAttemptID = nil
        latestAttemptAwaitingAction = false
        latestAttemptIsUnbound = false
        attemptByNavigationID = attemptByNavigationID.filter {
            $0.value != attemptID
        }
    }
}
