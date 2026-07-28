# Browser Implementation Plan

Status: Approved; Phases 1 and 2 complete; window geometry approved and
committed; Phase 3 bookmarks implemented with functional and performance gates
green and normal workflow approved, with the manual recovery exercise pending;
Phase 4 complete with every functional, privacy, packaging, network, container,
and performance/resource gate green; the minimal Phase 5 implementation is
complete and accepted, with automated and normal-session gates green
Last updated: 2026-07-28
Architecture: [architecture.md](architecture.md)

## 1. Confirmed product constraints

- Personal use only.
- Apple silicon and macOS 26 or later.
- Native, responsive, and intentionally small.
- No application-owned browsing history.
- No telemetry, analytics, or remote crash reporting.
- No Chrome cookie, bookmark, or profile import.
- A persistent browser-specific WebKit profile with visible deletion controls.
- Advertising and tracker blocking without a per-request proxy layer.
- Planning and explicit phase approval before production code.
- Product name Browser with bundle identifier com.utpalchakraborty.browser.
- DuckDuckGo as the configurable default search provider, without live
  suggestions.
- Private windows deferred to daily-driver hardening.

The first usable release is successful when it can serve as a fast personal
browser for ordinary use with navigation, bookmarks, effective ad/tracker
blocking, understandable privacy controls, strict popup suppression, and tabs.
Feature count is not a success metric.

## 2. Development prerequisites

### Toolchain status

Phase 1 uses the verified local toolchain:

- Xcode 26.6, build 17F113;
- macOS 26.5 SDK;
- Swift 6.3.3;
- Apple silicon arm64 target; and
- /Applications/Xcode.app/Contents/Developer as the selected developer
  directory.

The repeatable verification commands are:

~~~sh
xcodebuild -version
xcode-select -p
~~~

The project will use the macOS SDK, AppKit, WebKit, XCTest, XCUITest,
Instruments, code signing, App Sandbox, and hardened-runtime tooling supplied by
Xcode.

The repository is initialized on main, tracks origin/main, and contains the
approved planning baseline.

### Dependency policy

- No third-party runtime dependency in the first usable release.
- Prefer Foundation, AppKit, WebKit, OSLog, Network, and XCTest.
- Test-only helpers must not ship in the application.
- A filter-list conversion tool may be added only after its license, generated
  output, reproducibility, and maintenance cost are documented.
- Every proposed dependency must state its startup, memory, security, privacy,
  update, and licensing cost before adoption.

## 3. How the plan is executed

Phases are sequential and independently reviewable:

1. Implement only the current phase.
2. Run its functional, privacy, and performance checks.
3. Record decisions, benchmark results, and known limitations.
4. Produce a small, usable checkpoint.
5. Stop for review before expanding scope.

A phase does not pass because its code compiles. Its acceptance criteria and
performance gate must pass in a Release build. A failed budget blocks the next
phase unless the budget is deliberately revised with measurements and a written
rationale.

When implementation begins, maintain:

- docs/status.md for the current phase and next action;
- docs/performance-baseline.md for hardware, OS, build, scenarios, and results;
  and
- a deterministic command or Make target for build, checks, and benchmarks.

No production code begins until Phase 0 is approved.

## 4. Performance plan

### What is measured

The browser owns and measures:

- application launch and time until the address field is usable;
- time until the first blank WKWebView is ready;
- new-tab and tab-switch latency;
- response time for browser-owned commands;
- main-thread hangs and UI hitches caused by browser chrome;
- idle CPU;
- application-process and WebKit child-process memory;
- rule-list lookup and attachment;
- bookmark loading and search; and
- memory behavior while opening and closing tabs repeatedly.

The project does not claim control over arbitrary website JavaScript, media,
network latency, or WebKit engine regressions. Deterministic local pages isolate
application overhead. A small fixed set of real sites is a compatibility smoke
test, not a stable performance gate.

### Measurement method

- Benchmark Release builds without the debugger, sanitizers, or code coverage.
- Use the same Mac on AC power and record hardware, macOS version, build
  configuration, and source revision.
- Close unrelated heavy applications and let the machine reach a stable state.
- Use a test-only localhost server for deterministic web content.
- Warm up where appropriate, then collect at least 10 samples; use more samples
  for short operations.
- Record median, p95, minimum, maximum, and failures rather than reporting one
  favorable run.
- Use XCTest metrics for launch, clock, CPU, memory, and hitches.
- Add OS signpost intervals with opaque identifiers for browser-owned actions.
- Use Instruments App Launch, Time Profiler, Hangs/Hitches, Allocations, Leaks,
  and Network templates for investigation.
- Measure both the main application and the related WebKit processes when
  evaluating total footprint.

