# Browser Implementation Plan

Status: Approved; Phase 1 complete; Phase 2 awaiting review
Last updated: 2026-07-26
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
browser for ordinary use with navigation, tabs, bookmarks, and understandable
privacy controls. Feature count is not a success metric.

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
  actually needs during the single-page and tabbed-browser pilot. Phase 0
  defines the categories; exact sites are selected before Phase 5 blocking
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
exact sites are selected from the Phase 2 through 4 pilot before Phase 5.

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
   website-data clear-all behavior. Mask/reveal presentation remains Phase 5 UI
   work.
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

Repeated creation/destruction and leak inspection now belong to Phase 3's
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
risk report records an unconditional WKWebView GO. Stop for checkpoint review
before building the Phase 2 browser shell.

## 7. Phase 2 — Fast single-page browser

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

### Stopping point

Use and review the single-page browser before adding tabs.

## 8. Phase 3 — Tabs and web-view lifecycle

### Goal

Add reliable multi-tab browsing without turning tabs into a memory or
responsiveness problem.

### Work

- Implement TabManager and TabController.
- Add new, close, select, and reorder behavior.
- Route commands to the selected tab in the key window.
- Add familiar tab keyboard shortcuts.
- Route user-initiated popup and target-blank navigation to a new tab.
- Keep tab title, URL, progress, and navigation state independent.
- Create a tab's web view lazily and keep resident views alive when switching.
- Release all observations and delegates when a tab closes.
- Keep all tab/session state in memory and disable recently closed behavior.
- Show a recovery state if a tab's content process terminates.

Do not add tab previews, favicon fetching, animated effects, automatic
suspension, or session restoration.

### Tests

- Unit tests for selection after closing the first, middle, selected, and last
  tab.
- Unit tests for reorder and command routing.
- UI tests for tab creation, switching, closing, shortcuts, and popup routing.
- Verify switching does not reload a resident page.
- Verify quit/relaunch restores no URL or tab.
- Ten-tab switching benchmark.
- One-hundred-cycle tab churn and leak test.
- Content-process termination recovery test where automation permits.

### Exit criteria

- Closing or switching can never operate on the wrong web view.
- Closed tab URLs are not retained.
- Existing-tab switching meets the latency budget.
- Memory settles after churn and remains within the locked tab budget.

### Stopping point

Use the browser for ordinary multi-tab browsing and record friction before
adding persistence.

## 9. Phase 4 — Bookmarks and owned persistence

### Goal

Persist only what the user explicitly asks the browser to remember.

### Work

- Implement versioned Bookmark and BookmarkFile models.
- Implement actor-isolated atomic storage and a last-valid backup.
- Add bookmark, edit, delete, list, search, and open workflows.
- Handle duplicates deliberately without silently multiplying entries.
- Add visible recovery for malformed or unmigratable data.
- Add reset/export documentation for the local bookmark file.
- Keep settings limited to required browser behavior.

### Tests

- Round-trip and schema-version tests.
- Atomic replacement and interrupted-write scenarios.
- Corrupt primary file and valid-backup recovery.
- Duplicate and invalid URL handling.
- UI tests for all bookmark operations.
- Search and load benchmark with a deliberately large bookmark fixture.
- Container inspection after navigation to confirm that no application history
  file exists.

### Exit criteria

- Bookmarks survive relaunch and are recoverable.
- Bookmark I/O never blocks typing, navigation, or tab switching.
- Only explicitly bookmarked URLs enter application-owned persistence.
- All bookmark workflows are keyboard accessible.

### Stopping point

Back up, corrupt, recover, and restore the bookmark data once manually.

## 10. Phase 5 — Privacy controls and content blocking

### Goal

Complete the minimum useful privacy browser promised by the project.

### Work

- Add a privacy window grouped by website/domain.
- List cookie metadata and mask values by default; reveal is an explicit local
  action.
- Delete one cookie, all cookies for a domain, or all cookies.
- Show other WebKit site-data categories without pretending their contents are
  inspectable.
- Delete selected domain data or all website data.
- Bundle and load the approved pinned advertising/tracker ruleset.
- Show whether blocking is active for the current site.
- Add and remove a persistent per-site exception with an explicit reload.
- Prepare rule JSON away from the main actor, invoke WebKit's asynchronous
  compilation API without blocking the interface, and never compile during
  normal launch.
- Retain the last valid compiled rules after failure.
- Add an in-app privacy explanation matching architecture.md.
- Provide reset actions for blocker exceptions and compiled blocker artifacts.

No automatic filter update network request is added in this phase. A manual or
scheduled updater is a separate future decision.

### Tests

- Cookie creation, persistence, masking, reveal, deletion, and relaunch tests.
- Site-data creation and domain/global deletion tests.
- Known tracker and advertising resource blocking tests.
- First-party resource and login non-regression tests.
- Exception enable/disable/reload tests.
- Cold and cached blocker-state launch tests.
- Large-list compile, lookup, attachment, and failure rollback tests.
- Network audit proving no telemetry or silent update call.
- Container audit proving no visit database, URL log, restored session, or
  recently closed list.

### Exit criteria

- The user can understand and delete all WebKit-exposed website data.
- Deletion remains effective after restart.
- Blocking works on the deterministic suite and the agreed real-site smoke set.
- A broken site can be recovered with a clear per-site switch.
- Blocking does not violate launch, navigation, scrolling, CPU, or memory gates.
- The privacy explanation matches actual disk and network behavior.

### Stopping point

This is the minimum viable personal browser. Use it as the primary pilot before
adding daily-driver features.

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
| Tabs | Phase 3 | Tab behavior, churn, and switching tests |
| Bookmarks | Phase 4 | Persistence, recovery, and UI tests |
| Separate cookies | Phase 1 | Explicit WebKit profile persistence test |
| Inspect/delete cookies | Phase 5 | Cookie fixture and relaunch tests |
| Delete broader site data | Phase 5 | Per-domain and clear-all integration tests |
| Block ads and trackers | Phase 5 | Deterministic blocking and exception tests |
| No history | Every phase | Container, logging, relaunch, and code review checks |
| No telemetry | Every phase | Blank/idle network audits and dependency review |
| Reasonable CPU and memory | Every phase | Locked performance gates and churn tests |
| Native Apple silicon app | Phases 1 and 7 | arm64 Release artifact and entitlement inspection |

## 14. Principal risks

| Risk | Mitigation |
| --- | --- |
| Per-site blocker exceptions do not behave as expected across live tabs | Prove rule ordering, attachment, and reload behavior in Phase 1 before designing the final UI |
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
