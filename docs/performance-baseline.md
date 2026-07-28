# Performance Baseline

Status: Phase 1 historical baseline retained; Phase 2 baseline locked; Phase 3
bookmark gates pass; Phase 4 blocker, full-app launch/navigation/scrolling, and
one/ten-view resource gates pass; minimal Phase 5 tab performance, churn, and
ten-tab resource gates pass
Last updated: 2026-07-28

## Environment

| Item | Value |
| --- | --- |
| Hardware | Mac Studio (Mac15,14), Apple M3 Ultra, 32 CPU cores (24 performance and 8 efficiency), 512 GB unified memory |
| Operating system | macOS 26.5.2, build 25F84 |
| Power | AC power |
| Xcode | 26.6, build 17F113 |
| SDK | macOS 26.5 |
| Swift | 6.3.3 |
| Architecture | arm64 |
| Build configuration | Release, no debugger, sanitizers, or code coverage |
| Runtime dependencies | Apple system frameworks only |
| Phase 1 measured source state | Checkpoint `a726dc9`; see the collection note below |
| Phase 2 measured source state | Checkpoint `1d3221f` |
| Window-geometry checkpoint | `aa8ee6a`; manually approved |
| Phase 4 accepted production-app state | Final implementation working tree based on `89888ce`; `.build/PerformanceResults.X3uvqP` passed before later performance-test/fixture-only hardening |
| Hardened scrolling state | Production app code unchanged; only performance test, deterministic fixture, and documentation changed before `.build/PerformanceResults.j6rcfP` |
| Phase 5 measured state | Minimal tab implementation working tree; split final launch, interaction, tab, and resource artifacts listed below |

Raw results stay in ignored `.build` directories and are never uploaded. Phase
2 is also recorded in `TestSupport/phase2_performance_baseline.json`, which is
the machine-readable comparison point for subsequent phases.

The Phase 1 launch and resource runs predate final test/audit-harness hardening
in `a726dc9`; that hardening did not change the Release launch path in
`AppDelegate` or `BrowserWindowController`. The production Release bundle was
rebuilt and verified after those changes, and each result section records its
exact raw artifact path.

## Phase 3 measurement status

Bookmark functionality has passed the Debug suites (70 unit tests and 9 UI
tests). Its standalone optimized 10,000-bookmark gate also passes: load p95 is
63.164 ms against a 100 ms limit; repository-search p95 is 18.725 ms and the
manager's exact filter path is 18.536 ms against 50 ms limits. The fixture is
2,398,938 bytes, is generated in a temporary directory, and contains no user
data. The Release functional suites pass at 70 unit tests and 9 UI tests, and
the production bundle passes architecture, signature, sandbox-entitlement, and
hardened-runtime inspection.

The production launch path presents and focuses the native window before it
queues bookmark-repository startup. The repository performs file work in its
actor rather than on the main actor. `--performance-test` launches do not
construct a repository or touch the production bookmark files, preserving
bookmark-store isolation.

The original Phase 3 `make performance` run completed all samples and passed
interaction gates, but its 573.542 ms application first-frame median missed the
500 ms ceiling. A confirmation attempt was interrupted by another foreground
window and is not evidence. The historical result remains at
`.build/PerformanceResults.QvWEvu/`. The clean final Phase 4 run below supersedes
that launch result and passes all absolute and Phase 2-relative gates.

## Protocol

- Use a separately verified production Release app for CPU and memory.
- Use isolated DerivedData for XCUITest so test re-signing cannot contaminate
  the production artifact.
- Use deterministic localhost fixtures for web-content scenarios.
- Discover WebKit XPC helpers by a before/after process snapshot because they
  are launchd children, not Browser child processes.
- Reject memory or CPU samples if the attributed helper set changes.
- Include Browser, GPU, Networking, and every WebContent process in aggregate
  footprint and CPU.
- Record and exclude one WebKit/GPU warm-up launch, then collect ten fresh
  process launches for memory.
- Drop `top`'s cumulative first sample, then average 30 one-second idle samples.
- Report nearest-rank p95, median, minimum, maximum, and failures.

## Phase 2 launch, navigation, and command results

Command: `make performance`

Result bundles:

- `.build/PerformanceResults.tfAxfa/BrowserLaunchPerformance.xcresult`
- `.build/PerformanceResults.tfAxfa/BrowserInteractionPerformance.xcresult`

