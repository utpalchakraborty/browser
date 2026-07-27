import AppKit
import WebKit
import XCTest
@testable import Browser

@MainActor
final class BrowserWindowControllerTests: XCTestCase {
    func testInitialStateExposesNativeShellWithoutConstructingWebView() {
        let controller = BrowserWindowController()

        XCTAssertNil(controller.webView)
        XCTAssertEqual(
            controller.window?.identifier?.rawValue,
            "BrowserMainWindow"
        )
        XCTAssertEqual(
            controller.window?.accessibilityIdentifier(),
            "BrowserMainWindow"
        )
        XCTAssertEqual(
            controller.window?.contentView?.accessibilityIdentifier(),
            "BrowserNativeShell"
        )
        XCTAssertFalse(controller.window?.isRestorable ?? true)
        XCTAssertEqual(
            controller.window?.contentMinSize,
            NSSize(width: 460, height: 300)
        )
        XCTAssertNotNil(controller.window?.initialFirstResponder)
    }

    func testApplicationStateRestorationIsDisabled() {
        let delegate = AppDelegate()

        XCTAssertFalse(
            delegate.applicationShouldSaveApplicationState(.shared)
        )
        XCTAssertFalse(
            delegate.applicationShouldRestoreApplicationState(.shared)
        )
    }

    func testWindowFrameAutosaveRestoresOnlyGeometry() throws {
        let autosaveName: NSWindow.FrameAutosaveName =
            "BrowserWindowControllerTests.\(UUID().uuidString)"
        var autosaveWindows: [NSWindow] = []
        defer {
            autosaveWindows.forEach {
                _ = $0.setFrameAutosaveName("")
            }
            NSWindow.removeFrame(usingName: autosaveName)
        }

        let firstController = BrowserWindowController(
            frameAutosaveName: autosaveName
        )
        let firstWindow = try XCTUnwrap(firstController.window)
        autosaveWindows.append(firstWindow)
        var savedFrame = firstWindow.frame
        savedFrame.size.width -= 120
        savedFrame.size.height -= 80
        savedFrame.origin.x += 40
        savedFrame.origin.y += 20
        savedFrame = firstWindow.constrainFrameRect(
            savedFrame,
            to: firstWindow.screen
        )
        firstWindow.setFrame(savedFrame, display: false)
        firstWindow.saveFrame(usingName: autosaveName)
        _ = firstWindow.setFrameAutosaveName("")

        let restoredController = BrowserWindowController(
            frameAutosaveName: autosaveName
        )
        let restoredWindow = try XCTUnwrap(restoredController.window)
        autosaveWindows.append(restoredWindow)

        XCTAssertEqual(restoredController.windowFrameAutosaveName, autosaveName)
        XCTAssertEqual(restoredWindow.frameAutosaveName, autosaveName)
        XCTAssertEqual(
            restoredWindow.frame.origin.x,
            savedFrame.origin.x,
            accuracy: 1
        )
        XCTAssertEqual(
            restoredWindow.frame.origin.y,
            savedFrame.origin.y,
            accuracy: 1
        )
        XCTAssertEqual(
            restoredWindow.frame.width,
            savedFrame.width,
            accuracy: 1
        )
        XCTAssertEqual(
            restoredWindow.frame.height,
            savedFrame.height,
            accuracy: 1
        )
        XCTAssertFalse(restoredWindow.isRestorable)
        XCTAssertNil(restoredController.webView)
    }

    func testWindowFrameAutosaveNameIsolatedByLaunchMode() {
        XCTAssertEqual(
            AppDelegate.windowFrameAutosaveName(arguments: ["Browser"]),
            BrowserWindowController.mainWindowFrameAutosaveName
        )
        XCTAssertEqual(
            AppDelegate.windowFrameAutosaveName(
                arguments: [
                    "Browser",
                    "--ui-test-profile",
                    "-ApplePersistenceIgnoreState",
                    "YES",
                ]
            ),
            BrowserWindowController.uiTestWindowFrameAutosaveName
        )
        XCTAssertNil(
            AppDelegate.windowFrameAutosaveName(
                arguments: ["Browser", "--performance-test"]
            )
        )
        XCTAssertNil(
            AppDelegate.windowFrameAutosaveName(
                arguments: [
                    "Browser",
                    "-ApplePersistenceIgnoreState",
                    "YES",
                ]
            )
        )
    }

