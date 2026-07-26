# Performance Baseline

Status: Phase 1 baseline locked
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
| Measured source state | `b493f16` plus the Phase 1 worktree; checkpoint revision pending the final network audit |

The measurements were collected from the Phase 1 checkpoint on a normally
loaded desktop. Raw results stay in ignored `.build` directories and are never
uploaded.

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

## Launch and initial WebKit results

Command: `make performance`

Result bundle: `.build/PerformanceResults.vXonZF/BrowserPerformance.xcresult`

Twenty terminated launches completed with zero failures.

| Metric | Minimum | Median | Mean | p95 | Maximum |
| --- | ---: | ---: | ---: | ---: | ---: |
| Application first frame responsive | 304.365 ms | 337.972 ms | 343.902 ms | 392.193 ms | 399.097 ms |
| Native window presentation signpost | 45.524 ms | 78.492 ms | 78.341 ms | 104.297 ms | 114.779 ms |
| Initial WKWebView construction | 18.263 ms | 24.008 ms | 24.998 ms | 33.113 ms | 43.385 ms |
| First `about:blank` navigation | 73.769 ms | 87.694 ms | 86.875 ms | 102.779 ms | 120.644 ms |

The scaffold has no address field yet, so first-frame responsiveness is the
Phase 1 proxy for interactive native chrome. The real address-field gate stays
unchanged for Phase 2. A conservative paired-sample proxy formed from first
frame plus WebKit construction plus blank navigation measured 448.682 ms
median, 504.267 ms p95, and 510.462 ms maximum. It is explicitly a component
sum, not a direct end-to-end signpost.

## Settled resource results

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

## Content-rule result

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
  p95 at or below 800 ms, first enforceable when Phase 2 adds the field;
- usable initial blank web view: p95 at or below 1.2 seconds;
- settled aggregate CPU: average below 1 percent over 30 seconds;
- one settled blank tab: aggregate p95 at or below 300 MiB;
- ten settled deterministic lightweight tabs: aggregate p95 at or below 1 GiB;
- cached rule-list attachment: p95 below 50 ms; and
- no unexplained established-benchmark regression greater than 10 percent.

## Notes and anomalies

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
