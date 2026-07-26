import Foundation
import XCTest
@testable import Browser

final class BrowserPageErrorTests: XCTestCase {
    func testCancellationHasNoPresentation() {
        XCTAssertNil(
            BrowserErrorPresentation.from(
                error: URLError(.cancelled),
                attemptedURL: URL(string: "https://example.com/private")
            )
        )
        XCTAssertNil(
            BrowserErrorPresentation.from(
                error: BrowserPageError.cancelled,
                attemptedURL: nil
            )
        )
    }

    func testURLErrorCategoriesHaveUsefulPresentations() throws {
        let cases: [(URLError.Code, BrowserPageError, String)] = [
            (.notConnectedToInternet, .offline, "You’re Offline"),
            (.cannotFindHost, .cannotReachServer, "Can’t Reach Server"),
            (.cannotConnectToHost, .cannotReachServer, "Can’t Reach Server"),
            (.dnsLookupFailed, .cannotReachServer, "Can’t Reach Server"),
            (.networkConnectionLost, .cannotReachServer, "Can’t Reach Server"),
            (.secureConnectionFailed, .tlsFailure, "Secure Connection Failed"),
            (.serverCertificateUntrusted, .tlsFailure, "Secure Connection Failed"),
            (.httpTooManyRedirects, .tooManyRedirects, "Too Many Redirects"),
            (.timedOut, .timedOut, "Connection Timed Out"),
            (.badURL, .generic, "Page Couldn’t Load"),
        ]

        for (code, expectedKind, expectedTitle) in cases {
            let presentation = try XCTUnwrap(
                BrowserErrorPresentation.from(
                    error: URLError(code),
                    attemptedURL: URL(string: "https://example.com/path")
                )
            )
            XCTAssertEqual(presentation.kind, expectedKind, String(describing: code))
            XCTAssertEqual(presentation.title, expectedTitle, String(describing: code))
            XCTAssertEqual(presentation.recoveryActionTitle, "Try Again")
        }
    }

    func testNSErrorInURLDomainIsClassifiedWithoutDependingOnConcreteErrorType() throws {
        let error = NSError(
            domain: NSURLErrorDomain,
            code: URLError.Code.cannotFindHost.rawValue
        )

        let presentation = try XCTUnwrap(
            BrowserErrorPresentation.from(
                error: error,
                attemptedURL: URL(string: "https://example.com")
            )
        )

        XCTAssertEqual(presentation.kind, .cannotReachServer)
    }

    func testProcessTerminationOffersReload() throws {
        let presentation = try XCTUnwrap(
            BrowserErrorPresentation.from(
                error: BrowserPageError.webContentProcessTerminated,
                attemptedURL: URL(string: "https://example.com")
            )
        )

        XCTAssertEqual(presentation.kind, .webContentProcessTerminated)
        XCTAssertEqual(presentation.title, "Page Stopped Working")
        XCTAssertEqual(presentation.recoveryActionTitle, "Reload")
    }

    func testPresentationUsesOnlyTheHostFromAttemptedURL() throws {
        let url = try XCTUnwrap(
            URL(string: "https://user:password@example.com/private/path?token=secret#fragment")
        )
        let presentation = try XCTUnwrap(
            BrowserErrorPresentation.from(
                error: URLError(.cannotConnectToHost),
                attemptedURL: url
            )
        )

        XCTAssertTrue(presentation.message.contains("example.com"))
        for privateValue in ["user", "password", "private", "token", "secret", "fragment"] {
            XCTAssertFalse(presentation.message.contains(privateValue), privateValue)
        }
    }

    func testGenericPresentationDoesNotEchoLocalizedErrorDetails() throws {
        let secret = "sensitive-error-detail"
        let error = NSError(
            domain: "UnrelatedDomain",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: secret]
        )

        let presentation = try XCTUnwrap(
            BrowserErrorPresentation.from(error: error, attemptedURL: nil)
        )

        XCTAssertEqual(presentation.kind, .generic)
        XCTAssertFalse(presentation.message.contains(secret))
    }
}
