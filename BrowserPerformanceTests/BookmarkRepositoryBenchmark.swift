#if BOOKMARK_REPOSITORY_BENCHMARK
import Dispatch
import Foundation

@main
struct BookmarkRepositoryBenchmark {
    private static let bookmarkCount = 10_000
    private static let loadSampleCount = 10
    private static let searchSampleCount = 50
    private static let loadP95LimitMilliseconds = 100.0
    private static let searchP95LimitMilliseconds = 50.0

    static func main() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "BookmarkRepositoryBenchmark.\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }

        let fixture = try makeFixture()
        let fixtureData = try encoded(fixture)
        let primaryURL = directoryURL.appendingPathComponent(
            BookmarkRepository.primaryFileName,
            isDirectory: false
        )
        try fixtureData.write(to: primaryURL, options: .atomic)

        // Prime file-system caches outside the measurements. Each measured load
        // still constructs a fresh repository and decodes and validates all rows.
        let primedSnapshot = try await BookmarkRepository(
            directoryURL: directoryURL
        ).load()
        try require(
            primedSnapshot.bookmarks.count == bookmarkCount,
            "Primed load returned \(primedSnapshot.bookmarks.count) bookmarks"
        )

        var loadDurations = [Double]()
        loadDurations.reserveCapacity(loadSampleCount)
        for _ in 0..<loadSampleCount {
            let repository = BookmarkRepository(directoryURL: directoryURL)
            let start = DispatchTime.now().uptimeNanoseconds
            let snapshot = try await repository.load()
            loadDurations.append(milliseconds(since: start))
            try require(
                snapshot.bookmarks.count == bookmarkCount,
                "Measured load returned \(snapshot.bookmarks.count) bookmarks"
            )
            try require(
                snapshot.recovery == nil,
                "A valid benchmark fixture unexpectedly entered recovery"
            )
        }

        let searchRepository = BookmarkRepository(directoryURL: directoryURL)
        _ = try await searchRepository.load()
        let searchQueries = stride(from: 0, to: bookmarkCount, by: 1_000)
            .map { String(format: "bookmark %05d", $0) }
        var repositorySearchDurations = [Double]()
        repositorySearchDurations.reserveCapacity(searchSampleCount)
        for sample in 0..<searchSampleCount {
            let query = searchQueries[sample % searchQueries.count]
            let start = DispatchTime.now().uptimeNanoseconds
            let matches = try await searchRepository.search(query)
            repositorySearchDurations.append(milliseconds(since: start))
            try validate(matches: matches, for: query, path: "Repository search")
        }

        var managerFilterDurations = [Double]()
        managerFilterDurations.reserveCapacity(searchSampleCount)
        for sample in 0..<searchSampleCount {
            let query = searchQueries[sample % searchQueries.count]
            let start = DispatchTime.now().uptimeNanoseconds
            let matches = BookmarkSearch.filteredBookmarks(
                in: primedSnapshot.bookmarks,
                matching: query
            )
            managerFilterDurations.append(milliseconds(since: start))
            try validate(matches: matches, for: query, path: "Manager filter")
        }

        let report = BookmarkBenchmarkReport(
            bookmarkCount: bookmarkCount,
            fixtureBytes: fixtureData.count,
            load: .init(samples: loadDurations),
            repositorySearch: .init(samples: repositorySearchDurations),
            managerFilter: .init(samples: managerFilterDurations),
            loadP95LimitMilliseconds: loadP95LimitMilliseconds,
            searchP95LimitMilliseconds: searchP95LimitMilliseconds
        )
        print("BROWSER_BOOKMARK_BENCHMARK=\(try report.encodedJSON())")

