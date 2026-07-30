import AppKit

nonisolated struct BookmarkPageCandidate: Equatable, Sendable {
    let url: URL
    let suggestedTitle: String

    static func currentPage(
        url: URL?,
        title: String?,
        isLoading: Bool,
        hasVisibleError: Bool
    ) -> BookmarkPageCandidate? {
        guard
            !isLoading,
            !hasVisibleError,
            let url,
            let canonicalURL = try? Bookmark.canonicalURL(for: url)
        else {
            return nil
        }

        let trimmedTitle = title?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return BookmarkPageCandidate(
            url: canonicalURL,
            suggestedTitle: trimmedTitle.isEmpty
                ? Bookmark.defaultTitle(for: canonicalURL)
                : trimmedTitle
        )
    }
}

@MainActor
final class BookmarkManagerWindowController: NSWindowController,
    NSSearchFieldDelegate,
    NSTableViewDataSource,
    NSTableViewDelegate
{
    var currentPageProvider: (() -> BookmarkPageCandidate?)?
    var onAddCurrentPage: ((BookmarkPageCandidate) -> Void)?
    var onEdit: ((Bookmark) -> Void)?
    var onDelete: ((Bookmark) -> Void)?
    var onOpen: ((Bookmark) -> Void)?
    var onRestoreBackup: (() -> Void)?
    var onReset: (() -> Void)?

    private let searchField = NSSearchField()
    private let tableView = BookmarkTableView()
    private let scrollView = NSScrollView()
    private let emptyLabel = NSTextField(wrappingLabelWithString: "")
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let recoveryStack = NSStackView()
    private let recoveryLabel = NSTextField(wrappingLabelWithString: "")
    private let restoreButton = NSButton(
        title: "Restore Backup",
        target: nil,
        action: nil
    )
    private let resetButton = NSButton(
        title: "Reset Bookmarks…",
        target: nil,
        action: nil
    )
    private let addButton = NSButton(
        title: "Add Current Page…",
        target: nil,
        action: nil
    )
    private let editButton = NSButton(title: "Edit…", target: nil, action: nil)
    private let deleteButton = NSButton(title: "Delete", target: nil, action: nil)
    private let openButton = NSButton(title: "Open", target: nil, action: nil)
    private let doneButton = NSButton(title: "Done", target: nil, action: nil)

    private var bookmarks: [Bookmark] = []
    private var filteredBookmarks: [Bookmark] = []
    private var selectedBookmarkID: UUID?
    private var allowsChanges = false
    private var allowsRecoveryRestore = false
    private var allowsReset = false
    private var isLoading = true

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Bookmarks"
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.contentMinSize = NSSize(width: 560, height: 360)
        window.identifier = NSUserInterfaceItemIdentifier("BrowserBookmarksWindow")
        window.setAccessibilityIdentifier("BrowserBookmarksWindow")

        super.init(window: window)
        configureContent(in: window)
        showLoading()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.center()
        window?.makeKeyAndOrderFront(sender)
        window?.makeFirstResponder(searchField)
    }

    func showLoading() {
        isLoading = true
        bookmarks = []
        filteredBookmarks = []
        allowsChanges = false
        allowsRecoveryRestore = false
        allowsReset = false
        statusLabel.stringValue = "Loading bookmarks…"
        recoveryStack.isHidden = true
        tableView.reloadData()
        renderEmptyState()
        renderButtons()
    }

    func update(
        bookmarks: [Bookmark],
        statusMessage: String? = nil,
        allowsChanges: Bool = true,
        recoveryMessage: String? = nil,
        canRestoreBackup: Bool = false,
        canReset: Bool = false
    ) {
        isLoading = false
        self.bookmarks = bookmarks
        self.allowsChanges = allowsChanges
        allowsRecoveryRestore = canRestoreBackup
        allowsReset = canReset
        statusLabel.stringValue = statusMessage
            ?? Self.countDescription(bookmarks.count)
        recoveryLabel.stringValue = recoveryMessage ?? ""
        recoveryStack.isHidden = recoveryMessage == nil
        restoreButton.isHidden = !canRestoreBackup
        applySearch(preservingSelection: true)
    }

    func showFailure(_ message: String, canReset: Bool = true) {
        isLoading = false
        bookmarks = []
        filteredBookmarks = []
        allowsChanges = false
        allowsRecoveryRestore = false
        allowsReset = canReset
        statusLabel.stringValue = message
        recoveryLabel.stringValue = "Bookmarks could not be loaded. "
            + "The damaged data has not been replaced."
        recoveryStack.isHidden = !canReset
        restoreButton.isHidden = true
        tableView.reloadData()
        renderEmptyState()
        renderButtons()
    }

    func showOperationStatus(_ message: String) {
        statusLabel.stringValue = message
    }

    func refreshCurrentPageAvailability() {
        renderButtons()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        filteredBookmarks.count
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard filteredBookmarks.indices.contains(row) else {
            return nil
        }
        let identifier = NSUserInterfaceItemIdentifier("BookmarkListCell")
        let cell = tableView.makeView(
            withIdentifier: identifier,
            owner: self
        ) as? BookmarkListCellView ?? BookmarkListCellView(identifier: identifier)
        cell.update(with: filteredBookmarks[row])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        selectedBookmarkID = filteredBookmarks.indices.contains(row)
            ? filteredBookmarks[row].id
            : nil
        renderButtons()
    }

    private func configureContent(in window: NSWindow) {
        guard let contentView = window.contentView else {
            return
        }
        contentView.setAccessibilityIdentifier("BrowserBookmarksView")

        searchField.placeholderString = "Search bookmarks"
        searchField.sendsSearchStringImmediately = true
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchChanged(_:))
        searchField.setAccessibilityIdentifier("BrowserBookmarkSearchField")
        searchField.setAccessibilityLabel("Search bookmarks")

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        statusLabel.maximumNumberOfLines = 2
        statusLabel.setAccessibilityIdentifier("BrowserBookmarkStatus")

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Bookmark"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 50
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.doubleAction = #selector(openSelected(_:))
        tableView.onOpenRequested = { [weak self] in
            self?.openSelected(nil)
        }
        tableView.onDeleteRequested = { [weak self] in
            self?.deleteSelected(nil)
        }
        tableView.onEditRequested = { [weak self] in
            self?.editSelected(nil)
        }
        tableView.setAccessibilityIdentifier("BrowserBookmarkList")
        tableView.setAccessibilityLabel("Bookmarks")

        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = tableView

        emptyLabel.alignment = .center
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.font = .systemFont(ofSize: 15)
        emptyLabel.setAccessibilityIdentifier("BrowserBookmarksEmptyState")

        recoveryLabel.maximumNumberOfLines = 3
        recoveryLabel.textColor = .systemOrange
        recoveryLabel.setAccessibilityIdentifier("BrowserBookmarkRecoveryView")
        configureButton(
            restoreButton,
            action: #selector(restoreBackup(_:)),
            identifier: "BrowserBookmarkRestoreBackupButton"
        )
        configureButton(
            resetButton,
            action: #selector(resetBookmarks(_:)),
            identifier: "BrowserBookmarkResetButton"
        )
        recoveryStack.orientation = .horizontal
        recoveryStack.alignment = .centerY
        recoveryStack.spacing = 8
        recoveryStack.addArrangedSubview(recoveryLabel)
        recoveryStack.addArrangedSubview(restoreButton)
        recoveryStack.addArrangedSubview(resetButton)

        configureButton(
            addButton,
            action: #selector(addCurrentPage(_:)),
            identifier: "BrowserBookmarkAddButton"
        )
        configureButton(
            editButton,
            action: #selector(editSelected(_:)),
            identifier: "BrowserBookmarkEditButton"
        )
        configureButton(
            deleteButton,
            action: #selector(deleteSelected(_:)),
            identifier: "BrowserBookmarkDeleteButton"
        )
        configureButton(
            openButton,
            action: #selector(openSelected(_:)),
            identifier: "BrowserBookmarkOpenButton"
        )
        configureButton(
            doneButton,
            action: #selector(closeWindow(_:)),
            identifier: "BrowserBookmarksDoneButton"
        )
        openButton.keyEquivalent = "\r"

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttonStack = NSStackView(views: [
            addButton,
            editButton,
            deleteButton,
            spacer,
            openButton,
            doneButton,
        ])
        buttonStack.orientation = .horizontal
        buttonStack.alignment = .centerY
        buttonStack.spacing = 8

        for view in [
            searchField,
            statusLabel,
            recoveryStack,
            scrollView,
            emptyLabel,
            buttonStack,
        ] {
            view.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(view)
        }

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            searchField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            searchField.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor,
                constant: -14
            ),

            statusLabel.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 6),
            statusLabel.leadingAnchor.constraint(equalTo: searchField.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: searchField.trailingAnchor),

            recoveryStack.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            recoveryStack.leadingAnchor.constraint(equalTo: searchField.leadingAnchor),
            recoveryStack.trailingAnchor.constraint(equalTo: searchField.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: recoveryStack.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: searchField.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: searchField.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: buttonStack.topAnchor, constant: -12),

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            emptyLabel.widthAnchor.constraint(
                lessThanOrEqualTo: scrollView.widthAnchor,
                constant: -40
            ),

            buttonStack.leadingAnchor.constraint(equalTo: searchField.leadingAnchor),
            buttonStack.trailingAnchor.constraint(equalTo: searchField.trailingAnchor),
            buttonStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14),

            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 200),
        ])
    }

    private func configureButton(
        _ button: NSButton,
        action: Selector,
        identifier: String
    ) {
        button.bezelStyle = .rounded
        button.target = self
        button.action = action
        button.setAccessibilityIdentifier(identifier)
    }

    @objc
    private func searchChanged(_ sender: NSSearchField) {
        applySearch(preservingSelection: true)
    }

    @objc
    private func addCurrentPage(_ sender: Any?) {
        guard allowsChanges, let candidate = currentPageProvider?() else {
            NSSound.beep()
            return
        }
        onAddCurrentPage?(candidate)
    }

    @objc
    private func editSelected(_ sender: Any?) {
        guard allowsChanges, let bookmark = selectedBookmark else {
            return
        }
        onEdit?(bookmark)
    }

    @objc
    private func deleteSelected(_ sender: Any?) {
        guard allowsChanges, let bookmark = selectedBookmark, let window else {
            return
        }
        let alert = NSAlert()
        alert.messageText = "Delete “\(bookmark.title)”?"
        alert.informativeText = "This bookmark will be removed from this Mac."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else {
                return
            }
            self?.onDelete?(bookmark)
        }
    }

    @objc
    private func openSelected(_ sender: Any?) {
        guard let bookmark = selectedBookmark else {
            return
        }
        onOpen?(bookmark)
    }

    @objc
    private func restoreBackup(_ sender: Any?) {
        guard allowsRecoveryRestore else {
            return
        }
        onRestoreBackup?()
    }

    @objc
    private func resetBookmarks(_ sender: Any?) {
        guard allowsReset, let window else {
            return
        }
        let alert = NSAlert()
        alert.messageText = "Reset all bookmarks?"
        alert.informativeText = "The active bookmark library and backup will be "
            + "deleted. Any damaged primary file already preserved for recovery "
            + "will remain on this Mac."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Reset Bookmarks")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else {
                return
            }
            self?.onReset?()
        }
    }

    @objc
    private func closeWindow(_ sender: Any?) {
        close()
    }

    private var selectedBookmark: Bookmark? {
        guard let selectedBookmarkID else {
            return nil
        }
        return bookmarks.first { $0.id == selectedBookmarkID }
    }

    private func applySearch(preservingSelection: Bool) {
        let previousSelection = preservingSelection ? selectedBookmarkID : nil
        filteredBookmarks = BookmarkSearch.filteredBookmarks(
            in: bookmarks,
            matching: searchField.stringValue
        )
        tableView.reloadData()

        if let previousSelection,
           let row = filteredBookmarks.firstIndex(where: { $0.id == previousSelection })
        {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            tableView.scrollRowToVisible(row)
            selectedBookmarkID = previousSelection
        } else {
            tableView.deselectAll(nil)
            selectedBookmarkID = nil
        }
        renderEmptyState()
        renderButtons()
    }

    private func renderEmptyState() {
        let hasQuery = !searchField.stringValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        if isLoading {
            emptyLabel.stringValue = "Loading bookmarks…"
            emptyLabel.isHidden = false
        } else if filteredBookmarks.isEmpty {
            emptyLabel.stringValue = hasQuery
                ? "No bookmarks match your search."
                : "No bookmarks yet.\nOpen a page and press Command-D."
            emptyLabel.isHidden = false
        } else {
            emptyLabel.isHidden = true
        }
    }

    private func renderButtons() {
        let hasSelection = selectedBookmark != nil
        let currentPage = currentPageProvider?()
        let currentPageIsBookmarked = currentPage.map { candidate in
            bookmarks.contains { $0.url == candidate.url }
        } ?? false
        addButton.title = currentPageIsBookmarked
            ? "Edit Current Page…"
            : "Add Current Page…"
        addButton.isEnabled = allowsChanges && currentPage != nil
        editButton.isEnabled = allowsChanges && hasSelection
        deleteButton.isEnabled = allowsChanges && hasSelection
        openButton.isEnabled = hasSelection
        resetButton.isEnabled = allowsReset && !isLoading
        restoreButton.isEnabled = allowsRecoveryRestore
    }

    private static func countDescription(_ count: Int) -> String {
        count == 1 ? "1 bookmark" : "\(count) bookmarks"
    }
}

@MainActor
private final class BookmarkTableView: NSTableView {
    var onOpenRequested: (() -> Void)?
    var onDeleteRequested: (() -> Void)?
    var onEditRequested: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(
            .deviceIndependentFlagsMask
        )
        if modifiers == .command,
           event.charactersIgnoringModifiers?.lowercased() == "e"
        {
            onEditRequested?()
            return
        }

        switch event.keyCode {
        case 36, 76:
            onOpenRequested?()
        case 51, 117:
            onDeleteRequested?()
        default:
            super.keyDown(with: event)
        }
    }
}

@MainActor
private final class BookmarkListCellView: NSTableCellView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let urlLabel = NSTextField(labelWithString: "")

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        urlLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        urlLabel.textColor = .secondaryLabelColor
        urlLabel.lineBreakMode = .byTruncatingMiddle

        let stack = NSStackView(views: [titleLabel, urlLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func update(with bookmark: Bookmark) {
        titleLabel.stringValue = bookmark.title
        urlLabel.stringValue = bookmark.url.absoluteString
        setAccessibilityIdentifier("BrowserBookmarkRow.\(bookmark.id.uuidString)")
        setAccessibilityLabel(bookmark.title)
        setAccessibilityHelp(bookmark.url.absoluteString)
    }
}
