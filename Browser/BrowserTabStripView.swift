import AppKit

@MainActor
final class BrowserTabStripView: NSView {
    var onNewTab: (() -> Void)?
    var onSelectTab: ((UUID) -> Void)?
    var onCloseTab: ((UUID) -> Void)?

    let newTabButton = NSButton()

    private let scrollView = NSScrollView()
    private let tabStack = NSStackView()
    private var itemViews: [UUID: BrowserTabItemView] = [:]
    private var orderedIDs: [UUID] = []
    private var selectedID: UUID?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        setAccessibilityIdentifier("BrowserTabStrip")
        setAccessibilityElement(true)
        setAccessibilityRole(.tabGroup)
        setAccessibilityLabel("Tabs")

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.horizontalScrollElasticity = .automatic
        scrollView.setAccessibilityIdentifier("BrowserTabList")

        tabStack.orientation = .horizontal
        tabStack.alignment = .centerY
        tabStack.spacing = 4
        tabStack.edgeInsets = NSEdgeInsets(top: 3, left: 6, bottom: 3, right: 6)
        tabStack.frame = NSRect(x: 0, y: 0, width: 12, height: 28)
        scrollView.documentView = tabStack

        newTabButton.translatesAutoresizingMaskIntoConstraints = false
        newTabButton.bezelStyle = .texturedRounded
        newTabButton.image = NSImage(
            systemSymbolName: "plus",
            accessibilityDescription: "New Tab"
        )
        newTabButton.imagePosition = .imageOnly
        newTabButton.toolTip = "New Tab (Command-T)"
        newTabButton.setAccessibilityIdentifier("BrowserNewTabButton")
        newTabButton.setAccessibilityLabel("New Tab")
        newTabButton.target = self
        newTabButton.action = #selector(createNewTab(_:))

        let separator = NSBox()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.boxType = .separator

        addSubview(scrollView)
        addSubview(newTabButton)
        addSubview(separator)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: separator.topAnchor),

            newTabButton.leadingAnchor.constraint(
                equalTo: scrollView.trailingAnchor,
                constant: 6
            ),
            newTabButton.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -8
            ),
            newTabButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            newTabButton.widthAnchor.constraint(equalToConstant: 28),
            newTabButton.heightAnchor.constraint(equalToConstant: 26),

            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func layout() {
        super.layout()
        updateDocumentFrame()
    }

    func update(_ presentations: [BrowserTabPresentation]) {
        let liveIDs = Set(presentations.map(\.id))
        let staleIDs = itemViews.keys.filter { !liveIDs.contains($0) }
        for id in staleIDs {
            guard let itemView = itemViews[id] else {
                continue
            }
            tabStack.removeArrangedSubview(itemView)
            itemView.removeFromSuperview()
            itemViews[id] = nil
        }

        let newOrderedIDs = presentations.map(\.id)
        let newSelectedID = presentations.first(where: \.isSelected)?.id
        let orderChanged = orderedIDs != newOrderedIDs
        let selectionChanged = selectedID != newSelectedID
        for presentation in presentations {
            let itemView: BrowserTabItemView
            if let existing = itemViews[presentation.id] {
                itemView = existing
            } else {
                itemView = BrowserTabItemView(id: presentation.id)
                itemView.onSelect = { [weak self] id in
                    self?.onSelectTab?(id)
                }
                itemView.onClose = { [weak self] id in
                    self?.onCloseTab?(id)
                }
                itemViews[presentation.id] = itemView
            }
            itemView.update(presentation)
        }

        if orderChanged {
            for view in tabStack.arrangedSubviews {
                tabStack.removeArrangedSubview(view)
                view.removeFromSuperview()
            }
            orderedIDs = newOrderedIDs
            updateDocumentFrame()
            for id in newOrderedIDs {
                if let itemView = itemViews[id] {
                    tabStack.addArrangedSubview(itemView)
                }
            }
        }

        selectedID = newSelectedID
        setAccessibilityTabs(
            newOrderedIDs.compactMap { itemViews[$0]?.selectionButton }
        )
        if orderChanged {
            needsLayout = true
            layoutSubtreeIfNeeded()
        }
        if selectionChanged {
            scrollSelectedTabToVisible(id: newSelectedID)
        }
    }

    private func updateDocumentFrame() {
        let tabWidth: CGFloat = 176
        let spacing = tabStack.spacing
        let horizontalInsets = tabStack.edgeInsets.left
            + tabStack.edgeInsets.right
        let contentWidth = horizontalInsets
            + CGFloat(orderedIDs.count) * tabWidth
            + CGFloat(max(0, orderedIDs.count - 1)) * spacing
        tabStack.frame = NSRect(
            x: 0,
            y: 0,
            width: max(scrollView.contentSize.width, contentWidth),
            height: max(28, scrollView.contentSize.height)
        )
    }

    private func scrollSelectedTabToVisible(id: UUID?) {
        guard let id, let itemView = itemViews[id] else {
            return
        }
        itemView.scrollToVisible(itemView.bounds)
    }

    @objc
    private func createNewTab(_ sender: Any?) {
        onNewTab?()
    }
}

