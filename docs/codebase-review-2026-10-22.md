# Browser codebase review — 2026-10-22

Status: Audit pass complete; remediation implemented and verified on 2026-10-22 (see the remediation update at the end). Of 14 findings, 10 are fixed, 3 are owner-accepted as-is (IN-01, BE-01, FE-01), and BE-03 was reassessed as intended design. None remain open.

Audit baseline: branch `main`, commit `fe477853d671783a357a0dad4b3416d0f5e1407d` ("Add manual WebKit connection reset for VPN recovery"). The working tree was clean at audit start. Source references describe this baseline unless a dated update says otherwise. No applicable AGENTS.md exists in the project or its parent.

## Purpose and method

Owner-requested thorough codebase audit, using the `codebase-audit` skill (imported from Codex into Claude Code for this run). Analysis and report only; no application, configuration, or test source is changed.

Layers, in review order: core (`BE`: address interpretation, navigation/blocking policy, tab lifecycle, bookmark persistence, rule preparation, website data, launch configuration), native AppKit presentation (`FE`: chrome, tab strip, sidebar, bookmark manager/editor, privacy window, menus), then integration/build/verification (`IN`: Makefile, schemes, test harness, scripts, docs vs. behavior).

Prior audit: [2026-09-06 review](codebase-review-2026-09-06.md), all eight findings remediated (G01–G06). Its fixes are rechecked here as counterevidence, not re-reported. Commits since that baseline (`ea65289..fe47785`): failed-document recovery (G05), Open Selected URL in New Tab, bookmarks sidebar, Makefile help/launch target, manual WebKit connection reset.

Accepted design, not treated as defects: personal-use AppKit/WKWebView browser; no history/session restore; memory-only tabs; pinned bundled AdGuard rules; exact-host exceptions; consent-bound per-tab local-folder grants; magnet-only direct-click external handoff; HTTPS-first host inference (including `localhost`, which is tested); deferred Phase-6 features (downloads, file upload, JS alert/confirm/prompt panels, HTTP auth, find-in-page, permissions, full screen, printing).

Evidence: confirmed (source), confirmed (reproduced), risk, or debt. Priority: P1 significant correctness/data/resource issues; P2 important robustness/performance/architecture work; P3 smaller cleanup. Evidence strength and priority are independent.

## Review map

Fourteen findings: **3 core, 5 native presentation, 6 integration/project**. Priority: **1 P1, 3 P2, 10 P3**. Evidence: **4 Confirmed (reproduced)** (BE-01, BE-02, FE-01, IN-01), **4 Confirmed (source)** (FE-02, FE-03, IN-04, IN-05), **2 Risk** (BE-03, FE-04), **4 Debt** (FE-05, IN-02, IN-03, IN-06). These counts describe the original audit; all findings were later resolved (see Current status). This is a completed review pass, not a claim that every defect has been found.

| Discussion area | Findings | Why it matters |
| --- | --- | --- |
| Tests exempt the real-world condition | IN-01, BE-02, FE-01 | Every web fixture is an IP-literal origin, a single document, or a single cookie. ATS, `pushState`, and host-only/domain cookie pairs are exactly what those fixtures cannot express, so 183 green tests coexist with a P1 and two P2s. |
| Heuristic identity drops a distinguishing bit | BE-02, FE-01, FE-05 (bookmark match) | Normalization (stale document URL, dot-stripped cookie domain, `==` vs symlink-aware match) merges two distinct things, and the UI then acts on the wrong one. |
| Central input path lacks a fallback | BE-01 | The address field has no search fallback for ambiguous dotted tokens, so common queries fail. |
| Command routing ignores the key window | FE-03, FE-04 | G04 fixed Close only; other shortcuts and stock context-menu items still act on, or silently fail in, a different context. |
| Silent loss or decay in persisted state | BE-03, IN-02 | Invalid state becomes "empty" and is then overwritten; pinned lists age with no repeatable refresh path, and superseded artifacts accumulate. |
| Shared busy state written from two places | FE-02 | One call site forgets the in-flight reset task. |
| Verification hygiene relies on convention | IN-03, IN-04, IN-05, IN-06 | Artifacts accumulate (9.9 GB of results), terminal-close leaves supervised runs orphaned, one release gate matches a substring, and scheme selection has no automated check. None currently masks a failing test. |

Counterevidence traced and found sound (not re-reported): the prior audit's G01–G06 fixes are present (magnet rejection before search, testhost isolation, journaled bookmark transactions with SHA-256 corrupt-copy dedup, key-window Close routing, failed-document recovery with stale guards, benchmark dependency closure). Tab teardown clears delegates, KVO, grants, and content-controller bookkeeping. Local-file containment resolves symlinks before prefix checks, and one-shot approval is cleared on commit. The strengthen-only blocker state machine rejects stale callbacks. Website-data deletes re-read WebKit before reporting. Revealed cookie values are scrubbed from the field editor, undo, and accessibility. The private network-reset hook is signature-checked and typed correctly. The DEBUG profile probe uses its own data-store UUID.

Accepted-design consequences worth revisiting (decisions, not defects): scripted `window.open` is denied, so popup-based "Sign in with …" flows fail without feedback. Quit/Close Window with many tabs has no confirmation and no session restore. HTTPS inference for `localhost`/LAN IPs is intentional and tested, but it is unusual for development servers.

## Grouped plan of attack

Originally proposed only. On 2026-10-22 the owner authorized G02 and all P3 items, and accepted IN-01 and BE-01 as-is. Statuses below reflect the remediation update.

| Group | Cohesive outcome | Findings / portions | Prerequisites | Status |
| --- | --- | --- | --- | --- |
| G01 | Plain-HTTP sites load; the packaged app proves it | IN-01 | None | Not pursued: owner accepted HTTPS-only behavior |
| G02 | Same-document history navigation never leaves a tab "navigating" | BE-02 | None | Implemented, verified |
| G03 | Cookie rows have exact identity; Privacy busy state is single-sourced | FE-01, FE-02, FE-05 (Privacy search portion) | None | FE-02 and FE-05 portion implemented; FE-01 accepted as-is |
| G04 | Ambiguous dotted input reaches search | BE-01 | Decision below | Not pursued: owner accepted current behavior |
| G05 | Commands and context-menu items act on the context that shows them | FE-03, FE-04 | None (interactive check for FE-04) | Implemented, verified (live right-click pending) |
| G06 | Persisted-state and maintenance hygiene | BE-03, IN-02, FE-05 (remaining portions) | None | Implemented (BE-03 reassessed; real-converter run pending) |
| G07 | Verification harness cleans up after itself and enforces its contracts | IN-03, IN-04, IN-05, IN-06 | None; do G07's IN-04 SIGHUP fix before the next interactive run | Implemented, verified |

