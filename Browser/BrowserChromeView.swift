import AppKit

@MainActor
final class BrowserChromeView: NSView {
    let tabStrip = BrowserTabStripView()
    let backButton = NSButton()
    let forwardButton = NSButton()
    let reloadStopButton = NSButton()
    let addressField = NSTextField()
    let bookmarkButton = NSButton()
    let progressIndicator = NSProgressIndicator()
    let pageContainer = NSView()
    let errorView = BrowserErrorView()

    init(searchProviderName: String) {
        super.init(frame: .zero)

        setAccessibilityIdentifier("BrowserNativeShell")
        configureNavigationButton(
            backButton,
            symbolName: "chevron.left",
            label: "Back",
            identifier: "BrowserBackButton"
        )
        configureNavigationButton(
            forwardButton,
            symbolName: "chevron.right",
            label: "Forward",
            identifier: "BrowserForwardButton"
        )
        configureNavigationButton(
            reloadStopButton,
            symbolName: "arrow.clockwise",
            label: "Reload",
            identifier: "BrowserReloadStopButton"
        )
        configureNavigationButton(
            bookmarkButton,
            symbolName: "star",
            label: "Add Bookmark",
            identifier: "BrowserBookmarkButton"
        )
        bookmarkButton.isEnabled = false

        addressField.translatesAutoresizingMaskIntoConstraints = false
        addressField.bezelStyle = .roundedBezel
        addressField.focusRingType = .exterior
        addressField.font = .systemFont(ofSize: NSFont.systemFontSize)
        addressField.lineBreakMode = .byTruncatingMiddle
        addressField.placeholderString = Self.addressPlaceholder(
            searchProviderName: searchProviderName
        )
        addressField.setAccessibilityIdentifier("BrowserAddressField")
        addressField.setAccessibilityLabel("Address and search")

        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        progressIndicator.style = .bar
        progressIndicator.isIndeterminate = false
        progressIndicator.minValue = 0
        progressIndicator.maxValue = 1
        progressIndicator.doubleValue = 0
        progressIndicator.isHidden = true
        progressIndicator.setAccessibilityIdentifier("BrowserLoadProgress")
        progressIndicator.setAccessibilityLabel("Page load progress")

        let toolbar = NSView()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.setAccessibilityIdentifier("BrowserToolbar")

        let controls = NSStackView(views: [
            backButton,
            forwardButton,
            reloadStopButton,
            addressField,
            bookmarkButton,
        ])
        controls.translatesAutoresizingMaskIntoConstraints = false
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 6
        toolbar.addSubview(controls)

        let separator = NSBox()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.boxType = .separator

        pageContainer.translatesAutoresizingMaskIntoConstraints = false
        pageContainer.setAccessibilityIdentifier("BrowserPageContainer")

        errorView.translatesAutoresizingMaskIntoConstraints = false
        errorView.isHidden = true
        pageContainer.addSubview(errorView)

        tabStrip.translatesAutoresizingMaskIntoConstraints = false

        addSubview(tabStrip)
        addSubview(toolbar)
        addSubview(separator)
        addSubview(progressIndicator)
        addSubview(pageContainer)

        NSLayoutConstraint.activate([
            tabStrip.topAnchor.constraint(equalTo: topAnchor),
            tabStrip.leadingAnchor.constraint(equalTo: leadingAnchor),
            tabStrip.trailingAnchor.constraint(equalTo: trailingAnchor),
            tabStrip.heightAnchor.constraint(equalToConstant: 36),

            toolbar.topAnchor.constraint(equalTo: tabStrip.bottomAnchor),
            toolbar.leadingAnchor.constraint(equalTo: leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 46),

            controls.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 10),
            controls.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -10),
            controls.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),

            backButton.widthAnchor.constraint(equalToConstant: 30),
            forwardButton.widthAnchor.constraint(equalToConstant: 30),
            reloadStopButton.widthAnchor.constraint(equalToConstant: 30),
            bookmarkButton.widthAnchor.constraint(equalToConstant: 30),
            addressField.widthAnchor.constraint(greaterThanOrEqualToConstant: 260),

