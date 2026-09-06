import AppKit
import XCTest
@testable import Browser

@MainActor
final class BrowserLaunchConfigurationTests: XCTestCase {
    func testBackgroundHostStartsWithoutApplicationServicesOrWindows() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, BrowserLaunchConfiguration.testBundleIdentifier)
        XCTAssertEqual(BrowserLaunchConfiguration.current.mode, .backgroundTests)
        XCTAssertEqual(NSApp.activationPolicy(), .prohibited)
        XCTAssertFalse(NSApp.windows.contains(where: \.isVisible))
        XCTAssertFalse(BrowserLaunchConfiguration.current.startsApplication)
    }

    func testIsolatedCompiledRuleStoreCanBeOpenedWithoutProductionFallback() async throws {
        let store = BrowserLaunchConfiguration.current.makeContentRuleListStore()
        let identifiers = await store.availableIdentifiers()
        XCTAssertNotNil(identifiers)
    }

    func testSearchProviderActionLeavesDisposableProductionSentinelUnchanged() throws {
        let sentinelSuite = "BrowserG02ProductionSentinel.\(UUID().uuidString)"
        let sentinelDefaults = try XCTUnwrap(UserDefaults(suiteName: sentinelSuite))
        let sentinel = ["searchProvider": "duckDuckGo", "NSWindow Frame BrowserMainWindow": "sentinel"]
        sentinelDefaults.setPersistentDomain(sentinel, forName: sentinelSuite)
        let testDefaults = BrowserLaunchConfiguration.current.defaults
        let oldProvider = testDefaults.object(forKey: "searchProvider")
        defer {
            sentinelDefaults.removePersistentDomain(forName: sentinelSuite)
            if let oldProvider { testDefaults.set(oldProvider, forKey: "searchProvider") }
            else { testDefaults.removeObject(forKey: "searchProvider") }
        }
        let controller = BrowserWindowController()
        defer { controller.close() }
        let item = NSMenuItem()
        item.representedObject = SearchProvider.bing.rawValue
        controller.selectSearchProvider(item)
        XCTAssertEqual(BrowserPreferences.searchProvider(), .bing)
        XCTAssertEqual(sentinelDefaults.persistentDomain(forName: sentinelSuite) as? [String: String], sentinel)
        XCTAssertFalse(controller.window?.isVisible ?? true)
    }

    func testProductionAndTestPersistencePoliciesAreDisjoint() throws {
        let production = BrowserLaunchConfiguration()
        let hosted = BrowserLaunchConfiguration(environment: ["XCTestConfigurationFilePath": "fixture"])
        let compiled = BrowserLaunchConfiguration(isTestBuild: true)
        let ui = BrowserLaunchConfiguration(arguments: ["--ui-test-profile", "--reset-ui-test-bookmarks", "--reset-ui-test-website-data"])
        let performance = BrowserLaunchConfiguration(arguments: ["--performance-test"])
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let productionBookmarks = try XCTUnwrap(production.bookmarkConfiguration(applicationSupportDirectory: root))
        try FileManager.default.createDirectory(at: productionBookmarks.directoryURL, withIntermediateDirectories: true)
        let sentinel = productionBookmarks.directoryURL.appendingPathComponent("bookmarks.json")
        let bytes = Data("production sentinel".utf8)
        try bytes.write(to: sentinel)
        XCTAssertNil(production.ruleStoreDirectory(applicationSupportDirectory: root))
        XCTAssertNil(production.defaultsSuiteName)
        XCTAssertEqual(production.frameAutosaveName, BrowserWindowController.mainWindowFrameAutosaveName)
        XCTAssertEqual(hosted.mode, compiled.mode)
        for isolated in [hosted, compiled, ui, performance] {
            XCTAssertNotNil(isolated.defaultsSuiteName)
            XCTAssertNotNil(isolated.ruleStoreDirectory(applicationSupportDirectory: root))
            XCTAssertNotEqual(isolated.dataStoreIdentifier, production.dataStoreIdentifier)
            XCTAssertNotEqual(isolated.frameAutosaveName, production.frameAutosaveName)
            if let bookmarks = isolated.bookmarkConfiguration(applicationSupportDirectory: root) {
                XCTAssertNotEqual(bookmarks.directoryURL, productionBookmarks.directoryURL)
                try FileManager.default.createDirectory(at: bookmarks.directoryURL, withIntermediateDirectories: true)
                try Data("test sentinel".utf8).write(to: bookmarks.directoryURL.appendingPathComponent("bookmarks.json"))
            }
        }
        XCTAssertEqual(try Data(contentsOf: sentinel), bytes)
        XCTAssertNil(hosted.bookmarkConfiguration(applicationSupportDirectory: root))
        XCTAssertNil(performance.bookmarkConfiguration(applicationSupportDirectory: root))
        XCTAssertTrue(ui.shouldResetWebsiteData)
        XCTAssertFalse(production.shouldResetWebsiteData)
        XCTAssertFalse(BrowserLaunchConfiguration(arguments: ["--reset-ui-test-website-data"]).shouldResetWebsiteData)
    }
}
