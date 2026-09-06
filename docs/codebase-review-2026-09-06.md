# Browser codebase review — 2026-09-06

Status: G01 and G02 implementation authorized and implemented on 2026-09-06. G01 and G02 passed background verification; interactive acceptance is explicitly deferred. G03–G05 remain proposed; the G02 standalone benchmark split also fixes G06's compiler source dependency, with benchmark execution deferred. The owner reported a successful smoke test and authorized committing G01/G02 and continuing G03/G04. Original finding evidence and audit-only checkpoints are preserved as historical baseline evidence.

Audit baseline: branch `main`, commit `ea6528921be27d8d0a3ef9a2c7df955daa2b591c`. The working tree was clean at audit start. Source references describe that baseline. No applicable AGENTS.md was found in the project or ancestor directories.

## Purpose and method

Requested broad codebase audit using the codebase-audit skill. Review order is core (`BE`), native AppKit presentation (`FE`), then integration/build/verification (`IN`). The initial pass was analysis and report writing only; the owner subsequently authorized G01/G02 implementation.

The approved architecture is a personal macOS AppKit/WKWebView browser with a shared persistent WebKit profile, memory-only tabs and navigation, explicit JSON bookmarks, pinned content-blocking rules, exact-host exceptions, consent-bound per-tab local-folder access, and narrowly allowed magnet handoff. Deferred downloads, session restoration, tab rearrangement, and broader browser features are not defects merely because they are absent. Existing status documents contain historical acceptance evidence, not fresh verification of this snapshot.

Evidence labels: Confirmed (source), Confirmed (reproduced), Risk, and Debt. Priority is independent of evidence: P1 significant correctness/data/resource issues; P2 important robustness or architecture work; P3 smaller cleanup.

## Review map

Eight findings: **3 core, 2 native presentation, 3 integration**. Priority: **1 P1, 6 P2, 1 P3**. Evidence: **4 Confirmed (reproduced), 4 Confirmed (source)**. All are open. This is a completed review pass, not a claim that every defect has been found.

| Discussion area | Findings | Why it matters |
| --- | --- | --- |
| Policy differs between entry points | BE-01, FE-01, IN-02 | Address submission, command routing, and test startup can bypass the intended ownership boundary. |
| Durable state differs from reported operation outcome | BE-02, BE-03 | Failed writes can reappear through recovery; unresolved corruption accumulates duplicate preserved files. |
| Recovery assumes prior success | FE-02 | The exception UI cannot recover the first blocked main document. |
| Verification dependency lists drift from production | IN-01 | The app builds while a documented performance gate cannot compile. |
| Routine verification takes over the user's desktop | IN-03 | Default checks include foreground automation; repeated activation, typing, clicks, and swipes prevent ordinary work and contaminate timing measurements. |

Useful counterevidence: per-tab teardown clears delegates, KVO observers, pending URLs, grants, and content-controller bookkeeping; the blocker navigation state explicitly distinguishes stale callbacks and strengthen-only policy; bookmark mutations are actor-serialized; website-data mutations refresh their result rather than claiming deletion without checking; cookie reveal is explicitly masked and scrubbed in the native view; production bundle hashes and entitlements are independently verified. These mechanisms were traced and are not replaced by generic cleanup recommendations. No measured runtime performance regression is asserted.

## Grouped plan of attack

The initial plan was proposed only. The owner subsequently authorized G01/G02 implementation; other application groups remain proposed. Implementation authorization did not request a commit or merge.

| Group | Cohesive outcome | Findings | Prerequisites | Status |
| --- | --- | --- | --- | --- |
| G01 | Reject pasted magnet URIs before search | BE-01 | None for core checks; G02 for native acceptance | Implemented; background verified |
| G02 | Make routine checks safe during ordinary desktop use | IN-02, IN-03 | None | Implemented; background verified; interactive acceptance deferred |
| G03 | Make bookmark failure and recovery outcomes consistent | BE-02, BE-03 | None for repository checks; G02 for recovery UI acceptance | Proposed |
| G04 | Make Close act on the active window's content | FE-01 | G02 for keyboard acceptance | Proposed |
| G05 | Recover an explicitly selected failed document with a site exception | FE-02 | G02 for WebKit/UI acceptance | Proposed |
| G06 | Restore the supported performance build path | IN-01 | None for compilation; G02 for subsequent interactive gates | Compiler fix/build verified through G02; workload deferred |

### G01 — Reject unintended external-URI searches

Scope: classify magnet input before generic search fallback and add tests at both the interpreter and submitted-navigation boundary. Preserve all three search providers, host:port recognition, ordinary colon-containing prose, and the direct-click-only magnet handoff. No persistence changes.

Acceptance: mixed-case and query-rich magnet inputs cause a visible unsupported-address result with zero search/external-open calls; ordinary search and direct link handoff continue to work.

### G02 — Isolate test storage, desktop interaction, and measurement

Scope: provide one launch-mode decision for app-owned directories, preferences, named website-data profile, compiled-rule store/reset scope, geometry, and activation. Use a separate test-host identity and a non-activating mode for unit checks. Also inspect test bodies: a quiet app startup does not prevent a test from calling `orderFront`, `makeKeyAndOrderFront`, `activate`, or input automation later.