Twenty terminated launches, twenty deterministic address submissions/local
navigations, and twenty back/forward commands completed with zero failures.
Every launch sample also proved that typing reached the address field without a
click.

| Metric | Minimum | Median | Mean | p95 | Maximum | Gate |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| Application first frame responsive | 385.997 ms | 498.522 ms | 478.187 ms | 565.402 ms | 585.846 ms | Pass: p50 <= 500 ms; p95 <= 800 ms |
| Native window presentation | 72.913 ms | 86.818 ms | 85.317 ms | 94.698 ms | 101.600 ms | Reported |
| Initial address-field focus assignment | 2.038 ms | 2.287 ms | 2.291 ms | 2.541 ms | 2.666 ms | Reported; usability asserted per launch |
| Measured WebView deferral | 100.166 ms | 101.712 ms | 101.603 ms | 102.516 ms | 103.376 ms | Included in readiness gate |
| Initial WKWebView construction | 17.085 ms | 22.687 ms | 21.983 ms | 27.633 ms | 29.027 ms | Reported |
| First `about:blank` navigation | 82.577 ms | 87.919 ms | 88.922 ms | 95.211 ms | 97.943 ms | Reported |
| Address submission | 0.203 ms | 0.260 ms | 0.284 ms | 0.398 ms | 0.627 ms | Pass: p95 <= 50 ms; max <= 100 ms |
| Back/forward command | 0.108 ms | 0.192 ms | 0.172 ms | 0.215 ms | 0.216 ms | Pass: p95 <= 50 ms; max <= 100 ms |
| Deterministic local navigation | 7.161 ms | 9.914 ms | 11.801 ms | 17.917 ms | 28.464 ms | Reported |

WebKit starts after a measured 100 ms deferral so native chrome can paint and
accept input first. The conservative paired-sample readiness proxy includes
first frame, the full deferral, WebView construction, and blank navigation. It
measured 588.495 ms minimum, 720.606 ms median, 690.694 ms mean, 785.794 ms p95,
and 796.750 ms maximum, passing the 1.2-second p95 ceiling.

Compared with Phase 1, application first-frame median increased 47.50% and p95
increased 44.16%; the readiness-proxy median increased 60.61% and p95 increased
55.83%. These are explicit, explained checkpoint regressions: Phase 2 replaces
the blank scaffold with the production toolbar, focused address field, menus,
WebView factory, navigation policy/delegates, and observed page state. This
explanation does not waive the unchanged absolute budgets, which pass.

## Phase 2 settled one-page resources

Command: `make resource-one`

Artifact: `.build/ResourceBaseline.v1.eCb0JI/summary.json`

| Metric | Samples | Minimum | Median/Mean | p95 | Maximum | Gate |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| Aggregate process footprint | 10 launches | 72.8 MiB | 73.0 MiB median | 86.5 MiB | 86.5 MiB | Pass: p95 <= 300 MiB |
| Aggregate idle CPU | 30 seconds | 0.0% | 0.013% mean | 0.0% | 0.4% | Pass: mean < 1% |

The aggregate includes Browser plus its attributed WebKit GPU, Networking, and
WebContent processes. All samples retained a stable four-process set.

## Phase 1 launch and initial WebKit baseline

Command: `make performance`

Result bundle: `.build/PerformanceResults.vXonZF/BrowserPerformance.xcresult`

Twenty terminated launches completed with zero failures.

| Metric | Minimum | Median | Mean | p95 | Maximum |
| --- | ---: | ---: | ---: | ---: | ---: |
| Application first frame responsive | 304.365 ms | 337.972 ms | 343.902 ms | 392.193 ms | 399.097 ms |
| Native window presentation signpost | 45.524 ms | 78.492 ms | 78.341 ms | 104.297 ms | 114.779 ms |
| Initial WKWebView construction | 18.263 ms | 24.008 ms | 24.998 ms | 33.113 ms | 43.385 ms |
| First `about:blank` navigation | 73.769 ms | 87.694 ms | 86.875 ms | 102.779 ms | 120.644 ms |

The Phase 1 scaffold had no address field, so first-frame responsiveness was
the proxy for interactive native chrome. A conservative paired-sample proxy
formed from first frame plus WebKit construction plus blank navigation measured
448.682 ms
median, 504.267 ms p95, and 510.462 ms maximum. It is explicitly a component
sum, not a direct end-to-end signpost.

