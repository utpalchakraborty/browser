import Foundation
import XCTest

@MainActor
final class BrowserNavigationUITests: XCTestCase {
    private static let fixtureOrigin = "http://127.0.0.1:18765"
    private static let recoveryOrigin = "http://127.0.0.1:18769"

    private var application: XCUIApplication!

    func testLaunchFocusAndAddressSubmission() throws {
        launchApplication()
        defer { application.terminate() }
        try assertAddressFieldIsFocused()
        assertCriticalControlsExist()

        navigate(to: "/phase2/page-a")

        XCTAssertTrue(
            pageText("Phase 2 Page A").waitForExistence(timeout: 5),
            "Submitting a local HTTP URL did not render Page A."
        )
        waitForAddress(fixtureURL("/phase2/page-a"))
    }

    func testRedirectDisplaysFinalURL() {
        launchApplication()
        defer { application.terminate() }
        submit(fixtureURL("/phase2/redirect"))

        XCTAssertTrue(
            pageText("Phase 2 Page B").waitForExistence(timeout: 5),
            "The redirect did not render its destination."
        )
        waitForAddress(fixtureURL("/phase2/page-b"))
    }

    func testTitleOpenLocationShortcutAndUnsupportedSchemePolicy() {
        launchApplication()
        defer { application.terminate() }
        navigate(to: "/phase2/page-a")
        XCTAssertTrue(pageText("Phase 2 Page A").waitForExistence(timeout: 5))
        waitForWindowTitle("Page A — Browser")

        application.typeKey("l", modifierFlags: .command)
        let unsupportedAddress = "mailto:user@example.com"
        addressField.typeText(unsupportedAddress)
        XCTAssertEqual(addressField.value as? String, unsupportedAddress)
        addressField.typeKey(.return, modifierFlags: [])

        XCTAssertTrue(
            errorView.waitForExistence(timeout: 5),
            "An unsupported top-level scheme did not fail visibly."
        )
        XCTAssertTrue(pageText("Unsupported Address").exists)
    }

    func testBackAndForwardFollowWebKitState() {
        launchApplication()
        defer { application.terminate() }
        navigate(to: "/phase2/page-a")
        XCTAssertTrue(pageText("Phase 2 Page A").waitForExistence(timeout: 5))
        navigate(to: "/phase2/page-b")
        XCTAssertTrue(pageText("Phase 2 Page B").waitForExistence(timeout: 5))

        waitUntilEnabled(backButton)
        backButton.click()
        XCTAssertTrue(pageText("Phase 2 Page A").waitForExistence(timeout: 5))
        waitForAddress(fixtureURL("/phase2/page-a"))

        waitUntilEnabled(forwardButton)
        forwardButton.click()
        XCTAssertTrue(pageText("Phase 2 Page B").waitForExistence(timeout: 5))
        waitForAddress(fixtureURL("/phase2/page-b"))

        application.typeKey("[", modifierFlags: .command)
        XCTAssertTrue(pageText("Phase 2 Page A").waitForExistence(timeout: 5))
        application.typeKey("]", modifierFlags: .command)
        XCTAssertTrue(pageText("Phase 2 Page B").waitForExistence(timeout: 5))
    }

    func testReloadRequestsThePageAgain() async throws {
        launchApplication()
        defer { application.terminate() }
        try await requestFixture("/phase2/reload-reset")
        navigate(to: "/phase2/reload-count")
        XCTAssertTrue(pageText("Reload count 1").waitForExistence(timeout: 5))

        waitForButtonLabel(reloadStopButton, containing: "Reload")
        reloadStopButton.click()

        XCTAssertTrue(
            pageText("Reload count 2").waitForExistence(timeout: 5),
            "Reload did not issue a second request to the fixture."
        )

        application.typeKey("r", modifierFlags: .command)
        XCTAssertTrue(
            pageText("Reload count 3").waitForExistence(timeout: 5),
            "Command-R did not reload the page."
        )
    }