Split the supported commands and schemes into explicit execution modes:

- **Routine background checks (default):** core/repository tests, builds, package validation, and only AppKit/WebKit integration fixtures demonstrated to work without activation, visible windows, or synthetic desktop input. Use disposable data and bounded build/test concurrency. Routine `make test`/`make check` should not implicitly invoke interactive suites. Output must list included and deferred gates, so a background pass never masquerades as full release acceptance.
- **Non-interactive benchmarks (explicit):** standalone bookmark work and other measurements that need no desktop input. Give these a separate entry point instead of coupling them to repeated app launch/scroll tests. Background execution can preserve desktop interaction but still compete for CPU, memory, and I/O; strict performance acceptance needs controlled conditions. Routine low-impact checks should not change benchmark priorities/budgets and then compare altered results with the historical baseline.
- **Interactive UI/performance gates (explicit opt-in):** actual keyboard/menu/mouse, first-frame/focus, and scrolling tests. Preserve real user-visible acceptance. Run these only when the owner makes the desktop available, or in a separate interactive environment whose automation behavior has first been verified. A different bundle identifier, hidden window, or another Space is not by itself an established solution for the current foreground automation. Measurements from another environment require their own characterized baseline.

Cancellation must stop the current run and its owned fixtures/processes promptly, without touching the user's running Browser. A comprehensive command may remain available, but its desktop interaction must be explicit and it must not be a dependency of routine checks.

Compatibility: production paths, identifiers, profile contents, and accepted first-frame behavior must remain unchanged. Test cleanup must only remove the created test namespace. No migration or reset of the user's data is needed.

Acceptance: run the real Debug/Release routine entry points with sentinel normal data in a disposable fixture; verify unchanged sentinel files/preferences, no normal-profile access, no activation or visible test windows, no mouse movement or injected input, and preserved focus in another disposable app. Check command dependencies as well as individual fixtures. Record elapsed time and resource behavior under representative ordinary use; allow bounded concurrency to be configured. Verify cancel/failure cleanup and clear reporting of deferred interactive gates. Confirm UI tests target their own app identity and that explicit production launches still select normal storage.

Owner constraint (2026-09-06): the full suites previously took over the computer, preventing other work; this was the reason the owner requested that they not be run. Do not rerun those suites on the active desktop as a prerequisite for fixing the harness. Validate the background mode first; an interactive run remains separately scheduled/authorized.

### G03 — Define bookmark commit and recovery semantics

Scope: make first-save and later mutation failures agree across memory, primary, and backup; reconcile reset/restore partial failures within the same storage contract. Deduplicate preservation of identical corrupt bytes while retaining distinct originals. Include injected failures and reopen/recovery tests with the implementation.

Compatibility: retain schema-1 bookmarks and stable UUIDs, explicit local URLs, and the successful-operation requirement to remove edited/deleted URLs from both active copies. Preserve existing corrupt files; any new recovery bookkeeping must have a bounded, documented rollback path. Two independent atomic file writes do not by themselves provide an atomic user operation.

Decision needed: after one durable copy changes but the other fails, should the API report a committed operation with degraded redundancy, or an operation rolled back to the previous committed state? Specify and test the outcome before choosing the write protocol.

Acceptance: first add, later add, edit, delete, reset, and restore with failure at each durable step; fresh process and in-memory views agree with the reported outcome. Three launches over unchanged corruption preserve one new copy, and distinct corruption remains separately recoverable. Finish the historically pending manual bookmark-recovery exercise using isolated data.

### G04 — Route Close through window ownership

Scope: make the main browser's Close action close its selected tab, while auxiliary windows close themselves; include menu validation and sheet behavior. Preserve sole-tab replacement and existing tab-neighbor selection.

Acceptance: actual Command-W from browser content/address, Bookmarks, and Privacy affects the intended window or tab only. Check active bookmark/confirmation sheets, cancellation, local grants, and retained unsaved page state. Do not substitute a direct controller-method test for the keyboard path.

### G05 — Add failed-document exception recovery

Scope: bind a recovery action to the currently failed top-level attempt and display its exact destination host. Explicitly retry after applying the chosen exception, with stale-attempt guards and cross-tab policy synchronization.

Compatibility: preserve exact-host persistence and strengthen-only policy during ordinary navigation. Do not relax a live page because an unrelated or stale navigation failed; do not bypass TLS or general scheme policy.

Acceptance: first-load document block and block after another host, redirected failure, overlapping replacement navigation, and a same-host background tab. Recovery only acts after the user's explicit choice and the winning document loads with the intended policy.

### G06 — Restore benchmark dependency closure

Scope: fix the standalone bookmark benchmark's source list or share its existing production compilation dependencies. If separating pure local-file policy from the AppKit consent controller is chosen, keep that change bounded and verify identical validation behavior; a broader module rewrite is unnecessary.

Acceptance: clean standalone benchmark compilation, `make performance-build`, and the separately invocable 10,000-bookmark benchmark pass. Apply G02's command separation before any interactive performance run; fixing this compiler error does not authorize taking over the active desktop. Keep original budgets. Historical July measurements remain historical until refreshed in appropriate conditions.

