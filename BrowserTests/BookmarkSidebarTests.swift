import AppKit
import WebKit
import XCTest
@testable import Browser

@MainActor
final class BookmarkSidebarTests: XCTestCase {
    func testSidebarActivationOpensForegroundTabsAndPreservesSourcePage() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = BookmarkRepository(directoryURL: directory)
        let destinationURL = Phase1Fixture.url("/phase2/page-b").absoluteURL
        _ = try await repository.add(url: destinationURL, title: "Page B")
        let controller = BrowserWindowController()
        defer { controller.window?.close() }
        let chrome = try XCTUnwrap(controller.window?.contentView as? BrowserChromeView)
        controller.startBookmarks(repository: repository)
        controller.installWebViews(
            profile: BrowserProfile(dataStoreIdentifier: UUID()), viewCount: 1,
            initialURL: Phase1Fixture.url("/phase2/page-a")
        )
        let source = try XCTUnwrap(controller.webView)
        let sourceID = controller.selectedTabID
        try await wait { source.url != nil && !source.isLoading && chrome.bookmarkSidebar.tableView.numberOfRows == 1 }
        chrome.layoutSubtreeIfNeeded()
        let table = chrome.bookmarkSidebar.tableView
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        XCTAssertEqual(controller.tabCount, 1, "Selecting a row must not navigate")

        // Dispatch the configured single-click action using the row metadata
        // AppKit supplies, without posting mouse input to the desktop.
        XCTAssertTrue(NSApp.sendAction(
            try XCTUnwrap(table.action), to: table.target,
            from: SidebarClickSender(row: 0)
        ))
        XCTAssertEqual(controller.tabCount, 2)
        XCTAssertNotEqual(controller.selectedTabID, sourceID)
        let destination = try XCTUnwrap(controller.webView)
        try await wait { destination.url == destinationURL && !destination.isLoading }
        XCTAssertEqual(source.url, Phase1Fixture.url("/phase2/page-a").absoluteURL)
        XCTAssertTrue(source.configuration.websiteDataStore === destination.configuration.websiteDataStore)
        XCTAssertTrue(NSApp.sendAction(
            try XCTUnwrap(table.action), to: table.target,
            from: SidebarClickSender(row: -1)
        ))
        XCTAssertEqual(controller.tabCount, 2, "Clicking below the rows must not reopen the selection")