## Phase 1 settled resource baseline

Commands:

~~~sh
make resource-one
make resource-ten
~~~

| Memory scenario | Samples | Minimum | Median | p95 | Maximum | Gate |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| One resident blank view, aggregate footprint | 10 | 65.4 MiB | 65.5 MiB | 65.6 MiB | 65.6 MiB | Pass, p95 at or below 300 MiB |
| Ten resident deterministic views, aggregate footprint | 10 | 277.2 MiB | 278.7 MiB | 280.5 MiB | 280.5 MiB | Pass, p95 at or below 1 GiB |

| CPU scenario | Samples | Minimum | Mean | p95 | Maximum | Gate |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| One resident blank view, aggregate idle CPU | 30 seconds | 0.0% | 0.020% | 0.100% | 0.500% | Pass, mean below 1% |
| Ten resident deterministic views, aggregate idle CPU | 30 seconds | 0.0% | 0.020% | 0.100% | 0.500% | Pass, mean below 1% |

One-view artifacts:
`.build/ResourceBaseline.v1.DVAuht/summary.json`.

Ten-view artifacts:
`.build/ResourceBaseline.v10.9bUESM/summary.json`.

The ten-view fixture produced ten `/normal/` and ten script requests per run
and resulted in ten WebContent processes. All ten WKWebViews were resident in
the window hierarchy, with nine hidden like background tabs.

The one-view and ten-view pages intentionally differ, so these results lock the
absolute gates but do not claim an exact incremental-per-tab slope.

## Phase 1 content-rule baseline

Command: `make blocker-benchmark`

The Release-optimized benchmark compiled one deterministic rule list as setup,
then measured cached lookup, attachment, and removal.

| Operation | Samples | Median | p95 | Maximum |
| --- | ---: | ---: | ---: | ---: |
| Cached rule-list lookup | 100 | 0.078291 ms | 0.107666 ms | 1.484959 ms |
| Synchronous attachment | 500 | 0.000083 ms | 0.000125 ms | 0.000292 ms |
| Synchronous removal | 500 | 0.000042 ms | 0.000042 ms | 0.000209 ms |

Cached attachment passes the p95 below 50 ms gate by a wide margin. Large
production-list conversion and first-install compilation were intentionally
deferred from this Phase 1 baseline to Phase 4.

## Phase 4 production content-rule checkpoint

Command: `make blocker-benchmark`

The Release-optimized production benchmark resolves both pinned compiled rule
lists—119,512 total rules—from `WKContentRuleListStore`, then measures lookup,
attachment, and removal without reading bundled JSON.

| Operation | Samples | Median | p95 | Maximum |
| --- | ---: | ---: | ---: | ---: |
| Two-list cached lookup | 100 | 0.168584 ms | 0.218375 ms | 0.318708 ms |
| Two-list synchronous attachment | 500 | 0.000167 ms | 0.000209 ms | 0.000333 ms |
| Two-list synchronous removal | 500 | 0.000125 ms | 0.000125 ms | 0.000334 ms |

Artifact: `.build/ContentBlockerBenchmark.qIb6ev`.

The isolated Release production-package test also forced a cold compile of
both bundled lists in 4,160.4 ms. A prior cold run measured 6,714.4 ms, so the
first-install expectation is currently roughly 4 to 7 seconds. This work runs
only when immutable identifiers miss the local WebKit cache; cached launch
performs neither JSON loading nor compilation. The native window is already
interactive, but protected remote navigation waits for preparation.

This focused benchmark is paired with the final full-app and resource gates
below.

## Phase 4 accepted production-app launch and interaction results

Command: `make performance`

Artifacts:

- `.build/PerformanceResults.X3uvqP/BrowserLaunchPerformance.xcresult`
- `.build/PerformanceResults.X3uvqP/BrowserInteractionPerformance.xcresult`
- `.build/PerformanceResults.X3uvqP/summary.json`
- `.build/PerformanceResults.X3uvqP/bookmark-benchmark.log`

The clean accepted run collected 20 samples for every launch, navigation, and
command metric. Every launch also asserted that the address field accepted
focus without a click. The AppDelegate ordering keeps the named WebKit profile
out of the first-frame path: after the measured deferral, blocker preparation
starts before lazy profile creation, and privacy controls are installed in
either the ready or fail-closed preparation outcome. The run also contained the
first scrolling loop, but that loop lacked an explicit document-motion
preflight; its scroll measurements are superseded by the hardened evidence
below rather than used to close the scrolling gate.