## Core findings

### BE-01 — Address-field magnet URLs become outbound search queries (P1, Confirmed (reproduced))

Status: Implemented in G01/G02 (2026-09-06); see remediation evidence and limits below.

Evidence: `Browser/AddressInterpreter.swift:102–132,227–248` recognizes `magnet` as a scheme but omits it from the unsupported-scheme set, then falls back to `SearchProvider.searchURL` (`:22–33`). `Browser/BrowserWindowController.swift:483–494,801–815` submits that generated HTTPS URL through the normal tab load. `Browser/NavigationPolicy.swift:23–42` limits actual magnet handoff to a direct pointer link; that policy never sees the original pasted value after search conversion.

Trigger: paste a conventional `magnet:?xt=urn:btih:…&dn=…` URI and press Return. The complete URI becomes the search provider's `q` parameter, exposing its identifiers, display name, and any embedded private tracker information to the provider. This contradicts the documented blocked address-field path. P1 reflects unintended disclosure of an explicitly unsupported URI; it requires the user to submit it.

Direction: explicitly reject magnet URI input before search fallback, preserving the accepted direct-click-only handoff. Keep plain colon-containing search prose and host:port interpretation compatible.

Verify: all three providers must return an unsupported-address result for pasted magnet URIs; no navigation or external opener should run. Retain direct-click handoff and ordinary search/host:port regressions. The disposable probe confirmed `host=duckduckgo.com entire-input-in-search=true`; it made no network request.

### BE-02 — Failed bookmark writes leave a different recoverable library (P2, Confirmed (reproduced))

Status: Open.

Evidence: `Browser/BookmarkRepository.swift:327–341` writes the new backup before the primary; successful mutations update cached state only after both writes (`:135–139,169–175,186–192`). `:256–266` recovers a backup when primary is absent; `Browser/BookmarkCoordinator.swift:168–174` reports a thrown write as an operation error without reconciling disk state. `BrowserTests/BookmarkRepositoryTests.swift:288–316` injects a later primary-write failure but checks only the old primary on reopen, not the changed backup or a failed first save.

Trigger: the backup write succeeds and the primary replacement fails. The app reports failure and retains the previous in-memory library, but the backup contains the failed change. A failed first save reappears on reopen as a recoverable bookmark; later failed edits/deletes can become effective if recovery is subsequently needed. Each file is atomic, but the user-visible operation across the two files is not.

Direction: define one committed snapshot and reconcile partial-write outcomes, preserving the accepted requirement that successful edits/deletes scrub old URLs from both active copies. Do not merely reverse writes and move the inconsistency elsewhere. Keep backup/recovery compatibility and failure reporting explicit.

Verify: inject failure at each write on first add, later add, edit, and delete; compare memory, both files, fresh load, and explicit recovery. The disposable first-save probe threw `AuditInjectedFailure`, then reported `memory-count=0 fresh-count=1 recovery=true`.

### BE-03 — Every unresolved corrupt-file launch creates another full preserved copy (P3, Confirmed (reproduced))

Status: Open.

Evidence: `Browser/BookmarkRepository.swift:247–252,282–288,344–351` copies the unchanged corrupt primary to a fresh UUID filename on every fresh repository load, leaving the primary intact. `reset` (`:211–218`) intentionally retains preserved input. Startup automatically loads the library (`Browser/AppDelegate.swift:84–103`).

Trigger: leave a corrupt primary unresolved and relaunch repeatedly. Each launch stores another identical artifact, with no deduplication or bound. The isolated probe produced three preserved files from three loads of one unchanged input. This creates redundant disk data and a larger manual erasure/recovery burden; no material resource usage is claimed for normal small libraries.

Direction: preserve each distinct corrupt input once, using verified content identity or durable recovery bookkeeping; retain every distinct original and avoid destructive automatic cleanup.

Verify: repeated launches over unchanged corruption produce one preserved copy; changing the corrupt bytes produces a second; restore/reset continue to preserve the distinct originals.

## Native presentation findings

### FE-01 — Command-W in auxiliary windows closes a browsing tab (P2, Confirmed (source))

Status: Open.

Evidence: `Browser/AppDelegate.swift:440–445` gives Command-W an explicit target of the main `BrowserWindowController`. Its `closeSelectedTab` (`Browser/BrowserWindowController.swift:303–306,328–357`) removes the selected browsing tab without checking the key window; menu validation (`:712–754`) has no close-action guard and defaults to enabled. Both Bookmarks and Privacy are nonmodal key windows (`Browser/BookmarkManagerWindowController.swift:106–111`, `Browser/WebsiteDataPrivacyWindowController.swift:124–132`). The alternate Shift-Command-W command targets `NSWindow.performClose` through the responder chain (`Browser/AppDelegate.swift:447–452`).

Trigger: open Bookmarks or Privacy and press Command-W to dismiss the active window. The installed menu action instead destroys the main window's selected tab, including memory-only navigation state and local grants; no closed-tab recovery exists by design. The active auxiliary window is not the target of that command. Source tracing establishes the target mismatch; a native keyboard reproduction has not been run.

Direction: route Close according to the active window/responder: close a tab in the browser window and close the auxiliary window when it owns the command. Define sheet behavior explicitly and protect background tabs from accidental destruction.