    func testProgressAndStopCancelSlowNavigation() {
        launchApplication()
        defer { application.terminate() }
        submit(fixtureURL("/phase2/slow-response"))

        XCTAssertTrue(
            progressIndicator.waitForExistence(timeout: 3),
            "A bounded slow load never exposed progress."
        )
        waitForButtonLabel(reloadStopButton, containing: "Stop")
        application.typeKey(".", modifierFlags: .command)

        waitForButtonLabel(reloadStopButton, containing: "Reload")
        XCTAssertTrue(
            progressIndicator.waitForNonExistence(timeout: 3),
            "Progress remained visible after stopping navigation."
        )
        XCTAssertFalse(
            pageText("Slow response complete").waitForExistence(timeout: 4.5),
            "The page completed even though Stop was invoked."
        )
    }

    func testVisibleConnectionErrorCanRetry() async throws {
        launchApplication()
        defer { application.terminate() }
        submit(Self.recoveryOrigin + "/recovered")

        XCTAssertTrue(
            errorView.waitForExistence(timeout: 5),
            "A local connection failure did not present a visible error."
        )
        XCTAssertTrue(
            errorReloadButton.waitForExistence(timeout: 2),
            "The connection error did not offer a retry action."
        )

        try await requestFixture("/phase2/recovery-enable")
        errorReloadButton.click()

        XCTAssertTrue(
            pageText("Recovered after retry").waitForExistence(timeout: 5),
            "Retry did not reload the formerly unavailable local page."
        )
        XCTAssertTrue(
            errorView.waitForNonExistence(timeout: 2),
            "The error remained visible after a successful retry."
        )
    }

    func testBookmarksCanBeAddedEditedSearchedOpenedDeletedAndRelaunched() throws {
        launchApplication()
        defer { application.terminate() }
        navigate(to: "/phase2/page-a")
        XCTAssertTrue(pageText("Phase 2 Page A").waitForExistence(timeout: 5))
        waitUntilEnabled(bookmarkButton)

        application.typeKey("d", modifierFlags: .command)
        XCTAssertTrue(
            bookmarkEditor.waitForExistence(timeout: 3),
            "Command-D did not present the bookmark editor."
        )
        replaceText(in: bookmarkTitleField, with: "Favorite Page A")
        bookmarkSaveButton.click()
        waitForButtonLabel(bookmarkButton, containing: "Edit Bookmark")

        showBookmarks()
        XCTAssertTrue(
            pageText("Favorite Page A").waitForExistence(timeout: 3),
            "The saved bookmark did not appear in the manager."
        )

        replaceText(in: bookmarkSearchField, with: "favorite")
        XCTAssertTrue(pageText("Favorite Page A").waitForExistence(timeout: 2))
        replaceText(in: bookmarkSearchField, with: "phase2/page-a")
        XCTAssertTrue(pageText("Favorite Page A").waitForExistence(timeout: 2))
        replaceText(in: bookmarkSearchField, with: "")

        pageText("Favorite Page A").click()
        application.typeKey("e", modifierFlags: .command)
        XCTAssertTrue(bookmarkEditor.waitForExistence(timeout: 3))
        replaceText(in: bookmarkTitleField, with: "Renamed Page A")
        bookmarkSaveButton.click()
        XCTAssertTrue(pageText("Renamed Page A").waitForExistence(timeout: 3))

        application.terminate()
        application.launchArguments = [
            "--ui-test-profile",
            "--reset-ui-test-content-blocking",
        ]
        application.launch()
        XCTAssertTrue(mainWindow.waitForExistence(timeout: 5))
        try assertAddressFieldIsFocused()
        XCTAssertFalse(pageText("Phase 2 Page A").exists)

        showBookmarks()
        XCTAssertTrue(
            pageText("Renamed Page A").waitForExistence(timeout: 3),
            "The bookmark did not survive relaunch."
        )
        pageText("Renamed Page A").click()
        application.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(
            pageText("Phase 2 Page A").waitForExistence(timeout: 5),
            "Opening the bookmark did not replace the current page."
        )
        waitForAddress(fixtureURL("/phase2/page-a"))

        showBookmarks()
        pageText("Renamed Page A").click()
        application.typeKey(.delete, modifierFlags: [])
        let confirmDeleteButton = application.sheets.buttons["Delete"].firstMatch
        XCTAssertTrue(confirmDeleteButton.waitForExistence(timeout: 2))
        confirmDeleteButton.click()
        XCTAssertTrue(
            pageText("Renamed Page A").waitForNonExistence(timeout: 3),
            "Deleting the bookmark left it in the manager."
        )
    }

