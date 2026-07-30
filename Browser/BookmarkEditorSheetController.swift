import AppKit

@MainActor
final class BookmarkEditorSheetController: NSWindowController {
    var onSave: ((UUID?, URL, String) -> Void)?
    var onRemove: ((Bookmark) -> Void)?

    private let headingLabel = NSTextField(labelWithString: "")
    private let titleField = NSTextField()
    private let urlField = NSTextField()
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let removeButton = NSButton(
        title: "Remove Bookmark",
        target: nil,
        action: nil
    )
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private let saveButton = NSButton(title: "Save", target: nil, action: nil)

    private var editingBookmark: Bookmark?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 230),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "Bookmark"
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.identifier = NSUserInterfaceItemIdentifier("BrowserBookmarkEditorSheet")
        window.setAccessibilityIdentifier("BrowserBookmarkEditorSheet")

        super.init(window: window)
        configureContent(in: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func beginAdding(
        _ candidate: BookmarkPageCandidate,
        for parentWindow: NSWindow
    ) {
        editingBookmark = nil
        headingLabel.stringValue = "Add Bookmark"
        titleField.stringValue = candidate.suggestedTitle
        urlField.stringValue = candidate.url.absoluteString
        removeButton.isHidden = true
        prepareForPresentation()
        beginSheet(for: parentWindow)
    }

    func beginEditing(_ bookmark: Bookmark, for parentWindow: NSWindow) {
        editingBookmark = bookmark
        headingLabel.stringValue = "Edit Bookmark"
        titleField.stringValue = bookmark.title
        urlField.stringValue = bookmark.url.absoluteString
        removeButton.isHidden = false
        prepareForPresentation()
        beginSheet(for: parentWindow)
    }

    func completeSave(errorMessage: String? = nil) {
        setBusy(false)
        if let errorMessage {
            showValidationError(errorMessage)
        } else {
            endSheet()
        }
    }

    func completeRemoval(errorMessage: String? = nil) {
        completeSave(errorMessage: errorMessage)
    }

    func activateIfPresented() -> Bool {
        guard let window, let parentWindow = window.sheetParent else {
            return false
        }
        parentWindow.makeKeyAndOrderFront(nil)
        window.makeKey()
        return true
    }

    private func configureContent(in window: NSWindow) {
        guard let contentView = window.contentView else {
            return
        }

        headingLabel.font = .systemFont(ofSize: 17, weight: .semibold)

        titleField.placeholderString = "Name"
        titleField.setAccessibilityIdentifier("BrowserBookmarkTitleField")
        titleField.setAccessibilityLabel("Bookmark name")
        urlField.placeholderString = "https://example.com/ or /path/page.html"
        urlField.lineBreakMode = .byTruncatingMiddle
        urlField.setAccessibilityIdentifier("BrowserBookmarkURLField")
        urlField.setAccessibilityLabel("Bookmark address")

        errorLabel.textColor = .systemRed
        errorLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        errorLabel.maximumNumberOfLines = 2
        errorLabel.isHidden = true
        errorLabel.setAccessibilityIdentifier("BrowserBookmarkEditorError")

        configureButton(
            removeButton,
            action: #selector(removeBookmark(_:)),
            identifier: "BrowserBookmarkRemoveButton"
        )
        removeButton.contentTintColor = .systemRed
        configureButton(
            cancelButton,
            action: #selector(cancel(_:)),
            identifier: "BrowserBookmarkCancelButton"
        )
        cancelButton.keyEquivalent = "\u{1b}"
        configureButton(
            saveButton,
            action: #selector(save(_:)),
            identifier: "BrowserBookmarkSaveButton"
        )
        saveButton.keyEquivalent = "\r"

        let titleLabel = NSTextField(labelWithString: "Name:")
        titleLabel.alignment = .right
        let urlLabel = NSTextField(labelWithString: "Address:")
        urlLabel.alignment = .right

        let grid = NSGridView(views: [
            [titleLabel, titleField],
            [urlLabel, urlField],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill
        grid.column(at: 1).width = 380
        grid.rowSpacing = 10

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttonStack = NSStackView(views: [
            removeButton,
            spacer,
            cancelButton,
            saveButton,
        ])
        buttonStack.orientation = .horizontal
        buttonStack.alignment = .centerY
        buttonStack.spacing = 8

        for view in [headingLabel, grid, errorLabel, buttonStack] {
            view.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(view)
        }

        NSLayoutConstraint.activate([
            headingLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            headingLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            headingLabel.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor,
                constant: -20
            ),

            grid.topAnchor.constraint(equalTo: headingLabel.bottomAnchor, constant: 16),
            grid.leadingAnchor.constraint(equalTo: headingLabel.leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: headingLabel.trailingAnchor),

            errorLabel.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 8),
            errorLabel.leadingAnchor.constraint(equalTo: headingLabel.leadingAnchor),
            errorLabel.trailingAnchor.constraint(equalTo: headingLabel.trailingAnchor),

            buttonStack.leadingAnchor.constraint(equalTo: headingLabel.leadingAnchor),
            buttonStack.trailingAnchor.constraint(equalTo: headingLabel.trailingAnchor),
            buttonStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
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

    private func prepareForPresentation() {
        errorLabel.stringValue = ""
        errorLabel.isHidden = true
        setBusy(false)
    }

    private func beginSheet(for parentWindow: NSWindow) {
        guard let window else {
            return
        }
        if activateIfPresented() {
            return
        }
        parentWindow.beginSheet(window)
        window.makeFirstResponder(titleField)
        titleField.currentEditor()?.selectAll(nil)
    }

    @objc
    private func save(_ sender: Any?) {
        let title = titleField.stringValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let address = urlField.stringValue
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !title.isEmpty else {
            showValidationError("Enter a name for this bookmark.")
            window?.makeFirstResponder(titleField)
            return
        }
        guard let url = Self.validBookmarkURL(from: address) else {
            showValidationError(
                "Enter an HTTP/HTTPS address or an absolute path to a local .html or .htm file."
            )
            window?.makeFirstResponder(urlField)
            return
        }

        setBusy(true)
        onSave?(editingBookmark?.id, url, title)
    }

    @objc
    private func removeBookmark(_ sender: Any?) {
        guard let bookmark = editingBookmark, let window else {
            return
        }
        let alert = NSAlert()
        alert.messageText = "Remove “\(bookmark.title)”?"
        alert.informativeText = "This bookmark will be removed from this Mac."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else {
                return
            }
            self?.setBusy(true)
            self?.onRemove?(bookmark)
        }
    }

    @objc
    private func cancel(_ sender: Any?) {
        endSheet()
    }

    private func endSheet() {
        guard let window else {
            return
        }
        if let parent = window.sheetParent {
            parent.endSheet(window)
        } else {
            close()
        }
    }

    private func setBusy(_ busy: Bool) {
        titleField.isEnabled = !busy
        urlField.isEnabled = !busy
        saveButton.isEnabled = !busy
        cancelButton.isEnabled = !busy
        removeButton.isEnabled = !busy
        if busy {
            errorLabel.stringValue = "Saving…"
            errorLabel.textColor = .secondaryLabelColor
            errorLabel.isHidden = false
        }
    }

    private func showValidationError(_ message: String) {
        errorLabel.textColor = .systemRed
        errorLabel.stringValue = message
        errorLabel.isHidden = false
    }

    private static func validBookmarkURL(from string: String) -> URL? {
        try? Bookmark.canonicalURL(fromAddress: string)
    }
}