    func testHiddenWindowDoesNotConstructWebView() {
        let controller = BrowserWindowController()
        let profile = BrowserProfile(dataStoreIdentifier: UUID())

        controller.startWebView(profile: profile)

        XCTAssertNil(controller.webView)
    }

    func testContentBlockingPreparationFailureIsVisibleBeforeNavigation() throws {
        let controller = BrowserWindowController()
        let chromeView = try XCTUnwrap(
            controller.window?.contentView as? BrowserChromeView
        )

        controller.contentBlockingPreparationDidFail()

        XCTAssertNil(controller.webView)
        XCTAssertFalse(
            chromeView.errorView.isHidden,
            "A cold-start blocker failure must not leave unexplained blank chrome."
        )
    }

    func testDeniedPopupAndFailedExceptionNavigationRestoreCommittedPolicy() async throws {
        let protectedURL = Phase1Fixture.url("/normal/")
        let exceptedFailureURL = try XCTUnwrap(
            URL(string: "http://localhost:18765/download")
        )
        let fixture = try await makeContentBlockingControllerFixture(
            initialURL: protectedURL,
            exceptionURL: exceptedFailureURL
        )
        defer { fixture.cleanUp() }

        _ = try await fixture.webView.evaluateJavaScript(
            "window.open('http://localhost:18765/popup-target', '_blank'); true"
        )
        let loadedAfterDeniedPopup = try await dynamicBlockedScriptLoaded(
            in: fixture.webView
        )
        XCTAssertFalse(
            loadedAfterDeniedPopup,
            "A denied popup targeting an excepted host detached protection from the committed page."
        )

        fixture.controller.openBookmark(exceptedFailureURL)
        let chromeView = try XCTUnwrap(
            fixture.window.contentView as? BrowserChromeView
        )
        let failureBecameVisible = await waitUntil {
            !chromeView.errorView.isHidden
        }
        XCTAssertTrue(
            failureBecameVisible,
            "The intentionally failed navigation did not reach its visible error state."
        )
        let loadedAfterFailedNavigation = try await dynamicBlockedScriptLoaded(
            in: fixture.webView
        )
        XCTAssertFalse(
            loadedAfterFailedNavigation,
            "A failed navigation to an excepted host left the committed page unprotected."
        )
    }

    func testProtectedDocumentStaysProtectedUntilExceptedNavigationCommits() async throws {
        let gateID = UUID().uuidString
        let gatePath = "/privacy/navigation-gate/\(gateID)"
        let protectedURL = Phase1Fixture.url("/normal/")
        let exceptedURL = try XCTUnwrap(
            URL(string: "http://localhost:18765\(gatePath)")
        )
        let fixture = try await makeContentBlockingControllerFixture(
            initialURL: protectedURL,
            exceptionURL: exceptedURL
        )
        defer {
            fixture.cleanUp(releasingNavigationGateIDs: [gateID])
        }

        try await requestFixture("/reset")
        fixture.controller.openBookmark(exceptedURL)
        let requestReachedGate = await waitUntilAsync {
            try await self.fixtureRequestCount(gatePath) > 0
        }
        XCTAssertTrue(
            requestReachedGate,
            "The excepted navigation never reached the response-header gate."
        )

        let committedHost = try await fixture.webView.evaluateJavaScript(
            "window.location.hostname"
        ) as? String
        XCTAssertEqual(
            committedHost,
            "127.0.0.1",
            "The protected document should remain committed while response headers are gated."
        )
        let loadedBeforeCommit = try await dynamicBlockedScriptLoaded(
            in: fixture.webView
        )
        XCTAssertFalse(
            loadedBeforeCommit,
            "An excepted provisional navigation weakened the still-committed protected page."
        )
        let blockedRequestCountBeforeCommit = try await fixtureRequestCount("/assets/blocked.js")
        XCTAssertEqual(
            blockedRequestCountBeforeCommit,
            0,
            "The blocked resource reached the fixture before the exception committed."
        )

        try await requestFixture("\(gatePath)/release")
        let exceptedPageFinished = await waitUntil {
            fixture.webView.url?.host == "localhost"
                && fixture.webView.url?.path == gatePath
                && fixture.webView.isLoading == false
        }
        XCTAssertTrue(
            exceptedPageFinished,
            "The released exception page did not finish loading."
        )
        let loadedAfterCommit = try await dynamicBlockedScriptLoaded(
            in: fixture.webView
        )
        XCTAssertTrue(
            loadedAfterCommit,
            "The exact-host exception was not applied after its document committed."
        )
        let blockedRequestCountAfterCommit = try await fixtureRequestCount("/assets/blocked.js")
        XCTAssertEqual(
            blockedRequestCountAfterCommit,
            1,
            "The committed exact-host exception did not allow the resource request."
        )
    }

