import Darwin
import Foundation

nonisolated enum SearchProvider: String, CaseIterable, Sendable {
    case duckDuckGo = "duckduckgo"
    case google
    case bing

    static let defaultProvider: SearchProvider = .duckDuckGo

    var displayName: String {
        switch self {
        case .duckDuckGo:
            "DuckDuckGo"
        case .google:
            "Google"
        case .bing:
            "Bing"
        }
    }

    func searchURL(for query: String) -> URL {
        var components: URLComponents
        switch self {
        case .duckDuckGo:
            components = URLComponents(string: "https://duckduckgo.com/")!
        case .google:
            components = URLComponents(string: "https://www.google.com/search")!
        case .bing:
            components = URLComponents(string: "https://www.bing.com/search")!
        }
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        return components.url!
    }
}

nonisolated enum AddressInterpretation: Equatable, Sendable {
    case navigate(URL)
    case localFile(URL)
    case failure(AddressInterpretationError)
}

nonisolated enum AddressSubmissionIntent: Equatable, Sendable {
    case standard
    case completeDotCom
}

nonisolated enum AddressInterpretationError: Error, Equatable, Sendable {
    case emptyInput
    case malformedURL
    case invalidLocalFile
    case unsupportedLocalFileType
    case unsupportedScheme(String)
}

extension AddressInterpretationError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .emptyInput:
            "Enter a web address, local HTML path, or search term."
        case .malformedURL:
            "That web address is not valid."
        case .invalidLocalFile:
            "That local file address is not valid."
        case .unsupportedLocalFileType:
            "Browser can open local .html and .htm files."
        case .unsupportedScheme:
            "Browser can open HTTP and HTTPS addresses or approved local HTML files."
        }
    }
}