### G01 — Allow cleartext web content

Scope: add `NSAllowsArbitraryLoadsInWebContent` to the generated Info.plist for the app target (production and testhost). Give -1022 a distinct error message. Make `scripts/verify-release.sh` assert the key in the packaged plist.

Compatibility and tradeoffs: the key affects only WKWebView loads; the app has no other networking. Mixed-content blocking inside HTTPS pages is unchanged. If HTTPS-first-with-fallback is desired for explicit `http://` input, `preferredHTTPSNavigationPolicy` is a separate product choice.

Acceptance: the ATS probe passes for a named host; `make verify-release` fails when the key is missing; manual Release smoke on `http://neverssl.com/` and an `http://`→`https://` redirect link.

### G02 — Settle same-document navigations

Scope: update `currentDocumentURL` from `url` KVO when no provisional navigation is in flight. Add a generation-guarded idle settlement for approved main-frame actions that never start provisionally. Add regression tests (pushState + anchor, pushState + Back/Forward, fragment control, a cross-document navigation immediately after).

Compatibility: preserve strengthen-only and stale-callback rules; never relax policy from this path. Existing G05 blocked-redirect settlement must keep its guards (it shares the "unbound approved action" shape).

Acceptance: hidden real-WebKit tests above; `hasActiveNavigation == false` and the Privacy toggle is enabled on a pushState fixture.

### G03 — Exact cookie identity and Privacy busy state

Scope: add a host-only/raw-domain component to `WebsiteCookieID` and its accessibility token. Keep the normalized domain as the grouping key. Fix `updatePrivacyBlockingResetState` to OR in the running reset task. Keep one search rebuild path.

Compatibility: the exact-domain "delete all cookies for domain" action must still remove both variants. The snapshot test that asserts the collapse is updated deliberately.

Acceptance: two-variant non-persistent-store test (distinct IDs, correct reveal, single deletion); a stalled-reset test keeps controls disabled after a site toggle.

### G04 — Search fallback for ambiguous dotted input

Scope: interpreter and/or navigation-failure fallback per the decision; tests for `node.js`, `3.14`, `v1.2`, `user@example.com`, explicit `https://` never falling back, and stale-failure guards.

Decisions needed: (a) DNS-failure fallback to search for *inferred* hosts only (closest to Safari/Chrome; requires per-attempt tracking), (b) a bundled public-suffix/TLD list (offline, larger bundle), or (c) narrow heuristics (numeric last label, known file extensions). Should the fallback search be automatic, or offered as a button on the error page (no query leaves the machine without an explicit click)?

### G05 — Window-scoped commands and honest context menus

Scope: validate or route navigation/zoom/reload items by key window, following the G04 Close pattern. In `willOpenMenu`, convert the stock new-window link item into an explicit new-tab request and remove image/frame/download items until downloads exist.

Acceptance: hidden menu-key-equivalent tests with an auxiliary key window; an interactive/manual right-click check for every remaining stock item.

### G06 — Persisted-state hygiene and filter maintenance

Scope: per-entry tolerant site-exception decoding that never overwrites unreadable state. A developer-only, reproducible rule-update script. Pruning of superseded production rule-list identifiers after successful current preparation. The remaining FE-05 cleanups.

Acceptance: stale-entry fixture test; the script reproduces current bundled bytes at the recorded commits; the store holds only current and last-valid lists after a simulated update.

### G07 — Harness hygiene and enforcement

Scope: per-test WebKit store removal; result-directory retention; SIGHUP/SIGQUIT cancellation; curl time limits; Makefile job-range validation; flag-only hardened-runtime parsing; automated scheme-selection diff; status-doc count refresh.

Compatibility: cleanup must stay confined to the testhost identity and the run's own products (never the production Browser or container). Keep failed-run artifacts.

Acceptance: extended `scripts/test-verification-session.py` cases (SIGHUP, silent listener); a negative hardened-runtime fixture; a scratch-worktree selection-drift failure; before/after store counts from an owner-run `make test`.

## Core findings

### BE-01 — Dotted single-token searches navigate to nonexistent hosts or show "Invalid Address" (P2, Confirmed (reproduced))

Status: Accepted as-is by the owner on 2026-10-22 (no change). See remediation update.

Evidence: `Browser/AddressInterpreter.swift:124–132` tries `inferredHTTPSURL` before search; `isValidHost` (`:318–371`) accepts any two-or-more alphanumeric labels with no public-suffix or TLD check, and `looksLikeMalformedHostInput` (`:271–296`) turns any remaining dotted token into `.malformedURL` instead of search.

Trigger → mechanism → impact: typing `node.js`, `next.js`, `vue.js`, `Swift.Task`, or `v1.2` produces `https://node.js` etc., which then fails with a DNS error page; typing `3.14` or `1.5` produces "Invalid Address". Neither offers a search. These are common developer-style queries in the central workflow; the user must add a space or other punctuation to search. A related case: `user@example.com` is rejected as malformed rather than searched.

Direction: decide the rule for ambiguous dotted tokens. Options: (a) fall back to search when an inferred-host navigation fails with a DNS "cannot find host" error (keeps HTTPS-first, needs a per-attempt flag so a stale failure cannot redirect a newer navigation); (b) a small local TLD allowlist or bundled public-suffix list (offline, no network); (c) search when the last label is numeric or a well-known file extension. (a) matches Chrome/Safari behavior most closely. Keep existing `localhost`, IPv4/IPv6, host:port, and Command-Return `.com` completion behavior.

Verify: probe below; add interpreter tests for `node.js`, `3.14`, `v1.2`, `user@example.com`, and an integration test for any DNS-failure fallback (only for inferred hosts, never for explicit `https://` input).

### BE-02 — Same-document history navigation on `pushState` sites leaves a tab permanently "navigating" (P2, Confirmed (reproduced))

Status: Implemented and verified 2026-10-22 (G02). The trigger is broader than first recorded: a repeated click on the same anchor sticks on any page. See remediation update.

