import XCTest
@testable import Browser

final class AddressInterpreterTests: XCTestCase {
    func testDefaultSearchProviderIsDuckDuckGoAndChoicesAreVisible() {
        let interpreter = AddressInterpreter()

        XCTAssertEqual(interpreter.searchProvider, .duckDuckGo)
        XCTAssertEqual(SearchProvider.defaultProvider, .duckDuckGo)
        XCTAssertEqual(
            SearchProvider.allCases.map(\.displayName),
            ["DuckDuckGo", "Google", "Bing"]
        )
    }

    func testAcceptsExplicitHTTPAndHTTPSURLs() {
        let interpreter = AddressInterpreter()

        XCTAssertEqual(
            interpreter.interpret("http://example.com/path?q=value#fragment"),
            .navigate(URL(string: "http://example.com/path?q=value#fragment")!)
        )
        XCTAssertEqual(
            interpreter.interpret("  HTTPS://example.com/secure  \n"),
            .navigate(URL(string: "https://example.com/secure")!)
        )
        XCTAssertEqual(
            interpreter.interpret("http://intranet/resource"),
            .navigate(URL(string: "http://intranet/resource")!)
        )
    }

    func testInfersHTTPSForPlausibleHosts() {
        let interpreter = AddressInterpreter()

        let cases = [
            ("example.com", "https://example.com"),
            ("example.com/path?q=value", "https://example.com/path?q=value"),
            ("localhost:8443/test", "https://localhost:8443/test"),
            ("127.0.0.1:8080/test", "https://127.0.0.1:8080/test"),
            ("[::1]:8443/test", "https://[::1]:8443/test"),
        ]

        for (input, expected) in cases {
            XCTAssertEqual(
                interpreter.interpret(input),
                .navigate(URL(string: expected)!),
                input
            )
        }
    }

    func testPlainTextAndSingleLabelInputBecomeSearches() {
        let interpreter = AddressInterpreter()

        XCTAssertEqual(
            interpreter.interpret("swift concurrency"),
            .navigate(URL(string: "https://duckduckgo.com/?q=swift%20concurrency")!)
        )
        XCTAssertEqual(
            interpreter.interpret("intranet"),
            .navigate(URL(string: "https://duckduckgo.com/?q=intranet")!)
        )
        XCTAssertEqual(
            interpreter.interpret("site:example.com privacy"),
            .navigate(
                URL(
                    string: "https://duckduckgo.com/?q=site:example.com%20privacy"
                )!
            )
        )
    }

    func testSelectedProviderConstructsItsOwnEncodedSearchURL() {
        let query = "privacy & browsers"
        let cases: [(SearchProvider, String)] = [
            (.duckDuckGo, "https://duckduckgo.com/?q=privacy%20%26%20browsers"),
            (.google, "https://www.google.com/search?q=privacy%20%26%20browsers"),
            (.bing, "https://www.bing.com/search?q=privacy%20%26%20browsers"),
        ]

        for (provider, expected) in cases {
            XCTAssertEqual(
                AddressInterpreter(searchProvider: provider).interpret(query),
                .navigate(URL(string: expected)!),
                provider.displayName
            )
        }
    }

    func testEmptyInputIsRejected() {
        let interpreter = AddressInterpreter()

        XCTAssertEqual(interpreter.interpret(""), .failure(.emptyInput))
        XCTAssertEqual(interpreter.interpret(" \n\t "), .failure(.emptyInput))
        XCTAssertEqual(
            AddressInterpretationError.emptyInput.errorDescription,
            "Enter a web address or search term."
        )
    }

    func testMalformedExplicitWebURLsAreRejectedInsteadOfSearched() {
        let interpreter = AddressInterpreter()
        let cases = [
            "https://",
            "http:example.com",
            "https://user:password@example.com/private",
            "https://example..com",
            "https://example.com:",
            "https://example.com:99999",
            "https://[not:an-ipv6-address]",
        ]

        for input in cases {
            XCTAssertEqual(
                interpreter.interpret(input),
                .failure(.malformedURL),
                input
            )
        }
    }

    func testMalformedHostIntentIsRejectedInsteadOfSearched() {
        let interpreter = AddressInterpreter()
        let cases = [
            "//example.com",
            "example..com",
            "localhost:not-a-port",
            "example.com:",
            "999.999.999.999",
        ]

        for input in cases {
            XCTAssertEqual(
                interpreter.interpret(input),
                .failure(.malformedURL),
                input
            )
        }
    }

    func testUnsupportedSchemesAreRejectedExplicitly() {
        let interpreter = AddressInterpreter()
        let cases = [
            ("file:///tmp/private", "file"),
            ("javascript:alert(1)", "javascript"),
            ("mailto:user@example.com", "mailto"),
            ("custom-scheme://host/path", "custom-scheme"),
            ("about:blank", "about"),
        ]

        for (input, scheme) in cases {
            XCTAssertEqual(
                interpreter.interpret(input),
                .failure(.unsupportedScheme(scheme)),
                input
            )
        }
    }
}