nonisolated struct AddressInterpreter: Sendable {
    var searchProvider: SearchProvider

    init(searchProvider: SearchProvider = .defaultProvider) {
        self.searchProvider = searchProvider
    }

    func interpret(
        _ input: String,
        intent: AddressSubmissionIntent = .standard
    ) -> AddressInterpretation {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(.emptyInput)
        }

        if trimmed.hasPrefix("/"), !trimmed.hasPrefix("//") {
            return Self.localFileInterpretation(
                for: URL(fileURLWithPath: trimmed)
            )
        }

        if
            intent == .completeDotCom,
            let url = Self.dotComShortcutURL(from: trimmed)
        {
            return .navigate(url)
        }

        if let explicitScheme = Self.explicitScheme(in: trimmed) {
            let normalizedScheme = explicitScheme.lowercased()
            if normalizedScheme == "file" {
                return Self.localFileInterpretation(
                    for: URL(string: trimmed)
                )
            }
            if ["http", "https"].contains(normalizedScheme) {
                guard let url = Self.validWebURL(from: trimmed) else {
                    return .failure(.malformedURL)
                }
                return .navigate(url)
            }

            if Self.isExplicitUnsupportedScheme(
                normalizedScheme,
                in: trimmed
            ) {
                return .failure(.unsupportedScheme(normalizedScheme))
            }
        }

        if let url = Self.inferredHTTPSURL(from: trimmed) {
            return .navigate(url)
        }

        if Self.looksLikeMalformedHostInput(trimmed) {
            return .failure(.malformedURL)
        }

        return .navigate(searchProvider.searchURL(for: trimmed))
    }

    private static func localFileInterpretation(
        for url: URL?
    ) -> AddressInterpretation {
        guard
            let url,
            let normalizedURL = LocalFileAccessPolicy
                .standardizedNavigationURL(url),
            !url.path.isEmpty
        else {
            return .failure(.invalidLocalFile)
        }
        guard LocalFileAccessPolicy.isSupportedHTMLFile(normalizedURL) else {
            return .failure(.unsupportedLocalFileType)
        }
        return .localFile(normalizedURL)
    }

    private static func dotComShortcutURL(from input: String) -> URL? {
        guard
            !input.contains("."),
            input.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
            input.rangeOfCharacter(from: CharacterSet(charactersIn: "/:?#")) == nil
        else {
            return nil
        }

        return inferredHTTPSURL(from: "\(input).com")
    }

    private static func validWebURL(from input: String) -> URL? {
        guard var components = URLComponents(string: input) else {
            return nil
        }

        let normalizedScheme = components.scheme?.lowercased()
        guard
            let normalizedScheme,
            ["http", "https"].contains(normalizedScheme),
            let host = components.host,
            isValidHost(host, allowSingleLabel: true),
            components.user == nil,
            components.password == nil,
            !hasEmptyPort(in: input),
            validPort(components.port)
        else {
            return nil
        }

        components.scheme = normalizedScheme
        return components.url
    }

    private static func inferredHTTPSURL(from input: String) -> URL? {
        guard
            !input.unicodeScalars.contains(where: {
                CharacterSet.whitespacesAndNewlines.contains($0)
            }),
            !input.hasPrefix("//"),
            var components = URLComponents(string: "https://\(input)"),
            let host = components.host,
            isValidHost(host, allowSingleLabel: false),
            components.user == nil,
            components.password == nil,
            !hasEmptyPort(in: input),
            validPort(components.port)
        else {
            return nil
        }

        components.scheme = "https"
        return components.url
    }

    private static func explicitScheme(in input: String) -> String? {
        guard let colonIndex = input.firstIndex(of: ":") else {
            return nil
        }

        let candidate = input[..<colonIndex]
        guard
            let first = candidate.unicodeScalars.first,
            CharacterSet.asciiLetters.contains(first),
            candidate.dropFirst().unicodeScalars.allSatisfy({
                CharacterSet.schemeCharacters.contains($0)
            })
        else {
            return nil
        }

        return String(candidate)
    }

    private static func isExplicitUnsupportedScheme(
        _ scheme: String,
        in input: String
    ) -> Bool {
        if input.range(of: "://") != nil {
            return true
        }

        let recognizedNonWebSchemes: Set<String> = [
            "about",
            "blob",
            "data",
            "facetime",
            "facetime-audio",
            "file",
            "ftp",
            "javascript",
            "mailto",
            "magnet",
            "sms",
            "tel",
        ]
        return recognizedNonWebSchemes.contains(scheme)
    }

    private static func looksLikeMalformedHostInput(_ input: String) -> Bool {
        guard
            !input.unicodeScalars.contains(where: {
                CharacterSet.whitespacesAndNewlines.contains($0)
            })
        else {
            return false
        }

        if input.hasPrefix("//") {
            return true
        }

        let authorityEnd = input.firstIndex(where: { ["/", "?", "#"].contains($0) })
            ?? input.endIndex
        let authority = input[..<authorityEnd]

        if authority.hasPrefix("[") {
            return true
        }

        let hostCandidate = authority.split(separator: ":", maxSplits: 1).first
            .map(String.init) ?? ""
        return hostCandidate.lowercased() == "localhost"
            || hostCandidate.contains(".")
    }

    private static func validPort(_ port: Int?) -> Bool {
        guard let port else {
            return true
        }
        return (1...65_535).contains(port)
    }

    private static func hasEmptyPort(in input: String) -> Bool {
        let authorityStart: String.Index
        if let schemeSeparator = input.range(of: "://") {
            authorityStart = schemeSeparator.upperBound
        } else {
            authorityStart = input.startIndex
        }
        let authorityEnd = input[authorityStart...].firstIndex(where: {
            ["/", "?", "#"].contains($0)
        }) ?? input.endIndex
        return input[authorityStart..<authorityEnd].hasSuffix(":")
    }

    private static func isValidHost(
        _ host: String,
        allowSingleLabel: Bool
    ) -> Bool {
        guard !host.hasPrefix("."), !host.hasSuffix("..") else {
            return false
        }
        let normalized = host.hasSuffix(".") ? String(host.dropLast()) : host
        guard !normalized.isEmpty, normalized.utf8.count <= 253 else {
            return false
        }

        if normalized.lowercased() == "localhost" {
            return true
        }

        if normalized.hasPrefix("[") && normalized.hasSuffix("]") {
            var address = in6_addr()
            return normalized.dropFirst().dropLast().withCString {
                inet_pton(AF_INET6, $0, &address) == 1
            }
        }

        if normalized.unicodeScalars.allSatisfy({
            CharacterSet.decimalDigits.contains($0) || $0 == "."
        }) {
            let octets = normalized.split(separator: ".", omittingEmptySubsequences: false)
            return octets.count == 4 && octets.allSatisfy {
                guard let value = Int($0) else {
                    return false
                }
                return (0...255).contains(value)
            }
        }

        let labels = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard allowSingleLabel || labels.count >= 2 else {
            return false
        }

        return labels.allSatisfy { label in
            guard
                !label.isEmpty,
                label.count <= 63,
                label.first != "-",
                label.last != "-"
            else {
                return false
            }
            return label.unicodeScalars.allSatisfy {
                CharacterSet.alphanumerics.contains($0) || $0 == "-"
            }
        }
    }
}

private nonisolated extension CharacterSet {
    static let asciiLetters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
    )
    static let schemeCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+.-"
    )
}
