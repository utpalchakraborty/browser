# Project Status

Last updated: 2026-07-27

## Current phase

Phase 4 — the first ad/tracker-blocking and popup-suppression checkpoint is
complete and approved. Pinned production rules are enabled by default, an
exact-host compatibility exception is available from the Privacy menu, and the
browser-level popup backstop is covered independently of filter matches.
Website-data privacy controls are the next Phase 4 slice. Tabs remain Phase 5.

The Phase 3 manual bookmark-recovery exercise and clean idle-desktop launch-
performance rerun are still pending. Post-fix Debug and Release unit and UI
verification, the production-list benchmark, and production Release bundle
verification are green. The navigation-boundary privacy race described below
is resolved. On 2026-07-27, the user reported that the Phase 4 blocker and popup
checkpoint works in hands-on use and approved it.

The browser is now a usable native single-page pilot. It accepts HTTP and HTTPS
URLs, infers HTTPS for plausible hosts, searches plain text, exposes WebKit
navigation state through responsive AppKit controls, and creates no passive
visit history. Application-owned persistence is limited to explicit bookmarks,
required preferences and window geometry, exact-host blocker exceptions, and
last-valid blocker identifiers. The Phase 1 WKWebView GO decision remains
unchanged.

## Phase 3 implemented

- A toolbar star and Command-D add the current page or edit its existing
  bookmark. Option-Command-B opens a nonmodal, searchable Bookmarks manager.
- Add, edit, delete, title/URL search, duplicate handling, relaunch persistence,
  and open-in-current-page workflows are implemented. Tabs remain deliberately
  absent until Phase 5.
- The bookmark library is intentionally a flat, keyboard-first searchable
  manager with no persistent bookmarks bar. The user approved this cleaner
  workflow; folder hierarchy is deferred until real use demonstrates a need.
- Versioned bookmark models are independent of AppKit and WebKit. An
  actor-isolated repository performs atomic JSON writes outside the main actor
  and retains a last-valid backup.
- Production data lives under the app's Application Support container as
  `Bookmarks.json` and `Bookmarks.backup.json`. UI tests use an isolated
  `UITests` directory and can reset it explicitly.
- Corrupt primary data is preserved, a valid backup is presented read-only,
  and the manager offers explicit restore or reset actions. Invalid or
  unsupported files are not silently replaced.
- Normal bookmark startup is queued after the initial native window is shown.
  Performance-test launches do not create or touch a bookmark repository.
- The no-history and no-telemetry invariants are unchanged: only explicitly
  saved bookmark URLs enter application-owned persistence.

Debug automated verification is green: 70 of 70 unit tests passed and 9 of 9
UI tests passed. The UI suite covers add, edit, title/URL search, relaunch,
keyboard-driven open/edit/delete, and confirmed deletion. The storage suite
also verifies that edited and deleted URLs disappear from both active JSON
copies. Artifacts: `.build/TestResults.SgT7hl/Browser.xcresult` and
`.build/TestResults.I0omV2/Browser.xcresult`.

Release automated verification is also green: 70 of 70 unit tests and 9 of 9
UI tests passed. The production bundle passed arm64, sandbox-entitlement,
hardened-runtime, and signature inspection. Artifacts:
`.build/TestResults.1ViJIr/Browser.xcresult`,
`.build/TestResults.LvYCDE/Browser.xcresult`, and
`.build/DerivedData/Build/Products/Release/Browser.app`.

The Release 10,000-bookmark gate is green: load p95 is 63.164 ms against a
100 ms limit, repository search p95 is 18.725 ms, and the exact manager filter
path is 18.536 ms against 50 ms limits. The generated 2,398,938-byte fixture
lives only in a temporary benchmark directory and contains no user data.

The full Release performance run completed all 20 launch, 20 address/local
navigation, and 20 back/forward samples. Bookmark and interaction gates passed:
address submission p95 was 0.758 ms, browser-command p95 was 0.187 ms, and
local navigation p95 was 24.206 ms. The launch gate did not pass: first-frame
median was 573.542 ms against 500 ms, although p95 was 624.031 ms against
800 ms; Phase 2-relative first-frame and readiness comparisons exceeded their
10% budgets. Performance-test launches do not initialize bookmarks, which
isolates bookmark-store I/O but does not by itself explain the launch result.
A confirmation attempt was invalidated by foreground Ghostty-window
interference and stopped. A clean idle-desktop rerun is required. Artifacts:
`.build/PerformanceResults.QvWEvu/`.

A fresh container inspection after automated navigation found no Browser-owned
history, visit, session, or navigation database. The app-owned Application
Support namespace contained only the empty isolated `UITests` directory; the
normal and test WebKit `SearchHistory` directories were also empty. Other
database-like files were confined to WebKit's website-data store and represent
WebKit-managed site data, caches, and privacy infrastructure rather than
application-owned visit history.

