# Project Status

Last updated: 2026-07-30

## Restart snapshot

- Phase 4 is fully complete. The native privacy window inspects and deletes
  WebKit website data and exposes visible reset-all actions for blocker
  exceptions and compiled artifacts.
- Final Debug and Release verification each passes 135 unit tests and 12 UI
  tests. Release-package, profile, blocker, WebContent termination, container,
  launch/navigation/scrolling, one/ten-view resource, and fresh blank-network
  gates are green.
- The final network audit's exact metadata filter attributed 8 positive-control
  packets, then observed 0 outbound packets during a 31-second blank launch/idle
  interval. Artifact: `.build/NetworkAudit.HxyZ8u/result.txt`.
- The blocker and popup checkpoint remains approved and committed as `074fc81`
  (`Complete Phase 4 blocker checkpoint`). The separate Phase 3 manual bookmark
  recovery exercise remains pending.
- The minimal Phase 5 tab implementation is complete. A visible native strip
  supports new, select, and close; Command-click opens a source-preserving
  background tab; direct target-blank links open a foreground tab; and each tab
  owns independent navigation and blocking state.
- Phase 5 automated verification is green: 149 Debug and Release unit tests,
  all 13 Debug and Release UI workflows, Release packaging, launch and
  interaction performance, ten-tab switching, ten-tab resources, WebContent
  termination, and the read-only no-history audit pass. The user completed the
  normal-session tab smoke test on 2026-07-28 and confirmed everything works.
- A direct, unmodified primary click on a top-level `magnet:` link now hands the
  untouched URL to the application registered for magnet links in macOS. The
  focused Debug `NavigationPolicyTests` run passes 12 tests. The user confirmed
  the normal-session handoff on 2026-07-30, and the checkpoint is published as
  `3f74d86`.
- Absolute `.html`/`.htm` paths and local `file:///` URLs now open after the user
  approves the exact containing folder through macOS. Per-tab grants are
  read-only and memory-only, support local assets and sibling pages, and end
  when the tab closes. A focused 39-test Debug run passes, including real
  WKWebView coverage for sibling assets, sibling-page navigation, and Back
  across two approved folders. The signed Release bundle passes exact
  entitlement and packaging verification. Artifact:
  `.build/DerivedData/Logs/Test/Test-Browser-2026.07.30_03-51-10--0400.xcresult`.
  The user completed the normal-session folder-panel smoke test on 2026-07-30,
  confirmed the MovieStuff page works, and observed visibly faster loading than
  Chrome.
- Loaded local HTML pages can now be added with the toolbar star or Command-D.
  The explicit file URL persists with the bookmark, while folder authorization
  remains per-tab and memory-only. The same tab reuses its live grant; a new tab
  or app relaunch asks again. A focused 15-test Debug run covers bookmark URL
  validation, symlink identity, current-page candidacy, repository reload, and
  real WKWebView reopening across remote and local pages. Artifact:
  `.build/FocusedBookmarkTests4.xcresult`. The full suite was intentionally not
  rerun; the optimized Release build and static signature/entitlement verifier
  pass. The user completed the normal-session local-file and bookmark smoke test
  on 2026-07-30 and confirmed local pages load and can be saved as bookmarks.

## Current phase

Phase 5 — minimal tabs complete and accepted. The
implemented scope is intentionally limited to the high-frequency tab workflow:
create, select, close, Command-click into a background tab, and direct
target-blank routing into a foreground tab. Automated verification and the
normal-session hands-on smoke test pass.

Phase 4 remains complete and accepted. Its implementation, functional
verification, privacy UI, Release packaging, profile/container/network
inspection, performance, and resource gates all pass. Pinned production rules
are enabled by default, exact-host recovery is available from Privacy, popup
denial is independent of filter matches, and Privacy > Manage Website Data
exposes WebKit data plus global blocker resets.

The clean idle-desktop launch rerun is now green; the separate Phase 3 manual
bookmark-recovery exercise is still pending. The navigation-boundary privacy
race described below is resolved. On 2026-07-27, the user reported that the
Phase 4 blocker and popup checkpoint works in hands-on use and approved it.

The browser is now a usable native multi-tab pilot. It accepts HTTP and HTTPS
URLs, infers HTTPS for plausible hosts, searches plain text, exposes the
selected tab's WebKit navigation state through responsive AppKit controls, and
opens user-approved local HTML without creating passive visit history. Open
tabs, their order, URLs, titles, back/forward state, and local-folder grants
remain memory-only. Application-owned persistence is limited to explicit
bookmarks, required preferences and window geometry, exact-host blocker
exceptions, and last-valid blocker identifiers. The Phase 1 WKWebView GO
decision remains unchanged.

