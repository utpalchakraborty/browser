import Foundation
import XCTest
@testable import Browser

@MainActor
final class BookmarkTransactionTests: XCTestCase {
    private enum Operation: CaseIterable { case firstAdd, add, edit, delete, reset, restore }
    private struct Fixture {
        let directory: URL
        let original: Bookmark?
        var primary: URL { directory.appendingPathComponent(BookmarkRepository.primaryFileName) }
        var backup: URL { directory.appendingPathComponent(BookmarkRepository.backupFileName) }
        var journal: URL { directory.appendingPathComponent(BookmarkRepository.transactionFileName) }
    }

    func testEveryMutationRollsBackAtEachDurableStep() async throws {
        for operation in Operation.allCases {
            // Restore reuses the valid backup, so only journal/primary/commit mutate.
            for failingStep in 1...(operation == .restore ? 3 : 4) {
                let fixture = try await prepare(operation)
                defer { try? FileManager.default.removeItem(at: fixture.directory) }
                let faults = BookmarkFaults(failingSteps: [failingStep])
                let repository = BookmarkRepository(directoryURL: fixture.directory,
                    fileManager: FaultingBookmarkFileManager(faults: faults), atomicWriter: faults)
                let before = try await repository.load()
                let primary = try bytes(fixture.primary)
                let backup = try bytes(fixture.backup)
                do {
                    try await perform(operation, in: repository, original: fixture.original)
                    XCTFail("Expected failure: \(operation), step \(failingStep)")
                } catch {
                    XCTAssertTrue(error is BookmarkFault, "\(operation) step \(failingStep): \(error)")
                }
                XCTAssertEqual(try bytes(fixture.primary), primary)
                XCTAssertEqual(try bytes(fixture.backup), backup)
                XCTAssertNil(try bytes(fixture.journal))
                let cached = try await repository.load()
                let fresh = try await BookmarkRepository(directoryURL: fixture.directory).load()
                XCTAssertEqual(cached, before)
                XCTAssertEqual(fresh, before)
                // Even explicit backup recovery must not reveal the rejected edit.
                if backup != nil {
                    try FileManager.default.removeItem(at: fixture.primary)
                    let recovering = BookmarkRepository(directoryURL: fixture.directory)
                    let recovered = try await recovering.load()
                    XCTAssertEqual(recovered.bookmarks, before.bookmarks)
                    let restored = try await recovering.restoreBackup()
                    XCTAssertEqual(restored.bookmarks, before.bookmarks)
                }
            }
        }
    }

    func testRollbackFailureBlocksCachedAndFreshReadsUntilStorageRecovers() async throws {
        let fixture = try await prepare(.add)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let primary = try bytes(fixture.primary)
        let backup = try bytes(fixture.backup)
        let faults = BookmarkFaults(failingSteps: Set(3...20))
        let repository = BookmarkRepository(directoryURL: fixture.directory, atomicWriter: faults)
        _ = try await repository.load()
        do {
            try await perform(.add, in: repository, original: fixture.original)
            XCTFail("Expected primary write and rollback to fail")
        } catch {
            XCTAssertEqual(error as? BookmarkRepositoryError, .transactionRecoveryRequired(journalURL: fixture.journal))
        }
        XCTAssertNotNil(try bytes(fixture.journal))
        for reader in [repository, BookmarkRepository(directoryURL: fixture.directory, atomicWriter: faults)] {
            do { _ = try await reader.load(); XCTFail("Must not expose uncommitted backup") }
            catch { XCTAssertEqual(error as? BookmarkRepositoryError, .transactionRecoveryRequired(journalURL: fixture.journal)) }
        }
        faults.clearFailures()
        let recovered = try await repository.load()
        XCTAssertEqual(recovered.bookmarks, [try XCTUnwrap(fixture.original)])
        XCTAssertEqual(try bytes(fixture.primary), primary)
        XCTAssertEqual(try bytes(fixture.backup), backup)
        XCTAssertNil(try bytes(fixture.journal))
    }

    func testFirstSaveRollbackDeletionFailureCannotResurrectRejectedBookmark() async throws {
        let fixture = try await prepare(.firstAdd)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let faults = BookmarkFaults(failingSteps: [3, 4])
        let repository = BookmarkRepository(directoryURL: fixture.directory,
            fileManager: FaultingBookmarkFileManager(faults: faults), atomicWriter: faults)
        do {
            try await perform(.firstAdd, in: repository, original: nil)
            XCTFail("Expected primary write and rollback deletion to fail")
        } catch {
            XCTAssertEqual(error as? BookmarkRepositoryError, .transactionRecoveryRequired(journalURL: fixture.journal))
        }
        // The rejected candidate physically exists, but the journal makes it uncommitted.
        XCTAssertNotNil(try bytes(fixture.backup))
        XCTAssertNotNil(try bytes(fixture.journal))
        let fresh = try await BookmarkRepository(directoryURL: fixture.directory).load()
        let cached = try await repository.load()
        XCTAssertEqual(fresh.bookmarks, [])
        XCTAssertEqual(cached, fresh)
        XCTAssertNil(fresh.recovery)
        XCTAssertNil(try bytes(fixture.primary))
        XCTAssertNil(try bytes(fixture.backup))
        XCTAssertNil(try bytes(fixture.journal))
    }