Evidence: `Browser/TabController.swift:506–534` approves a main-frame action (`approveAction()`, or `beginRequest()` first via `goBack`/`goForward` at `:210–236`) unless `ContentBlockingNavigationURL.isFragmentOnlyNavigation` (`Browser/ContentBlockingNavigationState.swift:18–48`) says the target differs from `currentDocumentURL` only by fragment. `currentDocumentURL` is written only at commit (`TabController.swift:629`) and on recognized fragment actions (`:513`); KVO `url` changes from `history.pushState`/`replaceState` update only `observedURL` (`:943–956`). An approved attempt is cleared only by provisional/commit/fail callbacks (`ContentBlockingNavigationState.swift:125–200`), which WebKit never sends for same-document navigations. `hasActiveNavigation` (`:59–61`) then stays true.

Trigger → mechanism → impact: on any history-API site (YouTube, GitHub, X, Reddit, most documentation SPAs), either (a) click an in-page `#anchor` after the app has pushed a new URL, or (b) press Back/Forward between two `pushState` entries. The decision is not recognized as same-document, an attempt is opened, and no callback ever resolves it. Until a later full navigation: the Privacy toggle shows "No Website Selected" and is disabled (`BrowserWindowController.swift:1094–1101`); Option-Command-P beeps (`:733–743`); same-host sibling tabs show "Wait for <host> Navigation to Finish" (`:1102–1113`); Reset Site Exceptions refuses when the stuck tab's host is excepted (`:1268–1280`); failed-document recovery is gated off (`TabController.swift:321–333`). Policy is not weakened (later commits still resolve correctly), so this is a stuck-control defect, not a protection bypass.

Direction: two parts. (1) Track the live same-document URL: when `url` KVO changes with no provisional navigation in flight, update `currentDocumentURL`, so fragment detection compares against the real document URL. (2) History traversal between `pushState` entries cannot be detected from URLs at all, so add an idle settlement for an approved main-frame action that receives no `didStartProvisionalNavigation` (similar to the existing `settleBlockedAction` generation guard at `:1066–1087`), resolving it with `.strengthenOnly`/`.none` because the document did not change. Keep the strengthen-only contract and stale-callback guards; do not use WebKit's private same-document delegate unless the owner accepts more SPI.

Verify: the reproduction below as a hidden `WKWebView` test (pushState + anchor; pushState + `goBack`; plus the fragment-only control), asserting `hasActiveNavigation == false` and an enabled toggle; and a cross-document navigation started right after a same-document one still commits under the correct policy.

### BE-03 — One unreadable site-exception entry silently drops every exception, and the next toggle overwrites them (P3, Risk)

Status: Withdrawn as a behavior change on 2026-10-22. Fail-closed-and-heal is a deliberate, tested design (`BrowserTests/ContentBlockerSitePolicyStoreTests.swift:73–104`). The residual normalization risk is now guarded by a test. See remediation update.

Evidence: `Browser/ContentBlockerSitePolicyStore.swift:42–59` returns `[]` when the stored array fails to decode, has a duplicate, or contains any host whose `ContentBlockerSite(host:)` normalization differs from the stored string. `setException` (`:29–40`) starts from that empty set and persists only the new host.

Trigger → mechanism → impact: today `setException` writes only normalized hosts, so no in-app path produces a bad entry. A future change to `ContentBlockerSite.normalize` (`Browser/ContentBlockerSite.swift:45–116`) that is not perfectly idempotent for previously stored hosts, or a hand-edited preference, would make all exceptions disappear with no message. That is the fail-safe direction for protection, but the user's exception list is then permanently replaced on the next Option-Command-P. Bookmarks use a stricter, visible variant of the same all-or-nothing pattern (`Browser/BookmarkRepository.swift:445–465`), but they surface recovery and preserve the original, so they are not counted here.

Direction: decode per entry, keep valid hosts, and never persist over an undecodable value (leave it in place, or move it aside under a dated key). Add a fixture test with one stale entry.

Verify: seed `[valid, invalid]`; the valid host stays excepted, and a toggle preserves it.

## Native presentation findings

### FE-01 — A host-only cookie and a same-name domain cookie share one identity; selecting, revealing, and deleting act on the wrong cookie (P2, Confirmed (reproduced))

Status: Accepted as-is by the owner on 2026-10-22 ("I am ok with same name cookies. That is a real edge case."). No change.

Evidence: `Browser/WebsiteDataSnapshot.swift:4–36` builds `WebsiteCookieID` from `normalizedDomain`, which strips leading dots, so `example.com` (host-only) and `.example.com` (domain) with the same name and path are equal. Both become rows of one group with the same ID (`:215–223`, sorted domain-first by `cookieSort`). `selectedCookie` resolves through `snapshot.cookie(id:)`, which returns the first match (`Browser/WebsiteDataPrivacyWindowController.swift:938–950`, `WebsiteDataSnapshot.swift:247–251`). Delete Cookie promises "Only this cookie for <domain> will be deleted" (`WebsiteDataPrivacyWindowController.swift:550–561`), but `WebsiteDataController.deleteCookie(withID:)` deletes every cookie with that ID and reports success (`Browser/WebsiteDataController.swift:32–57`). `BrowserTests/WebsiteDataSnapshotTests.swift:34–48` asserts the collapse as intended behavior.

Trigger → mechanism → impact: a site sets `sid` both host-only and with `Domain=example.com` (common with analytics and with sites migrating cookie scope). Selecting the host-only row shows the domain cookie's metadata, and Reveal shows the *other* cookie's secret value. Delete removes both after a confirmation that names one, which can sign the user out, and the result says "Cookie deleted." WebKit itself distinguishes the two: deleting the exact `HTTPCookie` leaves the other in place.

Direction: include a host-only bit (`!cookie.domain.hasPrefix(".")`) or the raw lowercased domain in `WebsiteCookieID` and its accessibility token. Keep the normalized domain as the group key, so "delete all cookies for this domain" still covers both. Update the snapshot test.

Verify: both variants in a non-persistent store → two distinct IDs; each row shows its own domain/value; Delete Cookie removes exactly one.

### FE-02 — Toggling a site exception re-enables Privacy controls while compiled-rule deletion is still running (P3, Confirmed (source))

Status: Implemented and verified 2026-10-22 (G03 portion). See remediation update.

Evidence: `deleteCompiledContentBlockingArtifacts` marks the Privacy window busy and stores `compiledBlockerResetTask` (`Browser/BrowserWindowController.swift:1335–1366`). `toggleContentBlockingForCurrentSiteAndReload` ends with an unconditional `updatePrivacyBlockingResetState(isBusy: false, statusMessage: nil)` (`:789–792`). `showWebsiteData` does account for the task (`:713–716`), so the two call sites have drifted.

