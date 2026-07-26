import Foundation

@MainActor
final class BookmarkCoordinator {
    enum State: Equatable {
        case idle
        case loading
        case ready(BookmarkRepositorySnapshot)
        case failed(String)
    }

    typealias MutationCompletion = (String?) -> Void

    var onStateChange: ((State) -> Void)?

    private let repository: BookmarkRepository
    private var task: Task<Void, Never>?
    private(set) var operationInProgress = false

    private(set) var state: State = .idle {
        didSet {
            onStateChange?(state)
        }
    }

    init(repository: BookmarkRepository) {
        self.repository = repository
    }

    deinit {
        task?.cancel()
    }

    var bookmarks: [Bookmark] {
        guard case let .ready(snapshot) = state else {
            return []
        }
        return snapshot.bookmarks
    }

    var recovery: BookmarkRecovery? {
        guard case let .ready(snapshot) = state else {
            return nil
        }
        return snapshot.recovery
    }

    var allowsChanges: Bool {
        guard case let .ready(snapshot) = state else {
            return false
        }
        return snapshot.recovery == nil && !operationInProgress
    }

    var allowsRecoveryActions: Bool {
        recovery != nil && !operationInProgress
    }

    func start(resetOnLaunch: Bool) {
        task?.cancel()
        state = .loading
        task = Task { [weak self, repository] in
            do {
                if resetOnLaunch {
                    try await repository.reset()
                }
                let snapshot = try await repository.load()
                try Task.checkCancellation()
                self?.state = .ready(snapshot)
            } catch is CancellationError {
                return
            } catch {
                self?.state = .failed(error.localizedDescription)
            }
        }
    }

    func add(
        url: URL,
        title: String,
        completion: MutationCompletion? = nil
    ) {
        performMutation(completion: completion) { repository in
            switch try await repository.add(url: url, title: title) {
            case .added:
                return
            case let .duplicate(existing):
                throw BookmarkRepositoryError.duplicateURL(
                    existingID: existing.id
                )
            }
        }
    }

    func update(
        id: UUID,
        url: URL,
        title: String,
        completion: MutationCompletion? = nil
    ) {
        performMutation(completion: completion) { repository in
            _ = try await repository.update(id: id, url: url, title: title)
        }
    }

    func delete(
        id: UUID,
        completion: MutationCompletion? = nil
    ) {
        performMutation(completion: completion) { repository in
            _ = try await repository.delete(id: id)
        }
    }

    func restoreBackup(completion: MutationCompletion? = nil) {
        performOperation(completion: completion) { repository in
            try await repository.restoreBackup()
        }
    }

    func reset(completion: MutationCompletion? = nil) {
        performOperation(completion: completion) { repository in
            try await repository.reset()
            return try await repository.load()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        operationInProgress = false
    }

    private func performMutation(
        completion: MutationCompletion?,
        operation: @escaping @Sendable (BookmarkRepository) async throws -> Void
    ) {
        performOperation(completion: completion) { repository in
            try await operation(repository)
            return try await repository.load()
        }
    }

    private func performOperation(
        completion: MutationCompletion?,
        operation: @escaping @Sendable (BookmarkRepository) async throws
            -> BookmarkRepositorySnapshot
    ) {
        guard !operationInProgress else {
            completion?("Another bookmark change is still finishing.")
            return
        }

        operationInProgress = true
        onStateChange?(state)
        task = Task { [weak self, repository] in
            do {
                let snapshot = try await operation(repository)
                try Task.checkCancellation()
                self?.operationInProgress = false
                self?.state = .ready(snapshot)
                self?.task = nil
                completion?(nil)
            } catch is CancellationError {
                self?.operationInProgress = false
                self?.task = nil
                return
            } catch {
                if let self {
                    operationInProgress = false
                    onStateChange?(state)
                    task = nil
                }
                completion?(error.localizedDescription)
            }
        }
    }
}