    func testInterruptedTransactionsRecoverPriorImagesBeforeReadingEitherCopy() async throws {
        for operation in Operation.allCases {
            for changedCopies in 0...2 {
                let fixture = try await prepare(operation)
                defer { try? FileManager.default.removeItem(at: fixture.directory) }
                let before = try await BookmarkRepository(directoryURL: fixture.directory).load()
                let primary = try bytes(fixture.primary)
                let backup = try bytes(fixture.backup)
                try writeJournal(fixture, primary: primary, backup: backup)
                if changedCopies >= 1 {
                    if operation == .reset { try FileManager.default.removeItem(at: fixture.backup) }
                    else { try Data("uncommitted backup".utf8).write(to: fixture.backup) }
                }
                if changedCopies >= 2 {
                    if operation == .reset { try FileManager.default.removeItem(at: fixture.primary) }
                    else { try Data("uncommitted primary".utf8).write(to: fixture.primary) }
                }
                let recovered = try await BookmarkRepository(directoryURL: fixture.directory).load()
                XCTAssertEqual(recovered, before)
                XCTAssertEqual(try bytes(fixture.primary), primary)
                XCTAssertEqual(try bytes(fixture.backup), backup)
                XCTAssertNil(try bytes(fixture.journal))
            }
        }
    }

    func testMalformedJournalFailsClosedWithoutChangingFilesEvenOnReset() async throws {
        let fixture = try await prepare(.add)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let primary = try bytes(fixture.primary)
        let backup = try bytes(fixture.backup)
        for raw in ["not JSON", "{\"schemaVersion\":1}", "{\"schemaVersion\":99,\"primary\":null,\"backup\":null}"] {
            let journal = Data(raw.utf8)
            try journal.write(to: fixture.journal)
            let repository = BookmarkRepository(directoryURL: fixture.directory)
            do { _ = try await repository.load(); XCTFail("Expected recovery failure") } catch {}
            do { try await repository.reset(); XCTFail("Reset must not discard an unreadable journal") } catch {}
            XCTAssertEqual(try bytes(fixture.primary), primary)
            XCTAssertEqual(try bytes(fixture.backup), backup)
            XCTAssertEqual(try bytes(fixture.journal), journal)
        }
    }

    func testSuccessfulMutationsLeaveNoJournalAndAlignedActiveCopies() async throws {
        for operation in Operation.allCases {
            let fixture = try await prepare(operation)
            defer { try? FileManager.default.removeItem(at: fixture.directory) }
            let repository = BookmarkRepository(directoryURL: fixture.directory)
            try await perform(operation, in: repository, original: fixture.original)
            let cached = try await repository.load()
            let fresh = try await BookmarkRepository(directoryURL: fixture.directory).load()
            XCTAssertEqual(cached, fresh)
            XCTAssertNil(cached.recovery)
            XCTAssertNil(try bytes(fixture.journal))
            XCTAssertEqual(try bytes(fixture.primary), try bytes(fixture.backup))
            if operation == .reset { XCTAssertNil(try bytes(fixture.primary)) }
            if operation == .edit || operation == .delete || operation == .reset {
                for url in [fixture.primary, fixture.backup] {
                    XCTAssertFalse(String(decoding: try bytes(url) ?? Data(), as: UTF8.self).contains("original.example"))
                }
            }
        }
    }

