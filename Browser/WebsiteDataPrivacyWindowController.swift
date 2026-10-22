import AppKit

@MainActor
final class WebsiteDataPrivacyWindowController: NSWindowController,
    NSWindowDelegate,
    NSTableViewDataSource,
    NSTableViewDelegate
{
    var onResetAllSiteExceptions: (() -> Void)? {
        didSet { renderBlockingResetState() }
    }
    var onDeleteCompiledBlockingRules: (() -> Void)? {
        didSet { renderBlockingResetState() }
    }

    private let dataController: WebsiteDataController
    private let searchField = NSSearchField()
    private let modeControl = NSSegmentedControl(
        labels: ["Cookies", "Website Data"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let refreshButton = NSButton(
        title: "Refresh",
        target: nil,
        action: nil
    )
    private let dataStatusLabel = NSTextField(wrappingLabelWithString: "")
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let emptyLabel = NSTextField(wrappingLabelWithString: "")
    private let detailLabel = NSTextField(wrappingLabelWithString: "")
    private let cookieValueLabel = NSTextField(labelWithString: "")
    private let revealCookieButton = NSButton(
        title: "Reveal Value",
        target: nil,
        action: nil
    )
    private let cookieValueStack = NSStackView()
    private let deleteCookieButton = NSButton(
        title: "Delete Cookie…",
        target: nil,
        action: nil
    )
    private let deleteDomainCookiesButton = NSButton(
        title: "Delete Domain Cookies…",
        target: nil,
        action: nil
    )
    private let deleteAllCookiesButton = NSButton(
        title: "Delete All Cookies…",
        target: nil,
        action: nil
    )
    private let deleteWebsiteDataButton = NSButton(
        title: "Delete Selected Website Data…",
        target: nil,
        action: nil
    )
    private let deleteAllWebsiteDataButton = NSButton(
        title: "Delete All Website Data…",
        target: nil,
        action: nil
    )
    private let blockingStatusLabel = NSTextField(wrappingLabelWithString: "")
    private let blockingResultLabel = NSTextField(wrappingLabelWithString: "")
    private let resetSiteExceptionsButton = NSButton(
        title: "Reset Site Exceptions…",
        target: nil,
        action: nil
    )
    private let deleteCompiledRulesButton = NSButton(
        title: "Delete Compiled Blocking Rules…",
        target: nil,
        action: nil
    )
    private let doneButton = NSButton(title: "Done", target: nil, action: nil)

    private var snapshot = WebsiteDataSnapshot.empty
    private var rows: [Row] = []
    private var selectedRowID: RowID?
    private var revealedCookieID: WebsiteCookieID?
    private var hasLoadedSnapshot = false
    private var websiteDataIsBusy = false
    private var operationGeneration: UInt = 0
    private var operationTask: Task<Void, Never>?
    private var operationKind: OperationKind?

    private var exceptionCount = 0
    private var canResetCompiledArtifacts = false
    private var blockingResetIsBusy = false
    private var blockingResultMessage: String?

    init(dataController: WebsiteDataController) {
        self.dataController = dataController

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Privacy"
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.contentMinSize = NSSize(width: 720, height: 720)
        window.identifier = NSUserInterfaceItemIdentifier("BrowserPrivacyWindow")
        window.setAccessibilityIdentifier("BrowserPrivacyWindow")

        super.init(window: window)
        window.delegate = self
        configureContent(in: window)
        renderSnapshot(statusMessage: "Website data has not been loaded yet.")
        renderBlockingResetState()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func showWindow(_ sender: Any?) {
        let wasVisible = window?.isVisible == true
        super.showWindow(sender)
        if !wasVisible {
            window?.center()
            refresh()
        }
        window?.makeKeyAndOrderFront(sender)
        window?.makeFirstResponder(searchField)
    }

    func windowWillClose(_ notification: Notification) {
        if operationKind == .refresh {
            operationGeneration &+= 1
            operationTask?.cancel()
            operationTask = nil
            operationKind = nil
            websiteDataIsBusy = false
        }
        revealedCookieID = nil
        scrubCookieValue()
    }

    func refresh() {
        guard operationKind != .mutation else {
            return
        }
        beginRefresh(statusMessage: "Refreshing website data…")
    }

    func updateBlockingResetState(
        exceptionCount: Int,
        canResetCompiledArtifacts: Bool,
        isBusy: Bool,
        statusMessage: String?
    ) {
        self.exceptionCount = max(0, exceptionCount)
        self.canResetCompiledArtifacts = canResetCompiledArtifacts
        blockingResetIsBusy = isBusy
        blockingResultMessage = statusMessage
        renderButtons()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard rows.indices.contains(row) else {
            return nil
        }
        let identifier = NSUserInterfaceItemIdentifier("PrivacyListCell")
        let cell = tableView.makeView(
            withIdentifier: identifier,
            owner: self
        ) as? WebsiteDataPrivacyListCell
            ?? WebsiteDataPrivacyListCell(identifier: identifier)

        switch rows[row] {
        case let .cookieDomain(domain):
            cell.update(
                title: domain.domain,
                detail: Self.cookieCountDescription(domain.cookies.count),
                indentation: 0,
                isGroup: true,
                accessibilityIdentifier: "BrowserPrivacyCookieDomainRow."
                    + Self.accessibilityToken(domain.domain),
                accessibilityHelp: "Exact cookie domain"
            )
        case let .cookie(cookie):
            cell.update(
                title: cookie.name,
                detail: Self.cookieListDetail(cookie),
                indentation: 18,
                isGroup: false,
                accessibilityIdentifier: "BrowserPrivacyCookieRow."
                    + cookie.id.accessibilityToken,
                accessibilityHelp: "Cookie metadata. Select to inspect or delete."
            )
        case let .record(record):
            cell.update(
                title: record.displayName,
                detail: record.categories.map(\.displayName).joined(separator: ", "),
                indentation: 0,
                isGroup: true,
                accessibilityIdentifier: "BrowserPrivacyWebsiteDataRow."
                    + record.id.accessibilityToken,
                accessibilityHelp: "WebKit website-data record grouped by public suffix rules"
            )
        }
        return cell
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard rows.indices.contains(row) else {
            return 44
        }
        switch rows[row] {
        case .cookieDomain:
            return 38
        case .cookie, .record:
            return 50
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        selectedRowID = rows.indices.contains(row) ? rows[row].id : nil
        revealedCookieID = nil
        renderSelection()
        renderButtons()
    }

    private func configureContent(in window: NSWindow) {
        guard let contentView = window.contentView else {
            return
        }
        contentView.setAccessibilityIdentifier("BrowserPrivacyView")

        let headingLabel = NSTextField(labelWithString: "Website Data")
        headingLabel.font = .systemFont(ofSize: 22, weight: .semibold)

        let explanationLabel = NSTextField(
            wrappingLabelWithString: "Browser does not keep a visit history. Websites can still store cookies, caches, local storage, databases, and service workers in this separate WebKit profile. Cookie-only actions leave other website data intact. Full website-data actions can sign you out, and an open page may recreate data after deletion."
        )
        explanationLabel.textColor = .secondaryLabelColor
        explanationLabel.maximumNumberOfLines = 4
        explanationLabel.setAccessibilityIdentifier("BrowserPrivacyExplanation")

        searchField.placeholderString = "Search domains, cookie names, paths, or categories"
        searchField.sendsSearchStringImmediately = true
        searchField.target = self
        searchField.action = #selector(searchChanged(_:))
        searchField.setAccessibilityIdentifier("BrowserPrivacySearchField")
        searchField.setAccessibilityLabel("Search website data")

        modeControl.selectedSegment = 0
        modeControl.target = self
        modeControl.action = #selector(modeChanged(_:))
        modeControl.setAccessibilityIdentifier("BrowserPrivacyDataMode")
        modeControl.setAccessibilityLabel("Website data category")

        configureButton(
            refreshButton,
            action: #selector(refreshData(_:)),
            identifier: "BrowserPrivacyRefreshButton"
        )
        let searchRow = NSStackView(views: [searchField, modeControl, refreshButton])
        searchRow.orientation = .horizontal
        searchRow.alignment = .centerY
        searchRow.spacing = 8
        searchField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        dataStatusLabel.textColor = .secondaryLabelColor
        dataStatusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        dataStatusLabel.maximumNumberOfLines = 2
        dataStatusLabel.setAccessibilityIdentifier("BrowserPrivacyStatus")

        let column = NSTableColumn(
            identifier: NSUserInterfaceItemIdentifier("WebsiteData")
        )
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.setAccessibilityIdentifier("BrowserPrivacyDataList")
        tableView.setAccessibilityLabel("Stored website data")

        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = tableView

        emptyLabel.alignment = .center
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.font = .systemFont(ofSize: 15)
        emptyLabel.maximumNumberOfLines = 3
        emptyLabel.setAccessibilityIdentifier("BrowserPrivacyEmptyState")

        detailLabel.maximumNumberOfLines = 5
        detailLabel.setAccessibilityIdentifier("BrowserPrivacySelectionDetail")

        let cookieValueTitle = NSTextField(labelWithString: "Value:")
        cookieValueTitle.font = .systemFont(
            ofSize: NSFont.systemFontSize,
            weight: .medium
        )
        cookieValueLabel.lineBreakMode = .byTruncatingMiddle
        cookieValueLabel.setAccessibilityIdentifier("BrowserPrivacyCookieValue")
        cookieValueLabel.setAccessibilityLabel("Cookie value")
        cookieValueLabel.stringValue = WebsiteCookieSnapshot.maskedValue
        configureButton(
            revealCookieButton,
            action: #selector(toggleCookieValueReveal(_:)),
            identifier: "BrowserPrivacyRevealCookieButton"
        )
        cookieValueStack.orientation = .horizontal
        cookieValueStack.alignment = .centerY
        cookieValueStack.spacing = 8
        cookieValueStack.addArrangedSubview(cookieValueTitle)
        cookieValueStack.addArrangedSubview(cookieValueLabel)
        cookieValueStack.addArrangedSubview(revealCookieButton)
        cookieValueLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        configureButton(
            deleteCookieButton,
            action: #selector(confirmDeleteCookie(_:)),
            identifier: "BrowserPrivacyDeleteCookieButton"
        )
        configureButton(
            deleteDomainCookiesButton,
            action: #selector(confirmDeleteDomainCookies(_:)),
            identifier: "BrowserPrivacyDeleteDomainCookiesButton"
        )
        configureButton(
            deleteAllCookiesButton,
            action: #selector(confirmDeleteAllCookies(_:)),
            identifier: "BrowserPrivacyDeleteAllCookiesButton"
        )
        configureButton(
            deleteWebsiteDataButton,
            action: #selector(confirmDeleteWebsiteData(_:)),
            identifier: "BrowserPrivacyDeleteSiteDataButton"
        )
        configureButton(
            deleteAllWebsiteDataButton,
            action: #selector(confirmDeleteAllWebsiteData(_:)),
            identifier: "BrowserPrivacyDeleteAllWebsiteDataButton"
        )
        for button in [
            deleteCookieButton,
            deleteDomainCookiesButton,
            deleteAllCookiesButton,
            deleteWebsiteDataButton,
            deleteAllWebsiteDataButton,
        ] {
            button.contentTintColor = .systemRed
        }

        let cookieActionRow = NSStackView(views: [
            deleteCookieButton,
            deleteDomainCookiesButton,
            deleteAllCookiesButton,
        ])
        cookieActionRow.orientation = .horizontal
        cookieActionRow.alignment = .centerY
        cookieActionRow.spacing = 8
        let websiteDataActionRow = NSStackView(views: [
            deleteWebsiteDataButton,
            deleteAllWebsiteDataButton,
        ])
        websiteDataActionRow.orientation = .horizontal
        websiteDataActionRow.alignment = .centerY
        websiteDataActionRow.spacing = 8

        let blockerHeading = NSTextField(
            labelWithString: "Ad & Tracker Blocking"
        )
        blockerHeading.font = .systemFont(ofSize: 16, weight: .semibold)
        blockingStatusLabel.maximumNumberOfLines = 2
        blockingStatusLabel.textColor = .secondaryLabelColor
        blockingStatusLabel.setAccessibilityIdentifier(
            "BrowserPrivacyBlockingResetStatus"
        )
        blockingResultLabel.maximumNumberOfLines = 2
        blockingResultLabel.textColor = .secondaryLabelColor
        blockingResultLabel.setAccessibilityIdentifier(
            "BrowserPrivacyBlockingResetResult"
        )
        configureButton(
            resetSiteExceptionsButton,
            action: #selector(confirmResetSiteExceptions(_:)),
            identifier: "BrowserPrivacyResetSiteExceptionsButton"
        )
        configureButton(
            deleteCompiledRulesButton,
            action: #selector(confirmDeleteCompiledRules(_:)),
            identifier: "BrowserPrivacyDeleteCompiledRulesButton"
        )
        resetSiteExceptionsButton.contentTintColor = .systemRed
        deleteCompiledRulesButton.contentTintColor = .systemRed
        let blockingButtonRow = NSStackView(views: [
            resetSiteExceptionsButton,
            deleteCompiledRulesButton,
        ])
        blockingButtonRow.orientation = .horizontal
        blockingButtonRow.alignment = .centerY
        blockingButtonRow.spacing = 8

        configureButton(
            doneButton,
            action: #selector(closeWindow(_:)),
            identifier: "BrowserPrivacyDoneButton"
        )
        doneButton.keyEquivalent = "\u{1b}"
        let doneSpacer = NSView()
        doneSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let doneRow = NSStackView(views: [doneSpacer, doneButton])
        doneRow.orientation = .horizontal
        doneRow.alignment = .centerY

        let separator = NSBox()
        separator.boxType = .separator

        let rootStack = NSStackView(views: [
            headingLabel,
            explanationLabel,
            searchRow,
            dataStatusLabel,
            scrollView,
            detailLabel,
            cookieValueStack,
            cookieActionRow,
            websiteDataActionRow,
            separator,
            blockerHeading,
            blockingStatusLabel,
            blockingResultLabel,
            blockingButtonRow,
            doneRow,
        ])
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 8
        contentView.addSubview(rootStack)

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(emptyLabel)

        for view in [
            explanationLabel,
            searchRow,
            dataStatusLabel,
            scrollView,
            detailLabel,
            cookieValueStack,
            cookieActionRow,
            websiteDataActionRow,
            separator,
            blockerHeading,
            blockingStatusLabel,
            blockingResultLabel,
            blockingButtonRow,
            doneRow,
        ] {
            view.widthAnchor.constraint(equalTo: rootStack.widthAnchor).isActive = true
        }

        NSLayoutConstraint.activate([
            rootStack.topAnchor.constraint(
                equalTo: contentView.topAnchor,
                constant: 16
            ),
            rootStack.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: 18
            ),
            rootStack.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor,
                constant: -18
            ),
            rootStack.bottomAnchor.constraint(
                lessThanOrEqualTo: contentView.bottomAnchor,
                constant: -14
            ),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 230),
            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            emptyLabel.widthAnchor.constraint(
                lessThanOrEqualTo: scrollView.widthAnchor,
                constant: -48
            ),
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
        rebuildRows(preservingSelection: true)
    }

    @objc
    private func modeChanged(_ sender: NSSegmentedControl) {
        selectedRowID = nil
        revealedCookieID = nil
        rebuildRows(preservingSelection: false)
    }

    @objc
    private func refreshData(_ sender: Any?) {
        refresh()
    }

    @objc
    private func toggleCookieValueReveal(_ sender: Any?) {
        guard let cookie = selectedCookie else {
            return
        }
        revealedCookieID = revealedCookieID == cookie.id ? nil : cookie.id
        renderSelection()
    }

    @objc
    private func confirmDeleteCookie(_ sender: Any?) {
        guard let cookie = selectedCookie else {
            return
        }
        confirmDestructiveAction(
            message: "Delete cookie “\(cookie.name)”?",
            informativeText: "Only this cookie for \(cookie.id.domain) will be deleted. Caches and other website data will remain.",
            confirmTitle: "Delete Cookie"
        ) { [weak self] in
            self?.performMutation(statusMessage: "Deleting cookie…") {
                await $0.deleteCookie(withID: cookie.id)
            }
        }
    }

    @objc
    private func confirmDeleteDomainCookies(_ sender: Any?) {
        guard let domain = selectedCookieDomain else {
            return
        }
        confirmDestructiveAction(
            message: "Delete all cookies for \(domain)?",
            informativeText: "This uses the exact cookie domain shown. Caches, local storage, databases, and service workers will remain.",
            confirmTitle: "Delete Domain Cookies"
        ) { [weak self] in
            self?.performMutation(statusMessage: "Deleting domain cookies…") {
                await $0.deleteCookies(exactDomain: domain)
            }
        }
    }

    @objc
    private func confirmDeleteAllCookies(_ sender: Any?) {
        confirmDestructiveAction(
            message: "Delete all cookies?",
            informativeText: "This can sign you out of websites. Other WebKit website data will remain.",
            confirmTitle: "Delete All Cookies"
        ) { [weak self] in
            self?.performMutation(statusMessage: "Deleting all cookies…") {
                await $0.clearAllCookiesAndVerify()
            }
        }
    }

    @objc
    private func confirmDeleteWebsiteData(_ sender: Any?) {
        guard let record = selectedWebsiteDataRecord else {
            return
        }
        confirmDestructiveAction(
            message: "Delete website data for \(record.displayName)?",
            informativeText: "WebKit groups this record using public suffix rules. This full-data action removes every reported category for the record and may remove cookies and sign-ins.",
            confirmTitle: "Delete Website Data"
        ) { [weak self] in
            self?.performMutation(statusMessage: "Deleting website data…") {
                await $0.deleteWebsiteData(for: record.id)
            }
        }
    }

    @objc
    private func confirmDeleteAllWebsiteData(_ sender: Any?) {
        confirmDestructiveAction(
            message: "Delete all WebKit website data?",
            informativeText: "This removes cookies, caches, local storage, databases, service workers, and every other WebKit-exposed website-data category. It can sign you out of all websites. Bookmarks and Browser settings remain.",
            confirmTitle: "Delete All Website Data"
        ) { [weak self] in
            self?.performMutation(statusMessage: "Deleting all website data…") {
                await $0.clearAllWebsiteDataAndVerify()
            }
        }
    }

    @objc
    private func confirmResetSiteExceptions(_ sender: Any?) {
        guard
            exceptionCount > 0,
            !blockingResetIsBusy,
            onResetAllSiteExceptions != nil
        else {
            return
        }
        confirmDestructiveAction(
            message: "Reset all ad and tracker blocking exceptions?",
            informativeText: "Blocking will be enabled again for every exact host where you explicitly disabled it.",
            confirmTitle: "Reset Site Exceptions"
        ) { [weak self] in
            self?.onResetAllSiteExceptions?()
        }
    }

    @objc
    private func confirmDeleteCompiledRules(_ sender: Any?) {
        guard canResetCompiledArtifacts,
              !blockingResetIsBusy,
              onDeleteCompiledBlockingRules != nil
        else {
            return
        }
        confirmDestructiveAction(
            message: "Delete compiled blocking rules?",
            informativeText: "Browser will delete its locally compiled blocker artifacts. Current pages stay protected in memory; the pinned rules remain in the signed app and rebuild locally on the next launch before remote navigation.",
            confirmTitle: "Delete Compiled Rules"
        ) { [weak self] in
            self?.onDeleteCompiledBlockingRules?()
        }
    }

    @objc
    private func closeWindow(_ sender: Any?) {
        close()
    }

    private func confirmDestructiveAction(
        message: String,
        informativeText: String,
        confirmTitle: String,
        action: @escaping @MainActor () -> Void
    ) {
        guard let window else {
            return
        }
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = informativeText
        alert.alertStyle = .critical
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else {
                return
            }
            action()
        }
    }

    private func beginRefresh(statusMessage: String) {
        operationGeneration &+= 1
        let generation = operationGeneration
        operationTask?.cancel()
        operationKind = .refresh
        websiteDataIsBusy = true
        revealedCookieID = nil
        scrubCookieValue()
        dataStatusLabel.textColor = .secondaryLabelColor
        dataStatusLabel.stringValue = statusMessage
        renderButtons()

        operationTask = Task { [weak self] in
            guard let self else {
                return
            }
            let refreshed = await dataController.snapshot()
            guard
                !Task.isCancelled,
                operationGeneration == generation
            else {
                return
            }
            websiteDataIsBusy = false
            hasLoadedSnapshot = true
            snapshot = refreshed
            revealedCookieID = nil
            renderSnapshot(statusMessage: Self.summary(for: refreshed))
            operationTask = nil
            operationKind = nil
        }
    }

    private func performMutation(
        statusMessage: String,
        operation: @escaping @MainActor (
            WebsiteDataController
        ) async -> WebsiteDataMutationResult
    ) {
        operationGeneration &+= 1
        let generation = operationGeneration
        operationTask?.cancel()
        operationKind = .mutation
        websiteDataIsBusy = true
        revealedCookieID = nil
        scrubCookieValue()
        dataStatusLabel.textColor = .secondaryLabelColor
        dataStatusLabel.stringValue = statusMessage
        renderButtons()

        operationTask = Task { [weak self] in
            guard let self else {
                return
            }
            let result = await operation(dataController)
            guard
                !Task.isCancelled,
                operationGeneration == generation
            else {
                return
            }
            websiteDataIsBusy = false
            hasLoadedSnapshot = true
            snapshot = result.snapshot
            revealedCookieID = nil
            selectedRowID = nil
            dataStatusLabel.textColor = result.didRemoveRequestedData
                ? .secondaryLabelColor
                : .systemOrange
            renderSnapshot(statusMessage: result.message)
            operationTask = nil
            operationKind = nil
        }
    }

    private func renderSnapshot(statusMessage: String) {
        dataStatusLabel.stringValue = statusMessage
        rebuildRows(preservingSelection: true)
        renderSelection()
        renderButtons()
    }

    private func rebuildRows(preservingSelection: Bool) {
        let previousSelection = preservingSelection ? selectedRowID : nil
        let query = searchField.stringValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
        switch selectedMode {
        case .cookies:
            rows = snapshot.cookieDomains.flatMap { domain -> [Row] in
                let domainMatches = Self.matches(domain.domain, query: query)
                let matchingCookies = domainMatches
                    ? domain.cookies
                    : domain.cookies.filter {
                        Self.cookieMatches($0, query: query)
                    }
                guard domainMatches || !matchingCookies.isEmpty || query.isEmpty
                else {
                    return []
                }
                return [.cookieDomain(domain)] + matchingCookies.map(Row.cookie)
            }
        case .websiteData:
            rows = snapshot.records
                .filter { record in
                    query.isEmpty
                        || Self.matches(record.displayName, query: query)
                        || record.categories.contains {
                            Self.matches($0.displayName, query: query)
                        }
                }
                .map(Row.record)
        }

        tableView.reloadData()
        if let previousSelection,
           let row = rows.firstIndex(where: { $0.id == previousSelection })
        {
            tableView.selectRowIndexes(
                IndexSet(integer: row),
                byExtendingSelection: false
            )
            tableView.scrollRowToVisible(row)
            selectedRowID = previousSelection
        } else {
            tableView.deselectAll(nil)
            selectedRowID = nil
            revealedCookieID = nil
        }
        renderEmptyState()
        renderSelection()
        renderButtons()
    }

    private func renderEmptyState() {
        if !hasLoadedSnapshot {
            emptyLabel.stringValue = "Loading website data…"
            emptyLabel.isHidden = false
        } else if rows.isEmpty {
            emptyLabel.stringValue = selectedMode == .cookies
                ? "No cookies match this view."
                : "No WebKit website-data records match this view."
            emptyLabel.isHidden = false
        } else {
            emptyLabel.isHidden = true
        }
    }

    private func renderSelection() {
        scrubCookieValue()
        guard let selectedRow else {
            detailLabel.stringValue = selectedMode == .cookies
                ? "Cookie domains are exact cookie scopes and are intentionally separate from WebKit’s website-data record names. Select a domain or cookie for deletion controls."
                : "WebKit groups website-data records using public suffix rules. Select a record to review its reported categories."
            cookieValueStack.isHidden = true
            return
        }

        switch selectedRow {
        case let .cookieDomain(domain):
            detailLabel.stringValue = "Exact cookie domain: \(domain.domain)\n\(Self.cookieCountDescription(domain.cookies.count)). Cookie-only deletion leaves caches and other website data intact."
            cookieValueStack.isHidden = true
        case let .cookie(cookie):
            let expiry = cookie.expiresDate?.formatted(
                date: .abbreviated,
                time: .shortened
            ) ?? "Session cookie"
            detailLabel.stringValue = [
                "Name: \(cookie.name)",
                "Domain: \(cookie.domain)",
                "Path: \(cookie.path)",
                "Expiry: \(expiry)",
                "Secure: \(Self.yesNo(cookie.isSecure))    HTTPOnly: \(Self.yesNo(cookie.isHTTPOnly))    SameSite: \(cookie.sameSitePolicy ?? "Not reported")",
            ].joined(separator: "\n")
            cookieValueStack.isHidden = false
            let isRevealed = revealedCookieID == cookie.id
            // Never assign the underlying value to an AppKit accessibility
            // object until the user explicitly reveals this selected cookie.
            cookieValueLabel.stringValue = isRevealed
                ? cookie.value
                : WebsiteCookieSnapshot.maskedValue
            cookieValueLabel.isSelectable = isRevealed
            revealCookieButton.title = isRevealed
                ? "Hide Value"
                : "Reveal Value"
            revealCookieButton.setAccessibilityLabel(
                isRevealed ? "Hide cookie value" : "Reveal cookie value"
            )
        case let .record(record):
            let categories = record.categories.map(\.displayName)
                .joined(separator: ", ")
            detailLabel.stringValue = "WebKit record: \(record.displayName)\nReported categories: \(categories)\nThis display name is grouped by WebKit using public suffix rules and is not an exact cookie-domain identity."
            cookieValueStack.isHidden = true
        }
    }

    private func renderButtons() {
        refreshButton.isEnabled = !websiteDataIsBusy
            && !blockingResetIsBusy
        deleteCookieButton.isEnabled = selectedCookie != nil
            && !websiteDataIsBusy
            && !blockingResetIsBusy
        deleteDomainCookiesButton.isEnabled = selectedCookieDomain != nil
            && !websiteDataIsBusy
            && !blockingResetIsBusy
        deleteAllCookiesButton.isEnabled = snapshot.cookieCount > 0
            && !websiteDataIsBusy
            && !blockingResetIsBusy
        deleteWebsiteDataButton.isEnabled = selectedWebsiteDataRecord != nil
            && !websiteDataIsBusy
            && !blockingResetIsBusy
        deleteAllWebsiteDataButton.isEnabled = (
            snapshot.cookieCount > 0 || !snapshot.records.isEmpty
        ) && !websiteDataIsBusy && !blockingResetIsBusy
        revealCookieButton.isEnabled = selectedCookie != nil
            && !websiteDataIsBusy
            && !blockingResetIsBusy
        renderBlockingResetState()
    }

    private func renderBlockingResetState() {
        let exceptionDescription = exceptionCount == 1
            ? "1 exact-host exception"
            : "\(exceptionCount) exact-host exceptions"
        let artifactDescription = canResetCompiledArtifacts
            ? "Compiled-rule deletion is available."
            : "Compiled-rule deletion is unavailable right now."
        blockingStatusLabel.stringValue = blockingResetIsBusy
            ? "Updating blocking data…"
            : "\(exceptionDescription). \(artifactDescription)"
        blockingResultLabel.stringValue = blockingResultMessage ?? ""
        blockingResultLabel.isHidden = blockingResultMessage == nil
        resetSiteExceptionsButton.isEnabled = exceptionCount > 0
            && !blockingResetIsBusy
            && !websiteDataIsBusy
            && onResetAllSiteExceptions != nil
        deleteCompiledRulesButton.isEnabled = canResetCompiledArtifacts
            && !blockingResetIsBusy
            && !websiteDataIsBusy
            && onDeleteCompiledBlockingRules != nil
    }

    private func scrubCookieValue() {
        cookieValueLabel.stringValue = WebsiteCookieSnapshot.maskedValue
        cookieValueLabel.isSelectable = false
        revealCookieButton.title = "Reveal Value"
        revealCookieButton.setAccessibilityLabel("Reveal cookie value")
    }

    private var selectedMode: Mode {
        Mode(rawValue: modeControl.selectedSegment) ?? .cookies
    }

    private var selectedRow: Row? {
        guard let selectedRowID else {
            return nil
        }
        return rows.first { $0.id == selectedRowID }
    }

    private var selectedCookie: WebsiteCookieSnapshot? {
        guard case let .cookie(cookie)? = selectedRow else {
            return nil
        }
        return snapshot.cookie(id: cookie.id)
    }

    private var selectedCookieDomain: String? {
        switch selectedRow {
        case let .cookieDomain(domain):
            return domain.domain
        case let .cookie(cookie):
            return cookie.id.domain
        case .record, nil:
            return nil
        }
    }

    private var selectedWebsiteDataRecord: WebsiteDataRecordSnapshot? {
        guard case let .record(record)? = selectedRow else {
            return nil
        }
        return snapshot.records.first { $0.id == record.id }
    }

    private static func summary(for snapshot: WebsiteDataSnapshot) -> String {
        let cookieDescription = snapshot.cookieCount == 1
            ? "1 cookie"
            : "\(snapshot.cookieCount) cookies"
        let domainDescription = snapshot.cookieDomains.count == 1
            ? "1 exact cookie domain"
            : "\(snapshot.cookieDomains.count) exact cookie domains"
        let recordDescription = snapshot.records.count == 1
            ? "1 WebKit website-data record"
            : "\(snapshot.records.count) WebKit website-data records"
        return "\(cookieDescription) across \(domainDescription); \(recordDescription)."
    }

    private static func cookieCountDescription(_ count: Int) -> String {
        count == 1 ? "1 cookie" : "\(count) cookies"
    }

    private static func cookieListDetail(
        _ cookie: WebsiteCookieSnapshot
    ) -> String {
        var parts = ["Path \(cookie.path)"]
        parts.append(cookie.isSessionOnly ? "Session" : "Persistent")
        if cookie.isSecure {
            parts.append("Secure")
        }
        if cookie.isHTTPOnly {
            parts.append("HTTPOnly")
        }
        if let sameSitePolicy = cookie.sameSitePolicy {
            parts.append("SameSite \(sameSitePolicy)")
        }
        return parts.joined(separator: " · ")
    }

    private static func cookieMatches(
        _ cookie: WebsiteCookieSnapshot,
        query: String
    ) -> Bool {
        // Values are deliberately excluded so a masked secret cannot become a
        // searchable or accessibility-visible field by accident.
        [
            cookie.name,
            cookie.domain,
            cookie.path,
            cookie.sameSitePolicy ?? "",
            cookie.isSessionOnly ? "session" : "persistent",
            cookie.isSecure ? "secure" : "",
            cookie.isHTTPOnly ? "httponly" : "",
        ].contains { matches($0, query: query) }
    }

    private static func matches(_ text: String, query: String) -> Bool {
        query.isEmpty
            || text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive])
                != nil
    }

    private static func yesNo(_ value: Bool) -> String {
        value ? "Yes" : "No"
    }

    private static func accessibilityToken(_ value: String) -> String {
        Data(value.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension WebsiteDataPrivacyWindowController {
    enum OperationKind {
        case refresh
        case mutation
    }

    enum Mode: Int {
        case cookies = 0
        case websiteData = 1
    }

    enum RowID: Equatable {
        case cookieDomain(String)
        case cookie(WebsiteCookieID)
        case record(WebsiteDataRecordID)
    }

    enum Row: Equatable {
        case cookieDomain(WebsiteCookieDomainSnapshot)
        case cookie(WebsiteCookieSnapshot)
        case record(WebsiteDataRecordSnapshot)

        var id: RowID {
            switch self {
            case let .cookieDomain(domain):
                return .cookieDomain(domain.domain)
            case let .cookie(cookie):
                return .cookie(cookie.id)
            case let .record(record):
                return .record(record.id)
            }
        }
    }
}

@MainActor
private final class WebsiteDataPrivacyListCell: NSTableCellView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let stack = NSStackView()
    private var leadingConstraint: NSLayoutConstraint!

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        titleLabel.lineBreakMode = .byTruncatingTail
        detailLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(detailLabel)
        addSubview(stack)

        leadingConstraint = stack.leadingAnchor.constraint(
            equalTo: leadingAnchor,
            constant: 8
        )
        NSLayoutConstraint.activate([
            leadingConstraint,
            stack.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingAnchor,
                constant: -8
            ),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func update(
        title: String,
        detail: String,
        indentation: CGFloat,
        isGroup: Bool,
        accessibilityIdentifier: String,
        accessibilityHelp: String
    ) {
        titleLabel.stringValue = title
        titleLabel.font = .systemFont(
            ofSize: NSFont.systemFontSize,
            weight: isGroup ? .semibold : .regular
        )
        detailLabel.stringValue = detail
        leadingConstraint.constant = 8 + indentation
        setAccessibilityIdentifier(accessibilityIdentifier)
        setAccessibilityLabel(title)
        setAccessibilityHelp(accessibilityHelp)
    }
}