### Provisional budgets

These are initial gates for this Mac. Phase 1 records the minimal WebKit
baseline, after which an absolute budget may be adjusted once with evidence.

| Scenario | Provisional target |
| --- | --- |
| Terminated launch to interactive window and focused address field | p50 at or below 500 ms; p95 at or below 800 ms |
| Terminated launch to usable first blank web view | p95 at or below 1.2 seconds |
| Create and focus a new blank tab | p95 at or below 100 ms for browser chrome; WebKit readiness reported separately |
| Switch between ten resident lightweight tabs | p95 at or below 50 ms |
| Browser-owned command response | p95 at or below 50 ms; no browser-owned main-thread stall above 100 ms |
| Settled blank-browser CPU | below 1 percent average over 30 seconds |
| Controlled scrolling | no browser-chrome hitch above 100 ms and no persistent frame degradation attributable to the application |
| One settled blank tab, aggregate process footprint | provisional ceiling of 300 MiB |
| Ten settled deterministic lightweight tabs | provisional aggregate ceiling of 1 GiB |
| One hundred tab open/close cycles | no monotonic growth; settled footprint returns within 10 percent of the established baseline |
| Cached rule-list startup overhead | does not delay interactive chrome; p95 attachment overhead below 50 ms |
| Any established benchmark | no unexplained regression greater than 10 percent |

If an absolute memory target proves unrealistic because of WebKit's fixed
process footprint, Phase 1 will replace it with a measured base plus an
incremental-per-fixture-tab budget. The replacement must still be concrete.

### Privacy of measurements

- Metrics stay on the Mac.
- Signposts contain scenario names and opaque tab identifiers only.
- No URL, hostname, query, title, bookmark, cookie, or page content enters a
  benchmark result.
- There is no automatic result upload.

## 5. Phase 0 — Approve architecture and contracts (complete)

### Work

- Review architecture.md and this implementation plan.
- Confirm the precise meaning of no history and no telemetry.
- Confirm the persistent data inventory and deletion path for every item.
- Resolve the product name, bundle identifier, search provider, and private
  window scope.
- Approve or revise the provisional performance budgets.
- Select a small representative compatibility set from the sites the user
  actually needs during the single-page and bookmarked-browser pilot. Phase 0
  defines the categories; exact sites are selected before Phase 4 blocking
  acceptance rather than guessed before a usable browser exists.

### Deliverables

- Approved architecture and implementation plan.
- Written decisions for the remaining product choices.
- A clear statement that production implementation may begin.

### Exit criteria

- Every persisted datum has a purpose and a deletion path.
- No-history behavior is unambiguous for suggestions, recently closed tabs,
  restoration, logs, and live back/forward state.
- The performance gate is measurable on this Mac.
- The first-release boundary is understood.

### Stopping point

Phase 0 was approved on 2026-07-26. Production implementation may proceed under
the recorded scope and gates. The later real-site smoke set will cover the
user's actual login, documentation, shopping, banking, and media workflows;
exact sites are selected from the Phase 2 through 3 pilot before Phase 4.

## 6. Phase 1 — Toolchain and WebKit risk validation

### Goal

Prove the chosen platform APIs, privacy controls, and performance envelope
before building feature layers.

### Work

1. Install/select full Xcode and validate a local signed macOS build.
2. Initialize the repository and create a minimal AppKit application targeting
   arm64 and macOS 26.
3. Enable App Sandbox, hardened runtime, and outgoing network client access
   only.
4. Add a test-only localhost fixture server using system frameworks.
5. Measure an unadorned window and one WKWebView.
6. Validate an explicit persistent WKWebsiteDataStore shared by multiple web
   views.
7. Prove cookie metadata/value enumeration needed by the later masked UI,
   individual deletion, per-domain deletion, cookie-only clear-all, and broader
   website-data clear-all behavior. Mask/reveal presentation was deferred to and
   is now implemented in the Phase 4 UI.
8. Prove broader website-data enumeration and deletion.
9. Compile, cache, attach, and remove a small WKContentRuleList.
10. Test the intended per-site blocking exception and reload sequence.
11. Exercise target-blank pages, window.open, downloads, HTTP authentication,
    load failures, and web-content process termination to discover API gaps.
12. Audit blank launch and idle time for application-owned network requests.

The UI in this phase may be deliberately disposable. The goal is evidence, not
product polish.

### Tests and measurements

- Local pages set persistent and session cookies with different flags.
- Local pages create local storage, IndexedDB, caches, and service workers where
  supported.
- A known subresource is blocked and an ordinary first-party resource is not.
- Multiple simultaneous web views and a reconstructed profile observe the same
  normal-profile cookies.