Verify: actual Command-W with browser content, address editing, Bookmarks search/table, Privacy search/table, and each sheet active; assert the intended window/tab count and retained page state. Use a separate app identity for these checks.

### FE-02 — A first document-level block has no usable site-exception recovery (P2, Confirmed (source))

Status: Open.

Evidence: `Browser/BrowserWindowController.swift:969–995` requires a committed URL before enabling the site toggle; its action (`:639–667`) also derives the host solely from `tab.committedURL`. `Browser/TabController.swift:597–602` only sets that field when a document commits. Failure keeps the prior committed URL and offers retry (`:985–1004`, `Browser/BrowserPageError.swift`). `TabController.currentContentBlockingURL` (`:75–77`) prefers the old commit. The existing document-rule test (`BrowserTests/BrowserWindowControllerTests.swift:816–846`) first loads an excepted page through a helper that preinstalls the exception (`:949–1005`), so it cannot detect first-navigation recovery failure.

Trigger: from a fresh blank tab, navigate to a host whose main document is blocked before commit. The toggle is disabled because no web host committed. From another host, the toggle applies to that previous host instead of the failed destination. Retrying repeats the same rule match. Privacy can reset exceptions but has no alternate add-exception control. This defeats the documented main-document recovery workflow; it does not claim every filter match blocks main documents. The bundled Base list contains explicit document-blocking rules (`Browser/ContentBlockerRules/AdGuardBaseRules.json:1`, including the `jaya9` query-matching rule); no live matching site was contacted or runtime rule outcome claimed.

Direction: retain a separately identified failed top-level destination and provide an explicit host-scoped recovery action for that failure. Preserve the approved strengthen-only behavior for ordinary pending navigation; do not weaken policy automatically or reinterpret a stale failure as the current site.

Verify: a deterministic document-blocking rule on the first destination, then the same destination after visiting another host. The UI should identify the failed host and, only after the explicit exception action, successfully load it. Cover redirects, superseding navigation, and same-host background tabs.

## Integration and project findings

### IN-01 — The performance entry point no longer compiles its bookmark benchmark (P2, Confirmed (reproduced))

Status: Compiler dependency fixed as part of G02; compile verification recorded below. Workload execution and timing acceptance remain deferred.

Evidence: `scripts/run-performance-tests.sh:37–50` compiles `Browser/Bookmark.swift`, `Browser/BookmarkSearch.swift`, `Browser/BookmarkRepository.swift`, and the benchmark main, but omits `Browser/LocalFileAccess.swift`. `Browser/Bookmark.swift:45–54,157` now directly references `LocalFileAccessPolicy`. Both `make performance` and `make performance-build` call this script, and the build-only exit occurs after the failing compiler command (`:52–54`).

Trigger: invoke either supported performance target on this snapshot. Its standalone compiler invocation fails with `cannot find 'LocalFileAccessPolicy' in scope`; no performance samples run. The regular app build succeeds because its target includes the dependency. The exact source list and compiler flags were reproduced into disposable output storage; exit 1.

Direction: bring the standalone benchmark's source dependency closure up to date, or share that closure with an existing build target. Keep the benchmark on production model/repository code and avoid replacing it with a stub that bypasses local-file validation.

Verify: run the standalone compile and the supported build-only target from clean artifacts, then the bookmark benchmark. Run the full interactive performance gate in a suitable isolated session before renewing acceptance claims.

### IN-02 — Hosted unit-test startup still uses production app-owned storage (P2, Confirmed (source))

Status: Implemented in G01/G02 (2026-09-06); see remediation evidence and limits below.

Evidence: `Browser/BrowserProfile.swift:25–39` detects `XCTestConfigurationFilePath` and selects a test WebKit profile, but `AppDelegate.bookmarkLaunchConfiguration` (`Browser/AppDelegate.swift:237–257`) recognizes only command-line UI/performance flags and otherwise chooses the production bookmark directory. Startup unconditionally loads that repository (`Browser/AppDelegate.swift:84–103`) and constructs production-key blocker stores (`:320–368`). `Browser.xcodeproj/xcshareddata/xcschemes/Browser.xcscheme:58–106` supplies no isolating command-line arguments; `scripts/run-tests.sh:70–103` adds no such arguments for unit-only runs. The hosted tests execute `Browser.app` with the production bundle identifier (`Browser.xcodeproj/project.pbxproj:441,480,495–530`). Startup also activates the normal native shell (`Browser/AppDelegate.swift:43–65`).

Trigger: run the normal hosted unit-test command. WebKit's named profile is separate, but app startup reads the normal bookmark library, can write preserved corrupt copies (BE-03), and records blocker identifiers under production preferences. It also presents/activates the host window. This is an incomplete isolation boundary, not a claim that ordinary tests deliberately delete healthy production bookmarks. UI tests have additional scoped keys/directories, but still share the production application identity.

Direction: use one explicit test launch configuration consistently for app-owned storage, preferences, WebKit/rule stores, geometry, and shell activation, with a separate test-host bundle identity. Preserve normal-launch behavior and keep app UI acceptance in an explicit isolated mode.