The user approved the production add/edit/search/open/delete, keyboard-command,
and relaunch-persistence workflow on 2026-07-26. One manual
backup/recovery/reset scenario and a clean launch-performance rerun remain
pending.

## Phase 4 blocker checkpoint complete

- Production ships pinned AdGuard Base and Tracking Protection WebKit rule
  lists: 36,356 and 83,156 rules, respectively, for 119,512 total. The source
  registry commit is `1429043fe73b7a16577966ff04afa7e5ba630925`; conversion
  used pinned Safari Converter 4.3.0. Exact source, converter, input, output,
  license, and attribution data is bundled with the app.
- Blocking is enabled by default. Browser performs no filter download or
  automatic update request. Updates are manual and release-bound.
- A normal cached launch resolves the immutable compiled identifiers without
  loading the 15,149,980 bytes of JSON. A first install or changed bundle hashes
  and loads the JSON away from the main actor, then uses WebKit's asynchronous
  compiler. The latest Release cold compile measured 4,160.4 ms; observed cold
  runs are roughly 4 to 7 seconds.
- The native window and focused address field appear before preparation.
  Remote navigation is queued until protected rules are ready. A changed rule
  package activates transactionally; a failure retains the complete last-valid
  set, and no available set produces a visible fail-closed state.
- Privacy displays `Active`, `Active (Last Valid Rules)`, `Preparing`, an exact-
  host disabled state, or `Unavailable`. Option-Command-P toggles a persistent
  exception for the current exact HTTP(S) host and explicitly reloads. The
  exception does not inherit to subdomains, alternate names such as
  `localhost`, or unrelated hosts.
- Popup denial remains a separate browser-level invariant. Load-time, promise,
  timer, click-handler, scripted-anchor, and target-blank-form paths are denied
  without creating another app window or WKWebView. A directly clicked HTTP(S)
  anchor may route deliberately into the existing page. Denied or failed
  navigation restores the blocker policy of the committed page.
- An ordinary pending navigation may only strengthen the resident content policy. An
  exact-host relaxation is applied only after the winning document commits;
  stale, overlapping, and post-commit callbacks cannot weaken the committed or
  newer page. The explicit current-site switch applies its chosen policy before
  reload so a document-level match cannot make the recovery control ineffective.

Debug unit verification passed 117 of 117 tests. Release unit verification also
passed 117 of 117 tests, including compiling and attaching the actual production
lists, proving an ordinary local resource loads, proving a production-matched
ad resource is never requested, and proving list removal restores it. The
navigation suite covers a slow protected-to-excepted transition, an overlapping
replacement navigation, stale commits and failures, post-commit and unbound
callback ordering, and fragment navigations that emit only an action callback.
Artifacts: `.build/TestResults.VlB318/Browser.xcresult` and
`.build/TestResults.JJXn94/Browser.xcresult`.

The pre-commit navigation-boundary blocker is resolved. Policy application is
strengthen-only while an ordinary navigation is pending, exact relaxation is
reserved for the winning commit, and stale or overlapping callbacks leave the
resident policy unchanged. The deliberate current-site switch is applied
before its explicit reload, including for a document-blocking rule. The
deterministic regressions above exercise both the live WebKit boundary and the
navigation-state ordering model.

The dedicated production-list benchmark passed with cached lookup p95
0.216417 ms, synchronous attachment p95 0.000250 ms, and removal p95
0.000125 ms. Artifact: `.build/ContentBlockerBenchmark.BjTFAk`. The packaged
Release app passed arm64, signature, App Sandbox, hardened-runtime, entitlement,
and independently pinned blocker-resource checks.

The expanded UI suite now checks blocked-request counts, exception persistence,
exact-host isolation, re-enabling, scripted-anchor denial, and unchanged app-
window and WKWebView counts. Debug and Release each passed all 11 tests.
Artifacts: `.build/TestResults.UqqvcE/Browser.xcresult` and
`.build/TestResults.LgnTdT/Browser.xcresult`.

## Phase 2 delivered

- Native toolbar with a launch-focused address field, Back, Forward,
  Reload/Stop, progress, page title, and displayed final URL.
- HTTPS-first address interpretation plus DuckDuckGo, Google, and Bing search
  selection. The selected provider is application-owned persistent state.
- Sanitized connection, TLS, redirect, timeout, generic navigation, and
  WebContent-process errors, with retry where recovery is meaningful.
- HTTP/HTTPS top-level navigation policy, explicit unsupported-scheme blocking,
  and current-page routing for user-activated new-window links.
- A central WebView factory, persistent normal WebKit profile, isolated test
  and performance profiles, disabled scripted popups, and disabled AppKit
  restoration.
- Standard Command-L, Command-[, Command-], Command-R, and Command-period
  navigation shortcuts.
- No third-party runtime dependencies, telemetry, or application-owned visit
  history.