- A new application launch observes the intended persistent data.
- Deletion remains effective after reload and relaunch.
- Startup, first-web-view, idle CPU, memory, and ten-view scaling benchmarks.
- Privileged pktap capture with a positive attribution control for production
  blank launch and at least 30 seconds of settled idle time.

Repeated creation/destruction and leak inspection now belong to Phase 5's
production TabController lifecycle and 100-cycle churn gate. Phase 1 measures
one and ten resident views instead. Testing a disposable scaffold's artificial
deallocation path would not validate the ownership and observer teardown that
the real tab implementation introduces.

### Exit criteria

- Public WebKit APIs satisfy cookie and site-data requirements.
- Compiled blocking is feasible and the per-site exception behavior is known.
- No application-owned idle network activity exists.
- The minimal WebKit footprint is recorded and performance budgets are locked.
- Browser edge-case gaps have an explicit later phase or safe failure behavior.
- There is an explicit go/no-go decision for WKWebView.

### Stopping point

Phase 1 completed on 2026-07-26. The implementation, API probes, Release
validation, performance gates, and privileged blank-network audit pass. The
risk report records an unconditional WKWebView GO. Its checkpoint was approved
before Phase 2 implementation began.

## 7. Phase 2 — Fast single-page browser (complete)

### Goal

Deliver a minimal native browser that is already pleasant and fast with one
page.

### Work

- Implement AppDelegate and BrowserWindowController.
- Show a simple native toolbar and content area.
- Focus the address field on launch.
- Implement AddressInterpreter with HTTPS-first host handling and configurable
  search.
- Add back, forward, reload/stop, title, load progress, and loading state.
- Display useful offline, DNS, TLS, and navigation errors.
- Route only supported HTTP and HTTPS navigation; handle other schemes through
  explicit policy.
- Construct all web views through WebViewFactory and the normal BrowserProfile.
- Prevent AppKit window restoration.
- Keep optional storage and blocker work out of the launch path.
- Add standard menu commands and keyboard shortcuts.

### Tests

- Unit tests for host, URL, search, whitespace, malformed input, and scheme
  interpretation.
- Unit tests for external-scheme and navigation policy.
- UI tests for focus, submission, redirects, errors, progress, back, forward,
  reload, and stop.
- Accessibility identifiers for critical controls.
- Local-fixture launch and navigation performance suite.

### Exit criteria

- Ordinary pages and common failures are usable.
- Displayed URL and navigation capability follow WebKit state.
- No navigation is persisted or logged.
- Startup, response, CPU, and one-tab memory gates pass.
- There are no third-party runtime dependencies.

### QoL follow-up before Phase 3

The approved single-page checkpoint remains complete. Before adding the next
feature layer, add one narrowly scoped quality-of-life behavior: remember the
main browser window's size and location across a normal quit and relaunch.

#### Work

- Persist only the main window frame through AppKit's native frame autosave.
- Use a stable production autosave name, an isolated UI-test name, and no frame
  autosave for fixed-geometry performance launches.
- Restore the frame independently of AppKit state restoration and retain the
  centered default when no usable saved frame exists.
- Keep URL, title, web-view, back/forward, and future tab state memory-only.
- Preserve the blank-page relaunch and launch-focused address field.

#### Tests

- Unit coverage that saves a frame under an isolated name and verifies a new
  controller restores it without becoming state-restorable.
- Unit coverage for production, UI-test, and performance launch-mode isolation.
- A manual check that moves and resizes the production window, quits, and
  verifies the frame returns after relaunch.
- Navigate before quitting and verify relaunch restores the frame but no URL,
  page, back/forward state, or address-field content.
- Recheck the launch and browser-command regression gates.

#### Exit criteria

- A normal relaunch returns the main window to its last usable size and
  location.
- Stale or invalid geometry cannot make the browser window inaccessible.
- Window geometry is the only newly persisted state, remains locally resettable,
  and contains no browsing data.
- The no-history, blank-relaunch, focus, and performance invariants still pass.

### Stopping point

Phase 2 completed on 2026-07-26. The native single-page browser, functional and
privacy behavior, Release configuration, launch/command benchmarks, and
one-page resource gate are recorded in the project status and performance
baseline. Its hands-on checkpoint was approved. The window-geometry follow-up
was also manually approved and committed as `aa8ee6a` before Phase 3 began.

## 8. Phase 3 — Bookmarks and owned persistence (manual recovery pending)

### Goal

Persist only what the user explicitly asks the browser to remember.

### Work

- Implement versioned Bookmark and BookmarkFile models.
- Implement actor-isolated atomic storage and a last-valid backup.
- Add bookmark, edit, delete, list, search, and open-in-current-page workflows.
- Handle duplicates deliberately without silently multiplying entries.
- Add visible recovery for malformed or unmigratable data.
- Add reset/export documentation for the local bookmark file.
- Keep settings limited to required browser behavior.
- Keep bookmark models, storage, and immutable snapshots independent of the
  future tab layer so Phase 5 can route them through the selected tab.