Trigger → mechanism → impact: start Delete Compiled Blocking Rules, then press Option-Command-P before it finishes. Refresh, website-data deletes, and Reset Site Exceptions become enabled mid-operation, and the "Deleting compiled blocking rules…" status disappears. Compiled-rule delete itself stays disabled through `ContentBlockingCoordinator.canResetCompiledArtifacts`. This breaks the mutual-exclusion contract covered by `testWebsiteDataAndBlockingOperationsDisableEachOther`; no data hazard was found.

Direction: compute `isBusy` inside `updatePrivacyBlockingResetState` as `isBusy || compiledBlockerResetTask != nil`, and keep the in-progress status message.

Verify: stall `resetCompiledArtifacts` in a test, invoke the toggle, and assert that controls stay disabled and the status is retained.

### FE-03 — Explicit-target shortcuts act on the browser window while Bookmarks or Privacy is key (P3, Confirmed (source))

Status: Implemented and verified 2026-10-22 (G05). See remediation update.

Evidence: every Navigate/View/Bookmarks/Privacy menu item has `target = navigationTarget` (`Browser/AppDelegate.swift:456–576`), so AppKit dispatches it to `BrowserWindowController` regardless of the key window. G04 fixed this for Close only (`Browser/BrowserCloseCommand.swift`). `validateMenuItem` (`Browser/BrowserWindowController.swift:810–862`) never consults the key window.

Trigger → mechanism → impact: with Bookmarks or Privacy key, Command-R reloads the hidden main page (losing unsaved form input), Command-[ / Command-] navigate it, Command-+/−/0 zoom it, and Command-L moves first responder in a non-key window, so nothing visible happens. This is the same root cause as the prior FE-01, with less destructive effects.

Direction: either validate these items as disabled unless the browser window is key (Add Bookmark and Show Bookmarks/Website Data can stay enabled), or route them through the responder chain with `target = nil`. Keep the existing Close command behavior.

Verify: a hidden-fixture `NSMenu.performKeyEquivalent` test like the G04 tests, with an auxiliary window key: zero reloads/navigations/zoom changes.

### FE-04 — WebKit's "Open Link in New Window" and download context-menu items are shown but do nothing (P3, Risk)

Status: Implemented and verified 2026-10-22 (G05); a live right-click check remains. See remediation update.

Evidence: `BrowserWebView.willOpenMenu` (`Browser/BrowserWebView.swift:8–29`) adds one item but leaves WebKit's stock items. A context-menu "Open Link/Image/Frame in New Window" reaches `createWebViewWith` (`Browser/TabController.swift:575–608`), and `NewContextNavigationPolicy` (`Browser/NavigationPolicy.swift:89–116`) returns `.deny` unless the action is a link activation with `buttonNumber == 1`. WebKit's `ContextMenuController::openNewWindow` passes the stored context-menu event (a secondary click) or none, so the action cannot qualify. The download items have no `WKDownloadDelegate` (downloads are deferred). No "Open Link in New Tab" item exists, although Command-click and the selected-URL item do open tabs.

Trigger → impact: right-click a link and choose Open Link in New Window, Download Linked File, or Download Image. Nothing happens and no message is shown. This contradicts the architecture's "unsupported … fail closed with understandable UI" (`docs/architecture.md` §10).

Direction: public API does not expose the context-menu link URL directly. In `willOpenMenu`, retitle the stock item identified as `WKMenuItemIdentifierOpenLinkInNewWindow` to "Open Link in New Tab" and set a one-shot, menu-scoped flag so the next `createWebViewWith` from this view is treated as an explicit user request (clear it when the menu closes). Remove the image/frame new-window and download items until downloads exist. Foreground vs. background is a product choice.

Verify (missing runtime check): right-click a link in the Release app and choose each stock item. A context menu cannot be driven in a background test, so this needs the interactive suite or a manual check.

### FE-05 — Small drift and dead UI (P3, Debt)

Status: Implemented 2026-10-22 (all four portions). See remediation update.

- The Bookmarks manager decides "Add" vs "Edit Current Page" with URL `==` (`Browser/BookmarkManagerWindowController.swift:503–512`), while the main window uses `Bookmark.refersToSamePage` (`Browser/BrowserWindowController.swift:1198–1205`), which resolves local-file symlinks. For a symlinked local bookmark the manager button reads "Add…" while the star reads Edit; the action itself is routed correctly.
- `BrowserErrorView` has a host label (`Browser/BrowserChromeView.swift:269,301–305,355–356`), but its only caller always passes `host: nil` (`Browser/BrowserWindowController.swift:1184–1189`), and `BrowserTabErrorState` has no host field. The host appears only inside the message text.
- The Privacy search field rebuilds and reloads its rows twice per keystroke: once through its action (`Browser/WebsiteDataPrivacyWindowController.swift:262–265,524–526`) and once through `controlTextDidChange` (`:241–243`). The result is idempotent; no measured cost is claimed.
- `ContentBlockerSitePolicyStore.defaultKey` is `contentBlocker.siteExceptions` (`:12`), but production always passes `contentBlocker.sitePolicy` (`Browser/BrowserLaunchConfiguration.swift:87–89`). The default is unused and misleading.

Direction: share one bookmark-match helper; remove the host label or populate it from `BrowserErrorPresentation`; keep one search path; drop or align the default key.

## Integration and project findings

### IN-01 — App Transport Security blocks every cleartext `http://` page on a named host (P1, Confirmed (reproduced))

Status: Accepted by the owner on 2026-10-22 as intended behavior (HTTP beyond local addresses should not load). No change. See remediation update.

Evidence: `Browser.xcodeproj/project.pbxproj:430–435,468–473` generates the app Info.plist with no `NSAppTransportSecurity` dictionary; the built `.build/DerivedData/Build/Products/Release/Browser.app/Contents/Info.plist` confirms none. Navigation policy explicitly allows `http` (`Browser/NavigationPolicy.swift:53–55`), the address field accepts explicit `http://` (`Browser/AddressInterpreter.swift:109–114`), and bookmarks accept `http` (`Browser/Bookmark.swift:60–62`). WebKit applies the app's ATS policy to web-content loads. `Browser/BrowserPageError.swift:105–113` classifies the resulting `NSURLErrorAppTransportSecurityRequiresSecureConnection` (-1022) as `.tlsFailure`.