## Approved Phase 2 QoL follow-up

The implementation remembers only the main browser window's last usable size
and location through AppKit's native frame autosave. AppKit applies the saved
frame for the current display environment, while the browser keeps its centered
default when there is no usable saved frame. AppKit state restoration stays
disabled, and relaunch must remain blank with the address field focused; no URL,
page, back/forward, or future tab state may be restored.

The user manually approved this behavior, and it was committed as `aa8ee6a`.

The Debug unit suite passed 48 tests, including isolated native-frame save and
restore plus launch-mode coverage. The Debug UI suite passed all 8 tests,
including the blank relaunch and focused-address-field invariant. Artifacts:
`.build/TestResults.mxVJk2/Browser.xcresult` and
`.build/TestResults.UYdLip/Browser.xcresult`.

A post-change Release performance run completed every launch, navigation, and
command sample. The browser-specific comparisons stayed within the 10%
regression budget, including a 91.364 ms median native-window presentation, but
XCTest's outer first-frame median was 547.960 ms against the 500 ms absolute
ceiling. The p95 was 599.275 ms against its 800 ms ceiling. The overall gate is
therefore not yet green; rerun it on an otherwise idle desktop because separate
confirmation attempts were invalidated by foreground-window interference.
Artifact: `.build/PerformanceResults.NfA7if/`.

Detailed design and historical evidence:

- [performance-baseline.md](performance-baseline.md)
- [phase-1-risk-report.md](phase-1-risk-report.md)

## Phase 2 verification summary

- Debug functional suite: 54 tests passed (46 unit and 8 UI), 0 failures.
  Artifact: `.build/TestResults.LmiNhY/Browser.xcresult`.
- Release unit suite: 46 tests passed, 0 failures. Artifact:
  `.build/TestResults.iDzvUB/Browser.xcresult`.
- Release UI suite: 8 tests passed, 0 failures. Artifact:
  `.build/TestResults.zroTLm/Browser.xcresult`.
- Release performance suite: 20 focused launches, 20 address submissions/local
  navigations, and 20 back/forward commands passed. First-frame median was
  498.522 ms and p95 was 565.402 ms. Initial WebView readiness-proxy p95 was
  785.794 ms. Artifacts: `.build/PerformanceResults.tfAxfa/`.
- One-page Release resources: aggregate memory p95 86.5 MiB and idle CPU mean
  0.013%, both passing. Artifact:
  `.build/ResourceBaseline.v1.eCb0JI/summary.json`.
- Production Release verification passed: arm64, hardened runtime, exactly App
  Sandbox and outgoing-network entitlements, no coverage instrumentation, and
  no DEBUG profile-probe markers.
- Production WebContent termination passed: the attributed process exited,
  Browser survived, and cleanup completed. Artifact:
  `.build/WebContentTermination.n6I7uO`.
- The restoration UI test navigated with a unique sentinel and verified a blank
  relaunch. That sentinel was absent from application preferences, AppKit
  saved-state data, and Browser unified logs.

The Phase 1 privileged pktap audit remains the current blank-network evidence:
8 positive-control packets and 0 Browser-attributed outbound packets during a
31-second blank launch/idle window (`.build/NetworkAudit.aG4SkM`). A fresh
Phase 2 invocation reached the scoped `sudo` password prompt and was stopped;
rerun `make network-audit` from an interactive Terminal if fresh packet-capture
evidence is desired.

## Current limitations

There is one page and one window. Opening a bookmark replaces the current page.
Production ad/tracker rules are active. The website-data privacy-management UI
remains Phase 4; tabs are Phase 5. Downloads and private windows remain later
work.

Programmatic popups are suppressed, and the roadmap now makes that behavior an
explicit invariant: no page-created secondary app window, WKWebView, background
tab, or tab-under is permitted. Scripted `window.open` and forms targeting a new
context are denied. Only a direct pointer click on an HTTP or HTTPS anchor
targeting a new context may route anywhere; it replaces the current page now
and will open a foreground tab in Phase 5. Ad/tracker blocking often stops
popup scripts and advertising overlays before they run, but popup denial is a
separate backstop that does not depend on a filter match.

DNS and TLS presentations have deterministic unit coverage; the end-to-end UI
retry scenario uses a refused localhost connection. Representative real-site
compatibility remains a hands-on regression check rather than a stable
automated gate.

## Next action

Implement the website-data privacy window as the next Phase 4 slice, including
cookie/site-data deletion plus reset controls for all blocker exceptions and
compiled blocker artifacts. A fresh blank-network and container audit and the
full launch/resource performance gates remain Phase 4 acceptance work.

Separately, back up the bookmark files, force one recovery, test Restore Backup
or Reset Bookmarks, and rerun the launch-performance gate on an idle desktop.
Tabs follow in Phase 5. Revisit bookmark folders only if ordinary use shows
that the flat searchable manager is insufficient.