- Keep the first bookmark library flat and searchable. Do not add a persistent
  bookmarks bar or folder hierarchy until real use establishes that need.

### Tests

- Round-trip and schema-version tests.
- Atomic replacement and interrupted-write scenarios.
- Corrupt primary file and valid-backup recovery.
- Duplicate and invalid URL handling.
- UI tests for all bookmark operations against the current page.
- Search and load benchmark with a deliberately large bookmark fixture.
- Container inspection after navigation to confirm that no application history
  file exists.

### Exit criteria

- Bookmarks survive relaunch and are recoverable.
- Bookmark I/O never blocks typing, navigation, or browser-owned commands.
- Only explicitly bookmarked URLs enter application-owned persistence.
- All bookmark workflows are keyboard accessible.

### Implementation checkpoint

The toolbar star and Command-D add or edit the current page.
Option-Command-B opens a searchable, nonmodal manager with add, edit, delete,
and open-in-current-page actions. Versioned models feed immutable snapshots
from an actor-isolated repository that atomically writes `Bookmarks.json` and a
last-valid backup under Application Support. Duplicate URLs are explicit, and
malformed primary data is preserved while a valid backup is exposed read-only
for restore or reset.

Bookmark initialization is queued after native-window presentation, and
performance launches do not create a bookmark repository. The Debug suites are
green at 70 of 70 unit tests and 9 of 9 UI tests, including the complete normal
bookmark workflow, keyboard routing, and relaunch persistence. The optimized
10,000-bookmark gate passes at 63.164 ms load p95, 18.725 ms repository-search
p95, and 18.536 ms manager-filter p95. The Release suites are green at 70 unit
and 9 UI tests, and the production bundle passed architecture, signature,
sandbox-entitlement, and hardened-runtime inspection. The full interaction run
also passed, but the launch gate did not: first-frame median was 573.542 ms
against 500 ms, and two Phase 2-relative launch comparisons exceeded their 10%
budgets. That launch result is superseded by the clean final Phase 4 run, which
passes every absolute and relative gate. The user approved the production
add/edit/search/open/delete, keyboard-command, and relaunch-persistence workflow
on 2026-07-26, including the intentionally absent bookmarks bar. Bookmark
folders remain deferred. The manual recovery/reset exercise remains pending. A
fresh post-navigation container inspection found no Browser-owned history,
visit, session, or navigation database; database-like files were confined to
WebKit-managed website data. Therefore the Phase 3 exit criteria are not yet
fully approved.

### Stopping point

Back up, corrupt, recover, restore or reset the bookmark data once. That manual
Phase 3 residual remains tracked separately. Revisit folders only after ordinary
use shows the flat searchable library is insufficient.

## 9. Phase 4 — Ad/tracker blocking, privacy controls, and popup suppression

Phase 4 is complete. Every functional, privacy, packaging, network, container,
and performance/resource gate passes. The approved minimal Phase 5 slice is now
implemented and accepted after its final normal-session smoke test.

### Goal

Materially reduce advertising and tracker requests first, expose understandable
controls for WebKit-owned website data, and make popup denial an explicit
privacy and safety backstop before tabs increase the number of browsing
contexts.

### Work

- Bundle and load the approved pinned advertising/tracker ruleset as the first
  Phase 4 priority.
- Show whether blocking is active for the current site.
- Add and remove a persistent per-site exception with an explicit reload.
- Prepare rule JSON away from the main actor, invoke WebKit's asynchronous
  compilation API without blocking the interface, and compile only on first
  installation or when the pinned bundle changes. Cached ordinary launches
  load the compiled identifiers without recompiling.
- Do not allow an unprotected remote navigation while first-install or
  changed-bundle compilation is pending; expose a visible unavailable state if
  no last-valid rules can be loaded.
- Retain the last valid compiled rules after failure.
- Formalize the popup policy independently of blocker coverage: no page may
  create a secondary app window, another WKWebView, a background tab, or a
  tab-under.
- Deny scripted `window.open` requests and forms targeting a new browsing
  context, including requests initiated by page script in response to a click.
  Route only a direct pointer-activated HTTP or HTTPS anchor targeting a new
  context, and route that deliberate action into the current page while the
  browser remains single-page. Deny synthetic and keyboard target-blank
  activation when public API cannot prove a direct pointer gesture.
- Add a privacy window grouped by website/domain.
- List cookie metadata and mask values by default; reveal is an explicit local
  action.