Trigger → mechanism → impact: follow any `http://` link, bookmark, or typed URL whose host is a DNS name — including the very common old `http://` links that would redirect to HTTPS, HTTP-only sites, and LAN devices addressed by hostname (other than `.local`/single-label names). The request is refused before it leaves the process, and the tab shows "Secure Connection Failed — couldn’t establish a secure connection to <host>" with a Try Again button that can never succeed. The message misattributes a local policy refusal to the server. The automated suites never see this because every fixture uses `http://127.0.0.1`, which ATS exempts.

Direction: add `NSAppTransportSecurity` → `NSAllowsArbitraryLoadsInWebContent = YES` via `INFOPLIST_KEY_…`/an Info.plist fragment (scoped to web views; the app has no other networking). Optionally pair with `WKWebpagePreferences.preferredHTTPSNavigationPolicy = .automaticFallbackToHTTP` if HTTPS-first with fallback is wanted for explicit `http://` input; that is a product decision. Map -1022 to its own message if the key is ever removed. Have `scripts/verify-release.sh` assert the key in the packaged Info.plist, since a runtime test against a named host needs DNS.

Verify: the probe below before/after; manual smoke `http://neverssl.com/` and an `http://` link that redirects to HTTPS in the Release app; packaged-Info.plist assertion in `make verify-release`.

### IN-02 — The manual filter-update path is not repeatable and leaves superseded compiled lists behind (P3, Debt)

Status: Implemented 2026-10-22 (G06); a real-converter reproduction run is pending owner approval. See remediation update.

Evidence: the bundled lists date from 2026-07-26 (`Browser/ContentBlockerRules/ContentBlockerManifest.json`), unchanged since `074fc81`. The manifest records the source commit, converter commit, binary hash, and arguments, but no script in `scripts/` or Make target fetches, converts, re-hashes, and rewrites the manifest. The architecture calls updates "manual and release-bound" (`docs/architecture.md:415`). On a successful preparation, `ContentBlockerRuleSetResolver.prepare` records the new identifiers (`Browser/ContentBlockerRuleSetResolver.swift:85–91`), but nothing removes previously cached identifiers. They leave the store only via the manual "Delete compiled blocking rules" action. A read-only listing of the production rule store shows 25 MB + 46 MB for the current pair, plus two leftover pre-G02 artifacts (`browser-ui-test-content-blocking-v1-…`, `phase1-content-rule-probe-v1`).

Impact: protection quality decays as the pinned lists age (the README already disclaims newer trackers). The first real update will be an ad-hoc reconstruction from manifest fields, and each update then leaves about 70 MB of unreferenced compiled data in the container. No user-facing failure today.

Direction: add a developer-only `scripts/update-blocker-rules.sh` that reproduces the pinned conversion from the manifest's recorded inputs, verifies hashes, and rewrites the manifest (still never run by the app). After a successful *current* preparation, remove cached identifiers in the production namespaces that are neither current nor last-valid. Keep the complete-set/last-valid fallback semantics.

Verify: rerunning the script at the recorded commits reproduces byte-identical rule files; after a simulated identifier change, the store holds only current plus last-valid lists.

### IN-03 — Routine verification leaves persistent artifacts that grow without bound (P3, Debt)

Status: Implemented and verified 2026-10-22 (G07). See remediation update.

Evidence: 19 test call sites create `BrowserProfile(dataStoreIdentifier: UUID())`, a *persistent* named WebKit store (`Browser/BrowserProfile.swift:19–24`). Examples: `BrowserTests/WebKitConnectionResetTests.swift`, `FailedDocumentRecoveryTests.swift`, `BookmarkSidebarTests.swift`, `SelectedURLTests.swift`, `TabManagerTests.swift`, `LocalFileAccessTests.swift`. Nothing in the repo calls `WKWebsiteDataStore.remove(forIdentifier:)`. Separately, `scripts/run-tests.sh:24` creates a new `.build/TestResults.XXXXXX` per run, and nothing prunes them; `make clean` (`Makefile:98–105`) only runs an Xcode clean. Measured: 190 result directories totaling 9.9 GB.

Impact: each background run adds roughly a dozen or more never-removed WebKit stores to the testhost container, and every run adds a result bundle. This contradicts G02's "disposable data" intent and slowly consumes disk. The testhost container itself was not inspected, to avoid a privacy prompt.

Direction: a shared test helper that removes each random store in teardown once its views are released; retain the last N result directories (keep failures) or prune passing `.xcresult` bundles.

Verify: count testhost `WebsiteDataStore` entries before/after `make test` (owner-run); two consecutive passing runs leave N result directories.

### IN-04 — Runner cancellation and bounds have gaps that matter most for interactive runs (P3, Confirmed (source))

Status: Implemented and verified 2026-10-22 (G07). See remediation update.

Evidence: `scripts/verification-session.py:49–50` handles only SIGINT/SIGTERM and starts the child with `start_new_session=True` (`:60`). Closing the terminal sends SIGHUP, whose default action kills the supervisor before its `finally` cleanup (`:71–88`), while the detached child session keeps running. Readiness polls use `curl` without `--max-time` (`scripts/run-tests.sh:39`, `run-performance-tests.sh:71`, `measure-resources.sh:192`, `run-cross-process-profile-probe.sh:29`; this portion is Risk). `BROWSER_BUILD_JOBS` is range-checked only inside the supervisor, after the Makefile's own `xcodebuild -jobs` build steps (`Makefile:6–7,16–29`; `BROWSER_BUILD_JOBS=64 make -n check` prints `-jobs "64"`).

Impact: closing the Terminal window during `make interactive-test` or `make performance INTERACTIVE=1` leaves desktop-driving automation running unsupervised, which is the owner's documented desktop-takeover concern. A silent listener on a fixture port can hang a run indefinitely, and an out-of-range job count runs a full unbounded build before the run is rejected.

Direction: route SIGHUP/SIGQUIT to `cancel`; add `--connect-timeout 1 --max-time 2`; validate the job range in the Makefile before any target runs.

Verify: add a SIGHUP case to `scripts/test-verification-session.py`; a silent-listener fixture fails within about 10 s; the 64-job dry run errors before any xcodebuild command.

### IN-05 — The hardened-runtime gate passes on any "runtime" substring in codesign output (P3, Confirmed (source))

Status: Implemented and verified 2026-10-22 (G07). See remediation update.

