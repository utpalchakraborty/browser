import Dispatch
import Foundation
import WebKit
import XCTest
@testable import Browser

@MainActor
final class ContentBlockerPerformanceTests: XCTestCase {
    private static let lookupSampleCount = 100
    private static let attachmentSampleCount = 500
    private static let attachmentP95LimitMilliseconds = 50.0

    func testCachedLookupAndSynchronousAttachmentPerformance() async throws {
        let rules = try ContentBlockerService.probeRules(
            blockedURLFilter: ".*/benchmark-blocked[.]js",
            exceptionTopURLFilters: []
        )
        let namespace = "phase1-content-rule-performance-v1"
        let identifier = ContentBlockerService.versionedIdentifier(
            namespace: namespace,
            encodedRules: rules
        )
        let service = ContentBlockerService()

        // Compilation is deliberately setup, not measurement. Removing the
        // stable identifier first makes every invocation follow the same path.
        try? await service.removeCachedRuleList(identifier: identifier)
        let compiledRuleList = try await service.cachedOrCompile(
            namespace: namespace,
            encodedRules: rules
        )
        XCTAssertEqual(compiledRuleList.identifier, identifier)

        // Prime WebKit's persisted-rule lookup before collecting samples.
        let warmedRuleList = try await service.cachedOrCompile(
            namespace: namespace,
            encodedRules: rules
        )
        XCTAssertEqual(warmedRuleList.identifier, identifier)

        var lookupDurations = [Double]()
        lookupDurations.reserveCapacity(Self.lookupSampleCount)
        var cachedRuleList = warmedRuleList
        for _ in 0..<Self.lookupSampleCount {
            let start = DispatchTime.now().uptimeNanoseconds
            cachedRuleList = try await service.cachedOrCompile(
                namespace: namespace,
                encodedRules: rules
            )
            lookupDurations.append(milliseconds(since: start))
            XCTAssertEqual(cachedRuleList.identifier, identifier)
        }

        let contentController = WKUserContentController()
        for _ in 0..<10 {
            service.replace(nil, with: cachedRuleList, on: contentController)
            service.remove(cachedRuleList, from: contentController)
        }

        var attachmentDurations = [Double]()
        attachmentDurations.reserveCapacity(Self.attachmentSampleCount)
        var removalDurations = [Double]()
        removalDurations.reserveCapacity(Self.attachmentSampleCount)
        for _ in 0..<Self.attachmentSampleCount {
            var start = DispatchTime.now().uptimeNanoseconds
            service.replace(nil, with: cachedRuleList, on: contentController)
            attachmentDurations.append(milliseconds(since: start))

            start = DispatchTime.now().uptimeNanoseconds
            service.remove(cachedRuleList, from: contentController)
            removalDurations.append(milliseconds(since: start))
        }

        let report = BlockerBenchmarkReport(
            lookup: .init(samples: lookupDurations),
            attachment: .init(samples: attachmentDurations),
            removal: .init(samples: removalDurations),
            attachmentP95LimitMilliseconds:
                Self.attachmentP95LimitMilliseconds
        )
        print("BROWSER_BLOCKER_BENCHMARK=\(try report.encodedJSON())")

        XCTAssertLessThan(
            report.attachment.p95Milliseconds,
            Self.attachmentP95LimitMilliseconds,
            "Cached content-rule attachment exceeded the Phase 1 p95 gate"
        )
        try await service.removeCachedRuleList(identifier: identifier)
    }

    private func milliseconds(since start: UInt64) -> Double {
        let elapsedNanoseconds = DispatchTime.now().uptimeNanoseconds - start
        return Double(elapsedNanoseconds) / 1_000_000.0
    }
}

private struct BlockerBenchmarkReport: Encodable {
    let lookup: DurationSummary
    let attachment: DurationSummary
    let removal: DurationSummary
    let attachmentP95LimitMilliseconds: Double

    enum CodingKeys: String, CodingKey {
        case lookup
        case attachment
        case removal
        case attachmentP95LimitMilliseconds =
            "attachment_p95_limit_milliseconds"
    }

    func encodedJSON() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        return String(decoding: data, as: UTF8.self)
    }
}

private struct DurationSummary: Encodable {
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