    func testNavigationIsNotRestoredAfterRelaunch() throws {
        launchApplication(ignoringSavedState: false)
        defer { application.terminate() }
        let sentinelURL = fixtureURL(
            "/phase2/page-a?phase2-history-sentinel=7f3d2e"
        )
        submit(sentinelURL)
        XCTAssertTrue(pageText("Phase 2 Page A").waitForExistence(timeout: 5))
        waitForAddress(sentinelURL)
        application.terminate()

        application.launchArguments = [
            "--ui-test-profile",
            "--reset-ui-test-content-blocking",
        ]
        application.launch()
        XCTAssertTrue(mainWindow.waitForExistence(timeout: 5))
        try assertAddressFieldIsFocused()

        let relaunchedValue = addressField.value as? String ?? ""
        XCTAssertFalse(
            relaunchedValue.contains("phase2-history-sentinel-7f3d2e"),
            "The prior navigation was restored after relaunch."
        )
        XCTAssertFalse(
            pageText("Phase 2 Page A").exists,
            "The prior page remained visible after relaunch."
        )
    }

    func testPopupPolicyBlocksScriptedAndFormWindowsButRoutesDirectLinkInPlace() {
        launchApplication()
        defer { application.terminate() }
        navigate(to: "/privacy/popup-policy")

        XCTAssertTrue(
            pageText("Popup Policy Fixture").waitForExistence(timeout: 5)
        )
        XCTAssertFalse(
            pageText("Phase 2 Page B").waitForExistence(timeout: 1.5),
            "A load-time, promise, or timer popup created a browsing surface."
        )
        waitForAddress(fixtureURL("/privacy/popup-policy"))
        XCTAssertEqual(application.windows.count, 1)
        XCTAssertEqual(application.webViews.count, 1)

        application.buttons["Try Scripted Popup"].click()
        XCTAssertFalse(
            pageText("Phase 2 Page B").waitForExistence(timeout: 1),
            "A user-activated window.open created a browsing surface."
        )
        waitForAddress(fixtureURL("/privacy/popup-policy"))
        XCTAssertEqual(application.windows.count, 1)
        XCTAssertEqual(application.webViews.count, 1)

        application.buttons["Try Scripted Anchor"].click()
        XCTAssertFalse(
            pageText("Phase 2 Page B").waitForExistence(timeout: 1),
            "A script-triggered anchor created or routed a browsing surface."
        )
        waitForAddress(fixtureURL("/privacy/popup-policy"))
        XCTAssertEqual(application.windows.count, 1)
        XCTAssertEqual(application.webViews.count, 1)

        application.buttons["Try Targeted Form"].click()
        XCTAssertFalse(
            pageText("Phase 2 Page B").waitForExistence(timeout: 1),
            "A target-blank form created a browsing surface."
        )
        waitForAddress(fixtureURL("/privacy/popup-policy"))
        XCTAssertEqual(application.windows.count, 1)
        XCTAssertEqual(application.webViews.count, 1)

        application.links["Open Direct Link"].click()
        XCTAssertTrue(pageText("Phase 2 Page B").waitForExistence(timeout: 5))
        waitForAddress(fixtureURL("/phase2/page-b"))
        XCTAssertEqual(
            application.windows.count,
            1,
            "A direct target-blank link created a second browser window."
        )
        XCTAssertEqual(
            application.webViews.count,
            1,
            "A direct target-blank link left a second WebView behind."
        )
    }