        // Reopening the selected bookmark should make another tab.
        table.keyDown(with: try keyEvent(36, characters: "\r", in: controller.window))
        XCTAssertEqual(controller.tabCount, 3)
        controller.selectTab(id: sourceID)
        XCTAssertTrue(controller.webView === source)
        XCTAssertFalse(try XCTUnwrap(controller.window).isVisible)
    }

    func testLocalSidebarBookmarkRequestsANewGrantAndRejectsStaleApproval() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("index.html")
        try Data("<html><title>Sidebar local page</title><body>Local page</body></html>".utf8).write(to: file)
        let authorizer = SidebarLocalFileAuthorizer()
        let controller = BrowserWindowController(localFileAccessAuthorizer: authorizer)
        defer { controller.window?.close() }
        controller.installWebViews(
            profile: BrowserProfile(dataStoreIdentifier: UUID()), viewCount: 1,
            initialURL: Phase1Fixture.url("/phase2/page-a")
        )
        let sourceID = controller.selectedTabID
        let source = try XCTUnwrap(controller.webView)
        try await wait { source.url != nil && !source.isLoading }

        controller.openBookmarkInNewTab(file)
        XCTAssertEqual(controller.tabCount, 2)
        XCTAssertEqual(authorizer.requests, [file])
        authorizer.resolve(directory)
        try await wait { controller.webView?.title == "Sidebar local page" && controller.webView?.isLoading == false }
        let localID = controller.selectedTabID
        let localView = try XCTUnwrap(controller.webView)

        controller.openBookmarkInNewTab(file)
        XCTAssertEqual(controller.tabCount, 3)
        XCTAssertEqual(authorizer.requests.count, 2, "A new tab cannot inherit another tab's folder grant")
        let pendingLocalID = controller.selectedTabID
        controller.selectTab(id: sourceID)
        authorizer.resolve(directory)
        XCTAssertTrue(controller.webView === source)
        controller.selectTab(id: pendingLocalID)
        XCTAssertFalse(controller.webView?.url?.isFileURL ?? false, "Approval after leaving its tab is stale")
        controller.selectTab(id: localID)
        XCTAssertTrue(controller.webView === localView)
        XCTAssertEqual(localView.title, "Sidebar local page")

        controller.openBookmarkInNewTab(file)
        authorizer.resolve(nil)
        XCTAssertFalse(controller.webView?.url?.isFileURL ?? false)
        XCTAssertFalse(try XCTUnwrap(controller.window).isVisible)
    }

    func testInvalidBookmarkDoesNotCreateTab() throws {
        let controller = BrowserWindowController()
        defer { controller.window?.close() }
        for address in ["javascript:alert(1)", "file:///tmp/not-html.txt", "https://user:password@example.com"] {
            controller.openBookmarkInNewTab(try XCTUnwrap(URL(string: address)))
            XCTAssertEqual(controller.tabCount, 1)
            XCTAssertNil(controller.pendingNavigationURL)
        }
    }

    func testVisibilityPersistsAndHidingReturnsFocusAndPageWidth() throws {
        let suite = "SidebarPreferencesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = BrowserWindowController(preferences: defaults)
        defer { controller.window?.close() }
        let chrome = try XCTUnwrap(controller.window?.contentView as? BrowserChromeView)
        XCTAssertTrue(chrome.isBookmarkSidebarVisible)
        chrome.layoutSubtreeIfNeeded()
        let originalWidth = chrome.pageContainer.frame.width
        XCTAssertTrue(controller.window?.makeFirstResponder(chrome.bookmarkSidebar.tableView) == true)
        chrome.sidebarButton.performClick(nil)
        chrome.layoutSubtreeIfNeeded()
        XCTAssertTrue(chrome.bookmarkSidebar.isHidden)
        XCTAssertEqual(chrome.pageContainer.frame.width, originalWidth + 224, accuracy: 1)
        XCTAssertFalse(controller.window?.firstResponder === chrome.bookmarkSidebar.tableView)

        let reopened = BrowserWindowController(preferences: defaults)
        defer { reopened.window?.close() }
        let reopenedChrome = try XCTUnwrap(reopened.window?.contentView as? BrowserChromeView)
        XCTAssertFalse(reopenedChrome.isBookmarkSidebarVisible)
        let menu = NSMenuItem(title: "", action: #selector(BrowserWindowController.toggleBookmarkSidebar(_:)), keyEquivalent: "")
        XCTAssertTrue(reopened.validateMenuItem(menu))
        XCTAssertEqual(menu.title, "Show Bookmarks Sidebar")
        reopened.toggleBookmarkSidebar(nil)
        XCTAssertTrue(BrowserPreferences.bookmarkSidebarVisible(in: defaults))
        XCTAssertTrue(reopened.validateMenuItem(menu))
        XCTAssertEqual(menu.title, "Hide Bookmarks Sidebar")
        XCTAssertFalse(try XCTUnwrap(reopened.window).isVisible)
    }

    func testCoordinatorMutationsUpdateRowsAndPreserveSelectionWithoutOpening() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let coordinator = BookmarkCoordinator(repository: BookmarkRepository(directoryURL: directory))
        defer { coordinator.cancel() }
        let sidebar = BookmarkSidebarView()
        coordinator.onStateChange = { sidebar.update(state: $0, canManage: true) }
        var opened: [Bookmark] = []
        sidebar.onOpen = { opened.append($0) }
        coordinator.start(resetOnLaunch: false)
        try await wait { if case .ready = coordinator.state { return true }; return false }
        let firstURL = try XCTUnwrap(URL(string: "https://example.com/first"))
        coordinator.add(url: firstURL, title: "First")
        try await wait { sidebar.tableView.numberOfRows == 1 }
        let first = try XCTUnwrap(coordinator.bookmarks.first)
        sidebar.tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        coordinator.add(url: try XCTUnwrap(URL(string: "https://example.com/second")), title: "Second")
        try await wait { sidebar.tableView.numberOfRows == 2 }
        sidebar.tableView.keyDown(with: try keyEvent(125, characters: "\u{F701}"))
        XCTAssertEqual(sidebar.tableView.selectedRow, 1)
        sidebar.tableView.keyDown(with: try keyEvent(126, characters: "\u{F700}"))
        XCTAssertEqual(sidebar.tableView.selectedRow, 0)
        let updatedURL = try XCTUnwrap(URL(string: "https://example.com/edited"))
        coordinator.update(id: first.id, url: updatedURL, title: "Edited")
        try await wait { coordinator.bookmarks.first(where: { $0.id == first.id })?.title == "Edited" }
        XCTAssertTrue(opened.isEmpty, "Refresh and selection changes must not open tabs")
        sidebar.tableView.keyDown(with: try keyEvent(36, characters: "\r"))
        XCTAssertEqual(opened.last?.url, updatedURL)
        XCTAssertEqual(opened.last?.title, "Edited")
        coordinator.delete(id: first.id)
        try await wait { sidebar.tableView.numberOfRows == 1 }
        sidebar.tableView.keyDown(with: try keyEvent(36, characters: "\r"))
        XCTAssertEqual(opened.count, 1, "Deleting the selected bookmark clears selection")
    }

    func testRecoveryLoadingAndFailureClearStaleRowsAndKeepManagementAvailable() throws {
        let sidebar = BookmarkSidebarView()
        let bookmark = sampleBookmark("Recovered page", url: "https://example.com/recovered")
        let recovery = BookmarkRecovery(
            reason: .corruptPrimary,
            backupFileURL: URL(fileURLWithPath: "/tmp/sidebar-backup.json"),
            preservedPrimaryFileURL: nil
        )
        sidebar.update(state: .ready(.init(bookmarks: [bookmark], recovery: recovery)), canManage: true)
        var opened: [Bookmark] = []
        sidebar.onOpen = { opened.append($0) }
        sidebar.tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        sidebar.tableView.keyDown(with: try keyEvent(36, characters: "\r"))
        XCTAssertEqual(opened, [bookmark], "Recovered bookmarks remain openable")
        let banner = try XCTUnwrap(sidebar.subviewsDeep.first { $0.accessibilityIdentifier() == "BrowserSidebarRecovery" })
        XCTAssertFalse(banner.isHidden)
        for state: BookmarkCoordinator.State in [.loading, .failed("Fixture error"), .ready(.init(bookmarks: [], recovery: nil))] {
            sidebar.update(state: state, canManage: true)
            XCTAssertEqual(sidebar.tableView.numberOfRows, 0)
            sidebar.tableView.keyDown(with: try keyEvent(36, characters: "\r"))
            XCTAssertEqual(opened.count, 1)
            XCTAssertTrue(sidebar.manageButton.isEnabled)
            XCTAssertTrue(banner.isHidden)
        }
        var manageCount = 0
        sidebar.onManage = { manageCount += 1 }
        sidebar.manageButton.performClick(nil)
        XCTAssertEqual(manageCount, 1)
    }

    func testNativeLayoutLongListAndAppearanceAttachments() throws {
        let controller = BrowserWindowController()
        defer { controller.window?.close() }
        let window = try XCTUnwrap(controller.window)
        let chrome = try XCTUnwrap(window.contentView as? BrowserChromeView)
        chrome.setBookmarkSidebarVisible(true)
        let names = ["Hacker News", "GitHub", "Local HTML notes", "A much longer bookmark title that needs to truncate gracefully"]
        let bookmarks = (0..<40).map {
            sampleBookmark(names[$0 % names.count], url: $0 == 2 ? "file:///tmp/notes.html" : "https://example.com/page/\($0)")
        }
        chrome.bookmarkSidebar.update(state: .ready(.init(bookmarks: bookmarks, recovery: nil)), canManage: true)
        for (name, size) in [
            ("Light", NSSize(width: 1100, height: 720)),
            ("Dark", NSSize(width: 1100, height: 720)),
            ("Minimum", NSSize(width: 460, height: 300)),
        ] {
            chrome.appearance = NSAppearance(named: name == "Dark" ? .darkAqua : .aqua)
            window.setContentSize(size)
            chrome.layoutSubtreeIfNeeded()
            XCTAssertEqual(chrome.bookmarkSidebar.frame.width, 224, accuracy: 1)
            XCTAssertEqual(chrome.pageContainer.frame.minX, 224, accuracy: 1)
            XCTAssertEqual(chrome.pageContainer.frame.maxX, size.width, accuracy: 1)
            XCTAssertFalse(chrome.hasAmbiguousLayout)
            let table = chrome.bookmarkSidebar.tableView
            XCTAssertEqual(table.numberOfRows, 40)
            table.scrollRowToVisible(39)
            XCTAssertTrue(table.rows(in: table.visibleRect).contains(39))
            table.scrollRowToVisible(0)
            let cell = try XCTUnwrap(table.view(atColumn: 0, row: 3, makeIfNecessary: true) as? NSTableCellView)
            XCTAssertEqual(cell.textField?.stringValue, names[3])
            XCTAssertTrue(cell.toolTip?.contains("https://example.com/page/3") == true)
            XCTAssertLessThanOrEqual(try XCTUnwrap(cell.textField).frame.maxX, cell.bounds.maxX)
            let bitmap = try XCTUnwrap(chrome.bitmapImageRepForCachingDisplay(in: chrome.bounds))
            chrome.cacheDisplay(in: chrome.bounds, to: bitmap)
            let image = NSImage(size: chrome.bounds.size)
            image.addRepresentation(bitmap)
            let attachment = XCTAttachment(image: image)
            attachment.name = "Bookmarks Sidebar \(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        XCTAssertFalse(window.isVisible)
    }

    private func sampleBookmark(_ title: String, url: String) -> Bookmark {
        try! Bookmark(id: UUID(), url: URL(string: url)!, title: title, createdAt: Date(), updatedAt: Date())
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SidebarTests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func keyEvent(_ key: UInt16, characters: String, in window: NSWindow? = nil) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window?.windowNumber ?? 0, context: nil,
            characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: key
        ))
    }

    private func wait(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(condition(), "Timed out waiting for sidebar state or navigation")
        if !condition() { throw WebViewTestError.loadDidNotStart }
    }
}

@MainActor
private final class SidebarClickSender: NSTableView {
    private let row: Int
    override var clickedRow: Int { row }

    init(row: Int) {
        self.row = row
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
}

@MainActor
private final class SidebarLocalFileAuthorizer: LocalFileAccessAuthorizing {
    var requests: [URL] = []
    private var completion: (@MainActor (URL?) -> Void)?

    func requestAccess(
        toContainingDirectoryOf fileURL: URL, from window: NSWindow,
        completion: @escaping @MainActor (URL?) -> Void
    ) {
        requests.append(fileURL)
        self.completion = completion
    }

    func cancel() { completion = nil }

    func resolve(_ url: URL?) {
        let callback = completion
        completion = nil
        callback?(url)
    }
}

private extension NSView {
    var subviewsDeep: [NSView] {
        subviews.flatMap { [$0] + $0.subviewsDeep }
    }
}