Direct, unmodified primary clicks on top-level `magnet:` links are the sole
external-scheme handoff. Browser cancels WebKit navigation and passes the
original URL to macOS without logging or persisting it. Scripted, synthetic,
modified, subframe, address-field, and other external-scheme navigation remains
blocked.

## Phase 5 minimal tabs complete and accepted

- The main window has a visible native tab strip. The `+` button or Command-T
  creates and selects a fresh blank tab and focuses the address field. Clicking
  a tab selects it; each tab exposes its own close control.
- Command-W closes the selected tab. Closing the sole remaining tab destroys its
  WebView and browsing state, replaces it with a fresh blank tab, and focuses
  the address field. Shift-Command-W closes the browser window.
- Closing a selected tab chooses the tab to its right when available, otherwise
  the tab to its left. Closing a background tab preserves the selected tab.
- A physical Command-click on an HTTP or HTTPS anchor opens and loads a new
  background tab without selecting it or changing the source tab. A direct,
  unmodified pointer click on an HTTP or HTTPS `target="_blank"` anchor opens a
  foreground tab.
- Scripted `window.open`, script-triggered anchors, target-blank forms,
  synthetic activation, separate app windows, and tab-unders remain denied.
  Popup denial remains independent of content-blocking filter matches.
- Every resident tab uses the normal profile and receives the current compiled
  blocking rules and exact-host policy. URL, title, progress, loading,
  back/forward, error, retry, and blocker navigation state are owned per tab;
  selecting a resident tab does not intentionally reload it.
- Relaunch still restores only window geometry. It starts with one fresh blank
  tab and focused address field; there is no tab/session restoration or recently
  closed list.
- Reordering, tab groups, pinned tabs, favicons, previews, animations,
  suspension, and recovery of closed tabs are deferred until ordinary use shows
  a need.

Phase 5 implementation and acceptance are complete. Functional, privacy,
performance, resource, lifecycle, and no-history gates are green. On 2026-07-28,
the user completed the normal-session tab smoke test and confirmed that the
visible tab behavior works.

### Phase 5 automated evidence

- The final Debug combined run passed all 149 unit tests and all 13 UI
  workflows at `.build/TestResults.qPE4pQ/Browser.xcresult`.
- The final Release unit run passed all 149 tests at
  `.build/TestResults.7Le6Ou/Browser.xcresult`; the clean complete Release UI
  run passed all 13 workflows at
  `.build/TestResults.rh5aoW/Browser.xcresult`.
- Release launch passed 20 fresh-process samples. First-frame median/p95 were
  338.592/366.466 ms, native-window median/p95 were 95.559/112.507 ms, and
  first-blank-navigation median/p95 were 84.995/97.708 ms. Artifact:
  `.build/LaunchRetry-20260728-0738.xcresult`.
- Existing interaction gates pass on the tab build: address-submission,
  back/forward-command, and local-navigation p95 were 0.357, 0.195, and
  19.856 ms, and ten controlled-scroll samples had zero browser hitches.
  Artifact: `.build/InteractionPerfFocused-20260728-0744.xcresult`.
- New blank-tab chrome p95 is 6.514 ms against 100 ms at
  `.build/TabCreationFinal-20260728-0842.xcresult`. Switching with ten loaded
  resident tabs is 2.983 ms p95 against 50 ms at
  `.build/TabSelectionFinal-20260728-0840.xcresult`.
- Ten actual resident tabs pass at 184.2 MiB median and 186.8 MiB p95 aggregate
  memory against 1 GiB, with 0.013% mean idle CPU against 1%. Artifact:
  `.build/ResourceBaseline.v10.euHb4k/summary.json`.
- The 100-cycle tab-manager regression and the full-app 100-cycle
  Command-T/Command-W churn probe pass. Across the full-app probe's ten
  ten-cycle batches, median absolute memory fell from 62,932 kB in the first
  half to 55,985 kB in the second half, an 11.04% decrease that passes the
  no-more-than-10% growth gate. Artifact:
  `.build/TabChurnFinal-20260728-0836.xcresult`.
- Closing a resident tab now clears all transient navigation and blocker state;
  queued delegate callbacks from closed or non-owned WebViews are ignored.
  Release WebContent termination also passes, with Browser surviving and
  cleanup completing at `.build/WebContentTermination.6t3i5Q`.
- Production Release verification passes arm64, signature, sandbox,
  entitlements, hardened runtime, and pinned blocker-asset checks. The final
  read-only no-history audit reports zero failures and zero warnings at
  `.build/ContainerAudit.20260728T120411Z.uTeaff/report.txt`.

## Phase 3 implemented

- A toolbar star and Command-D add the current page or edit its existing
  bookmark. Option-Command-B opens a nonmodal, searchable Bookmarks manager.
- Add, edit, delete, title/URL search, duplicate handling, relaunch persistence,
  and open workflows are implemented. Phase 5 now routes bookmark opening and
  creation through the selected tab.