            separator.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),

            progressIndicator.topAnchor.constraint(equalTo: separator.bottomAnchor),
            progressIndicator.leadingAnchor.constraint(equalTo: leadingAnchor),
            progressIndicator.trailingAnchor.constraint(equalTo: trailingAnchor),
            progressIndicator.heightAnchor.constraint(equalToConstant: 2),

            pageContainer.topAnchor.constraint(equalTo: progressIndicator.bottomAnchor),
            pageContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            pageContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            pageContainer.bottomAnchor.constraint(equalTo: bottomAnchor),

            errorView.topAnchor.constraint(equalTo: pageContainer.topAnchor),
            errorView.leadingAnchor.constraint(equalTo: pageContainer.leadingAnchor),
            errorView.trailingAnchor.constraint(equalTo: pageContainer.trailingAnchor),
            errorView.bottomAnchor.constraint(equalTo: pageContainer.bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func updateSearchProviderName(_ name: String) {
        addressField.placeholderString = Self.addressPlaceholder(
            searchProviderName: name
        )
    }

    func updateReloadStopButton(isLoading: Bool) {
        let label = isLoading ? "Stop" : "Reload"
        let symbolName = isLoading ? "xmark" : "arrow.clockwise"
        reloadStopButton.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: label
        )
        reloadStopButton.toolTip = label
        reloadStopButton.setAccessibilityLabel(label)
    }

    func updateBookmarkButton(isBookmarked: Bool, isEnabled: Bool) {
        let label = isBookmarked ? "Edit Bookmark" : "Add Bookmark"
        bookmarkButton.image = NSImage(
            systemSymbolName: isBookmarked ? "star.fill" : "star",
            accessibilityDescription: label
        )
        bookmarkButton.toolTip = label
        bookmarkButton.setAccessibilityLabel(label)
        bookmarkButton.isEnabled = isEnabled
    }

    private func configureNavigationButton(
        _ button: NSButton,
        symbolName: String,
        label: String,
        identifier: String
    ) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .texturedRounded
        button.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: label
        )
        button.imagePosition = .imageOnly
        button.toolTip = label
        button.setAccessibilityIdentifier(identifier)
        button.setAccessibilityLabel(label)
    }

    private static func addressPlaceholder(searchProviderName: String) -> String {
        "Search with \(searchProviderName) or enter an address"
    }
}

@MainActor
final class BrowserErrorView: NSView {
    let retryButton = NSButton(title: "Try Again", target: nil, action: nil)

    private let titleLabel = NSTextField(labelWithString: "")
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private let hostLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        setAccessibilityIdentifier("BrowserErrorView")
        setAccessibilityElement(true)
        setAccessibilityRole(.group)

        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let icon = NSImageView(
            image: NSImage(
                systemSymbolName: "exclamationmark.triangle",
                accessibilityDescription: "Page load error"
            ) ?? NSImage()
        )
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 34, weight: .regular)
        icon.contentTintColor = .secondaryLabelColor

        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        titleLabel.alignment = .center
        titleLabel.setAccessibilityIdentifier("BrowserErrorTitle")

        messageLabel.font = .systemFont(ofSize: NSFont.systemFontSize)
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.alignment = .center
        messageLabel.maximumNumberOfLines = 3
        messageLabel.setAccessibilityIdentifier("BrowserErrorMessage")

        hostLabel.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        hostLabel.textColor = .tertiaryLabelColor
        hostLabel.alignment = .center
        hostLabel.lineBreakMode = .byTruncatingMiddle
        hostLabel.setAccessibilityIdentifier("BrowserErrorHost")

        retryButton.bezelStyle = .rounded
        retryButton.setAccessibilityIdentifier("BrowserErrorReloadButton")

        let stack = NSStackView(views: [
            icon,
            titleLabel,
            messageLabel,
            hostLabel,
            retryButton,
        ])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.setCustomSpacing(18, after: hostLabel)
        addSubview(stack)
        setAccessibilityChildren([
            titleLabel,
            messageLabel,
            hostLabel,
            retryButton,
        ])

        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 40),
            icon.heightAnchor.constraint(equalToConstant: 40),
            messageLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 520),
            hostLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 520),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -20),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 40),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -40),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func update(
        title: String,
        message: String,
        host: String?,
        recoveryActionTitle: String?
    ) {
        titleLabel.stringValue = title
        messageLabel.stringValue = message
        hostLabel.stringValue = host ?? ""
        hostLabel.isHidden = host?.isEmpty != false
        retryButton.title = recoveryActionTitle ?? "Try Again"
        retryButton.isHidden = recoveryActionTitle == nil
        setAccessibilityLabel(title)
        setAccessibilityHelp(message)
    }
}
