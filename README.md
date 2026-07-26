# Browser

Browser is a small, native macOS browser for personal use. It uses AppKit and
WKWebView, targets Apple silicon and macOS 26 or later, stores no
application-owned browsing history, and includes no telemetry or third-party
runtime dependencies. Startup, CPU, and memory budgets are release gates.

Phase 2 delivers the single-page browser checkpoint: a native toolbar,
launch-focused address field, HTTP/HTTPS navigation, HTTPS-first host
interpretation, configurable search, Back/Forward, Reload/Stop, progress,
titles, and visible retryable errors.

This is a usable one-page pilot, not yet the daily-driver release. Tabs,
bookmarks, privacy-management UI, downloads, and production content blocking
remain later phases.

## Requirements

- Apple silicon Mac running macOS 26 or later
- Xcode 26.6 or a compatible newer release
- Xcode command-line tools selected with `xcode-select`

## Build and verify

~~~sh
make check
make performance
make resource-one
~~~

`make check` runs Debug and Release functional suites and verifies the
production Release signature, architecture, entitlements, and hardened runtime.
Some specialized checks launch apps or take several minutes;
`make network-audit` also requests administrator authorization for an
attributed macOS packet capture.

~~~sh
make profile-probe
make blocker-benchmark
make performance
make resource-one
make resource-ten
make webcontent-termination
make network-audit
~~~

`make resource-ten` remains a synthetic ten-resident-view scalability probe;
it is not a tab benchmark. Tabs begin in Phase 3.

## Use

~~~sh
make run
~~~

This builds the Release configuration and opens
`.build/DerivedData/Build/Products/Release/Browser.app`. Enter an explicit HTTP
or HTTPS URL, a plausible hostname such as `example.com`, or search text in the
address field and press Return.

- Command-L focuses the address field.
- Command-[ and Command-] navigate Back and Forward.
- Command-R reloads.
- Command-period stops an active load.
- Navigate > Search Provider selects DuckDuckGo, Google, or Bing.

Start with [project status](docs/status.md), then see the approved
[architecture](docs/architecture.md), the phased
[implementation plan](docs/implementation-plan.md), the locked
[performance baseline](docs/performance-baseline.md), and the
[Phase 1 risk report](docs/phase-1-risk-report.md).

This repository is currently intended only for the owner's personal use. No
license or distribution grant is asserted.
