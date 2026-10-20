import AppKit

@MainActor
final class BookmarkSidebarView: NSVisualEffectView, NSTableViewDataSource,
    NSTableViewDelegate
{
    var onOpen: ((Bookmark) -> Void)?
    var onManage: (() -> Void)?

    let tableView = BookmarkSidebarTableView()
    let manageButton = NSButton(title: "Manage Bookmarks…", target: nil, action: nil)
    private let countLabel = NSTextField(labelWithString: "")
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private let recoveryLabel = NSTextField(wrappingLabelWithString: "")
    private var bookmarks: [Bookmark] = []

    init() {
        super.init(frame: .zero)
        material = .sidebar
        blendingMode = .withinWindow
        setAccessibilityIdentifier("BrowserBookmarkSidebar")
        setAccessibilityLabel("Bookmarks sidebar")

        let heading = NSTextField(labelWithString: "Bookmarks")
        heading.font = .systemFont(ofSize: 12, weight: .semibold)
        heading.textColor = .secondaryLabelColor
        countLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        countLabel.textColor = .tertiaryLabelColor
        countLabel.setContentHuggingPriority(.required, for: .horizontal)
        let header = NSStackView(views: [heading, countLabel])
        header.orientation = .horizontal
        header.distribution = .fill

        recoveryLabel.font = .systemFont(ofSize: 11)
        recoveryLabel.textColor = .secondaryLabelColor
        recoveryLabel.maximumNumberOfLines = 0
        recoveryLabel.isHidden = true
        recoveryLabel.setAccessibilityIdentifier("BrowserSidebarRecovery")

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Bookmark"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.headerView = nil
        tableView.style = .sourceList
        tableView.rowHeight = 30
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.backgroundColor = .clear
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = true
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(openClickedBookmark(_:))
        tableView.onOpenRequested = { [weak self] in
            guard let self else { return }
            openBookmark(at: tableView.selectedRow)
        }
        tableView.setAccessibilityIdentifier("BrowserSidebarBookmarkList")
        tableView.setAccessibilityLabel("Bookmarks")
        tableView.setAccessibilityHelp("Click a bookmark to open it in a new tab, or select it and press Return.")

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        messageLabel.font = .systemFont(ofSize: 12)
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.alignment = .center
        messageLabel.maximumNumberOfLines = 0
        messageLabel.setAccessibilityIdentifier("BrowserSidebarMessage")
        let listContainer = NSView()
        for view in [scrollView, messageLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            listContainer.addSubview(view)
        }

        manageButton.bezelStyle = .rounded
        manageButton.controlSize = .small
        manageButton.font = .systemFont(ofSize: 11)
        manageButton.target = self
        manageButton.action = #selector(manageBookmarks(_:))
        manageButton.toolTip = "Add, edit, or remove bookmarks (Option-Command-B)"
        manageButton.setAccessibilityIdentifier("BrowserSidebarManageButton")

        let footerSeparator = NSBox()
        footerSeparator.boxType = .separator
        let stack = NSStackView(views: [
            header, recoveryLabel, listContainer, footerSeparator, manageButton,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        addSubview(divider)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            recoveryLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            listContainer.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footerSeparator.widthAnchor.constraint(equalTo: stack.widthAnchor),
            manageButton.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scrollView.topAnchor.constraint(equalTo: listContainer.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: listContainer.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: listContainer.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: listContainer.bottomAnchor),
            messageLabel.leadingAnchor.constraint(equalTo: listContainer.leadingAnchor, constant: 8),
            messageLabel.trailingAnchor.constraint(equalTo: listContainer.trailingAnchor, constant: -8),
            messageLabel.centerYAnchor.constraint(equalTo: listContainer.centerYAnchor),
            divider.topAnchor.constraint(equalTo: topAnchor),
            divider.bottomAnchor.constraint(equalTo: bottomAnchor),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),
        ])
        update(state: .idle, canManage: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func update(state: BookmarkCoordinator.State, canManage: Bool) {
        let selection = bookmarks.indices.contains(tableView.selectedRow)
            ? bookmarks[tableView.selectedRow].id : nil
        let newBookmarks: [Bookmark]
        switch state {
        case .idle, .loading:
            newBookmarks = []
            messageLabel.stringValue = "Loading bookmarks…"
            recoveryLabel.isHidden = true
        case let .ready(snapshot):
            newBookmarks = snapshot.bookmarks
            messageLabel.stringValue = "No bookmarks yet.\nAdd the current page with ⌘D."
            recoveryLabel.stringValue = "Showing a recovered backup. Use Manage Bookmarks to restore it."
            recoveryLabel.isHidden = snapshot.recovery == nil
        case .failed:
            newBookmarks = []
            messageLabel.stringValue = "Bookmarks couldn’t be loaded.\nOpen Manage Bookmarks for details."
            recoveryLabel.isHidden = true
        }
        if bookmarks != newBookmarks {
            bookmarks = newBookmarks
            tableView.reloadData()
            if let selection, let row = bookmarks.firstIndex(where: { $0.id == selection }) {
                tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            } else {
                tableView.deselectAll(nil)
            }
        }
        countLabel.stringValue = bookmarks.isEmpty ? "" : String(bookmarks.count)
        messageLabel.isHidden = !bookmarks.isEmpty
        manageButton.isEnabled = canManage
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        bookmarks.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard bookmarks.indices.contains(row) else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("SidebarBookmarkCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self)
            as? BookmarkSidebarCellView ?? BookmarkSidebarCellView(identifier: identifier)
        cell.update(bookmarks[row])
        return cell
    }

    @objc
    private func openClickedBookmark(_ sender: NSTableView) {
        openBookmark(at: sender.clickedRow)
    }

    private func openBookmark(at row: Int) {
        guard bookmarks.indices.contains(row) else { return }
        onOpen?(bookmarks[row])
    }

    @objc
    private func manageBookmarks(_ sender: Any?) {
        onManage?()
    }
}

@MainActor
final class BookmarkSidebarTableView: NSTableView {
    var onOpenRequested: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 {
            onOpenRequested?()
        } else {
            super.keyDown(with: event)
        }
    }
}

@MainActor
private final class BookmarkSidebarCellView: NSTableCellView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let symbolView = NSImageView()

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        symbolView.contentTintColor = .secondaryLabelColor
        textField = titleLabel
        imageView = symbolView
        for view in [symbolView, titleLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            symbolView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            symbolView.widthAnchor.constraint(equalToConstant: 14),
            symbolView.heightAnchor.constraint(equalToConstant: 14),
            symbolView.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: symbolView.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func update(_ bookmark: Bookmark) {
        titleLabel.stringValue = bookmark.title
        symbolView.image = NSImage(
            systemSymbolName: bookmark.url.isFileURL ? "doc" : "bookmark",
            accessibilityDescription: nil
        )
        toolTip = "\(bookmark.title)\n\(bookmark.url.absoluteString)"
        titleLabel.toolTip = toolTip
        setAccessibilityIdentifier("BrowserSidebarBookmark.\(bookmark.id.uuidString)")
        setAccessibilityLabel(bookmark.title)
        setAccessibilityHelp("Open in a new tab: \(bookmark.url.absoluteString)")
    }
}