    func testAdAndTrackerBlockingSupportsAnExactHostExceptionAndReload() async throws {
        launchApplication()
        defer { application.terminate() }
        try await requestFixture("/reset")
        navigate(to: "/privacy/blocking/")

        XCTAssertTrue(
            pageText("First-party resource loaded").waitForExistence(timeout: 5),
            "Blocking prevented the allowed first-party fixture resource."
        )
        XCTAssertTrue(
            pageText("Blocking fixture complete").waitForExistence(timeout: 5),
            "The blocking fixture did not finish parsing."
        )
        XCTAssertTrue(
            pageText("Ad resource blocked").waitForExistence(timeout: 5),
            "The deterministic advertising resource was not blocked."
        )
        var requestCounts = try await fixtureRequestCounts()
        XCTAssertEqual(requestCounts["/privacy/allowed.js"], 1)
        XCTAssertNil(
            requestCounts["/privacy/blocked.js"],
            "WebKit requested the resource that the blocker should stop."
        )

        application.typeKey("p", modifierFlags: [.command, .option])
        XCTAssertTrue(
            pageText("Ad resource loaded").waitForExistence(timeout: 5),
            "Disabling blocking for the current host did not reload unblocked."
        )
        requestCounts = try await fixtureRequestCounts()
        XCTAssertEqual(requestCounts["/privacy/allowed.js"], 2)
        XCTAssertEqual(requestCounts["/privacy/blocked.js"], 1)

        let localhostURL = "http://localhost:18765/privacy/blocking/"
        submit(localhostURL)
        waitForAddress(localhostURL)
        XCTAssertTrue(
            pageText("Blocking fixture complete").waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            pageText("Ad resource blocked").waitForExistence(timeout: 5),
            "An exception for 127.0.0.1 leaked to the distinct localhost host."
        )
        requestCounts = try await fixtureRequestCounts()
        XCTAssertEqual(requestCounts["/privacy/allowed.js"], 3)
        XCTAssertEqual(
            requestCounts["/privacy/blocked.js"],
            1,
            "The distinct localhost host inherited the 127.0.0.1 exception."
        )

        application.terminate()
        launchApplication(resetContentBlocking: false)
        navigate(to: "/privacy/blocking/")
        XCTAssertTrue(
            pageText("Ad resource loaded").waitForExistence(timeout: 5),
            "The explicit host exception did not survive relaunch."
        )
        requestCounts = try await fixtureRequestCounts()
        XCTAssertEqual(requestCounts["/privacy/allowed.js"], 4)
        XCTAssertEqual(requestCounts["/privacy/blocked.js"], 2)

        showPrivacy()
        let resetExceptionsButton = application.buttons[
            "BrowserPrivacyResetSiteExceptionsButton"
        ]
        waitUntilEnabled(resetExceptionsButton)
        resetExceptionsButton.click()
        let confirmResetButton = application.sheets.buttons[
            "Reset Site Exceptions"
        ]
        XCTAssertTrue(confirmResetButton.waitForExistence(timeout: 2))
        confirmResetButton.click()
        application.buttons["BrowserPrivacyDoneButton"].click()
        XCTAssertTrue(
            pageText("Ad resource blocked").waitForExistence(timeout: 5),
            "Resetting all exceptions did not reload with protection attached."
        )
        requestCounts = try await fixtureRequestCounts()
        XCTAssertEqual(requestCounts["/privacy/allowed.js"], 5)
        XCTAssertEqual(
            requestCounts["/privacy/blocked.js"],
            2,
            "Resetting all exceptions still requested the blocked resource."
        )

        showPrivacy()
        let deleteCompiledRulesButton = application.buttons[
            "BrowserPrivacyDeleteCompiledRulesButton"
        ]
        waitUntilEnabled(deleteCompiledRulesButton)
        deleteCompiledRulesButton.click()
        let confirmCompiledDeleteButton = application.sheets.buttons[
            "Delete Compiled Rules"
        ]
        XCTAssertTrue(confirmCompiledDeleteButton.waitForExistence(timeout: 2))
        confirmCompiledDeleteButton.click()
        waitForValue(
            application.descendants(matching: .any)[
                "BrowserPrivacyBlockingResetResult"
            ],
            containing: "Current pages remain protected"
        )
        application.buttons["BrowserPrivacyDoneButton"].click()

        application.terminate()
        launchApplication(resetContentBlocking: false)
        navigate(to: "/privacy/blocking/")
        XCTAssertTrue(
            pageText("Ad resource blocked").waitForExistence(timeout: 5),
            "Deleting compiled artifacts did not rebuild protection on relaunch."
        )
        requestCounts = try await fixtureRequestCounts()
        XCTAssertEqual(requestCounts["/privacy/allowed.js"], 6)
        XCTAssertEqual(
            requestCounts["/privacy/blocked.js"],
            2,
            "The relaunched blocker requested the protected resource."
        )
    }