Verify: seed sentinel production data in a disposable separate-identity installation; run the real unit-test entry point; assert no production path access/mutation and no focus changes. Verify production and UI launch-mode routing independently. This audit did not launch the affected host.

### IN-03 — Routine checks bundle foreground automation that monopolizes the desktop (P2, Confirmed (source))

Status: Implemented in G01/G02 (2026-09-06); see remediation evidence and limits below. Added 2026-09-06 from owner feedback; source mechanism checked against the unchanged audit baseline. The owner reports actual desktop takeover during earlier runs; this audit did not reproduce it by running those suites.

Evidence: `Makefile:35–49,75` wires `make test` to the combined suite and `make check` to both combined Debug and Release UI runs. `scripts/run-tests.sh:97–103` runs both test targets by default. `scripts/run-performance-tests.sh:64–66,92–121` couples the standalone bookmark benchmark with app-launch and interaction suites. `BrowserPerformanceTests/BrowserLaunchPerformanceTests.swift:25,58,144–148,188–192,252–303,328–330,368,396–398` repeatedly launches/activates the app, types keyboard commands, clicks tabs, and swipes the visible page. Functional UI tests likewise drive actual input, e.g. `BrowserUITests/BrowserNavigationUITests.swift:45–49,67–78`. The app startup activation described in IN-02 adds to this, but the test bodies independently request foreground control.

Trigger: run the default comprehensive checks, or the performance suite once IN-01's compile failure is repaired, while using the Mac. The tests repeatedly claim focus and drive the keyboard/mouse; competing user activity can also invalidate assertions and timing samples. Separate profile directories protect stored data but do not prevent this desktop interference. This is a verification usability/architecture defect, distinct from the storage boundary in IN-02 and the missing compiler dependency in IN-01.

Direction: implement G02's background-default checks, separately invocable non-interactive benchmarks, and explicit interactive gates. Move tests to background fixtures only where the behavior under test remains representative; retain native responder and visible scrolling checks in the interactive suite. Report deferred gates honestly, and provide scoped cancellation and cleanup.

Verify: default command dependency inspection plus an actual background run with a disposable foreground app holding focus; confirm zero activation/input/window interference throughout. Test cancellation. Check that a background pass clearly leaves keyboard/first-frame/scroll gates pending. Characterize performance under controlled conditions; do not promise identical timings while the machine is busy or in an unvalidated remote/virtual session.

## Verification and review coverage

### Environment and isolation

Working directory for all commands: `/Users/utpalrohan/code/browser`. Host: macOS 26.6.2 (`25G83`), arm64; Xcode 26.6 (`17F113`); Apple Swift 6.3.3. Artifact root: `/private/tmp/browser-audit-20260906` (abbreviated **A** below). Build products, compiler caches, package configuration, and probes were directed there. No app executable, hosted app test, server, network capture, external magnet handler, or live WebKit profile was launched by the audit. Standard Xcode build signing and LaunchServices registration steps ran as part of the builds.

For existing core tests, a disposable SwiftPM wrapper compiled byte-identical copies of 11 production files: AddressInterpreter, Bookmark, BookmarkRepository, BookmarkSearch, LocalFileAccess, PageZoom, NavigationPolicy, ContentBlockingNavigationState, ContentBlockerSite, BrowserPageError, and WebsiteDataSnapshot. It used nine complete, byte-identical existing test files with the corresponding `Tests` suffix, excluding BookmarkSearch (no separate test file) and LocalFileAccessTests (contains live WebKit tests). Repository and symlink fixtures use temporary directories and clean them up. No new application source or permanent test harness was introduced.

### Baseline checks

| Check | Exact invocation / reference | Result and limits |
| --- | --- | --- |
| Git baseline and final scope | `git status --short`; `git branch --show-current`; `git rev-parse HEAD`; `git diff --check` | Initially clean `main` at the recorded HEAD. Finally only this untracked report; no tracked source/configuration changes. |
| Fresh Release build | Command V1 below | Exit 0, `BUILD SUCCEEDED`; all production sources compile. |
| Fresh Release package verification | `./scripts/verify-release.sh /private/tmp/browser-audit-20260906/DerivedData/Build/Products/Release/Browser.app` | Exit 0; ad-hoc signature, arm64, sandbox, hardened runtime, three exact entitlements, no coverage/probe leakage, and pinned blocker resources verified. |
| Full Debug test-target compilation | Command V2 below | Exit 0, `TEST BUILD SUCCEEDED`. Unit and UI targets compile; this does not execute either target. |
| Isolated existing core tests | Command V3 below | Exit 0; **72 XCTest tests, 0 failures**, nine test classes. Separate wrapper, not the full Xcode suite or UI acceptance. |
| Container-audit fixture suite | `./scripts/test-audit-container.sh` | Exit 0; accepted empty fixture history and rejected persisted/unknown state. Six scripted cases; temporary synthetic container only, no real container inspection. |
| Shell syntax | `for f in scripts/*.sh; do sh -n "$f" || exit; done` | Exit 0; syntax only, no script workflows launched. |
| Python syntax | `ast.parse(p.read_text(), filename=str(p))` for every `scripts/*.py` and `TestSupport/*.py` | Four files parsed; no imports, providers, or bytecode writes. |
| Core behavior probe | Command V4 below | Exit 0; reproduced BE-01, BE-02, BE-03. Synthetic URI and files; no actual search request or app host. |
| Standalone performance compile | Command V5 below | Exit 1; five unresolved `LocalFileAccessPolicy` references. Reproduces IN-01 without launching the performance UI. |

