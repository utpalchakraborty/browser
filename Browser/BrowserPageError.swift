import Foundation

nonisolated enum BrowserPageError: Error, Equatable, Sendable {
    case offline
    case cannotReachServer
    case tlsFailure
    case tooManyRedirects
    case timedOut
    case generic
    case cancelled
    case webContentProcessTerminated
}

nonisolated struct BrowserErrorPresentation: Equatable, Sendable {
    let kind: BrowserPageError
    let title: String
    let message: String
    let recoveryActionTitle: String?

    static func from(
        error: any Error,
        attemptedURL: URL?
    ) -> BrowserErrorPresentation? {
        let kind = (error as? BrowserPageError) ?? classify(error)
        guard kind != .cancelled else {
            return nil
        }

        let host = sanitizedHost(from: attemptedURL)
        let destination = host.map { " \($0)" } ?? " the page"

        switch kind {
        case .offline:
            return BrowserErrorPresentation(
                kind: kind,
                title: "You’re Offline",
                message: "Check your internet connection and try again.",
                recoveryActionTitle: "Try Again"
            )
        case .cannotReachServer:
            return BrowserErrorPresentation(
                kind: kind,
                title: "Can’t Reach Server",
                message: "Browser couldn’t connect to\(destination).",
                recoveryActionTitle: "Try Again"
            )
        case .tlsFailure:
            return BrowserErrorPresentation(
                kind: kind,
                title: "Secure Connection Failed",
                message: "Browser couldn’t establish a secure connection to\(destination).",
                recoveryActionTitle: "Try Again"
            )
        case .tooManyRedirects:
            return BrowserErrorPresentation(
                kind: kind,
                title: "Too Many Redirects",
                message: "Browser stopped loading\(destination) because it redirected too many times.",
                recoveryActionTitle: "Try Again"
            )
        case .timedOut:
            return BrowserErrorPresentation(
                kind: kind,
                title: "Connection Timed Out",
                message: "Browser took too long to reach\(destination).",
                recoveryActionTitle: "Try Again"
            )
        case .webContentProcessTerminated:
            return BrowserErrorPresentation(
                kind: kind,
                title: "Page Stopped Working",
                message: "Browser can reload\(destination).",
                recoveryActionTitle: "Reload"
            )
        case .generic:
            return BrowserErrorPresentation(
                kind: kind,
                title: "Page Couldn’t Load",
                message: "Browser couldn’t load\(destination).",
                recoveryActionTitle: "Try Again"
            )
        case .cancelled:
            return nil
        }
    }

    private static func classify(_ error: any Error) -> BrowserPageError {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else {
            return .generic
        }

        let code = URLError.Code(rawValue: nsError.code)
        switch code {
        case .cancelled:
            return .cancelled
        case .notConnectedToInternet:
            return .offline
        case .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .networkConnectionLost,
             .resourceUnavailable:
            return .cannotReachServer
        case .secureConnectionFailed,
             .serverCertificateHasBadDate,
             .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid,
             .clientCertificateRejected,
             .clientCertificateRequired,
             .appTransportSecurityRequiresSecureConnection:
            return .tlsFailure
        case .httpTooManyRedirects:
            return .tooManyRedirects
        case .timedOut:
            return .timedOut
        default:
            return .generic
        }
    }

    private static func sanitizedHost(from url: URL?) -> String? {
        guard let host = url?.host else {
            return nil
        }

        let withoutControls = String(
            host.unicodeScalars.filter {
                !CharacterSet.controlCharacters.contains($0)
            }
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !withoutControls.isEmpty else {
            return nil
        }

        return String(withoutControls.prefix(255))
    }
}