    func testWebsiteDataPrivacyControlsMaskRevealDeleteAndPersistDeletion() {
        launchApplication()
        defer { application.terminate() }
        navigate(to: "/privacy/website-data")
        XCTAssertTrue(
            pageText("Website data ready").waitForExistence(timeout: 5),
            "The website-data fixture did not finish creating storage."
        )

        let inactiveOriginURL = "http://localhost:18765/phase2/page-a"
        submit(inactiveOriginURL)
        XCTAssertTrue(pageText("Phase 2 Page A").waitForExistence(timeout: 5))
        waitForAddress(inactiveOriginURL)

        showPrivacy()
        XCTAssertTrue(
            application.descendants(matching: .any)[
                "BrowserPrivacyExplanation"
            ].exists
        )
        XCTAssertTrue(
            application.buttons["BrowserPrivacyDeleteAllCookiesButton"].exists
        )
        XCTAssertTrue(
            application.buttons[
                "BrowserPrivacyDeleteAllWebsiteDataButton"
            ].exists
        )

        let persistentCookie = pageText("phase4persistent")
        XCTAssertTrue(
            persistentCookie.waitForExistence(timeout: 5),
            "The persistent fixture cookie was not listed."
        )
        persistentCookie.click()
        let cookieValue = application.descendants(matching: .any)[
            "BrowserPrivacyCookieValue"
        ]
        waitForValue(cookieValue, equalTo: "••••••••")
        XCTAssertNotEqual(cookieValue.value as? String, "privacy-value-sentinel")

        let revealButton = application.buttons[
            "BrowserPrivacyRevealCookieButton"
        ]
        revealButton.click()
        waitForValue(cookieValue, equalTo: "privacy-value-sentinel")
        revealButton.click()
        waitForValue(cookieValue, equalTo: "••••••••")

        application.buttons["BrowserPrivacyDeleteCookieButton"].click()
        let confirmCookieDelete = application.sheets.buttons["Delete Cookie"]
        XCTAssertTrue(confirmCookieDelete.waitForExistence(timeout: 2))
        confirmCookieDelete.click()
        XCTAssertTrue(
            persistentCookie.waitForNonExistence(timeout: 5),
            "Deleting one cookie left it in the privacy window."
        )

        let sessionCookie = pageText("phase4session")
        XCTAssertTrue(sessionCookie.waitForExistence(timeout: 3))
        sessionCookie.click()
        application.buttons[
            "BrowserPrivacyDeleteDomainCookiesButton"
        ].click()
        let confirmDomainCookieDelete = application.sheets.buttons[
            "Delete Domain Cookies"
        ]
        XCTAssertTrue(confirmDomainCookieDelete.waitForExistence(timeout: 2))
        confirmDomainCookieDelete.click()
        XCTAssertTrue(
            sessionCookie.waitForNonExistence(timeout: 5),
            "Deleting the exact domain's cookies left a cookie behind."
        )

        let websiteDataSegment = application.radioButtons["Website Data"]
        XCTAssertTrue(websiteDataSegment.waitForExistence(timeout: 2))
        websiteDataSegment.click()
        let websiteDataRecord = pageText("127.0.0.1")
        XCTAssertTrue(
            websiteDataRecord.waitForExistence(timeout: 5),
            "Cookie-only deletion also removed broader website data."
        )
        websiteDataRecord.click()
        waitForValue(
            application.descendants(matching: .any)[
                "BrowserPrivacySelectionDetail"
            ],
            containing: "Local Storage"
        )
        application.buttons["BrowserPrivacyDeleteSiteDataButton"].click()
        let confirmSiteDataDelete = application.sheets.buttons[
            "Delete Website Data"
        ]
        XCTAssertTrue(confirmSiteDataDelete.waitForExistence(timeout: 2))
        confirmSiteDataDelete.click()
        XCTAssertTrue(
            websiteDataRecord.waitForNonExistence(timeout: 5),
            "Deleting the selected WebKit record left it visible."
        )

        application.buttons["BrowserPrivacyDoneButton"].click()
        let secondOriginURL = "http://localhost:18765/privacy/website-data"
        submit(secondOriginURL)
        XCTAssertTrue(
            pageText("Website data ready").waitForExistence(timeout: 5),
            "The second website-data origin did not finish creating storage."
        )
        waitForAddress(secondOriginURL)
        let inactivePageURL = fixtureURL("/phase2/page-a")
        submit(inactivePageURL)
        XCTAssertTrue(pageText("Phase 2 Page A").waitForExistence(timeout: 5))
        waitForAddress(inactivePageURL)
        showPrivacy()

        application.radioButtons["Cookies"].click()
        let remainingPersistentCookie = pageText("phase4persistent")
        let remainingSessionCookie = pageText("phase4session")
        XCTAssertTrue(
            remainingPersistentCookie.waitForExistence(timeout: 5),
            "The second origin's cookies were not available for global deletion."
        )
        application.buttons["BrowserPrivacyDeleteAllCookiesButton"].click()
        let confirmAllCookieDelete = application.sheets.buttons[
            "Delete All Cookies"
        ]
        XCTAssertTrue(confirmAllCookieDelete.waitForExistence(timeout: 2))
        confirmAllCookieDelete.click()
        XCTAssertTrue(
            remainingPersistentCookie.waitForNonExistence(timeout: 5)
                && remainingSessionCookie.waitForNonExistence(timeout: 5),
            "Deleting all cookies left a cookie visible."
        )

        application.radioButtons["Website Data"].click()
        let remainingWebsiteDataRecord = pageText("localhost")
        XCTAssertTrue(
            remainingWebsiteDataRecord.waitForExistence(timeout: 5),
            "Global cookie deletion also removed broader website data."
        )
        application.buttons[
            "BrowserPrivacyDeleteAllWebsiteDataButton"
        ].click()
        let confirmAllWebsiteDataDelete = application.sheets.buttons[
            "Delete All Website Data"
        ]
        XCTAssertTrue(confirmAllWebsiteDataDelete.waitForExistence(timeout: 2))
        confirmAllWebsiteDataDelete.click()
        XCTAssertTrue(
            remainingWebsiteDataRecord.waitForNonExistence(timeout: 5),
            "Deleting all website data left a WebKit record visible."
        )
        application.buttons["BrowserPrivacyDoneButton"].click()

        application.terminate()
        launchApplication(
            resetContentBlocking: false,
            resetWebsiteData: false
        )
        XCTAssertTrue(
            application.descendants(matching: .any)["BrowserWebView"]
                .waitForExistence(timeout: 5)
        )
        showPrivacy()
        let privacyStatus = application.descendants(matching: .any)[
            "BrowserPrivacyStatus"
        ]
        waitForValue(privacyStatus, containing: "0 cookies across")
        XCTAssertTrue(
            pageText("phase4persistent").waitForNonExistence(timeout: 1)
                && pageText("phase4session").waitForNonExistence(timeout: 1),
            "Deleted cookies returned after relaunch."
        )
        application.radioButtons["Website Data"].click()
        XCTAssertTrue(
            pageText("127.0.0.1").waitForNonExistence(timeout: 1)
                && pageText("localhost").waitForNonExistence(timeout: 1),
            "Deleted website data returned after relaunch."
        )
    }

