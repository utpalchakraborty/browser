# Project Status

Last updated: 2026-07-26

## Current phase

Phase 2 — complete. Phase 3 has not started and awaits checkpoint review.

The checkpoint is a usable native single-page browser. It accepts HTTP and
HTTPS URLs, infers HTTPS for plausible hosts, searches plain text, and exposes
WebKit navigation state through responsive AppKit controls. The Phase 1
WKWebView GO decision remains unchanged.

## Phase 2 delivered

- Native toolbar with a launch-focused address field, Back, Forward,
  Reload/Stop, progress, page title, and displayed final URL.
- HTTPS-first address interpretation plus DuckDuckGo, Google, and Bing search
  selection. Only the selected provider is application-owned persistent state.
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

## Known Phase 2 limitations

There is one page and one window. Tabs, bookmarks, privacy-management UI,
downloads, production filter lists, and private windows remain later phases.
Programmatic popups are suppressed; a user-activated new-window link replaces
the current page until Phase 3 adds tabs.

DNS and TLS presentations have deterministic unit coverage; the end-to-end UI
retry scenario uses a refused localhost connection. Representative real-site
compatibility remains part of the hands-on checkpoint rather than a stable
automated gate.

## Next action

Use the single-page browser with representative sites and review the
checkpoint. Begin Phase 3 only after explicit approval.
