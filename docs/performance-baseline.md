# Performance Baseline

Status: Phase 1 historical baseline retained; Phase 2 baseline locked; Phase 3 interaction and bookmark gates pass; launch rerun pending
Last updated: 2026-07-26

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

The full `make performance` run completed all samples. The interaction gates
passed: address submission p95 was 0.758 ms, browser-command p95 was 0.187 ms,
and local-navigation p95 was 24.206 ms. Application first-frame p95 was
624.031 ms against the 800 ms ceiling, but its 573.542 ms median missed the
500 ms ceiling. Relative to Phase 2, first-frame median/p95 changed by
+15.05%/+10.37%, and the readiness proxy changed by +10.03%/+7.17%; each
comparison whose median exceeded the 10% budget failed. A clean idle-desktop
launch rerun is therefore pending. A confirmation attempt was stopped after
XCTest identified a foreground Ghostty window as an interrupting element, so
it is not treated as evidence. Artifacts:
`.build/PerformanceResults.QvWEvu/`.

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
production-list conversion and compilation remain Phase 5 work and never enter
normal launch.

## Locked budgets

The provisional absolute budgets remain realistic and are now locked:

- terminated launch to interactive address field: p50 at or below 500 ms and
  p95 at or below 800 ms;
- usable initial blank web view: p95 at or below 1.2 seconds;
- settled aggregate CPU: average below 1 percent over 30 seconds;
- one settled blank tab: aggregate p95 at or below 300 MiB;
- ten settled deterministic lightweight tabs: aggregate p95 at or below 1 GiB;
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