    private func launchApplication(
        ignoringSavedState: Bool = true,
        resetContentBlocking: Bool = true,
        resetWebsiteData: Bool = true
    ) {
        continueAfterFailure = false
        application = XCUIApplication()
        application.launchArguments = [
            "--ui-test-profile",
            "--reset-ui-test-bookmarks",
        ]
        if resetContentBlocking {
            application.launchArguments.append(
                "--reset-ui-test-content-blocking"
            )
        }
        if resetWebsiteData {
            application.launchArguments.append(
                "--reset-ui-test-website-data"
            )
        }
        if ignoringSavedState {
            application.launchArguments += [
                "-ApplePersistenceIgnoreState",
                "YES",
            ]
        }
        application.launch()
        XCTAssertTrue(
            mainWindow.waitForExistence(timeout: 5),
            "Browser did not present its main window."
        )
    }

    private var mainWindow: XCUIElement {
        application.windows["BrowserMainWindow"]
    }

    private var addressField: XCUIElement {
        application.descendants(matching: .any)["BrowserAddressField"]
    }

    private var backButton: XCUIElement {
        application.buttons["BrowserBackButton"]
    }

    private var forwardButton: XCUIElement {
        application.buttons["BrowserForwardButton"]
    }

    private var reloadStopButton: XCUIElement {
        application.buttons["BrowserReloadStopButton"]
    }