    func testCorruptPreservationDeduplicatesRelaunchesAndLegacyCopies() async throws {
        let fixture = try await prepare(.add)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let legacy = fixture.directory.appendingPathComponent("Bookmarks.corrupt.legacy-uuid.json")
        let first = Data("corruption one".utf8)
        try first.write(to: legacy)
        try first.write(to: fixture.primary)
        for _ in 0..<3 {
            let result = try await BookmarkRepository(directoryURL: fixture.directory).load()
            XCTAssertEqual(result.recovery?.preservedPrimaryFileURL, legacy)
        }
        let second = Data("corruption two".utf8)
        try second.write(to: fixture.primary)
        var preserved: URL?
        for _ in 0..<3 {
            let result = try await BookmarkRepository(directoryURL: fixture.directory).load()
            if let preserved { XCTAssertEqual(result.recovery?.preservedPrimaryFileURL, preserved) }
            preserved = result.recovery?.preservedPrimaryFileURL
        }
        let copies = try FileManager.default.contentsOfDirectory(at: fixture.directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("Bookmarks.corrupt.") }
        XCTAssertEqual(copies.count, 2)
        XCTAssertEqual(try Data(contentsOf: legacy), first)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(preserved)), second)
        try await BookmarkRepository(directoryURL: fixture.directory).reset()
        XCTAssertEqual(try Data(contentsOf: legacy), first)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(preserved)), second)
    }

    func testResetPreservesCorruptPrimaryWithoutPriorLoad() async throws {
        let fixture = try await prepare(.add)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let corruption = Data("unreadable primary".utf8)
        try corruption.write(to: fixture.primary)
        try await BookmarkRepository(directoryURL: fixture.directory).reset()
        let artifacts = try FileManager.default.contentsOfDirectory(at: fixture.directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(artifacts.count, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(artifacts.first)), corruption)
        XCTAssertNil(try bytes(fixture.primary))
        XCTAssertNil(try bytes(fixture.backup))
    }

    func testPreservationDoesNotOverwriteMismatchingHashNamedArtifact() async throws {
        let fixture = try await prepare(.restore)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let original = try Data(contentsOf: fixture.primary)
        let initial = try await BookmarkRepository(directoryURL: fixture.directory).load()
        let preserved = try XCTUnwrap(initial.recovery?.preservedPrimaryFileURL)
        let other = Data("different preserved original".utf8)
        try other.write(to: preserved)
        let reopened = try await BookmarkRepository(directoryURL: fixture.directory).load()
        let second = try XCTUnwrap(reopened.recovery?.preservedPrimaryFileURL)
        XCTAssertNotEqual(second, preserved)
        XCTAssertEqual(try Data(contentsOf: preserved), other)
        XCTAssertEqual(try Data(contentsOf: second), original)
        let again = try await BookmarkRepository(directoryURL: fixture.directory).load()
        XCTAssertEqual(again.recovery?.preservedPrimaryFileURL, second)
    }

    private func prepare(_ operation: Operation) async throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BookmarkTransactionTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var original: Bookmark?
        if operation != .firstAdd {
            let result = try await BookmarkRepository(directoryURL: directory).add(url: URL(string: "https://original.example/")!, title: "Original")
            if case let .added(bookmark) = result { original = bookmark }
        }
        let fixture = Fixture(directory: directory, original: original)
        if operation == .restore { try Data("corrupt primary".utf8).write(to: fixture.primary) }
        return fixture
    }

    private func perform(_ operation: Operation, in repository: BookmarkRepository, original: Bookmark?) async throws {
        switch operation {
        case .firstAdd, .add: _ = try await repository.add(url: URL(string: "https://new.example/")!, title: "New")
        case .edit: _ = try await repository.update(id: XCTUnwrap(original).id, url: URL(string: "https://new.example/")!, title: "New")
        case .delete: _ = try await repository.delete(id: XCTUnwrap(original).id)
        case .reset: try await repository.reset()
        case .restore: _ = try await repository.restoreBackup()
        }
    }

    private func bytes(_ url: URL) throws -> Data? {
        FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
    }

    private func writeJournal(_ fixture: Fixture, primary: Data?, backup: Data?) throws {
        let object: [String: Any] = ["schemaVersion": 1,
            "primary": primary.map { $0.base64EncodedString() as Any } ?? NSNull(),
            "backup": backup.map { $0.base64EncodedString() as Any } ?? NSNull()]
        try JSONSerialization.data(withJSONObject: object).write(to: fixture.journal, options: .atomic)
    }
}

private enum BookmarkFault: Error { case injected }

private final class BookmarkFaults: BookmarkAtomicWriting, @unchecked Sendable {
    private let lock = NSLock()
    private var step = 0
    private var failingSteps: Set<Int>
    init(failingSteps: Set<Int>) { self.failingSteps = failingSteps }
    func clearFailures() { lock.withLock { failingSteps.removeAll() } }
    func check() throws {
        let fails = lock.withLock { step += 1; return failingSteps.contains(step) }
        if fails { throw BookmarkFault.injected }
    }
    func write(_ data: Data, to url: URL) throws {
        try check()
        try data.write(to: url, options: .atomic)
    }
}

private final class FaultingBookmarkFileManager: FileManager, @unchecked Sendable {
    private let faults: BookmarkFaults
    init(faults: BookmarkFaults) { self.faults = faults; super.init() }
    override func removeItem(at URL: URL) throws {
        try faults.check()
        try super.removeItem(at: URL)
    }
}