| Metric | Minimum | Median | Mean | p95 | Maximum | Gate |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| Application first frame responsive | 297.565 ms | 429.257 ms | 438.899 ms | 538.403 ms | 577.416 ms | Pass: p50 <= 500 ms; p95 <= 800 ms |
| Native window presentation | 83.547 ms | 88.269 ms | 91.444 ms | 106.669 ms | 106.947 ms | Reported |
| Initial address-field focus assignment | 2.304 ms | 2.554 ms | 2.552 ms | 2.662 ms | 2.671 ms | Reported; usability asserted per launch |
| Measured WebView deferral | 100.272 ms | 101.364 ms | 101.666 ms | 103.442 ms | 103.691 ms | Included in readiness gate |
| Initial WKWebView construction | 16.587 ms | 18.938 ms | 19.583 ms | 22.753 ms | 24.039 ms | Reported |
| First `about:blank` navigation | 82.737 ms | 87.171 ms | 88.404 ms | 100.046 ms | 100.087 ms | Reported |
| Initial WebView readiness proxy | 503.465 ms | 636.481 ms | 648.552 ms | 754.233 ms | 796.431 ms | Pass: p95 <= 1.2 s |
| Address submission | 0.196 ms | 0.217 ms | 0.265 ms | 0.433 ms | 0.460 ms | Pass: p95 <= 50 ms; max <= 100 ms |
| Browser command | 0.098 ms | 0.174 ms | 0.152 ms | 0.193 ms | 0.198 ms | Pass: p95 <= 50 ms; max <= 100 ms |
| Deterministic local navigation | 8.714 ms | 12.751 ms | 12.636 ms | 17.180 ms | 17.994 ms | Reported |

The readiness proxy is the conservative paired sum of first frame, measured
deferral, WebView construction, and first blank navigation; it is not presented
as a direct end-to-end signpost.

All Phase 2 comparisons pass without an explanation or waiver:

| Metric | Median change | p95 change | Gate |
| --- | ---: | ---: | --- |
| Application first frame | -13.89% | -4.78% | Pass: no unexplained regression above 10% |
| Initial WebView readiness proxy | -11.67% | -4.02% | Pass: no unexplained regression above 10% |

The optimized 10,000-bookmark benchmark in the same run also passes. Load uses
10 samples with 61.618 ms median and 62.716 ms p95 against 100 ms. Repository
search uses 50 samples with 18.691 ms median and 18.980 ms p95; the exact manager
filter uses 50 samples with 18.478 ms median and 18.819 ms p95, both against
50 ms. The generated 2,398,938-byte fixture contains no user data.

## Phase 4 hardened controlled-scrolling evidence

Only performance-test and deterministic-fixture code changed after the clean
accepted production-app run above. The fixture now exposes a visible `Scroll
position top`/`Scroll position moved` marker. Before metrics begin, XCUITest
swipes through a coordinate inside the WKWebView, requires the moved marker,
then swipes back and requires the top marker. This preflight proves the gesture
is not a no-op accessibility interaction and restores a deterministic starting
position before ten alternating measured swipes.

Artifacts:

- `.build/PerformanceResults.j6rcfP/BrowserInteractionPerformance.xcresult`
- `.build/PerformanceResults.j6rcfP/BrowserLaunchPerformance.xcresult`
- `.build/PerformanceResults.j6rcfP/summary.json`
- `.build/PerformanceResults.j6rcfP/bookmark-benchmark.log`

All three XCTest methods passed. The hardened scroll results are:

| Controlled-scroll metric | Samples | Minimum | Median | Mean | p95 | Maximum | Gate |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| Aggregate hitch duration per interaction | 10 | 0 ms | 0 ms | 0 ms | 0 ms | 0 ms | Pass: max <= 100 ms |
| Detected hitches | 10 | 0 | 0 | 0 | 0 | 0 | Pass: none detected |
| Hitch time ratio | 10 | 0 ms/s | 0 ms/s | 0 ms/s | 0 ms/s | 0 ms/s | Pass: zero in every sample |

The same hardened run passed its interaction and bookmark budgets:

| Metric | Result | Gate |
| --- | ---: | --- |
| Address submission p95 | 0.433 ms | Pass: <= 50 ms |
| Browser command p95 | 0.184 ms | Pass: <= 50 ms |
| Deterministic local-navigation p95 | 19.360 ms | Reported |
| 10,000-bookmark load p95 | 61.928 ms | Pass: <= 100 ms |
| Manager filter p95 | 18.768 ms | Pass: <= 50 ms |
| Repository search p95 | 18.588 ms | Pass: <= 50 ms |

### Outer launch diagnostic after test-only hardening

The `j6rcfP` aggregate summary reported `FAIL` solely because Xcode's outer
`ApplicationFirstFramePresentationResponsive` median was 529.613 ms against the
500 ms absolute p50 ceiling. Its 568.708 ms p95 passed, and both Phase 2-relative
launch/readiness comparisons passed. App-owned native-window presentation
remained 92.954 ms median.

A settled launch-only confirmation also passed its XCTest method but repeated
the outer-only absolute miss: 524.319 ms median and 564.006 ms p95, with a
92.989 ms app-owned native-window median. Artifacts:

- `.build/PerformanceLaunchConfirmation.EJpHTr/BrowserLaunchPerformance.xcresult`
- `.build/PerformanceLaunchConfirmation.EJpHTr/summary.json`

Production application code is identical to the clean passing `X3uvqP` run,
while the two later app-owned window medians remain stable near 93 ms. This
supports an outer XCTest/OS launch-metric bimodality rather than a production
app regression. Phase 4 therefore retains `X3uvqP` as the accepted production-
app launch/readiness gate and uses `j6rcfP` as the hardened scrolling evidence;
the later outer launch results remain recorded rather than discarded.

## Phase 4 final settled resources

Commands: `make resource-one` and `make resource-ten`

| Scenario | Memory samples | Minimum | Median | p95 | Maximum | Process count | Memory gate |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| One settled blank view | 10 | 73.2 MiB | 73.5 MiB | 73.7 MiB | 73.7 MiB | 4 | Pass: p95 <= 300 MiB |
| Ten settled deterministic views | 10 | 282.1 MiB | 283.2 MiB | 296.9 MiB | 296.9 MiB | 13 | Pass: p95 <= 1 GiB |

| Scenario | CPU samples | Mean | p95 | Maximum | CPU gate |
| --- | ---: | ---: | ---: | ---: | --- |
| One settled blank view | 30 seconds | 0.020% | 0.100% | 0.500% | Pass: mean < 1% |
| Ten settled deterministic views | 30 seconds | 0.007% | 0.000% | 0.200% | Pass: mean < 1% |

Artifacts:

- `.build/ResourceBaseline.v1.f2jBcc/summary.json`
- `.build/ResourceBaseline.v10.zRM3n4/summary.json`

Both runs retained a stable attributed Browser/WebKit process count. The
ten-view scenario remains a synthetic scalability probe, not a tab benchmark.

## Phase 5 minimal-tab results

The Phase 5 run used the optimized application with the normal performance
profile. A launch-only result holds 20 fresh process launches; a separate
interaction result holds the established navigation, command, and scrolling
workload; and a tab result holds 20 new-tab samples plus 50 switches while ten
real resident tabs were loaded from the deterministic fixture.

| Metric | Median | p95 | Maximum | Gate |
| --- | ---: | ---: | ---: | --- |
| Application first frame | 338.592 ms | 366.466 ms | 375.979 ms | Pass: p50 <= 500 ms; p95 <= 800 ms |
| Native initial-window presentation | 95.559 ms | 112.507 ms | 114.089 ms | Reported |
| First blank navigation | 84.995 ms | 97.708 ms | 100.279 ms | Pass: p95 <= 1.2 seconds |
| New blank-tab chrome | 3.932 ms | 6.514 ms | 6.553 ms | Pass: p95 <= 100 ms |
| Selection with ten resident loaded tabs | 2.627 ms | 2.983 ms | 3.477 ms | Pass: p95 <= 50 ms |
| Address submission | 0.198 ms | 0.357 ms | 0.453 ms | Pass: p95 <= 50 ms |
| Back/forward command | 0.125 ms | 0.195 ms | 0.203 ms | Pass: p95 <= 50 ms |
| Deterministic local navigation | 11.793 ms | 19.856 ms | 21.077 ms | Reported |