Evidence: `scripts/verify-release.sh:14–33` matches `*"runtime"*` against the entire `codesign --display --verbose=4` output, which includes `Executable=<full path>`.

Trigger → impact: if the Release configuration ever lost `--options=runtime` and the build path contained "runtime" (e.g. `make verify-release DERIVED_DATA=.build/runtime-check`; the docs already use this override style), the release gate would still report hardened runtime. This requires two preconditions, hence P3.

Direction: parse the `CodeDirectory … flags=0x…(…)` line and check for the `runtime` flag (bit 0x10000) only.

Verify: an ad-hoc-signed copy without hardened runtime under a `runtime-*` path fails the script.

### IN-06 — The test-selection contract is enforced only by review, and documentation counts have drifted (P3, Debt)

Status: Implemented and verified 2026-10-22 (G07). See remediation update.

Evidence: `scripts/run-tests.sh:58–63` prints the executed count but never compares it with the expected selection. `docs/status.md:3,12` ("Last updated 2026-10-20") reports 178 tests; the current baseline runs 183. README's historical UI-test count (13) predates the current 15.

Impact: today's correctness rests on manual review (README: "New test classes must be reviewed and added"). A new class added outside every scheme would silently never run, and the green count would not reveal it.

Direction: a pre-test check (shell or the Python supervisor) that diffs `class …: XCTestCase` declarations against the union of scheme `<Test Identifier>` entries, and fails on missing, duplicate, or stale names. Refresh `docs/status.md` with the 183-test baseline.

Verify: a dummy test class in a scratch worktree makes the check fail.

## Verification and review coverage

### Baseline checks

Environment: macOS 27.0 (Darwin 27.0.0) arm64, working directory `/Users/utpalrohan/code/browser`. Scratch artifacts under the session scratchpad (abbreviated **S**).

| Check / exact command | Working directory | Result and limits |
| --- | --- | --- |
| `make test` (→ `scripts/run-tests.sh`, DebugTesting, non-activating `com.utpalchakraborty.browser.testhost`, isolated storage) | repo root | Exit 0. **183 tests, 0 failures**, XCTest 11.4 s; runner self-tests 4/4. `.build/TestResults.ea6l7V/Browser.xcresult`. Background suite only. |
| `sh -n scripts/*.sh` (12 files); `python3 -I -m py_compile` (6 files, output to S) | repo root | Exit 0 (delegated harness review). Syntax only. |
| `./scripts/test-audit-container.sh` | repo root | Exit 0, PASS; synthetic container fixtures only. |
| `/usr/bin/python3 -I scripts/test-verification-session.py` | repo root | Exit 0, 4 tests OK; disposable processes. |
| `xcodebuild -list`; `make -n check/performance/interactive-test/blocker-benchmark/help`; `BROWSER_BUILD_JOBS=64 make -n check` | repo root | Exit 0. Dry runs only; the last shows `-jobs "64"` reaching xcodebuild (IN-04). |
| Scheme selection vs. `XCTestCase` declarations (grep/comm) | repo root | 34 classes; each in exactly one scheme; none missing or stale (IN-06 counterevidence). |
| `du -sch .build/TestResults.*` | repo root | 190 directories, 9.9 GB (IN-03). |
| Read-only listing of `~/Library/Containers/com.utpalchakraborty.browser/Data/Library/WebKit/ContentRuleLists/` | — | File names/sizes only, no contents (IN-02). |
| `make release-test`, `make verify-release` | — | **Not re-run.** Same-commit results from earlier today are recorded in `docs/vpn-reset-handoff-2026-10-22.md` (183 Release tests; package verification passed). Not re-run to avoid rebuilding the owner's `.build/DerivedData` Release app and competing with the concurrent harness review's runner lock. |
| Interactive/UI/performance suites, network audit, resource probes | — | **Not run** (owner constraint: no desktop takeover; privileged capture). |

### Isolated evidence

| Finding | Probe / reproduction | Expected and observed result | Limits |
| --- | --- | --- | --- |
| BE-01 | `xcrun swiftc -parse-as-library -swift-version 6 -default-isolation MainActor Browser/AddressInterpreter.swift Browser/LocalFileAccess.swift S/probe-address/main.swift`; interpret listed inputs | `node.js → https://node.js`, `next.js → https://next.js`, `Swift.Task → https://Swift.Task`, `v1.2 → https://v1.2`, `3.14 → malformedURL`, `1.5 → malformedURL`, `user@example.com → malformedURL`, `swift 6.2 → search` | Interpreter only; no network request made. |
| BE-02 | All `Browser/*.swift` except `AppDelegate.swift` (plus a 4-line `BookmarkLaunchConfiguration` shim) compiled with the app's Swift 6 / MainActor / complete-concurrency flags into `S/probe-spa/probe`. Production `TabController` with `contentBlockingCoordinator: nil`, `WebViewFactory(.nonPersistent())`, `.prohibited` activation, off-screen borderless window; `python3 -I -m http.server` on 127.0.0.1:18911 serving a page with `<a href="#section">`. | Control (no pushState) anchor click: `hasActiveNavigation=false`. After `history.pushState({}, '', '/b.html')` then anchor click: `true`, still `true` 2 s later, no server request. After pushState then `tab.goBack()`: `true`, still `true` 2 s later; a later real navigation to `/c.html` clears it. | Blocking coordinator absent (the navigation state machine runs regardless); menu presentation inferred from source, not driven. |
| FE-01 | Delegated probe `S/agent-websitedata/probe` (production `WebsiteDataSnapshot.swift` + `WebsiteDataController.swift`; `WKWebsiteDataStore.nonPersistent()`; `CFFIXED_USER_HOME` in S), re-run by the auditor. Sets `sid` host-only on `example.com` and with `Domain=.example.com`. | `IDs equal: true`; WebKit holds 2 cookies; snapshot has 1 distinct ID; resolving the second row's ID returns the first cookie's value; `deleteCookie(withID: hostOnly)` → `didRemove=true "Cookie deleted."`, remaining `[]`. A raw `WKHTTPCookieStore.deleteCookie(hostOnly)` (`probe2`) leaves the domain cookie. | No UI driven; the window's row/reveal behavior follows from the traced `selectedCookie` chain. |
| IN-01 | Minimal `WKWebView` probe `S/probe-ats/probe` with an embedded Info.plist containing only bundle id/name/type (no ATS keys, like the shipped app); `.nonPersistent()` store; local `http.server` on 127.0.0.1:18912. Loaded `http://127.0.0.1:18912/a.html` and `http://localtest.me:18912/a.html` (public DNS name resolving to 127.0.0.1). | IP literal: finished. Named host: `didFailProvisionalNavigation` `NSURLErrorDomain -1022` "App Transport Security policy requires the use of a secure connection"; server log shows only the IP request. | Unsandboxed CLI with equivalent Info.plist, not the signed app; one external DNS lookup, no external HTTP. |