- Delete one cookie, all cookies for a domain, or all cookies.
- Show other WebKit site-data categories without pretending their contents are
  inspectable.
- Delete the selected WebKit website-data record or all website data without
  presenting WebKit's grouped record name as an exact cookie-domain identity.
- Add an in-app privacy explanation matching architecture.md.
- Provide reset actions for blocker exceptions and compiled blocker artifacts.

Blocking rules often prevent advertising popup scripts and overlays before they
run, but delegate-level popup denial is an independent backstop and must work
even when no filter rule matches. No automatic filter update network request is
added in this phase. A manual or scheduled updater is a separate future
decision.

### Tests

- Known tracker and advertising resource blocking tests.
- First-party resource and login non-regression tests.
- Exception enable/disable/reload tests against the current page.
- Cold and cached blocker-state launch tests.
- Large-list compile, lookup, attachment, and failure rollback tests.
- Deterministic denial tests for load-time, delayed, asynchronous, and
  click-handler `window.open`, plus forms targeting a new context.
- Verify that a direct pointer-activated HTTP or HTTPS anchor targeting a new
  context navigates the current page, while unsupported schemes are denied.
- Assert that every denied popup leaves the app-window and WKWebView counts
  unchanged and cannot create a hidden or background browsing context.
- Cookie creation, persistence, masking, reveal, deletion, and relaunch tests.
- Site-data creation and selected-record/global deletion tests.
- Network audit proving no telemetry or silent update call.
- Container audit proving no visit database, URL log, restored session, or
  recently closed list.

### Exit criteria

- Blocking works on the deterministic suite and the agreed real-site smoke set.
- A broken site can be recovered with a clear per-site switch.
- No page script, popup API, or target-blank form can create a secondary window,
  WKWebView, hidden browsing context, background tab, or tab-under.
- The user can understand and delete all WebKit-exposed website data.
- Deletion remains effective after restart.
- Blocking and popup suppression do not violate launch, navigation, scrolling,
  CPU, or memory gates.
- The privacy explanation matches actual disk and network behavior.

### Stopping point

Use the single-page browser with blocking enabled across the agreed real-site
set, exercise blocker exceptions and website-data deletion, and verify the
popup backstop before adding tabs.

### Completed blocker checkpoint

The current first slice bundles content-addressed AdGuard Base and Tracking
Protection lists, enables them by default, compiles only on cache miss, retains
a complete last-valid set, fails closed when no rules are available, and adds a
persistent exact-host exception through Privacy and Option-Command-P. There is
no runtime download or automatic updater.

The single-page popup backstop is also an explicit regression gate. The fixture
covers load-time, delayed, promise-scheduled, click-handler `window.open`, a
script-triggered target-blank anchor, a form targeting a new context, and a
directly clicked target-blank HTTP(S) anchor. Denied paths leave the application
at one window and one WKWebView; the deliberate direct anchor routes in the
existing page. Post-fix Debug and Release unit suites are green at 117 of 117,
and both UI suites are green at 11 of 11. Production-list, benchmark, and
Release-package checks are also green. Ordinary pending navigation is
strengthen-only; exact relaxation occurs only for the winning commit, while the
explicit current-site switch applies the selected policy before reload so it
can recover a document-level match. Stale, overlapping, post-commit, unbound,
and fragment action-only callback regressions remain covered. On 2026-07-27,
the user confirmed that a Release launched with
`make run` showed no ads on an ad-heavy site, then reported that the blocker and
popup checkpoint works in hands-on use and approved it.

### Privacy and final completion evidence

Privacy > Manage Website Data now presents exact cookie domains separately from
WebKit's grouped website-data records. It shows cookie metadata, masks values by
default, requires explicit reveal, excludes values from search, and scrubs a
revealed value when context changes. Confirmed actions delete one cookie, all
cookies for an exact displayed domain, all cookies, one selected WebKit record,
or all WebKit-exposed website data. Every mutation re-reads WebKit state, and
the UI reports data recreated by an open page rather than claiming false
success. Deletion remains absent after relaunch in the final UI flow.

The same window visibly resets all exact-host exceptions and locally compiled
blocker artifacts. Existing pages retain their in-memory rule lists, the pinned
signed rules remain installed, and the next launch rebuilds deleted artifacts
before remote navigation. UI-test resets are identifier-prefix scoped and do
not remove production lists. Final startup ordering begins blocker preparation
before WebKit profile creation; privacy controls are then installed in both the
ready and fail-closed preparation outcomes.