@MainActor
private final class BrowserTabItemView: NSView {
    let id: UUID
    let selectionButton = NSButton()
    var onSelect: ((UUID) -> Void)?
    var onClose: ((UUID) -> Void)?

    private let closeButton = NSButton()
    private var isSelected = false

    init(id: UUID) {
        self.id = id
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false

        selectionButton.translatesAutoresizingMaskIntoConstraints = false
        selectionButton.setButtonType(.toggle)
        selectionButton.isBordered = false
        selectionButton.alignment = .left
        selectionButton.font = .systemFont(
            ofSize: NSFont.smallSystemFontSize,
            weight: .medium
        )
        selectionButton.lineBreakMode = .byTruncatingTail
        selectionButton.target = self
        selectionButton.action = #selector(selectTab(_:))
        selectionButton.setAccessibilityRole(.radioButton)
        selectionButton.setAccessibilityIdentifier(
            "BrowserTab.\(id.uuidString)"
        )

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.isBordered = false
        closeButton.image = NSImage(
            systemSymbolName: "xmark",
            accessibilityDescription: "Close Tab"
        )
        closeButton.imagePosition = .imageOnly
        closeButton.target = self
        closeButton.action = #selector(closeTab(_:))
        closeButton.setAccessibilityIdentifier(
            "BrowserTabCloseButton.\(id.uuidString)"
        )

        addSubview(selectionButton)
        addSubview(closeButton)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 176),
            heightAnchor.constraint(equalToConstant: 28),

            selectionButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            selectionButton.topAnchor.constraint(equalTo: topAnchor),
            selectionButton.bottomAnchor.constraint(equalTo: bottomAnchor),

            closeButton.leadingAnchor.constraint(
                equalTo: selectionButton.trailingAnchor,
                constant: 4
            ),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 18),
            closeButton.heightAnchor.constraint(equalToConstant: 18),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func update(_ presentation: BrowserTabPresentation) {
        selectionButton.title = presentation.title
        selectionButton.state = presentation.isSelected ? .on : .off
        selectionButton.setAccessibilityLabel(presentation.title)
        selectionButton.setAccessibilitySelected(presentation.isSelected)
        closeButton.toolTip = "Close \(presentation.title)"
        closeButton.setAccessibilityLabel("Close \(presentation.title)")
        isSelected = presentation.isSelected
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let backgroundColor = isSelected
            ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.22)
            : NSColor.controlBackgroundColor.withAlphaComponent(0.55)
        backgroundColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
    }

    @objc
    private func selectTab(_ sender: Any?) {
        onSelect?(id)
        if isSelected {
            selectionButton.state = .on
        }
    }

    @objc
    private func closeTab(_ sender: Any?) {
        onClose?(id)
    }
}