Tool limitations: Xcode logged unavailable CoreSimulator/XPC services and skipped AppIntents metadata extraction; both macOS builds nevertheless succeeded. The standalone XCTest build reported actor-isolation warnings in the existing repository test setup/teardown. The first SwiftPM attempt failed because its manifest compiler tried a cache outside the writable roots; explicit module-cache overrides resolved that. The next wrapper attempt included the mixed LocalFileAccessTests file and failed on its missing live-WebKit dependencies; that entire file was excluded before the successful nine-class run. Those two failures were harness preparation issues, not application findings.

### Exact build and diagnostic commands

V1 — fresh Release build (log `A/release-build.log`):

```sh
xcodebuild -project Browser.xcodeproj -scheme Browser -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/browser-audit-20260906/DerivedData \
  CLANG_MODULE_CACHE_PATH=/private/tmp/browser-audit-20260906/XcodeModuleCache \
  SWIFT_MODULE_CACHE_PATH=/private/tmp/browser-audit-20260906/XcodeModuleCache \
  ENABLE_CODE_COVERAGE=NO build
```

V2 — compile full Debug test targets (log `A/debug-test-build.log`):

```sh
xcodebuild -project Browser.xcodeproj -scheme Browser -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/browser-audit-20260906/DebugDerivedData \
  CLANG_MODULE_CACHE_PATH=/private/tmp/browser-audit-20260906/XcodeModuleCache \
  SWIFT_MODULE_CACHE_PATH=/private/tmp/browser-audit-20260906/XcodeModuleCache \
  -enableCodeCoverage NO build-for-testing
```

V3 — existing core tests (log `A/pure-tests-final.log`; the wrapper uses Swift tools/language 6.0, macOS 26, a `Browser` target, and a `BrowserTests` test target depending on it):

```sh
CLANG_MODULE_CACHE_PATH=/private/tmp/browser-audit-20260906/SPMModuleCache \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/browser-audit-20260906/SPMModuleCache \
swift test --package-path /private/tmp/browser-audit-20260906/PureChecks \
  --scratch-path /private/tmp/browser-audit-20260906/PureBuild \
  --cache-path /private/tmp/browser-audit-20260906/SwiftPMCache \
  --config-path /private/tmp/browser-audit-20260906/SwiftPMConfig \
  --security-path /private/tmp/browser-audit-20260906/SwiftPMSecurity \
  --disable-sandbox
```

V4 — direct core probe:

```sh
swiftc -parse-as-library -swift-version 6 \
  -module-cache-path /private/tmp/browser-audit-20260906/ModuleCache \
  Browser/AddressInterpreter.swift Browser/LocalFileAccess.swift \
  Browser/Bookmark.swift Browser/BookmarkRepository.swift Browser/BookmarkSearch.swift \
  /private/tmp/browser-audit-20260906/CoreProbe.swift \
  -o /private/tmp/browser-audit-20260906/core-probe
/private/tmp/browser-audit-20260906/core-probe
```

| Finding | Repeatable probe fixture | Observed result | Limit |
| --- | --- | --- | --- |
| BE-01 | Interpret `magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&dn=private-fixture`; inspect destination host and decoded `q`. | `navigate host=duckduckgo.com entire-input-in-search=true` | Interpreter execution plus source-traced load consumer; no remote request. |
| BE-02 | Fresh UUID-named temporary directory; injected `BookmarkAtomicWriting` writes atomically except it throws `AuditInjectedFailure` for `Bookmarks.json`; first add uses `https://private-fixture.example/`; compare same repository load with a fresh one. | Save throws; `memory-count=0 fresh-count=1 recovery=true`. | Deterministic write fault, not a physical disk failure or UI test. |
| BE-03 | Put bytes `broken` in `Bookmarks.json`, no backup; create/load three fresh repository instances, catching their errors; count `Bookmarks.corrupt.*`. | `launches=3 preserved-copies=3`. | Three repository loads model startup; app not launched. |

V5 — standalone compiler invocation from the performance script, with output/cache paths redirected to A (log `A/benchmark-build.log`):

```sh
xcrun --sdk macosx swiftc -O -whole-module-optimization -parse-as-library \
  -swift-version 6 -strict-concurrency=complete -default-isolation MainActor \
  -module-cache-path /private/tmp/browser-audit-20260906/BenchmarkModuleCache \
  -D BOOKMARK_REPOSITORY_BENCHMARK \
  Browser/Bookmark.swift Browser/BookmarkSearch.swift Browser/BookmarkRepository.swift \
  BrowserPerformanceTests/BookmarkRepositoryBenchmark.swift \
  -o /private/tmp/browser-audit-20260906/bookmark-benchmark
```

### Review coverage and remaining limits