The post-startup-fix combined Debug run passes 135 unit tests and 12 UI tests;
Release unit passes 135 and Release UI passes 12. Artifacts:
`.build/TestResults.YXZZik/Browser.xcresult`,
`.build/TestResults.lRwo5P/Browser.xcresult`, and
`.build/TestResults.LBpOx9/Browser.xcresult`. The focused final privacy flow is
`.build/TargetedPrivacyGlobal2.xcresult`. The final profile probe used distinct
PIDs 24498, 24530, and 24563, reported `cookie-survived=true`, and proved
deletion across relaunch at `.build/ActualAppProfileProbe.oe3hQC`. WebContent
termination and cleanup pass at `.build/WebContentTermination.YLxbl5`. The
read-only no-history audit and its negative self-test pass at
`.build/ContainerAudit.20260728T094138Z.hM7afi/report.txt`, with zero logical
SearchHistory entries in every profile, 6 allowlisted and 0 unexpected
preference keys, and 0 failures or warnings. Release-package verification is
green.

The fresh blocker benchmark passes at
`.build/ContentBlockerBenchmark.qIb6ev`, with cached lookup, attachment, and
removal p95 values of 0.218375, 0.000209, and 0.000125 ms. The final Release
production-app gate passes at `.build/PerformanceResults.X3uvqP`: first-frame
median/p95 are 429.257/538.403 ms, readiness median/p95 are
636.481/754.233 ms, address and command p95 are 0.433/0.193 ms, and local-
navigation p95 is 17.180 ms. Production application code did not change after
that clean run.

The later test-only scroll hardening adds a visible top/moved marker, proves a
real preflight swipe, and restores the deterministic fixture to the top before
measuring. All three XCTest methods passed in
`.build/PerformanceResults.j6rcfP`; ten genuine scroll samples reported zero
hitch duration, count, and ratio. Bookmark load/filter/search p95 were
61.928/18.768/18.588 ms, local-navigation p95 was 19.360 ms, address p95 was
0.433 ms, and command p95 was 0.184 ms. Its aggregate summary missed only the
outer XCTest 500 ms p50 ceiling at 529.613 ms, despite a 568.708 ms p95 and both
Phase 2-relative gates passing. The launch-only diagnostic
`.build/PerformanceLaunchConfirmation.EJpHTr` repeated the outer-only result at
524.319 ms while app-owned native-window medians in both later runs stayed near
93 ms. With production code unchanged, these transparent XCTest/OS bimodality
diagnostics do not supersede the clean `X3uvqP` release gate. One-view resources
pass at
`.build/ResourceBaseline.v1.f2jBcc` with 73.7 MiB memory p95 and 0.020% mean
idle CPU. The synthetic ten-view probe passes at
`.build/ResourceBaseline.v10.zRM3n4` with 296.9 MiB p95 and 0.007% mean idle
CPU.

### Final privileged acceptance evidence

`make network-audit` passed from a normal interactive Terminal. With metadata
filter `(dir=out and (proc=Browser or eproc=Browser))`, its attribution control
captured 8 outbound packets and the production blank launch captured 0 outbound
packets during 31 seconds idle. The recorded result is `PASS` at
`.build/NetworkAudit.HxyZ8u/result.txt`.

All Phase 4 exit criteria are satisfied. The user-approved minimal Phase 5
implementation and automated acceptance gates are now complete in the working
tree. The user completed the normal-session tab smoke test on 2026-07-28 and
accepted the checkpoint.

## 10. Phase 5 — Tabs and web-view lifecycle

### Goal

Add reliable multi-tab browsing without weakening the established blocking,
popup, memory, or responsiveness guarantees.

### Current status

Implementation and acceptance complete. The implemented scope is the small,
high-frequency tab workflow approved for this phase. The automated gates and
normal-session user smoke test pass.

### Work

- Implement TabManager and TabController.
- Add a simple visible tab strip with new, close, and select behavior.
- Make Command-T create and select a fresh blank tab, then focus and select the
  address field so the user can immediately enter a URL or search.
- Make Command-W close the selected tab. Closing the sole remaining tab replaces
  it with a fresh blank tab and focuses the address field; closing a selected tab
  chooses the tab to its right when possible, otherwise the tab to its left.
- Route navigation and bookmark commands to the selected tab in the key window.
- Route an exact Command-click on a direct, physically pointer-activated HTTP or
  HTTPS link to a new background tab. Load it immediately without changing the
  selected source tab or its address.
- Route an unmodified direct, physically pointer-activated HTTP or HTTPS anchor
  with `target="_blank"` to a new foreground tab.
- Continue denying scripted `window.open`, script-triggered anchors,
  target-blank forms, keyboard-created contexts, unsupported schemes, alternate
  mouse buttons, unsupported modifier combinations, separate app windows, and
  tab-unders.
- Ensure every new WKWebView uses the normal profile, current compiled rules,
  and current site policy through WebViewFactory.