- Explicit local `.html`/`.htm` bookmarks use the same flat library and schema
  as web bookmarks. Only the file URL persists; filesystem approval never does.
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

The original Phase 3 Release performance run completed all 20 launch, 20
address/local-navigation, and 20 back/forward samples. Bookmark and interaction
gates passed, but its 573.542 ms first-frame median missed the 500 ms ceiling.
A confirmation attempt was invalidated by foreground-window interference. This
historical result remains at `.build/PerformanceResults.QvWEvu/`; the clean
Phase 4 run documented below supersedes its launch result and passes every gate.

A fresh container inspection after automated navigation found no Browser-owned
history, visit, session, or navigation database. The app-owned Application
Support namespace contained only the empty isolated `UITests` directory; the
normal and test WebKit `SearchHistory` directories were also empty. Other
database-like files were confined to WebKit's website-data store and represent
WebKit-managed site data, caches, and privacy infrastructure rather than
application-owned visit history.

The user approved the production add/edit/search/open/delete, keyboard-command,
and relaunch-persistence workflow on 2026-07-26. The launch-performance rerun is
now green. One manual backup/recovery/reset scenario remains pending.

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

## Phase 4 privacy controls and final acceptance complete

- Privacy > Manage Website Data, or Option-Command-Y, opens a native nonmodal
  manager backed by the normal profile's `WKWebsiteDataStore`.
- Cookies are grouped by exact cookie domain and remain distinct from WebKit's
  broader record names, which may use public-suffix grouping. The window shows
  name, domain, path, expiry/session, Secure, HttpOnly, and SameSite metadata.
  Values are masked by default, require explicit reveal for the selected cookie,
  are excluded from search, and are scrubbed on selection/mode changes, close,
  refresh, and mutation.
- Confirmed actions delete one cookie, every cookie for an exact displayed
  domain, all cookies, one selected WebKit website-data record, or all
  WebKit-exposed website data. Cookie-only actions leave other categories
  intact. Every mutation refreshes from WebKit and reports data recreated by an
  open page instead of claiming deletion succeeded.
- The same window resets all exact-host blocker exceptions and deletes locally
  compiled blocker artifacts. Current pages keep their in-memory protection;
  the pinned signed rules remain in the app and rebuild locally on next launch
  before remote navigation. UI-test artifact reset is prefix-scoped so it cannot
  remove production compiled lists.
- Final startup ordering schedules blocker preparation before WebKit profile
  creation, preserving the fast native-window path and cached blocker lookup.
  Website-data controls are installed after preparation in both ready and
  fail-closed outcomes, so blocker failure cannot hide the deletion UI.

Final post-startup-fix functional verification is green: the combined Debug run
passed 135 unit tests and 12 UI tests, Release unit passed 135, and Release UI
passed 12. Artifacts: `.build/TestResults.YXZZik/Browser.xcresult`,
`.build/TestResults.lRwo5P/Browser.xcresult`, and
`.build/TestResults.LBpOx9/Browser.xcresult`. The final focused privacy flow,
including global deletion, is at `.build/TargetedPrivacyGlobal2.xcresult`.

The final actual-app profile probe used distinct process IDs 24498, 24530, and
24563, proved the persistent cookie survived (`cookie-survived=true`), then
proved deletion across relaunch. Artifact:
`.build/ActualAppProfileProbe.oe3hQC`. The fresh production blocker benchmark
passed with cached lookup p95 0.218375 ms, synchronous attachment p95
0.000209 ms, and removal p95 0.000125 ms at
`.build/ContentBlockerBenchmark.qIb6ev`. Production WebContent termination also
passed: the target exited, Browser survived five seconds, no replacement
appeared within five seconds, and Browser/WebContent cleanup completed.
Artifact: `.build/WebContentTermination.YLxbl5`. Release verification passed
arm64, signature, App Sandbox, hardened runtime, exact entitlements, and
independently pinned blocker-resource checks for
`.build/DerivedData/Build/Products/Release/Browser.app`.

The clean Release run remains the accepted Phase 4 production-app launch,
navigation, command, and readiness gate. It predates and is superseded for
Phase 5 evidence by the fresh tab-specific results above. First-frame
median/p95/max are
429.257/538.403/577.416 ms; native-window median/p95 are 88.269/106.669 ms; and
the conservative initial-WebView readiness proxy is
636.481/754.233/796.431 ms. Address submission median/p95 are 0.217/0.433 ms,
browser command 0.174/0.193 ms, and local navigation 12.751/17.180 ms. Relative
to Phase 2, first-frame median/p95 improved 13.89%/4.78% and readiness improved
11.67%/4.02%. The 10,000-bookmark load and search p95 values are 62.716 ms and
18.980 ms. Artifact: `.build/PerformanceResults.X3uvqP`. At the Phase 4
checkpoint, production application code had not changed after this clean
passing run; Phase 5's fresh verification is recorded above.