        try require(
            report.load.p95Milliseconds < loadP95LimitMilliseconds,
            "10,000-bookmark load p95 \(report.load.p95Milliseconds) ms "
                + "exceeded the \(loadP95LimitMilliseconds) ms gate"
        )
        try require(
            report.repositorySearch.p95Milliseconds
                < searchP95LimitMilliseconds,
            "10,000-bookmark repository search p95 "
                + "\(report.repositorySearch.p95Milliseconds) ms "
                + "exceeded the \(searchP95LimitMilliseconds) ms gate"
        )
        try require(
            report.managerFilter.p95Milliseconds < searchP95LimitMilliseconds,
            "10,000-bookmark manager filter p95 "
                + "\(report.managerFilter.p95Milliseconds) ms "
                + "exceeded the \(searchP95LimitMilliseconds) ms gate"
        )
    }

    private static func makeFixture() throws -> BookmarkFile {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let bookmarks = try (0..<bookmarkCount).map { index in
            let identifierSuffix = String(format: "%012x", index)
            guard
                let identifier = UUID(
                    uuidString: "B0000000-0000-4000-8000-\(identifierSuffix)"
                ),
                let url = URL(
                    string:
                        "https://benchmark.example/items/\(index)?fixture=phase3"
                )
            else {
                throw BookmarkBenchmarkError.invalidFixture(index)
            }
            return try Bookmark(
                id: identifier,
                url: url,
                title: String(format: "Benchmark Bookmark %05d", index),
                createdAt: timestamp,
                updatedAt: timestamp
            )
        }
        return BookmarkFile(bookmarks: bookmarks)
    }

    private static func encoded(_ file: BookmarkFile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys,
            .withoutEscapingSlashes,
        ]
        var data = try encoder.encode(file)
        data.append(0x0A)
        return data
    }

    private static func milliseconds(since start: UInt64) -> Double {
        let elapsedNanoseconds = DispatchTime.now().uptimeNanoseconds - start
        return Double(elapsedNanoseconds) / 1_000_000.0
    }

    private static func validate(
        matches: [Bookmark],
        for query: String,
        path: String
    ) throws {
        try require(
            matches.count == 1,
            "\(path) for \(query) returned \(matches.count) matches"
        )
        try require(
            matches.first?.title == "Benchmark \(query.capitalized)",
            "\(path) for \(query) returned the wrong bookmark"
        )
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: @autoclosure () -> String
    ) throws {
        guard condition() else {
            throw BookmarkBenchmarkError.failedGate(message())
        }
    }
}

private enum BookmarkBenchmarkError: Error, CustomStringConvertible {
    case invalidFixture(Int)
    case failedGate(String)

    var description: String {
        switch self {
        case let .invalidFixture(index):
            "Could not construct benchmark bookmark \(index)"
        case let .failedGate(message):
            message
        }
    }
}

private struct BookmarkBenchmarkReport: Encodable {
    let bookmarkCount: Int
    let fixtureBytes: Int
    let load: BookmarkDurationSummary
    let repositorySearch: BookmarkDurationSummary
    let managerFilter: BookmarkDurationSummary
    let loadP95LimitMilliseconds: Double
    let searchP95LimitMilliseconds: Double

    enum CodingKeys: String, CodingKey {
        case bookmarkCount = "bookmark_count"
        case fixtureBytes = "fixture_bytes"
        case load
        case repositorySearch = "repository_search"
        case managerFilter = "manager_filter"
        case loadP95LimitMilliseconds = "load_p95_limit_milliseconds"
        case searchP95LimitMilliseconds = "search_p95_limit_milliseconds"
    }

    func encodedJSON() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }
}

private struct BookmarkDurationSummary: Encodable {
    let sampleCount: Int
    let minimumMilliseconds: Double
    let medianMilliseconds: Double
    let p95Milliseconds: Double
    let maximumMilliseconds: Double

    enum CodingKeys: String, CodingKey {
        case sampleCount = "sample_count"
        case minimumMilliseconds = "minimum_milliseconds"
        case medianMilliseconds = "median_milliseconds"
        case p95Milliseconds = "p95_milliseconds"
        case maximumMilliseconds = "maximum_milliseconds"
    }

    init(samples: [Double]) {
        precondition(!samples.isEmpty)
        let ordered = samples.sorted()
        sampleCount = ordered.count
        minimumMilliseconds = ordered[0]
        medianMilliseconds = Self.percentile(0.50, in: ordered)
        p95Milliseconds = Self.percentile(0.95, in: ordered)
        maximumMilliseconds = ordered[ordered.count - 1]
    }

    private static func percentile(
        _ percentile: Double,
        in orderedSamples: [Double]
    ) -> Double {
        let nearestRank = Int(ceil(percentile * Double(orderedSamples.count)))
        return orderedSamples[max(0, nearestRank - 1)]
    }
}
#endif
