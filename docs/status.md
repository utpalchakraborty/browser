# Project Status

Last updated: 2026-07-26

## Current phase

Phase 2 — complete and checkpoint approved. A narrow Phase 2 quality-of-life
follow-up for window geometry is implemented with functional verification
passed; hands-on review and a clean performance rerun remain pending. Phase 3
bookmarks and owned persistence have not started; tabs now follow in Phase 4.

The checkpoint is a usable native single-page browser. It accepts HTTP and
HTTPS URLs, infers HTTPS for plausible hosts, searches plain text, and exposes
WebKit navigation state through responsive AppKit controls. The Phase 1
WKWebView GO decision remains unchanged.

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

## Implemented Phase 2 QoL follow-up

The implementation remembers only the main browser window's last usable size
and location through AppKit's native frame autosave. AppKit applies the saved
frame for the current display environment, while the browser keeps its centered
default when there is no usable saved frame. AppKit state restoration stays
disabled, and relaunch must remain blank with the address field focused; no URL,
page, back/forward, or future tab state may be restored.

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

## Known Phase 2 limitations

There is one page and one window. Bookmarks remain Phase 3 work; tabs,
privacy-management UI, downloads, production filter lists, and private windows
remain later phases.
Programmatic popups are suppressed; a user-activated new-window link replaces
the current page until Phase 4 adds tabs.

DNS and TLS presentations have deterministic unit coverage; the end-to-end UI
retry scenario uses a refused localhost connection. Representative real-site
compatibility remains part of the hands-on checkpoint rather than a stable
automated gate.

## Next action

Move and resize the browser, quit, and relaunch to verify the production window
returns to the expected frame while the page remains blank. Rerun
`make performance` on an idle desktop to clear the first-frame absolute gate.
Review that narrow checkpoint, then begin Phase 3 bookmarks. Tabs wait for
Phase 4.