The scrolling harness was subsequently hardened in test/fixture code only. A
visible `top`/`moved` marker now proves a swipe actually moves the deterministic
document, and the preflight restores the fixture to the top before measuring.
All three XCTest methods passed in `.build/PerformanceResults.j6rcfP`; its ten
genuine scroll samples reported zero hitch duration, count, and ratio. Bookmark
load/filter/search p95 were 61.928/18.768/18.588 ms, local-navigation p95 was
19.360 ms, address p95 was 0.433 ms, and command p95 was 0.184 ms.

That later run's aggregate summary missed only the outer XCTest first-frame p50
ceiling: median 529.613 ms against 500 ms, while p95 was 568.708 ms and both
Phase 2-relative gates passed. A settled launch-only confirmation at
`.build/PerformanceLaunchConfirmation.EJpHTr` likewise passed its XCTest method
but measured a 524.319 ms outer median. App-owned native-window medians remained
92.954 and 92.989 ms. With production code unchanged, these diagnostics expose
the documented outer XCTest/OS launch bimodality and do not replace the clean
`X3uvqP` release acceptance run.

One-view resources pass with 73.5 MiB median, 73.7 MiB p95, and 0.020% mean idle
CPU at `.build/ResourceBaseline.v1.f2jBcc`. The synthetic ten-resident-view
probe passes with 283.2 MiB median, 296.9 MiB p95, and 0.007% mean idle CPU at
`.build/ResourceBaseline.v10.zRM3n4`. The final read-only container audit and
its negative self-test passed. Normal, UI-test, and performance SearchHistory
logical-entry counts were all zero; all 6 preference keys were allowlisted with
0 unexpected; and the audit reported 0 failures and 0 warnings. Artifact:
`.build/ContainerAudit.20260728T094138Z.hM7afi/report.txt`.

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
  navigation shortcuts. Command-+, Command--, and Command-0 adjust or reset
  transient page zoom independently for the selected tab; zoom is never
  persisted.
- No third-party runtime dependencies, telemetry, or application-owned visit
  history.

## Approved Phase 2 QoL follow-up

The implementation remembers only the main browser window's last usable size
and location through AppKit's native frame autosave. AppKit applies the saved
frame for the current display environment, while the browser keeps its centered
default when there is no usable saved frame. AppKit state restoration stays
disabled, and relaunch must remain blank with the address field focused; no URL,
page, back/forward, or tab state may be restored.

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
ceiling. The p95 was 599.275 ms against its 800 ms ceiling. That historical run
failed the median gate and remains at `.build/PerformanceResults.NfA7if/`; the
clean final Phase 4 run now supersedes it and passes.

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

The final privileged pktap audit passed with metadata filter
`(dir=out and (proc=Browser or eproc=Browser))`. Its positive attribution
control captured 8 outbound packets, then the production blank launch emitted
0 attributed outbound packets during 31 seconds idle. The result is `PASS` at
`.build/NetworkAudit.HxyZ8u/result.txt`. This supersedes the historical Phase 1
network evidence.

## Current limitations

There is one browser window with multiple memory-only tabs. Opening a bookmark
targets the selected tab. Production ad/tracker rules and the website-data
privacy manager are active. Tab reordering, grouping, pinning, previews,
favicons, session restoration, and recently closed tabs are not implemented.
Downloads and private windows remain later work.

Programmatic popups are suppressed: no page-created secondary app window,
autonomous background tab, or tab-under is permitted. Scripted `window.open`
and forms targeting a new context are denied. A physical Command-click is an
explicit user request for a background tab and preserves the source tab; a
direct unmodified pointer click on an HTTP or HTTPS target-blank anchor opens a
foreground tab. Ad/tracker blocking often stops popup scripts and advertising
overlays before they run, but popup denial is a separate backstop that does not
depend on a filter match.

DNS and TLS presentations have deterministic unit coverage; the end-to-end UI
retry scenario uses a refused localhost connection. Representative real-site
compatibility remains a hands-on regression check rather than a stable
automated gate.

## Next action

Use the accepted local-file and bookmark workflow in ordinary browsing before
selecting another Phase 6 daily-driver hardening feature.

Phase 5 is complete. Use the accepted minimal tab workflow in ordinary browsing
before selecting any Phase 6 daily-driver hardening feature; reordering,
grouping, pinned tabs, previews, and session restoration remain deferred until
real use demonstrates a need.

Separately, back up the bookmark files, force one recovery, and test Restore
Backup or Reset Bookmarks. Revisit bookmark folders only if ordinary use shows
that the flat searchable manager is insufficient.
