import Foundation
import CryptoKit

nonisolated enum BookmarkRecoveryReason: Equatable, Sendable {
    case corruptPrimary
    case missingPrimary
}

nonisolated struct BookmarkRecovery: Equatable, Sendable {
    let reason: BookmarkRecoveryReason
    let backupFileURL: URL
    let preservedPrimaryFileURL: URL?
}

nonisolated struct BookmarkRepositorySnapshot: Equatable, Sendable {
    let bookmarks: [Bookmark]
    let recovery: BookmarkRecovery?
}

nonisolated enum BookmarkSaveResult: Equatable, Sendable {
    case added(Bookmark)
    case duplicate(Bookmark)
}

nonisolated enum BookmarkRepositoryError: Error, Equatable, Sendable {
    case bookmarkNotFound(UUID)
    case duplicateURL(existingID: UUID)
    case recoveryRequired
    case noRecoveryAvailable
    case transactionRecoveryRequired(journalURL: URL)
    case unrecoverableData(
        primaryFileURL: URL,
        preservedPrimaryFileURL: URL?,
        backupFileURL: URL?
    )
}

extension BookmarkRepositoryError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .bookmarkNotFound:
            "That bookmark no longer exists."
        case .duplicateURL:
            "A bookmark for that URL already exists."
        case .recoveryRequired:
            "Restore or reset the recovered bookmarks before making changes."
        case .noRecoveryAvailable:
            "There is no bookmark backup waiting to be restored."
        case .transactionRecoveryRequired:
            "Bookmark storage recovery could not finish. No change was committed. Retry when storage is available; the recovery journal has been retained."
        case .unrecoverableData:
            "The bookmark file cannot be read and no valid backup is available."
        }
    }
}

nonisolated protocol BookmarkAtomicWriting: Sendable {
    func write(_ data: Data, to url: URL) throws
}

nonisolated struct FoundationBookmarkAtomicWriter: BookmarkAtomicWriting {
    func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }
}