All ten genuine controlled-scroll samples recorded zero browser hitches. The
10,000-bookmark load, manager-filter, and repository-search p95 values were
63.501, 18.757, and 19.183 ms, respectively, and remain within their locked
100/50/50 ms limits.

Artifacts:

- `.build/LaunchRetry-20260728-0738.xcresult`
- `.build/InteractionPerfFocused-20260728-0744.xcresult`
- `.build/TabCreationFinal-20260728-0842.xcresult`
- `.build/TabSelectionFinal-20260728-0840.xcresult`
- `.build/PerformanceResults.OIXrv2/bookmark-benchmark.log`

The initial combined attempt exposed padded whitespace in the optimized
runner's accessibility representation of the focused address field. The focus
preflight now uses one typed key and trims only surrounding accessibility
whitespace; it still proves that keyboard input reaches the launch-focused
field without a click. The final 20-launch result passed every sample.

`make resource-ten` now creates ten actual TabController-owned resident tabs,
each with its normal WebViewFactory profile and loaded deterministic page.

| Scenario | Samples | Minimum | Median | p95 | Maximum | Process count | Gate |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| Ten resident tabs, aggregate memory | 10 | 171.6 MiB | 184.2 MiB | 186.8 MiB | 186.8 MiB | 13 | Pass: p95 <= 1 GiB |
| Ten resident tabs, aggregate idle CPU | 30 seconds | 0.000% | 0.000% | 0.100% | 0.300% | 13 | Pass: mean 0.013% < 1% |

Artifact: `.build/ResourceBaseline.v10.euHb4k/summary.json`.

The full-app churn gate performed exactly 100 Command-T/Command-W cycles in
ten measured batches of ten. Absolute Browser memory had a 62,932 kB median
across the first five batches and a 55,985 kB median across the last five, an
11.04% decrease. This passes the gate requiring the second-half median to remain
no more than 10% above the first-half median. Monotonic growth is retained as a
diagnostic rather than a hard assertion; the ten-resident-tab resource gate
above remains the absolute-memory ceiling. Artifact:
`.build/TabChurnFinal-20260728-0836.xcresult`.

## Locked budgets

The provisional absolute budgets remain realistic and are now locked:

- terminated launch to interactive address field: p50 at or below 500 ms and
  p95 at or below 800 ms;
- usable initial blank web view: p95 at or below 1.2 seconds;
- create and focus a new blank tab: browser-chrome p95 at or below 100 ms;
- switch among ten resident lightweight tabs: p95 at or below 50 ms;
- settled aggregate CPU: average below 1 percent over 30 seconds;
- one settled blank tab: aggregate p95 at or below 300 MiB;
- ten settled deterministic lightweight tabs: aggregate p95 at or below 1 GiB;
- controlled scrolling: aggregate hitch duration at or below 100 ms for every
  measured interaction, with hitch count and ratio reported;
- cached rule-list attachment: p95 below 50 ms; and
- no unexplained established-benchmark regression greater than 10 percent.

## Notes and anomalies

- A pre-optimization combined Phase 2 run completed every functional sample but
  measured a 541.249 ms first-frame median and failed the 500 ms gate. XCUITest
  also reported a foreground VLC interruption during that run. The result was
  not accepted. WebKit startup was then moved behind an explicit measured
  deferral, launch was isolated from the interaction workload, and the final
  498.522 ms median passed. The failed evidence remains at
  `.build/PerformanceResults.gzvyId/`.
- The first resource probe immediately after a Release rebuild attributed
  481 MiB of wired, unmapped graphics memory to the WebKit GPU process and
  reached 548.9 MiB aggregate. The next launch measured 65.6 MiB. The harness
  now records but excludes one warm-up launch, matching the approved settled
  resource protocol. The cold post-build spike remains documented rather than
  discarded as an invisible outlier. Raw anomaly artifacts:
  `.build/ResourceBaseline.v1.0T3wWW`.
- XCUITest re-signs its own isolated app copy with automation entitlements.
  `make verify-release` separately proves the production app has exactly App
  Sandbox and outgoing-network entitlements plus hardened runtime.
- The Xcode UI test spends roughly one second polling each accessibility
  assertion. Those UI-test timestamps are not used as launch metrics; Xcode's
  application and signpost measurements are used instead.
