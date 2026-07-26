import Foundation

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
        try createStorageDirectory()
        try atomicWriter.write(backupData, to: primaryFileURL)
        loadedFile = backup
        loadRecovery = nil
        return BookmarkRepositorySnapshot(bookmarks: backup.bookmarks, recovery: nil)
    }

    func reset() throws {
        for url in [primaryFileURL, backupFileURL] where fileExists(at: url) {
            try fileManager.removeItem(at: url)
        }

        loadedFile = BookmarkFile(bookmarks: [])
        loadRecovery = nil
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

        // Keep both active copies aligned with the latest explicit user
        // request. In particular, editing or deleting a bookmark must not
        // leave its previous URL behind in the recovery file.
        try atomicWriter.write(encoded, to: backupFileURL)
        try atomicWriter.write(encoded, to: primaryFileURL)
    }

    private func preserveCorruptPrimary() throws -> URL {
        let preservedURL = directoryURL.appendingPathComponent(
            "Bookmarks.corrupt.\(UUID().uuidString).json",
            isDirectory: false
        )
        try fileManager.copyItem(at: primaryFileURL, to: preservedURL)
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