actor BookmarkRepository {
    nonisolated static let defaultDirectoryURL = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
    )[0].appendingPathComponent(
        "com.utpalchakraborty.browser",
        isDirectory: true
    )

    nonisolated static let primaryFileName = "Bookmarks.json"
    nonisolated static let backupFileName = "Bookmarks.backup.json"
    nonisolated static let transactionFileName = "Bookmarks.transaction.json"

    private let directoryURL: URL
    private let fileManager: FileManager
    private let atomicWriter: any BookmarkAtomicWriting
    private var loadedFile: BookmarkFile?
    private var loadRecovery: BookmarkRecovery?

    init(
        directoryURL: URL = BookmarkRepository.defaultDirectoryURL,
        fileManager: FileManager = .default,
        atomicWriter: any BookmarkAtomicWriting = FoundationBookmarkAtomicWriter()
    ) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
        self.atomicWriter = atomicWriter
    }

    func load() throws -> BookmarkRepositorySnapshot {
        try reconcilePendingTransaction()
        if let loadedFile {
            return BookmarkRepositorySnapshot(
                bookmarks: loadedFile.bookmarks,
                recovery: loadRecovery
            )
        }

        let result = try loadFromDisk()
        loadedFile = result.file
        loadRecovery = result.recovery
        return BookmarkRepositorySnapshot(
            bookmarks: result.file.bookmarks,
            recovery: result.recovery
        )
    }

    func bookmarks() throws -> [Bookmark] {
        try load().bookmarks
    }

    func search(_ query: String) throws -> [Bookmark] {
        BookmarkSearch.filteredBookmarks(
            in: try bookmarks(),
            matching: query
        )
    }

    func add(
        url: URL,
        title: String,
        at date: Date = Date()
    ) throws -> BookmarkSaveResult {
        try requireWritableState()
        let file = try currentFile()
        let candidate = try Bookmark(
            url: url,
            title: title,
            createdAt: date
        )
        if let duplicate = file.bookmarks.first(where: { $0.url == candidate.url }) {
            return .duplicate(duplicate)
        }

        let updatedFile = BookmarkFile(bookmarks: file.bookmarks + [candidate])
        try persist(updatedFile)
        loadedFile = updatedFile
        loadRecovery = nil
        return .added(candidate)
    }

    @discardableResult
    func update(
        id: UUID,
        url: URL,
        title: String,
        at date: Date = Date()
    ) throws -> Bookmark {
        try requireWritableState()
        let file = try currentFile()
        guard let index = file.bookmarks.firstIndex(where: { $0.id == id }) else {
            throw BookmarkRepositoryError.bookmarkNotFound(id)
        }

        let current = file.bookmarks[index]
        let updated = try Bookmark(
            id: current.id,
            url: url,
            title: title,
            createdAt: current.createdAt,
            updatedAt: max(date, current.updatedAt)
        )
        if let duplicate = file.bookmarks.first(where: {
            $0.id != id && $0.url == updated.url
        }) {
            throw BookmarkRepositoryError.duplicateURL(existingID: duplicate.id)
        }

        var updatedBookmarks = file.bookmarks
        updatedBookmarks[index] = updated
        let updatedFile = BookmarkFile(bookmarks: updatedBookmarks)
        try persist(updatedFile)
        loadedFile = updatedFile
        loadRecovery = nil
        return updated
    }

    @discardableResult
    func delete(id: UUID) throws -> Bookmark {
        try requireWritableState()
        let file = try currentFile()
        guard let index = file.bookmarks.firstIndex(where: { $0.id == id }) else {
            throw BookmarkRepositoryError.bookmarkNotFound(id)
        }

        var updatedBookmarks = file.bookmarks
        let removed = updatedBookmarks.remove(at: index)
        let updatedFile = BookmarkFile(bookmarks: updatedBookmarks)
        try persist(updatedFile)
        loadedFile = updatedFile
        loadRecovery = nil
        return removed
    }

    @discardableResult
    func restoreBackup() throws -> BookmarkRepositorySnapshot {
        _ = try load()
        guard loadRecovery != nil else {
            throw BookmarkRepositoryError.noRecoveryAvailable
        }

        let backupData = try Data(contentsOf: backupFileURL)
        let backup = try decodeAndValidate(backupData)
        try replaceActiveFiles(primary: backupData, backup: backupData)
        loadedFile = backup
        loadRecovery = nil
        return BookmarkRepositorySnapshot(bookmarks: backup.bookmarks, recovery: nil)
    }

    func reset() throws {
        try reconcilePendingTransaction()
        if let primary = try readIfPresent(primaryFileURL),
           (try? decodeAndValidate(primary)) == nil {
            _ = try preserveCorruptPrimary()
        }
        try replaceActiveFiles(primary: nil, backup: nil)
        loadedFile = BookmarkFile(bookmarks: [])
        loadRecovery = nil
    }

    private var transactionFileURL: URL {
        directoryURL.appendingPathComponent(Self.transactionFileName)
    }

    private var primaryFileURL: URL {
        directoryURL.appendingPathComponent(Self.primaryFileName, isDirectory: false)
    }

    private var backupFileURL: URL {
        directoryURL.appendingPathComponent(Self.backupFileName, isDirectory: false)
    }

    private func currentFile() throws -> BookmarkFile {
        if let loadedFile {
            return loadedFile
        }
        _ = try load()
        return loadedFile ?? BookmarkFile(bookmarks: [])
    }

    private func requireWritableState() throws {
        _ = try load()
        if loadRecovery != nil {
            throw BookmarkRepositoryError.recoveryRequired
        }
    }

    private func loadFromDisk() throws -> (
        file: BookmarkFile,
        recovery: BookmarkRecovery?
    ) {
        if fileExists(at: primaryFileURL) {
            let primaryData = try Data(contentsOf: primaryFileURL)
            do {
                return (try decodeAndValidate(primaryData), nil)
            } catch {
                return try recoverCorruptPrimary()
            }
        }

        if fileExists(at: backupFileURL) {
            let backupData = try Data(contentsOf: backupFileURL)
            do {
                let backup = try decodeAndValidate(backupData)
                return (
                    backup,
                    BookmarkRecovery(
                        reason: .missingPrimary,
                        backupFileURL: backupFileURL,
                        preservedPrimaryFileURL: nil
                    )
                )
            } catch let error as BookmarkRepositoryError {
                throw error
            } catch {
                throw BookmarkRepositoryError.unrecoverableData(
                    primaryFileURL: primaryFileURL,
                    preservedPrimaryFileURL: nil,
                    backupFileURL: backupFileURL
                )
            }
        }

        return (BookmarkFile(bookmarks: []), nil)
    }

    private func recoverCorruptPrimary() throws -> (
        file: BookmarkFile,
        recovery: BookmarkRecovery?
    ) {
        let preservedURL: URL
        do {
            preservedURL = try preserveCorruptPrimary()
        } catch {
            throw BookmarkRepositoryError.unrecoverableData(
                primaryFileURL: primaryFileURL,
                preservedPrimaryFileURL: nil,
                backupFileURL: fileExists(at: backupFileURL) ? backupFileURL : nil
            )
        }

        guard fileExists(at: backupFileURL) else {
            throw BookmarkRepositoryError.unrecoverableData(
                primaryFileURL: primaryFileURL,
                preservedPrimaryFileURL: preservedURL,
                backupFileURL: nil
            )
        }

        let backupData = try Data(contentsOf: backupFileURL)
        do {
            let backup = try decodeAndValidate(backupData)
            return (
                backup,
                BookmarkRecovery(
                    reason: .corruptPrimary,
                    backupFileURL: backupFileURL,
                    preservedPrimaryFileURL: preservedURL
                )
            )
        } catch let error as BookmarkRepositoryError {
            throw error
        } catch {
            throw BookmarkRepositoryError.unrecoverableData(
                primaryFileURL: primaryFileURL,
                preservedPrimaryFileURL: preservedURL,
                backupFileURL: backupFileURL
            )
        }
    }

    private func persist(_ file: BookmarkFile) throws {
        let encoded = try encode(file)
        try createStorageDirectory()

        if fileExists(at: primaryFileURL) {
            let existingData = try Data(contentsOf: primaryFileURL)
            _ = try decodeAndValidate(existingData)
        }
        _ = try decodeAndValidate(encoded)

        try replaceActiveFiles(primary: encoded, backup: encoded)
    }

    /// A journal's presence means neither active file is committed yet. Its
    /// removal is the only commit point; all callers publish memory afterward.
    private func replaceActiveFiles(primary: Data?, backup: Data?) throws {
        try reconcilePendingTransaction()
        try createStorageDirectory()
        let previous = BookmarkTransaction(
            schemaVersion: 1,
            primary: try readIfPresent(primaryFileURL),
            backup: try readIfPresent(backupFileURL)
        )
        do {
            try atomicWriter.write(try JSONEncoder().encode(previous), to: transactionFileURL)
            try restoreImage(backup, at: backupFileURL)
            try restoreImage(primary, at: primaryFileURL)
            try fileManager.removeItem(at: transactionFileURL)
        } catch {
            let operationError = error
            // Even a writer that reports an error after replacement may have
            // left the journal in place. Resolve it before exposing the files.
            try reconcilePendingTransaction()
            throw operationError
        }
    }

    private func reconcilePendingTransaction() throws {
        guard fileExists(at: transactionFileURL) else { return }
        do {
            let previous = try JSONDecoder().decode(
                BookmarkTransaction.self,
                from: Data(contentsOf: transactionFileURL)
            )
            guard previous.schemaVersion == 1 else {
                throw BookmarkRepositoryError.transactionRecoveryRequired(journalURL: transactionFileURL)
            }
            try restoreImage(previous.backup, at: backupFileURL)
            try restoreImage(previous.primary, at: primaryFileURL)
            try fileManager.removeItem(at: transactionFileURL)
            loadedFile = nil
            loadRecovery = nil
        } catch {
            throw BookmarkRepositoryError.transactionRecoveryRequired(journalURL: transactionFileURL)
        }
    }

    private func readIfPresent(_ url: URL) throws -> Data? {
        fileExists(at: url) ? try Data(contentsOf: url) : nil
    }

    private func restoreImage(_ data: Data?, at url: URL) throws {
        guard let data else {
            if fileExists(at: url) { try fileManager.removeItem(at: url) }
            return
        }
        // Retrying rollback must not rewrite an already restored copy.
        if try readIfPresent(url) != data { try atomicWriter.write(data, to: url) }
    }

    private func preserveCorruptPrimary() throws -> URL {
        let data = try Data(contentsOf: primaryFileURL)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let preferredURL = directoryURL.appendingPathComponent("Bookmarks.corrupt.\(digest).json")
        if try readIfPresent(preferredURL) == data { return preferredURL }
        // Honor copies created by older versions as well as hash-named copies.
        for url in try fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
            where url.lastPathComponent.hasPrefix("Bookmarks.corrupt.") && url.pathExtension == "json" {
            if (try? Data(contentsOf: url)) == data { return url }
        }
        let preservedURL = fileExists(at: preferredURL)
            ? directoryURL.appendingPathComponent("Bookmarks.corrupt.\(digest).\(UUID().uuidString).json")
            : preferredURL
        // Never overwrite an existing preserved original.
        try data.write(to: preservedURL, options: .withoutOverwriting)
        return preservedURL
    }

    private func createStorageDirectory() throws {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    private func fileExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    private func encode(_ file: BookmarkFile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(file)
        data.append(0x0A)
        return data
    }

    private func decodeAndValidate(_ data: Data) throws -> BookmarkFile {
        let decoder = JSONDecoder()
        let file = try decoder.decode(BookmarkFile.self, from: data)
        guard file.schemaVersion == BookmarkFile.currentSchemaVersion else {
            throw BookmarkFileValidationError.unsupportedSchemaVersion(
                file.schemaVersion
            )
        }

        var identifiers = Set<UUID>()
        var urls = Set<URL>()
        for bookmark in file.bookmarks {
            guard identifiers.insert(bookmark.id).inserted else {
                throw BookmarkFileValidationError.duplicateIdentifier(bookmark.id)
            }
            guard urls.insert(bookmark.url).inserted else {
                throw BookmarkFileValidationError.duplicateURL(bookmark.url)
            }
        }
        return file
    }
}

private nonisolated enum BookmarkFileValidationError: Error {
    case unsupportedSchemaVersion(Int)
    case duplicateIdentifier(UUID)
    case duplicateURL(URL)
}

/// Explicit nulls distinguish a missing file from a damaged/incomplete journal.
private nonisolated struct BookmarkTransaction: Codable {
    let schemaVersion: Int
    let primary: Data?
    let backup: Data?

    enum CodingKeys: String, CodingKey { case schemaVersion, primary, backup }

    init(schemaVersion: Int, primary: Data?, backup: Data?) {
        self.schemaVersion = schemaVersion
        self.primary = primary
        self.backup = backup
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        primary = try values.decode(Data?.self, forKey: .primary)
        backup = try values.decode(Data?.self, forKey: .backup)
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(primary, forKey: .primary)
        try values.encode(backup, forKey: .backup)
    }
}