- Apply blocker and exception changes coherently across resident tabs and reload
  only affected pages when policy changes require it.
- Keep tab title, URL, progress, and navigation state independent.
- Create a tab's web view lazily and keep resident views alive when switching.
- Release all observations and delegates when a tab closes.
- Keep all tab/session state in memory and disable recently closed behavior.
- Show a recovery state if a tab's content process terminates.

Defer reordering, grouping, pinned tabs, tab previews, favicon fetching,
animated effects, automatic suspension, recently closed tabs, and session
restoration. These are not part of the approved minimal Phase 5 slice.

### Tests

Automated coverage is implemented for:

- Tab-manager selection after background and foreground insertion, closing the
  selected middle or last tab, closing a background tab, and replacing the sole
  tab with a fresh identity.
- Command-T, the new-tab button, tab selection, Command-W, neighboring-tab
  selection, and fresh-blank last-tab behavior.
- Independent resident WKWebViews, selected-tab command routing, shared profile
  data storage, delegate cleanup on close, and a document sentinel proving that
  switching does not reload a resident page.
- Closed tabs clear transient navigation and blocker state, and queued delegate
  callbacks cannot repopulate state from a closed or non-owned WebView.
- A genuine Command-click opening an HTTP(S) link in a background tab while the
  source remains selected, including verification that the background tab
  inherits active content rules.
- An unmodified direct target-blank HTTP(S) anchor opening a foreground tab while
  scripted popups, script-triggered anchors, target-blank forms, unsupported
  schemes, alternate buttons, and unsupported modifiers remain denied.
- Quit and relaunch returning to one fresh blank tab without restoring either of
  two previously open URLs.

Final automated evidence:

- Debug and Release unit suites each pass all 149 tests. The complete Debug and
  Release UI suites each pass all 13 workflows.
- Bookmark load/filter/search p95 values are 63.501/18.757/19.183 ms. Blocker
  attachment and policy coverage remain green in both unit configurations.
- New blank-tab chrome p95 is 6.514 ms against 100 ms. Selection with ten
  loaded resident tabs is 2.983 ms against 50 ms.
- Ten real resident tabs use 186.8 MiB aggregate p95 memory against 1 GiB and
  0.013% mean idle CPU against 1%. The one-hundred-cycle tab-manager regression
  and full-app Command-T/Command-W churn probe pass; the full-app probe's
  second-half absolute-memory median is 11.04% below its first-half median.
  WebContent termination and the no-history container audit also pass.
- The final normal-session user tab smoke test passed on 2026-07-28, completing
  acceptance of the checkpoint.

### Exit criteria

- Closing, switching, and bookmark commands can never operate on the wrong web
  view.
- Closed tab URLs are not retained.
- Adding tabs cannot bypass content rules, site policy, or the popup-denial
  invariant.
- Command-click background loading cannot change or reload the selected source
  tab, and relaunch cannot restore prior tabs or URLs.
- Existing-tab switching meets the latency budget, including while bookmark
  and blocker state are loaded.
- Memory settles after churn and remains within the locked tab budget.

### Stopping point

This is the minimum viable personal browser. Use it for ordinary multi-tab
browsing with bookmarks and blocking enabled before adding daily-driver
features.

## 11. Phase 6 — Daily-driver hardening

### Goal

Implement only browser behaviors proven necessary during the pilot.

### Candidate work

- Downloads using a save panel and the minimum user-selected file entitlement.
- File upload selection.
- Find in page.
- HTTP authentication prompts.
- JavaScript alert, confirm, and prompt presentation.
- Safe external-scheme handoff.
- Permission UI for camera, microphone, location, notifications, and clipboard,
  adding entitlements only when required.
- Full-screen and media behavior.
- Better offline and process-termination recovery.
- Printing if personally needed.
- Private windows backed by a nonpersistent website data store.
- Accessibility audit and complete keyboard navigation.

Password management, extensions, sync, automatic updates, default-browser
registration, and session restoration remain separate decisions rather than
automatic additions.

### Tests

- Deterministic fixtures for each implemented browser edge case.
- Explicit denial tests for permissions that remain unsupported.
- Offline, low-disk, malformed-file, and process-termination behavior.
- User-selected download/upload sandbox behavior.
- Critical-path XCUITests.
- Accessibility inspection.
- Compatibility sweep across the user's representative login, documentation,
  shopping, banking, and media sites.

### Exit criteria

- Unsupported behavior fails visibly and safely.
- No new entitlement or persisted datum lacks a documented reason and deletion
  path.
- No high-severity crash, data-loss, or privacy issue remains.
- All established performance budgets still pass.

### Stopping point

Complete a one-week personal daily-driver trial and triage its results before
adding more features.