### Scope and limitations

| Area / workflow | Review status | Evidence and remaining work |
| --- | --- | --- |
| Startup, launch modes, profile, preferences | Reviewed | AppDelegate, BrowserLaunchConfiguration, BrowserProfile, BrowserPreferences, WebViewFactory; DEBUG probe isolation checked. No live launch. |
| Address/search, navigation policy, external links, local files | Reviewed; interpreter probed | AddressInterpreter, NavigationPolicy, LocalFileAccess, TabController load paths. BE-01 reproduced. |
| Tabs, WebKit delegate lifecycle, blocker navigation state | Reviewed; real-WebKit probe | TabController, TabManager, ContentBlockingNavigationState, BrowserWindowController tab/menu paths. BE-02 reproduced. Back/forward-cache, process-swap, and memory-pressure paths not exercised. |
| Blocker preparation, packaging, exceptions | Reviewed | Resolver, service, bundle, site, stores, coordinator. Filter effectiveness and compilation time not re-measured. |
| Bookmarks (model, repository, coordinator, sidebar, manager, editor) | Reviewed | Journal/rollback logic re-read; no new defect beyond FE-05 drift. Mutation cost at 10k rows not measured. |
| Website data and Privacy window | Reviewed by delegated agent; key chain re-verified | FE-01 reproduced; FE-02 re-verified. Retained snapshot values after close noted as a non-finding (no leak channel). |
| Native chrome, tab strip, error view, menus, context menu | Reviewed | FE-03/04/05. Keyboard/visual/accessibility acceptance not performed. |
| WebKit connection reset (newest feature) | Reviewed | Typed SPI call, validation, and tests read; no defect found. |
| Build, schemes, scripts, fixture server, release gate | Reviewed by delegated agent; key claims re-verified | IN-03–IN-06. Privileged/network/resource scripts read, not run. |
| ATS / packaged-app networking | Probe with equivalent Info.plist | IN-01. Not reproduced in the signed, sandboxed app itself. |

Not in scope or not verified: interactive UI and performance suites; packaged-app manual flows (context menu, keyboard routing); network-privacy capture; third-party rule licensing and freshness beyond dates; security certification. Passing background tests do not establish UI, packaged-app, or performance acceptance. Deferred Phase-6 features (downloads, file upload, JS dialogs, HTTP auth, find-in-page, permissions) are accepted scope, not findings. Note that today they fail silently rather than with the "understandable UI" required by `docs/architecture.md` §10, which is worth weighing when they are scheduled.

Two delegated reviews (website-data/Privacy; build/test/scripts) ran read-only, in parallel with the auditor's pass. Every retained finding from them was re-verified against source, and FE-01's probe was re-run by the auditor.

Task-authored repository changes: this report only. Disposable probes, their sources, a local `http.server` fixture, and module caches are under the session scratchpad (**S** = `/private/tmp/claude-501/-Users-utpalrohan-code-browser/dd21fc3e-e094-4a51-a47a-7b1bb15bc15e/scratchpad`) and may expire; the findings record enough to rebuild each probe. `make test` added one result directory under `.build/`. The Codex `codebase-audit` skill was copied to `~/.claude/skills/codebase-audit/` (outside the repo) at the owner's suggestion. No production app launch, user-data mutation, branch, or commit.

## Continuation checkpoint

2026-10-22: all three requested layers are complete at the scope above. Fourteen findings are open; G01–G07 are proposed only. Highest value per effort: **G01** (one Info.plist key plus a release-gate assertion fixes the P1), then **G02** and **G03**. G04 needs the owner's search-fallback decision. G07's SIGHUP fix should precede the next interactive run. Remaining verification: packaged-app confirmation of IN-01 and FE-04, interactive checks for FE-03, and owner-run testhost store counts for IN-03. When remediating, preserve these IDs and add dated outcomes below rather than editing the original evidence.


## Remediation update — 2026-10-22 (current checkpoint)

Owner direction (2026-10-22): "I think it not loading a http beyond the local is good. We probably should never load a http. 2. is ok. 3. We should fix yes fix the 10 smaller items. especially deleting the old tests." Interpreted as follows: IN-01 is accepted as intended behavior; BE-01 is accepted as-is; fix BE-02 and every P3 (BE-03, FE-02–FE-05, IN-02–IN-06), starting with test-artifact cleanup. FE-01 (P2 cookie identity) was not mentioned at first; the owner later accepted it as an edge case. Committed and pushed on `main` as `6df8383` and `a07163f`.

### Implemented behavior

- **IN-03 (artifact cleanup):**
  - New `scripts/prune-results.sh` keeps the newest `BROWSER_KEEP_RESULTS` (default 3) directories per result kind; it never counts or removes symlinks or files. Every result-producing script calls it right after creating its own directory.
  - New `make clean-results` target.
  - One-time cleanup: kept the 3 newest of each script-produced kind, and removed all legacy ad-hoc outputs that no current script produces (`*.xcresult` bundles, `PerformanceLaunch*`, `PerformanceDiagnostics.*`, `ScrollGate.*`, `ContainerAudit.*`, `ContentBlockerBenchmark.*`, `CrossProcessProfileProbe.*`, UI diagnostics). `.build` went from 18 GB to 5.0 GB. Paths cited by older docs as historical evidence may no longer exist.
  - New background test `WebsiteDataStoreHygieneTests` (sorts last) removes every unused named WebKit store except the three fixed launch-mode profiles. It is guarded to run only under the testhost bundle identifier. The first run removed 315 accumulated stores; steady-state runs remove about 31, i.e. one run's worth.
