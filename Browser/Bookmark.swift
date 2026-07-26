import Foundation

nonisolated enum BookmarkURLValidationError: Error, Equatable, Sendable {
    case unsupportedScheme(String?)
    case missingHost
    case credentialsNotAllowed
    case malformedURL
}

extension BookmarkURLValidationError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .unsupportedScheme(scheme):
            if let scheme {
                return "Bookmarks support only HTTP and HTTPS URLs, not \(scheme)."
            }
            return "Bookmarks require an HTTP or HTTPS URL."
        case .missingHost:
            return "A bookmark URL must include a host."
        case .credentialsNotAllowed:
            return "Bookmark URLs cannot contain a username or password."
        case .malformedURL:
            return "That bookmark URL is not valid."
        }
    }
}

nonisolated enum BookmarkURLCanonicalizer {
    static func canonicalURL(for url: URL) throws -> URL {
        guard var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            throw BookmarkURLValidationError.malformedURL
        }

        let scheme = components.scheme?.lowercased()
        guard let scheme, ["http", "https"].contains(scheme) else {
            throw BookmarkURLValidationError.unsupportedScheme(components.scheme)
        }
        guard let host = components.host, !host.isEmpty else {
            throw BookmarkURLValidationError.missingHost
        }
        guard components.user == nil, components.password == nil else {
            throw BookmarkURLValidationError.credentialsNotAllowed
        }
        guard
            !host.unicodeScalars.contains(where: {
                CharacterSet.whitespacesAndNewlines.contains($0)
                    || CharacterSet.controlCharacters.contains($0)
            })
        else {
            throw BookmarkURLValidationError.malformedURL
        }

        components.scheme = scheme
        components.host = host.lowercased()
        if (scheme == "http" && components.port == 80)
            || (scheme == "https" && components.port == 443)
        {
            components.port = nil
        }
        if components.percentEncodedPath.isEmpty {
            components.percentEncodedPath = "/"
        }
        if components.percentEncodedQuery == "" {
            components.percentEncodedQuery = nil
        }
        if components.percentEncodedFragment == "" {
            components.percentEncodedFragment = nil
        }

        guard
            let canonicalURL = components.url,
            canonicalURL.scheme == scheme,
            canonicalURL.host != nil
        else {
            throw BookmarkURLValidationError.malformedURL
        }
        return canonicalURL
    }
}

nonisolated struct Bookmark: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let url: URL
    let title: String
    let createdAt: Date
    let updatedAt: Date

    static func canonicalURL(for url: URL) throws -> URL {
        try BookmarkURLCanonicalizer.canonicalURL(for: url)
    }

    static func canonicalURLString(for url: URL) throws -> String {
        try canonicalURL(for: url).absoluteString
    }

    init(
        id: UUID = UUID(),
        url: URL,
        title: String,
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) throws {
        let canonicalURL = try Self.canonicalURL(for: url)
        let normalizedTitle = Self.normalizedTitle(title, url: canonicalURL)
        let resolvedUpdatedAt = updatedAt ?? createdAt
        guard resolvedUpdatedAt >= createdAt else {
            throw BookmarkValidationError.updatePredatesCreation
        }

        self.id = id
        self.url = canonicalURL
        self.title = normalizedTitle
        self.createdAt = createdAt
        self.updatedAt = resolvedUpdatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case url
        case title
        case createdAt
        case updatedAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        let url = try container.decode(URL.self, forKey: .url)
        let title = try container.decode(String.self, forKey: .title)
        let createdAt = try container.decode(Date.self, forKey: .createdAt)
        let updatedAt = try container.decode(Date.self, forKey: .updatedAt)

        do {
            try self.init(
                id: id,
                url: url,
                title: title,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .url,
                in: container,
                debugDescription: "Invalid bookmark: \(error.localizedDescription)"
            )
        }
    }

    private static func normalizedTitle(_ title: String, url: URL) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        return url.host ?? url.absoluteString
    }
}

nonisolated enum BookmarkValidationError: Error, Equatable, Sendable {
    case updatePredatesCreation
}

extension BookmarkValidationError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .updatePredatesCreation:
            "A bookmark update cannot predate its creation."
        }
    }
}

nonisolated struct BookmarkFile: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let bookmarks: [Bookmark]

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        bookmarks: [Bookmark]
    ) {
        self.schemaVersion = schemaVersion
        self.bookmarks = bookmarks
    }
}