| Area / workflow | Review status | Evidence and remaining work |
| --- | --- | --- |
| Startup, profile, preferences, ownership | Source pass complete | AppDelegate, BrowserProfile, factory, state stores, launch-mode consumers. Live launch/focus acceptance not rerun. |
| Address/search/external links/local files | Source pass complete; selected core execution | Interpreter, scheme and new-context policies, authorization checks, grant reuse, stale panel result guards, tab load/retry/close. No live folder panel, external application, or sandbox grant-revocation check. |
| Tabs and WebKit lifecycle | Source pass complete | New/select/close, lazy creation, early queued URLs, observed state, navigation delegate, failed/cancelled loads, teardown. Existing runtime tests inspected; no current WebContent process or tab-churn measurement. |
| Bookmarks and recovery | Source and repository checks complete | Versioned decoding, canonicalization, actor mutation, primary/backup/recovery, coordinator and native consumers. Three focused defects reproduced; manual recovery remains unperformed. |
| Blocker preparation and policy | Source pass complete; packaging verified | Manifest/source loaders, hash identity, cache lookup, complete fallback, attachment bookkeeping, exact-host exceptions, pending/committed/stale navigation transitions, global resets. Actual production compilation/filter effectiveness not rerun. |
| Website data and privacy | Source pass complete | Cookie versus record identities, deletion refresh/verification, search/reveal, confirmation, close/refresh/mutation generations. No real cookie or website data read/deleted. |
| Native controls and feedback | Source pass complete | Chrome, address field, tab strip, menu targeting/validation, bookmark editor/manager, privacy manager, errors, zoom. Keyboard/visual/accessibility acceptance remains unperformed. |
| Build, tests, performance and scripts | Pass complete at source/check scope | Makefile, Xcode settings/schemes, test setup/fixtures, performance compiler/harness/metric parsers, signature verifier, container/network/resource/process scripts. Fresh Release and full Debug test builds pass; 72 core tests pass; performance compiler fails. Privileged/network/resource/live-profile checks not run. |
| Dependencies and bundled data | Local provenance/packaging checked | No third-party runtime dependency installation; signed bundled-list hashes verified. No external advisory, rule freshness, licensing, or engine-support audit; no internet research was needed for retained source defects. |

The read-through followed representative success/failure paths rather than exhaustively reviewing every line of third-party rule JSON or every historical artifact. Historical July status/performance reports were used for accepted scope and counterevidence, not presented as new runtime results. Passing core tests and build/signature checks do not establish packaged interactive, security, network-privacy, performance, or accessibility acceptance.

Task-authored repository changes are confined to this report. No application/configuration/dependency/test source was edited, no branches or commits were created, and no live user data was intentionally read or changed. Disposable logs, copied sources/tests, compiled artifacts, and probe source remain under A and may expire; synthetic probe bookmark directories and container-test fixtures were cleaned up. Findings include the fixture descriptions and observed outcomes needed to reconstruct the probes after those artifacts expire.

## Continuation checkpoint

2026-09-06: all three requested review layers complete at the scope above. The initial seven-finding checkpoint is superseded by the owner-feedback update adding IN-03 and expanding G02. Eight findings are now open; G01–G06 are proposed, not implemented, verified as fixes, accepted, or merged. Remaining verification is chiefly the native keyboard/blocker-recovery paths and full isolated app-hosted/runtime gates. Desktop takeover is an explicit remediation target, and those interactive gates must not be rerun on the owner's active desktop merely to repair the harness. Start remediation from this baseline after owner authorization; preserve finding IDs and add dated outcomes rather than replacing the original evidence.


## G01/G02 remediation — 2026-09-06 (current checkpoint)

Authorization: owner asked to start fixing G01 and G02. Design: [G01–G02 test isolation design](g01-g02-test-isolation-design.md). Changes remain uncommitted on `main`; G03–G05 application fixes were not included.

- G01 explicitly rejects `magnet:` input before search fallback. Tests cover all three providers, mixed case, whitespace, query-rich URIs, Return and Command-Return interpretation, and the actual hidden controller submission action: displayed Unsupported Address, no queued navigation, no WebView, no external opener. Ordinary submission still queues a URL; existing pointer handoff/host:port/colon-prose regressions remain selected.
- G02 centralizes launch/storage policy in `BrowserLaunchConfiguration`. DebugTesting/ReleaseTesting use `com.utpalchakraborty.browser.testhost`; background startup prohibits activation before the run loop and returns without building the normal app window or services. Preferences, bookmarks, WebKit profiles, geometry, and compiled rules are isolated. Production Debug/Release identity and launch policy are retained.
- The Browser scheme has an explicit background class allowlist. BrowserInteractive retains the two visible-window AppKit classes; BrowserUITests and BrowserPerformance retain desktop automation. BrowserBenchmarks selects only the background blocker benchmark. `make test`, `make release-test`, and `make check` no longer depend on interactive tests or benchmarks.
- Runners serialize fixture ownership, lower scheduling priority, default to two build jobs and two Swift batches, force one compiler thread for WMO, and run tests serially. `BROWSER_BUILD_JOBS=1..8` configures jobs/batches; this is not an OS resource quota. Make targets are serialized as well. Avoid simultaneous direct Xcode tests against the CLI runner's test products.
- SIGINT/SIGTERM cleanup targets the run's process groups and newly launched executables in its dedicated Testing product directory; it never kills by the production Browser name. Four disposable runner tests exercise cancellation/descendant cleanup, unrelated-process survival, lock exclusion/release, invalid concurrency, failure status propagation, and background versus explicit interactive scheduling priority.
- `make bookmark-benchmark` is standalone; `make blocker-benchmark` uses the nonactivating test host. `make performance` rejects execution without `INTERACTIVE=1`; the script requires `--interactive`. `make performance-build` compiles both interactive performance tests and the standalone benchmark without executing either. The bookmark source list now includes `LocalFileAccess.swift` (necessary G02 overlap with IN-01/G06).