    private var bookmarkButton: XCUIElement {
        application.buttons["BrowserBookmarkButton"]
    }

    private var bookmarkEditor: XCUIElement {
        application.descendants(matching: .any)["BrowserBookmarkEditorSheet"]
    }

    private var bookmarkTitleField: XCUIElement {
        application.textFields["BrowserBookmarkTitleField"]
    }

    private var bookmarkSaveButton: XCUIElement {
        application.buttons["BrowserBookmarkSaveButton"]
    }

    private var bookmarkSearchField: XCUIElement {
        application.descendants(matching: .any)["BrowserBookmarkSearchField"]
    }

    private var bookmarkEditButton: XCUIElement {
        application.buttons["BrowserBookmarkEditButton"]
    }

    private var bookmarkDeleteButton: XCUIElement {
        application.buttons["BrowserBookmarkDeleteButton"]
    }

    private var bookmarkOpenButton: XCUIElement {
        application.buttons["BrowserBookmarkOpenButton"]
    }

    private var progressIndicator: XCUIElement {
        application.progressIndicators["BrowserLoadProgress"]
    }

    private var errorView: XCUIElement {
        application.descendants(matching: .any)["BrowserErrorView"]
    }

    private var errorReloadButton: XCUIElement {
        application.buttons["BrowserErrorReloadButton"]
    }

    private func assertCriticalControlsExist(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for (name, element) in [
            ("web view", application.descendants(matching: .any)["BrowserWebView"]),
            ("back button", backButton),
            ("forward button", forwardButton),
            ("reload button", reloadStopButton),
            ("bookmark button", bookmarkButton),
        ] {
            XCTAssertTrue(
                element.waitForExistence(timeout: 5),
                "Missing critical \(name) accessibility identifier.",
                file: file,
                line: line
            )
        }
    }

