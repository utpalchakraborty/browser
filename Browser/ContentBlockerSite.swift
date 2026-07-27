import Darwin
import Foundation

nonisolated struct ContentBlockerSite: Codable, Hashable, Sendable {
    let host: String

    init?(url: URL) {
        guard
            let scheme = url.scheme?.lowercased(),
            ["http", "https"].contains(scheme),
            let host = url.host
        else {
            return nil
        }
        self.init(host: host)
    }

    init?(host: String) {
        guard let normalizedHost = Self.normalize(host) else {
            return nil
        }
        self.host = normalizedHost
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let encodedHost = try container.decode(String.self)
        guard
            let site = Self(host: encodedHost),
            site.host == encodedHost
        else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Content-blocker site host is not normalized."
            )
        }
        self = site
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(host)
    }

    private static func normalize(_ host: String) -> String? {
        guard !host.isEmpty else {
            return nil
        }

        var candidate = host
        if candidate.hasPrefix("[") || candidate.hasSuffix("]") {
            guard candidate.hasPrefix("["), candidate.hasSuffix("]") else {
                return nil
            }
            candidate.removeFirst()
            candidate.removeLast()
        }
        if candidate.hasSuffix(".") {
            candidate.removeLast()
        }

        guard
            !candidate.isEmpty,
            !candidate.unicodeScalars.contains(where: {
                CharacterSet.whitespacesAndNewlines.contains($0)
                    || CharacterSet.controlCharacters.contains($0)
            }),
            candidate.rangeOfCharacter(from: CharacterSet(charactersIn: "/?#@%[]")) == nil
        else {
            return nil
        }

        if candidate.contains(":") {
            return normalizedIPv6Address(candidate)
        }

        if candidate.unicodeScalars.allSatisfy({
            CharacterSet.decimalDigits.contains($0) || $0 == "."
        }) {
            return normalizedIPv4Address(candidate)
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = candidate
        components.percentEncodedPath = "/"
        guard
            let canonicalHost = components.url?.host?.lowercased(),
            !canonicalHost.isEmpty,
            canonicalHost.utf8.count <= 253
        else {
            return nil
        }

        let labels = canonicalHost.split(
            separator: ".",
            omittingEmptySubsequences: false
        )
        guard labels.allSatisfy({ label in
            guard
                !label.isEmpty,
                label.utf8.count <= 63,
                label.first != "-",
                label.last != "-"
            else {
                return false
            }
            return label.unicodeScalars.allSatisfy {
                CharacterSet.asciiHostCharacters.contains($0)
            }
        }) else {
            return nil
        }

        return canonicalHost
    }

    private static func normalizedIPv4Address(_ host: String) -> String? {
        var address = in_addr()
        guard inet_pton(AF_INET, host, &address) == 1 else {
            return nil
        }

        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET, &address, &buffer, socklen_t(buffer.count)) != nil else {
            return nil
        }
        return string(fromNullTerminated: buffer)
    }

    private static func normalizedIPv6Address(_ host: String) -> String? {
        var address = in6_addr()
        guard inet_pton(AF_INET6, host, &address) == 1 else {
            return nil
        }

        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        guard inet_ntop(AF_INET6, &address, &buffer, socklen_t(buffer.count)) != nil else {
            return nil
        }
        return string(fromNullTerminated: buffer).lowercased()
    }

    private static func string(
        fromNullTerminated buffer: [CChar]
    ) -> String {
        String(
            decoding: buffer.prefix(while: { $0 != 0 }).map {
                UInt8(bitPattern: $0)
            },
            as: UTF8.self
        )
    }
}

private nonisolated extension CharacterSet {
    static let asciiHostCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-"
    )
}