### Remediation verification

All commands below ran from `/Users/utpalrohan/code/browser`. The final fresh builds use two build jobs/two Swift batches and an explicit single compiler thread; compiler invocations were inspected to confirm the controls. Background tests run serially. The sandbox initially denied process inspection before any build started; subsequent isolated runner/build checks ran with tool approval for process inspection/testmanagerd access.

| Check | Result | Evidence |
| --- | --- | --- |
| `./scripts/run-tests.sh` (fresh DebugTesting products) | **147 tests, 0 failures**, 7.438 seconds in XCTest | `.build/TestResults.SUCqWm/Browser.xcresult`, adjacent `xcodebuild.log` |
| `./scripts/run-tests.sh --release` (fresh ReleaseTesting products) | **147 tests, 0 failures**, 7.526 seconds in XCTest | `.build/TestResults.cxXeRj/Browser.xcresult`, adjacent `xcodebuild.log` |
| `/usr/bin/python3 scripts/test-verification-session.py` | **4 tests passed**, 2.292 seconds; disposable processes only | `/private/tmp/browser-g01-g02-runner-final.log` |
| Passive foreground sampling during an earlier Debug/Release background run | **766 samples; zero foreground changes**, VLC remained frontmost throughout; monitor did not activate another app | `/private/tmp/browser-g01-g02-focus.log`; the paired runs had 145 tests before the last two isolation regressions were added |
| `./scripts/run-tests.sh --ui-only --build-only` | UI target build passed; no test execution | `.build/TestResults.uL0Yeb/Browser.xcresult` |
| `./scripts/run-performance-tests.sh --build-only` after fresh rebuild | Interactive performance target **and standalone bookmark binary compile passed**; no workload execution | `/private/tmp/browser-g01-g02-clean-performance-build.log`, `.build/BookmarkBenchmark/BookmarkRepositoryBenchmark` |
| `make verify-release DERIVED_DATA=.build/G01G02ReleaseDerivedData` | Fresh production Release build and signature, arm64, sandbox, hardened runtime, pinned blocker asset checks passed | `/private/tmp/browser-g01-g02-production-build.log` |
| Command and scheme inspection | `make -n check` contains no interactive/benchmark commands; all hosted test classes assigned exactly once to background, interactive, or benchmark selection; performance invocation without opt-in exits 2 | `/private/tmp/browser-g01-g02-make-check.txt`, `/private/tmp/browser-g01-g02-performance-guard.log` |
| Final identity/process inspection | Production bundle remains `com.utpalchakraborty.browser`; test app is `com.utpalchakraborty.browser.testhost`; **zero remaining isolated test app processes** | Built Info.plists and scoped `ps` inspection |
| Shell/Python/XML syntax and `git diff --check` | Passed | Local checks of changed runners/schemes |

Runtime isolation checks assert prohibited activation and no visible host windows, exercise isolated rule-store creation, and verify disposable production bookmark/preference sentinels survive actual test-side writes and the search-provider menu action. They do not read or modify the user's real production data.

The first attempt to disable automatic WMO threading exposed a toolchain object-output mismatch on a fresh performance target and stale incremental test objects. Those results are **superseded**: generated outputs (including stray root object files) were moved to `.build/TestingDerivedData/Build.before-thread-limit`, explicit `-num-threads 1` was added, and the final Debug/Release/performance/production products were rebuilt fresh. The two 147-test results above are the acceptance evidence.

Limits: no interactive suite, benchmark workload, production app launch, external handler, or user-data migration/reset ran during remediation. UI/performance test app identity is verified by build configuration and generated test metadata, with foreground behavior still pending an explicitly scheduled interactive run. ReleaseTesting uses optimized testable code with test-host signing accommodations; packaged production performance remains a distinct gate. Lower-priority background benchmarks can contend with other work and do not refresh historical performance baselines. This change limits concurrency and removes desktop automation from routine checks; it does not impose an OS CPU/RAM quota.

Current outcome: G01 and G02 are implemented and verified for routine background use. G03–G05 remain open and unimplemented. IN-01/G06's compiler issue is fixed and build-verified as a necessary part of G02; its 10,000-bookmark workload/timing acceptance is still deferred. Changes are uncommitted and unmerged.


### Owner acceptance and continuation

2026-09-06: the owner reported successful smoke testing and authorized committing the complete G01/G02 slice, then implementing G03 and G04. This is owner-reported smoke acceptance; no additional interactive automation was run by the agent. G03/G04 work starts from the accepted G01/G02 checkpoint.