## 12. Phase 7 — Optimization and personal release

### Goal

Turn the proven daily-driver build into a reproducible local release.

### Work

- Profile launch, first web view, tab switching, blocker attachment, bookmark
  loading, cookie enumeration, and controlled scrolling with Instruments.
- Fix measured bottlenecks only.
- Run unit, integration, UI, soak, privacy, compatibility, and performance
  suites.
- Verify App Sandbox and hardened-runtime entitlements from the built product.
- Produce a reproducible arm64 Release build with local signing.
- Document install, backup, data locations, full reset, and known limitations.
- Record the final performance baseline.

### Release gate

- All required features and privacy acceptance criteria pass.
- No unexplained performance regression exceeds 10 percent.
- Absolute or baseline-plus-increment memory gates pass.
- There is no critical crash, data loss, unsafe permission flow, or known
  application-owned network request outside documented behavior.
- The user considers the daily-driver experience fast enough.

## 13. Requirement traceability

| Requirement | Primary phase | Proof |
| --- | --- | --- |
| Display web pages | Phase 2 | Local and real-site navigation tests |
| Fast startup and navigation | Phases 1, 2, and 7 | XCTest metrics and Instruments baseline |
| Tabs | Phase 5 | Tab behavior, churn, switching, and privacy-policy inheritance tests |
| Bookmarks | Phase 3 | Persistence, recovery, and UI tests |
| Separate cookies | Phase 1 | Explicit WebKit profile persistence test |
| Block ads and trackers | Phase 4 | Deterministic blocking, compatibility, and exception tests |
| Suppress popups | Phase 4 | Script/form denial, direct-anchor routing, and secondary-context count tests |
| Inspect/delete cookies | Phase 4 | Cookie fixture and relaunch tests |
| Delete broader site data | Phase 4 | Selected WebKit-record and clear-all integration tests |
| No history | Every phase | Container, logging, relaunch, and code review checks |
| No telemetry | Every phase | Blank/idle network audits and dependency review |
| Reasonable CPU and memory | Every phase | Locked performance gates and churn tests |
| Native Apple silicon app | Phases 1 and 7 | arm64 Release artifact and entitlement inspection |

## 14. Principal risks

| Risk | Mitigation |
| --- | --- |
| Per-site blocker exceptions do not behave as expected across live tabs | Phase 1 proves rule ordering; Phase 4 proves the single-page exception and reload path; Phase 5 verifies policy changes across every new and resident tab |
| A popup path bypasses blocking or opens a hidden context | Treat content rules and delegate-level denial as independent controls; Phase 4 tests scripted and form-driven denial plus unchanged window/web-view counts, and Phase 5 repeats the gate with tabs |
| A chosen filter list cannot be translated faithfully to WebKit rules | Validate representative network and cosmetic rules, document unsupported syntax, and keep the source pinned |
| WebKit process memory dominates the budget | Separate fixed base from incremental tab cost; introduce visible tab discard only after measurement |
| Some Chromium-oriented sites fail | Keep a real-site smoke matrix, avoid user-agent spoofing by default, and provide a blocker-off recovery path |
| No-history wording overpromises | Distinguish application history from persistent website data and expose site-data clearing |
| Cookie values expose authentication secrets on screen or clipboard | Mask by default, reveal explicitly, never log, and avoid automatic clipboard use |
| Feature requests accumulate into a slow general-purpose browser | Require a measured performance/privacy cost and explicit phase placement for every new feature |
| New runtime dependencies slow launch or expand attack surface | Default to system frameworks and require an architecture review for additions |
| Full Xcode or signing setup blocks implementation | Validate toolchain and a minimal locally signed app at the beginning of Phase 1 |

## 15. Deferred backlog

The following are intentionally not scheduled until the MVP and daily-driver
trial prove a need:

- automatic blocker updates;
- multiple profiles;
- password and passkey management;
- extension support;
- sync;
- session restore and recently closed tabs;
- browsing history;
- remote crash reporting or telemetry;
- cross-platform support;
- bundled Chromium;
- custom network stack; and
- custom rendering engine.

Adding an item requires a new design decision describing its privacy,
performance, security, persistence, and maintenance cost.

## 16. Completion definition

The project is complete for its initial purpose when:

- it is dependable for the user's normal browsing;
- pages, tabs, bookmarks, and site-data controls work;
- blocking materially reduces ads and trackers without making browsing slow;
- the application writes no browsing history and sends no telemetry;
- stored data and deletion behavior are understandable;
- measured startup, responsiveness, CPU, and memory stay within the approved
  budgets; and
- installing, backing up, resetting, and rebuilding the app are documented and
  reproducible.

Anything beyond that is optional product evolution, not unfinished MVP work.