    func testPageNavigationSupersedesSlowProtectedNavigationWithoutWeakening() async throws {
        let firstGateID = UUID().uuidString
        let replacementGateID = UUID().uuidString
        let firstGatePath = "/privacy/navigation-gate/\(firstGateID)"
        let replacementGatePath = "/privacy/navigation-gate/\(replacementGateID)"
        let exceptedInitialURL = try XCTUnwrap(
            URL(string: "http://localhost:18765/normal/")
        )
        let protectedGateURL = Phase1Fixture.url(
            firstGatePath
        ).absoluteURL
        let protectedReplacementURL = Phase1Fixture.url(
            replacementGatePath
        ).absoluteURL
        let fixture = try await makeContentBlockingControllerFixture(
            initialURL: exceptedInitialURL,
            exceptionURL: exceptedInitialURL
        )
        defer {
            fixture.cleanUp(
                releasingNavigationGateIDs: [
                    firstGateID,
                    replacementGateID,
                ]
            )
        }

        let loadedWithInitialException = try await dynamicBlockedScriptLoaded(
            in: fixture.webView
        )
        XCTAssertTrue(
            loadedWithInitialException,
            "The overlap fixture did not begin with its exact-host exception applied."
        )

        try await requestFixture("/reset")
        fixture.controller.openBookmark(protectedGateURL)
        let firstRequestReachedGate = await waitUntilAsync {
            try await self.fixtureRequestCount(firstGatePath) > 0
        }
        XCTAssertTrue(
            firstRequestReachedGate,
            "The first protected navigation never reached the response-header gate."
        )
        let loadedDuringFirstNavigation = try await dynamicBlockedScriptLoaded(
            in: fixture.webView
        )
        XCTAssertFalse(
            loadedDuringFirstNavigation,
            "The first protected navigation did not strengthen the excepted document."
        )
        let blockedRequestCountDuringFirstNavigation = try await fixtureRequestCount(
            "/assets/blocked.js"
        )
        XCTAssertEqual(
            blockedRequestCountDuringFirstNavigation,
            0,
            "The first protected navigation allowed a blocked request from the resident page."
        )

        _ = try await fixture.webView.evaluateJavaScript(
            "window.location.assign('\(protectedReplacementURL.absoluteString)'); true"
        )
        let replacementRequestReachedGate = await waitUntilAsync {
            try await self.fixtureRequestCount(replacementGatePath) > 0
        }
        XCTAssertTrue(
            replacementRequestReachedGate,
            "The page-originated replacement navigation never reached its gate."
        )
        let committedHostDuringOverlap = try await fixture.webView.evaluateJavaScript(
            "window.location.hostname"
        ) as? String
        XCTAssertEqual(
            committedHostDuringOverlap,
            "localhost",
            "The excepted document should remain committed while both responses are gated."
        )
        let loadedDuringOverlap = try await dynamicBlockedScriptLoaded(
            in: fixture.webView
        )
        XCTAssertFalse(
            loadedDuringOverlap,
            "A stale failure weakened the resident page during the replacement navigation."
        )
        let blockedRequestCountDuringOverlap = try await fixtureRequestCount(
            "/assets/blocked.js"
        )
        XCTAssertEqual(
            blockedRequestCountDuringOverlap,
            0,
            "The overlapping protected navigation allowed a blocked resident-page request."
        )

        try await requestFixture("\(replacementGatePath)/release")
        let replacementPageFinished = await waitUntil {
            fixture.webView.url?.host == protectedReplacementURL.host
                && fixture.webView.url?.path == replacementGatePath
                && fixture.webView.isLoading == false
        }
        XCTAssertTrue(
            replacementPageFinished,
            "The released replacement navigation did not finish."
        )
        let loadedAfterReplacementCommit = try await dynamicBlockedScriptLoaded(
            in: fixture.webView
        )
        XCTAssertFalse(
            loadedAfterReplacementCommit,
            "The replacement protected page committed without blocking."
        )
        let blockedRequestCountAfterReplacementCommit = try await fixtureRequestCount(
            "/assets/blocked.js"
        )
        XCTAssertEqual(
            blockedRequestCountAfterReplacementCommit,
            0,
            "The committed protected replacement allowed a blocked request."
        )
        try await requestFixture("\(firstGatePath)/release")
    }

