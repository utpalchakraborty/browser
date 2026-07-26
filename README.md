# Browser

Browser is a small, native macOS browser for personal use. It uses AppKit and
WKWebView, targets Apple silicon and macOS 26 or later, stores no
application-owned browsing history, and includes no telemetry or third-party
runtime dependencies. Startup, CPU, and memory budgets are release gates.

Phase 1 WebKit validation is complete with an unconditional GO decision. This
is not yet a daily-driver browser: the checkpoint application opens a
disposable native window and blank WKWebView. Phase 2 will build the fast
single-page browser shell after checkpoint review.

## Requirements

- Apple silicon Mac running macOS 26 or later
- Xcode 26.6 or a compatible newer release
- Xcode command-line tools selected with `xcode-select`

## Build and verify

~~~sh
make build
make test
make verify-release
~~~

Specialized Phase 1 checks are exposed as Make targets. Some launch apps or
take several minutes; `make network-audit` also requests administrator
authorization for an attributed macOS packet capture.

~~~sh
make profile-probe
make blocker-benchmark
make performance
make resource-one
make resource-ten
make webcontent-termination
make network-audit
~~~

Start with [project status](docs/status.md), then see the approved
[architecture](docs/architecture.md), the phased
[implementation plan](docs/implementation-plan.md), the locked
[performance baseline](docs/performance-baseline.md), and the
[Phase 1 risk report](docs/phase-1-risk-report.md).

This repository is currently intended only for the owner's personal use. No
license or distribution grant is asserted.