    private func assertAddressFieldIsFocused(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertTrue(
            addressField.waitForExistence(timeout: 5),
            "The address field did not appear.",
            file: file,
            line: line
        )
        XCTAssertTrue(
            addressField.isEnabled,
            "The address field is not interactive.",
            file: file,
            line: line
        )

        let focusProbe = "focus-probe"
        addressField.typeText(focusProbe)
        XCTAssertEqual(
            addressField.value as? String,
            focusProbe,
            "Typing without clicking did not reach the launch-focused address field.",
            file: file,
            line: line
        )
        addressField.typeKey("a", modifierFlags: .command)
        addressField.typeKey(.delete, modifierFlags: [])
    }

    private func navigate(to path: String) {
        let url = fixtureURL(path)
        submit(url)
        waitForAddress(url)
    }

    private func submit(_ text: String) {
        application.activate()
        application.typeKey("l", modifierFlags: .command)
        let field = addressField
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeKey(.delete, modifierFlags: [])
        field.typeText(text)
        XCTAssertEqual(
            field.value as? String,
            text,
            "Address-field input was contaminated before submission."
        )
        field.typeKey(.return, modifierFlags: [])
    }

    private func showBookmarks() {
        application.activate()
        application.typeKey("b", modifierFlags: [.command, .option])
        XCTAssertTrue(
            application.windows["BrowserBookmarksWindow"]
                .waitForExistence(timeout: 3),
            "The Bookmarks manager did not appear."
        )
    }

    private func showPrivacy() {
        application.activate()
        let privacyMenu = application.menuBars.menuBarItems["Privacy"]
        XCTAssertTrue(privacyMenu.waitForExistence(timeout: 3))
        privacyMenu.click()
        let manageWebsiteData = application.menuItems[
            "Manage Website Data…"
        ]
        waitUntilEnabled(manageWebsiteData)
        manageWebsiteData.click()
        XCTAssertTrue(
            application.windows["BrowserPrivacyWindow"]
                .waitForExistence(timeout: 3),
            "The Privacy window did not appear."
        )
    }

    private func replaceText(in field: XCUIElement, with text: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.click()
        field.typeKey("a", modifierFlags: .command)
        if text.isEmpty {
            field.typeKey(.delete, modifierFlags: [])
        } else {
            field.typeText(text)
        }
    }

    private func waitForAddress(
        _ expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", expected),
            object: addressField
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 5),
            .completed,
            "Displayed URL did not become \(expected).",
            file: file,
            line: line
        )
    }

    private func waitForValue(
        _ element: XCUIElement,
        equalTo expectedValue: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", expectedValue),
            object: element
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 5),
            .completed,
            "Element value did not become \(expectedValue).",
            file: file,
            line: line
        )
    }

    private func waitForValue(
        _ element: XCUIElement,
        containing expectedText: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format: "value CONTAINS[c] %@",
                expectedText
            ),
            object: element
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 5),
            .completed,
            "Element value did not contain \(expectedText).",
            file: file,
            line: line
        )
    }

    private func waitForWindowTitle(
        _ expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "title == %@", expected),
            object: mainWindow
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 5),
            .completed,
            "Window title did not become \(expected).",
            file: file,
            line: line
        )
    }

    private func waitUntilEnabled(
        _ element: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"),
            object: element
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 5),
            .completed,
            "Control did not become enabled.",
            file: file,
            line: line
        )
    }

    private func waitForButtonLabel(
        _ button: XCUIElement,
        containing expectedText: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format: "label CONTAINS[c] %@",
                expectedText
            ),
            object: button
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 5),
            .completed,
            "Button label did not contain \(expectedText).",
            file: file,
            line: line
        )
    }

    private func pageText(_ text: String) -> XCUIElement {
        application.staticTexts[text]
    }

    private func fixtureURL(_ path: String) -> String {
        Self.fixtureOrigin + path
    }

    @discardableResult
    private func requestFixture(_ path: String) async throws -> Data {
        let url = try XCTUnwrap(URL(string: fixtureURL(path)))
        return try await URLSession.shared.data(from: url).0
    }

    private func fixtureRequestCounts() async throws -> [String: Int] {
        let data = try await requestFixture("/stats")
        return try JSONDecoder().decode(
            [String: Int].self,
            from: data
        )
    }
}
