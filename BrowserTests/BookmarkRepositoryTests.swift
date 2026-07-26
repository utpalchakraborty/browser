import Foundation
import XCTest
@testable import Browser

@MainActor
final class BookmarkRepositoryTests: XCTestCase {
    private var directoryURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "BookmarkRepositoryTests.\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let directoryURL {
            try FileManager.default.removeItem(at: directoryURL)
        }
        directoryURL = nil
        try super.tearDownWithError()
    }

    func testAddPersistsVersionedFileAndReloads() async throws {
        let repository = BookmarkRepository(directoryURL: directoryURL)
        let date = Date(timeIntervalSince1970: 1_000)
        let result = try await repository.add(
            url: XCTUnwrap(URL(string: "HTTPS://Example.COM:443")),
            title: "Example",
            at: date
        )
        guard case let .added(added) = result else {
            return XCTFail("Expected a newly added bookmark")
        }

        let reloaded = try await BookmarkRepository(
            directoryURL: directoryURL
        ).load()

        XCTAssertEqual(reloaded.bookmarks, [added])
        XCTAssertNil(reloaded.recovery)
        XCTAssertTrue(FileManager.default.fileExists(atPath: primaryURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: primaryURL))
                as? [String: Any]
        )
        XCTAssertEqual(
            object["schemaVersion"] as? Int,
            BookmarkFile.currentSchemaVersion
        )
    }

    func testCanonicalDuplicateReturnsExistingBookmarkWithoutWriting() async throws {
        let repository = BookmarkRepository(directoryURL: directoryURL)
        let firstResult = try await repository.add(
            url: XCTUnwrap(URL(string: "https://EXAMPLE.com:443")),
            title: "Original",
            at: Date(timeIntervalSince1970: 1_000)
        )
        guard case let .added(first) = firstResult else {
            return XCTFail("Expected the first bookmark to be added")
        }
        let primaryBeforeDuplicate = try Data(contentsOf: primaryURL)

        let duplicateResult = try await repository.add(
            url: XCTUnwrap(URL(string: "https://example.com/")),
            title: "Replacement",
            at: Date(timeIntervalSince1970: 2_000)
        )

        XCTAssertEqual(duplicateResult, .duplicate(first))
        let bookmarks = try await repository.bookmarks()
        XCTAssertEqual(bookmarks, [first])
        XCTAssertEqual(try Data(contentsOf: primaryURL), primaryBeforeDuplicate)
    }

    func testEditCannotCreateDuplicateAndDeleteRequiresExistingIdentifier() async throws {
        let repository = BookmarkRepository(directoryURL: directoryURL)
        let first = try await addedBookmark(
            from: repository.add(
                url: XCTUnwrap(URL(string: "https://one.example/")),
                title: "One"
            )
        )
        let second = try await addedBookmark(
            from: repository.add(
                url: XCTUnwrap(URL(string: "https://two.example/")),
                title: "Two"
            )
        )

        do {
            _ = try await repository.update(
                id: second.id,
                url: first.url,
                title: "Duplicate"
            )
            XCTFail("Expected an edit-to-duplicate error")
        } catch {
            XCTAssertEqual(
                error as? BookmarkRepositoryError,
                .duplicateURL(existingID: first.id)
            )
        }

        let missingID = UUID()
        do {
            _ = try await repository.delete(id: missingID)
            XCTFail("Expected a missing-bookmark error")
        } catch {
            XCTAssertEqual(
                error as? BookmarkRepositoryError,
                .bookmarkNotFound(missingID)
            )
        }
    }

    func testUpdateAndDeletePersistWhileKeepingStableBookmarkIdentity() async throws {
        let repository = BookmarkRepository(directoryURL: directoryURL)
        let createdAt = Date(timeIntervalSince1970: 1_000)
        let updatedAt = Date(timeIntervalSince1970: 2_000)
        let original = try await addedBookmark(
            from: repository.add(
                url: XCTUnwrap(URL(string: "https://before.example/")),
                title: "Before",
                at: createdAt
            )
        )

        let updated = try await repository.update(
            id: original.id,
            url: XCTUnwrap(URL(string: "https://after.example/path")),
            title: "After",
            at: updatedAt
        )
        let afterUpdate = try await BookmarkRepository(
            directoryURL: directoryURL
        ).bookmarks()

        XCTAssertEqual(updated.id, original.id)
        XCTAssertEqual(updated.createdAt, createdAt)
        XCTAssertEqual(updated.updatedAt, updatedAt)
        XCTAssertEqual(afterUpdate, [updated])

        let deleted = try await repository.delete(id: original.id)
        XCTAssertEqual(deleted, updated)
        let afterDelete = try await BookmarkRepository(
            directoryURL: directoryURL
        ).bookmarks()
        XCTAssertTrue(afterDelete.isEmpty)
    }

    func testSearchMatchesTitleAndURLWithoutChangingStoredOrder() async throws {
        let repository = BookmarkRepository(directoryURL: directoryURL)
        let first = try await addedBookmark(
            from: repository.add(
                url: XCTUnwrap(URL(string: "https://swift.example/reference")),
                title: "Language Guide"
            )
        )
        let second = try await addedBookmark(
            from: repository.add(
                url: XCTUnwrap(URL(string: "https://other.example/")),
                title: "Swift News"
            )
        )

        let swiftMatches = try await repository.search("SWIFT")
        let urlMatches = try await repository.search("reference")
        let allMatches = try await repository.search("   ")
        XCTAssertEqual(swiftMatches, [first, second])
        XCTAssertEqual(urlMatches, [first])
        XCTAssertEqual(allMatches, [first, second])
    }

    func testCorruptPrimaryIsPreservedAndRecoveredFromLastValidBackup() async throws {
        let repository = BookmarkRepository(directoryURL: directoryURL)
        let first = try await addedBookmark(
            from: repository.add(
                url: XCTUnwrap(URL(string: "https://one.example/")),
                title: "One"
            )
        )
        let second = try await addedBookmark(
            from: repository.add(
                url: XCTUnwrap(URL(string: "https://two.example/")),
                title: "Two"
            )
        )
        let corruptData = Data("{ truncated".utf8)
        try corruptData.write(to: primaryURL)

        let snapshot = try await BookmarkRepository(
            directoryURL: directoryURL
        ).load()

        XCTAssertEqual(snapshot.bookmarks, [first, second])
        XCTAssertEqual(snapshot.recovery?.reason, .corruptPrimary)
        XCTAssertEqual(snapshot.recovery?.backupFileURL, backupURL)
        let preservedURL = try XCTUnwrap(
            snapshot.recovery?.preservedPrimaryFileURL
        )
        XCTAssertEqual(try Data(contentsOf: preservedURL), corruptData)
        XCTAssertEqual(try Data(contentsOf: primaryURL), corruptData)

        do {
            _ = try await BookmarkRepository(
                directoryURL: directoryURL
            ).add(
                url: XCTUnwrap(URL(string: "https://three.example/")),
                title: "Three"
            )
            XCTFail("Expected recovery to remain read-only")
        } catch {
            XCTAssertEqual(
                error as? BookmarkRepositoryError,
                .recoveryRequired
            )
        }

        let restored = BookmarkRepository(directoryURL: directoryURL)
        _ = try await restored.load()
        let restoredSnapshot = try await restored.restoreBackup()
        XCTAssertEqual(restoredSnapshot.bookmarks, [first, second])
        XCTAssertNil(restoredSnapshot.recovery)
        XCTAssertNotEqual(try Data(contentsOf: primaryURL), corruptData)
    }

    func testMissingPrimaryRecoversBackupAfterInterruptedReplacement() async throws {
        let repository = BookmarkRepository(directoryURL: directoryURL)
        let first = try await addedBookmark(
            from: repository.add(
                url: XCTUnwrap(URL(string: "https://one.example/")),
                title: "One"
            )
        )
        let second = try await addedBookmark(
            from: repository.add(
                url: XCTUnwrap(URL(string: "https://two.example/")),
                title: "Two"
            )
        )
        try FileManager.default.removeItem(at: primaryURL)

        let snapshot = try await BookmarkRepository(
            directoryURL: directoryURL
        ).load()

        XCTAssertEqual(snapshot.bookmarks, [first, second])
        XCTAssertEqual(snapshot.recovery?.reason, .missingPrimary)
        XCTAssertNil(snapshot.recovery?.preservedPrimaryFileURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: primaryURL.path))

        let restoringRepository = BookmarkRepository(directoryURL: directoryURL)
        _ = try await restoringRepository.load()
        _ = try await restoringRepository.restoreBackup()
        XCTAssertTrue(FileManager.default.fileExists(atPath: primaryURL.path))
    }

    func testFailedAtomicPrimaryReplacementLeavesPreviousFileReadable() async throws {
        let writer = FailingPrimaryWriter(primaryURL: primaryURL, failureNumber: 2)
        let repository = BookmarkRepository(
            directoryURL: directoryURL,
            atomicWriter: writer
        )
        let first = try await addedBookmark(
            from: repository.add(
                url: XCTUnwrap(URL(string: "https://one.example/")),
                title: "One"
            )
        )

        do {
            _ = try await repository.add(
                url: XCTUnwrap(URL(string: "https://two.example/")),
                title: "Two"
            )
            XCTFail("Expected the injected atomic replacement failure")
        } catch {
            XCTAssertTrue(error is AtomicWriterProbeError)
        }

        let reloaded = try await BookmarkRepository(
            directoryURL: directoryURL
        ).load()
        XCTAssertEqual(reloaded.bookmarks, [first])
        XCTAssertNil(reloaded.recovery)
    }

    func testUnsupportedPrimarySchemaUsesBackupInsteadOfSilentlyResetting() async throws {
        let repository = BookmarkRepository(directoryURL: directoryURL)
        let first = try await addedBookmark(
            from: repository.add(
                url: XCTUnwrap(URL(string: "https://one.example/")),
                title: "One"
            )
        )
        let second = try await addedBookmark(
            from: repository.add(
                url: XCTUnwrap(URL(string: "https://two.example/")),
                title: "Two"
            )
        )
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: primaryURL))
                as? [String: Any]
        )
        object["schemaVersion"] = 999
        let futureData = try JSONSerialization.data(withJSONObject: object)
        try futureData.write(to: primaryURL)

        let snapshot = try await BookmarkRepository(
            directoryURL: directoryURL
        ).load()

        XCTAssertEqual(snapshot.bookmarks, [first, second])
        XCTAssertEqual(snapshot.recovery?.reason, .corruptPrimary)
        XCTAssertEqual(
            try Data(contentsOf: snapshot.recovery!.preservedPrimaryFileURL!),
            futureData
        )
    }

    func testCorruptPrimaryWithoutValidBackupIsPreservedAndReported() async throws {
        let corruptPrimary = Data("not json".utf8)
        let corruptBackup = Data("also not json".utf8)
        try corruptPrimary.write(to: primaryURL)
        try corruptBackup.write(to: backupURL)
        let repository = BookmarkRepository(directoryURL: directoryURL)

        do {
            _ = try await repository.load()
            XCTFail("Expected unrecoverable bookmark data")
        } catch let error as BookmarkRepositoryError {
            guard case let .unrecoverableData(
                primaryFileURL,
                preservedPrimaryFileURL,
                backupFileURL
            ) = error else {
                return XCTFail("Unexpected repository error: \(error)")
            }
            XCTAssertEqual(primaryFileURL, primaryURL)
            XCTAssertEqual(backupFileURL, backupURL)
            XCTAssertEqual(
                try Data(contentsOf: XCTUnwrap(preservedPrimaryFileURL)),
                corruptPrimary
            )
            XCTAssertEqual(try Data(contentsOf: primaryURL), corruptPrimary)
        }
    }

    func testEditAndDeleteScrubOldURLsFromPrimaryAndBackup() async throws {
        let repository = BookmarkRepository(directoryURL: directoryURL)
        let original = try await addedBookmark(
            from: repository.add(
                url: XCTUnwrap(URL(string: "https://private.example/original")),
                title: "Original"
            )
        )
        let updated = try await repository.update(
            id: original.id,
            url: XCTUnwrap(URL(string: "https://replacement.example/")),
            title: "Replacement"
        )

        for url in [primaryURL, backupURL] {
            let data = try Data(contentsOf: url)
            XCTAssertFalse(
                String(decoding: data, as: UTF8.self)
                    .contains("private.example")
            )
            XCTAssertEqual(
                try JSONDecoder().decode(BookmarkFile.self, from: data)
                    .bookmarks,
                [updated]
            )
        }

        _ = try await repository.delete(id: updated.id)

        for url in [primaryURL, backupURL] {
            let data = try Data(contentsOf: url)
            XCTAssertFalse(
                String(decoding: data, as: UTF8.self)
                    .contains("replacement.example")
            )
            XCTAssertTrue(
                try JSONDecoder().decode(BookmarkFile.self, from: data)
                    .bookmarks.isEmpty
            )
        }
    }

    func testResetDeletesActiveFilesButKeepsPreservedCorruptInput() async throws {
        let repository = BookmarkRepository(directoryURL: directoryURL)
        _ = try await repository.add(
            url: XCTUnwrap(URL(string: "https://one.example/")),
            title: "One"
        )
        _ = try await repository.add(
            url: XCTUnwrap(URL(string: "https://two.example/")),
            title: "Two"
        )
        let corruptData = Data("damaged primary".utf8)
        try corruptData.write(to: primaryURL)

        let recoveringRepository = BookmarkRepository(directoryURL: directoryURL)
        let recovery = try await recoveringRepository.load().recovery
        let preservedURL = try XCTUnwrap(recovery?.preservedPrimaryFileURL)

        try await recoveringRepository.reset()

        XCTAssertFalse(FileManager.default.fileExists(atPath: primaryURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: backupURL.path))
        XCTAssertEqual(try Data(contentsOf: preservedURL), corruptData)
        let snapshot = try await recoveringRepository.load()
        XCTAssertTrue(snapshot.bookmarks.isEmpty)
        XCTAssertNil(snapshot.recovery)
    }

    private var primaryURL: URL {
        directoryURL.appendingPathComponent(BookmarkRepository.primaryFileName)
    }

    private var backupURL: URL {
        directoryURL.appendingPathComponent(BookmarkRepository.backupFileName)
    }

    private func addedBookmark(
        from result: BookmarkSaveResult
    ) throws -> Bookmark {
        guard case let .added(bookmark) = result else {
            throw BookmarkTestError.expectedAddedBookmark
        }
        return bookmark
    }
}

private enum BookmarkTestError: Error {
    case expectedAddedBookmark
}

private enum AtomicWriterProbeError: Error {
    case injectedFailure
}

private final class FailingPrimaryWriter: BookmarkAtomicWriting, @unchecked Sendable {
    private let primaryURL: URL
    private let failureNumber: Int
    private let lock = NSLock()
    private var primaryWriteCount = 0

    init(primaryURL: URL, failureNumber: Int) {
        self.primaryURL = primaryURL
        self.failureNumber = failureNumber
    }

    func write(_ data: Data, to url: URL) throws {
        if url == primaryURL {
            let shouldFail = lock.withLock {
                primaryWriteCount += 1
                return primaryWriteCount == failureNumber
            }
            if shouldFail {
                throw AtomicWriterProbeError.injectedFailure
            }
        }
        try data.write(to: url, options: .atomic)
    }
}