- **IN-04:** the supervisor routes SIGHUP and SIGQUIT to cancellation; fixture `curl` calls use `--connect-timeout 1 --max-time 2`; the Makefile rejects `BROWSER_BUILD_JOBS` outside 1–8 before any recipe runs.
- **IN-05:** `verify-release.sh` checks only the `CodeDirectory` flag names for `runtime`.
- **IN-06:** new `scripts/check-test-selection.py` runs at the start of every `run-tests.sh` invocation and fails on unselected, doubly selected, or stale classes. README documents the rule.
- **BE-02:**
  - Detection: `isFragmentOnlyNavigation` now also treats a repeated identical fragment as same-document, and `TabController` excludes reloads, form submissions, and non-GET requests from that shortcut.
  - Live URL tracking: when `url` or `isLoading` KVO reports a same-origin URL change while WebKit is idle, `TabController.synchronizeSameDocumentURL` updates `currentDocumentURL`.
  - Settlement: the same handler resolves the latest attempt with `resolveSameDocumentNavigation()`, which returns `.none`, so policy is never relaxed.
  - G05's first-document and redirect paths are unaffected (they require a committed URL or a cross-origin change).
- **BE-03:** no behavior change (see status). Added `ContentBlockerSiteTests.testNormalizedHostsRoundTripUnchanged`, so a future normalization change cannot silently invalidate stored exceptions.
- **FE-02:** `updatePrivacyBlockingResetState` stays busy and keeps "Deleting compiled blocking rules…" while the reset task is in flight. The Privacy controller factory is internal so hidden tests can use it without showing the window.
- **FE-03:** `BrowserWindowController` takes an injectable `keyWindow` provider. Open Location, Back, Forward, Reload/Stop, and the zoom items validate as disabled while another window (Bookmarks, Privacy, or a sheet) is key. With no key window, behavior is unchanged.
- **FE-04:**
  - `BrowserWebView.willOpenMenu` removes WebKit's stock new-window and download items. Their identifiers were confirmed against the WebKit binary at runtime.
  - The link item is replaced with "Open Link in New Tab", which opens a background tab like Command-click.
  - The link URL is resolved at the click point in `WKContentWorld.defaultClient`, so page scripts cannot substitute it. Non-HTTP(S) results remove the item, and redundant separators are collapsed.
- **FE-05:**
  - The manager uses `Bookmark.refersToSamePage`.
  - The dead error-view host label was removed.
  - The Privacy search uses the field action only; the interactive test now sends that action.
  - `ContentBlockerSitePolicyStore.defaultKey` matches production.
- **IN-02:**
  - After a *compiled* (not cached) current preparation, the resolver removes earlier identifiers that match `<namespace>-<64 hex>` for the same namespaces, within the reset scope. Cached launches do no extra work.
  - New developer-only `scripts/update-blocker-rules.py`: `--verify` reproduces the bundled files byte-for-byte; `--registry-commit` regenerates them and rewrites the manifest. Pinning the verifier digest stays manual.

New background test classes are `SameDocumentNavigationTests`, `BrowserCommandRoutingTests`, `LinkContextMenuTests`, and `WebsiteDataStoreHygieneTests`, all added to the Browser scheme. `ContentBlockerRuleSetResolverTests` gained the namespace-pruning case. `HiddenBlockingBrowser` and `waitForWebKit` are shared test fixtures.

### Remediation verification

All commands ran from `/Users/utpalrohan/code/browser` in the isolated, nonactivating testhost; no interactive suite ran.

| Check | Result | Evidence / limits |
| --- | --- | --- |
| `make check` (Debug build, background Debug and Release suites, production Release build plus `verify-release`) | Exit 0. **194 tests, 0 failures** in DebugTesting and in ReleaseTesting; production Release verified (signature, arm64, sandbox, hardened runtime, pinned assets) | `.build/TestResults.tkDLQv`, `.build/TestResults.3gYu6H`; app at `.build/DerivedData/Build/Products/Release/Browser.app` |
| Negative control: scratch copy (outside the repo) with each behavioral fix neutralized but test seams kept, running `-only-testing` on the five affected classes | **All 10 new regression tests failed**; the other tests in those classes passed | Proves the tests detect BE-02, FE-02, FE-03, FE-04, IN-02, and the fragment rule |
| `/usr/bin/python3 -I scripts/test-verification-session.py` | 5/5 pass. The new SIGHUP case fails against the committed supervisor | Disposable processes only |
| `scripts/prune-results.sh` fixture (5 dated dirs, symlink, file, sibling prefix) | Keeps the newest N real directories; symlink, file, and sibling untouched; rejects bad prefix and count | Scratch tree |
| `scripts/check-test-selection.py` | Real tree passes; a fixture with an orphan class, a duplicate, and a stale name fails with all three messages | Scratch copy |
| Hardened-runtime gate | Real Release app passes. An ad-hoc bundle without runtime under `runtime-x/` passes the *old* check and fails the new one | Scratch bundle |
| `BROWSER_BUILD_JOBS={64,0,two,"2 3",""} make -n check` | Each stops before any xcodebuild command; `3` passes through | Dry runs |
| `scripts/update-blocker-rules.py --converter <stand-in>` | Both pinned FiltersRegistry sources downloaded and matched their recorded SHA-256. Identity stand-in → "reproduce", exit 0; wrong output → exit 1 with both mismatches. Rule files unchanged | Script mechanics only |
| `scripts/update-blocker-rules.py --verify` with the real converter (owner-approved; SafariConverterLib `7a2e93f` / v4.3.0 built with Swift 6.4) | First run: not byte-identical, but the same rules, rule counts, and byte lengths. Two plain runs of the converter gave two different hashes; two runs with `SWIFT_DETERMINISTIC_HASHING=1` gave identical output. The converter's order depends on Swift's per-process hash seed, so the bundled bytes cannot be reproduced exactly. Both lists match on the order-sensitive check: identical `ignore-previous-rules` sequences (6,041 and 2,579) and identical rule sets between them. The script now runs the converter deterministically and accepts an older bundle only by that check. Rerun: exit 0 for both lists | The binary hash differs from the recorded one (expected across toolchains). Rule files unchanged |
| `sh -n`, Python AST parse, `test-audit-container.sh`, `git diff --check` | Pass | Syntax and fixtures |

Not verified: the interactive AppKit/XCUI and performance suites; a live right-click in the packaged app (FE-04); packaged-app manual smoke of the changed shortcuts. The test-host hygiene count comes from in-process WebKit APIs, not from inspecting the container.

### Current status

Supersedes the "Continuation checkpoint" above. All fourteen findings are resolved: 10 implemented, and 3 owner-accepted as-is (IN-01, BE-01, FE-01). BE-03's behavior change was withdrawn with a guard test added. Remaining verification: the live context-menu check and the interactive suites. The real-converter check passed on 2026-10-22 (equivalent rules; see the table).