    func testSameDocumentFragmentNavigationDoesNotLeaveBlockingToggleBusy() async throws {
        let initialURL = Phase1Fixture.url("/normal/")
        let exceptionURL = try XCTUnwrap(
            URL(string: "http://localhost:18765/normal/")
        )
        let fixture = try await makeContentBlockingControllerFixture(
            initialURL: initialURL,
            exceptionURL: exceptionURL
        )
        defer { fixture.cleanUp() }
        try await requestFixture("/reset")
        let toggleItem = NSMenuItem(
            title: "",
            action: #selector(
                BrowserWindowController
                    .toggleContentBlockingForCurrentSiteAndReload(_:)
            ),
            keyEquivalent: ""
        )

        XCTAssertTrue(
            fixture.controller.validateMenuItem(toggleItem),
            "The blocking toggle should be available before a fragment navigation."
        )
        XCTAssertEqual(
            toggleItem.title,
            "Disable Blocking for 127.0.0.1 and Reload"
        )
        _ = try await fixture.webView.evaluateJavaScript(
            "window.location.hash = 'privacy-fragment'; true"
        )
        let fragmentChanged = await waitUntil {
            fixture.webView.url?.fragment == "privacy-fragment"
                && fixture.webView.isLoading == false
        }
        XCTAssertTrue(fragmentChanged, "The fragment navigation did not complete.")
        let documentRequestCount = try await fixtureRequestCount("/normal/")
        XCTAssertEqual(
            documentRequestCount,
            0,
            "A fragment-only change unexpectedly reloaded the document."
        )
        XCTAssertTrue(
            fixture.controller.validateMenuItem(toggleItem),
            "A same-document fragment action left content blocking marked busy."
        )
        XCTAssertEqual(
            toggleItem.title,
            "Disable Blocking for 127.0.0.1 and Reload"
        )
        let blockedScriptLoaded = try await dynamicBlockedScriptLoaded(
            in: fixture.webView
        )
        XCTAssertFalse(
            blockedScriptLoaded,
            "A fragment-only change detached protection from the current document."
        )
        let blockedRequestCount = try await fixtureRequestCount(
            "/assets/blocked.js"
        )
        XCTAssertEqual(
            blockedRequestCount,
            0,
            "The fragment-only change allowed a blocked resource request."
        )
    }

    func testCurrentSiteExceptionDetachesDocumentRuleBeforeReload() async throws {
        let pageURL = Phase1Fixture.url("/normal/")
        let fixture = try await makeContentBlockingControllerFixture(
            initialURL: pageURL,
            exceptionURL: pageURL,
            blockedURLFilter: ".*/normal/.*",
            blockedResourceTypes: ["document"]
        )
        defer { fixture.cleanUp() }

        XCTAssertNotNil(fixture.coordinator.toggleException(for: pageURL))
        XCTAssertTrue(
            fixture.coordinator.applyPolicy(
                to: fixture.webView.configuration.userContentController,
                for: pageURL
            )
        )
        try await requestFixture("/reset")

        fixture.controller.toggleContentBlockingForCurrentSiteAndReload(nil)

        let documentReloaded = await waitUntilAsync {
            try await self.fixtureRequestCount("/normal/") == 1
                && fixture.webView.isLoading == false
        }
        XCTAssertTrue(
            documentReloaded,
            "The exact-host exception did not detach a document-blocking rule before reload."
        )
        XCTAssertTrue(fixture.coordinator.snapshot(for: pageURL).isException)
        XCTAssertFalse(fixture.webView.isLoading)
    }

    func testRepeatedInitialFocusDoesNotReselectTypedText() throws {
        let controller = BrowserWindowController()
        let window = try XCTUnwrap(controller.window)
        let chromeView = try XCTUnwrap(
            window.contentView as? BrowserChromeView
        )
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }

        controller.ensureInitialAddressFieldFocus()
        let editor = try XCTUnwrap(chromeView.addressField.currentEditor())
        editor.string = "focus-probe"
        editor.selectedRange = NSRange(location: 1, length: 0)

        controller.ensureInitialAddressFieldFocus()

        XCTAssertEqual(editor.string, "focus-probe")
        XCTAssertEqual(editor.selectedRange, NSRange(location: 1, length: 0))
    }

    private func dynamicBlockedScriptLoaded(
        in webView: WKWebView
    ) async throws -> Bool {
        let result = try await webView.callAsyncJavaScript(
            """
            window.blockedLoaded = false;
            const script = document.createElement('script');
            script.src = `/assets/blocked.js?policy-restoration=${Date.now()}-${Math.random()}`;
            document.body.appendChild(script);
            await new Promise((resolve) => setTimeout(resolve, 300));
            return Boolean(window.blockedLoaded);
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        return try XCTUnwrap(result as? Bool)
    }

    private func makeContentBlockingControllerFixture(
        initialURL: URL,
        exceptionURL: URL,
        blockedURLFilter: String = ".*/assets/blocked[.]js.*",
        blockedResourceTypes: [String] = ["script"]
    ) async throws -> ContentBlockingControllerFixture {
        let ruleStoreDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "BrowserWindowControllerPolicyTests.\(UUID().uuidString)",
                isDirectory: true
            )
        let ruleStore = try XCTUnwrap(
            WKContentRuleListStore(url: ruleStoreDirectory)
        )
        let defaultsSuiteName =
            "BrowserWindowControllerPolicyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: defaultsSuiteName)
        )
        let rules = try ContentBlockerService.probeRules(
            blockedURLFilter: blockedURLFilter,
            exceptionTopURLFilters: [],
            resourceTypes: blockedResourceTypes
        )
        let namespace = "browser-window-controller-policy-\(UUID().uuidString)"
        let coordinator = ContentBlockingCoordinator(
            resolver: ContentBlockerRuleSetResolver(
                service: ContentBlockerService(ruleStore: ruleStore),
                stateStore: ContentBlockerStateStore(defaults: defaults)
            ),
            sitePolicyStore: ContentBlockerSitePolicyStore(defaults: defaults)
        )
        await coordinator.prepare(
            currentSources: [
                ContentBlockerRuleSource(
                    namespace: namespace,
                    identifier: ContentBlockerService.versionedIdentifier(
                        namespace: namespace,
                        encodedRules: rules
                    ),
                    encodedRulesLoader: { rules }
                )
            ]
        )
        XCTAssertNotNil(coordinator.toggleException(for: exceptionURL))

        let controller = BrowserWindowController(
            contentBlockingCoordinator: coordinator
        )
        let window = try XCTUnwrap(controller.window)
        window.orderFront(nil)
        controller.startWebViews(
            profile: BrowserProfile(dataStoreIdentifier: UUID()),
            viewCount: 1,
            initialURL: initialURL
        )
        let initialPageLoaded = await waitUntil {
            controller.webView?.url?.host == initialURL.host
                && controller.webView?.url?.path == initialURL.path
                && controller.webView?.isLoading == false
        }
        XCTAssertTrue(initialPageLoaded, "The policy test fixture did not load.")

        return ContentBlockingControllerFixture(
            controller: controller,
            coordinator: coordinator,
            webView: try XCTUnwrap(controller.webView),
            window: window,
            defaults: defaults,
            defaultsSuiteName: defaultsSuiteName,
            ruleStoreDirectory: ruleStoreDirectory
        )
    }

    private func requestFixture(_ path: String) async throws {
        let (_, response) = try await URLSession.shared.data(
            from: Phase1Fixture.url(path)
        )
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
    }

    private func fixtureRequestCount(_ path: String) async throws -> Int {
        let (data, response) = try await URLSession.shared.data(
            from: Phase1Fixture.url("/stats")
        )
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let object = try JSONSerialization.jsonObject(with: data)
        let counts = try XCTUnwrap(object as? [String: Int])
        return counts[path, default: 0]
    }

    private func waitUntilAsync(
        _ condition: @escaping @MainActor () async throws -> Bool
    ) async -> Bool {
        for _ in 0..<100 {
            if (try? await condition()) == true {
                return true
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return (try? await condition()) == true
    }

    private func waitUntil(
        _ condition: @MainActor () -> Bool
    ) async -> Bool {
        for _ in 0..<100 {
            if condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }

    func testPerformanceViewCountIsBoundedAndRequiresPerformanceMode() {
        XCTAssertEqual(
            AppDelegate.performanceViewCount(arguments: ["Browser"]),
            1
        )
        XCTAssertEqual(
            AppDelegate.performanceViewCount(
                arguments: [
                    "Browser",
                    "--performance-test",
                    "--performance-view-count",
                    "10",
                ]
            ),
            10
        )
        XCTAssertEqual(
            AppDelegate.performanceViewCount(
                arguments: [
                    "Browser",
                    "--performance-test",
                    "--performance-view-count",
                    "11",
                ]
            ),
            1
        )
    }

    func testPerformanceFixtureURLIsRestrictedToLocalHTTP() {
        let prefix = ["Browser", "--performance-test", "--performance-fixture-url"]

        XCTAssertEqual(
            AppDelegate.performanceFixtureURL(
                arguments: prefix + ["http://127.0.0.1:18765/normal/"]
            )?.absoluteString,
            "http://127.0.0.1:18765/normal/"
        )
        XCTAssertNil(
            AppDelegate.performanceFixtureURL(
                arguments: prefix + ["https://example.com/"]
            )
        )
        XCTAssertNil(
            AppDelegate.performanceFixtureURL(
                arguments: [
                    "Browser",
                    "--performance-fixture-url",
                    "http://127.0.0.1:18765/normal/",
                ]
            )
        )
    }
}

@MainActor
private struct ContentBlockingControllerFixture {
    let controller: BrowserWindowController
    let coordinator: ContentBlockingCoordinator
    let webView: WKWebView
    let window: NSWindow
    let defaults: UserDefaults
    let defaultsSuiteName: String
    let ruleStoreDirectory: URL

    func cleanUp(releasingNavigationGateIDs gateIDs: [String] = []) {
        webView.stopLoading()
        for gateID in gateIDs {
            URLSession.shared.dataTask(
                with: Phase1Fixture.url(
                    "/privacy/navigation-gate/\(gateID)/release"
                )
            ).resume()
        }
        window.orderOut(nil)
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        try? FileManager.default.removeItem(at: ruleStoreDirectory)
        coordinator.forget(webView.configuration.userContentController)
    }
}
