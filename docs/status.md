# Project Status

Last updated: 2026-07-26

## Current phase

Phase 1 — complete. Phase 2 has not started and awaits checkpoint review.

Every Phase 1 functional, privacy, Release, and performance gate passes. The
recorded decision is an unconditional GO for WKWebView on this macOS-only
architecture.

## Completed

- Approved macOS-only architecture, personal-use scope, no history, and no
  telemetry contracts.
- Native Swift 6 AppKit application with a window-first, deferred-WKWebView
  lifecycle.
- arm64 local Release build with App Sandbox, hardened runtime, outgoing
  network only, no debugger entitlement, and no coverage instrumentation.
- Deterministic localhost fixture and repeatable functional, performance,
  resource, profile, blocker, and lifecycle scripts.
- Explicit named persistent profile isolated from hosted tests and performance
  measurements.
- Cookie enumeration plus individual, domain, and cookie-only global deletion.
- Local storage, IndexedDB, Fetch Cache, and service-worker enumeration and
  deletion.
- Real-app persistence probe across three graceful Browser launches, including
  persistent cookie/localStorage survival, ephemeral isolation, and deletion
  after a later relaunch.
- Compiled content-rule caching, blocking, live exception on/off reload,
  removal, invalid-rule, and cached-attachment validation.
- Target-blank, `window.open`, download, HTTP Basic authentication,
  redirect-loop, and web-content-process termination probes.
- Twenty-launch Release benchmark and locked CPU and memory baselines for one
  and ten resident views.
- Privileged production pktap audit with a positive 8-packet attribution
  control and zero Browser-attributed packets during blank launch plus 31
  seconds idle.
- AdGuard Base and Tracking Protection source, converter, license, and manual
  update policy selected for later production-list work.

Detailed results:

- [performance-baseline.md](performance-baseline.md)
- [phase-1-risk-report.md](phase-1-risk-report.md)

## Verification summary

- Functional suite: 20 tests, 0 failures.
- Launch suite: 20 terminated launches, 0 failures; first-frame p95
  392.193 ms.
- One blank view: aggregate footprint p95 65.6 MiB; idle CPU mean 0.020%.
- Ten deterministic views: aggregate footprint p95 280.5 MiB; idle CPU mean
  0.020%.
- Cached blocker attachment: p95 0.000125 ms.
- Production content-process termination: Browser survived; no replacement
  WebContent process appeared during the five-second observation.
- Production Release verification: passed after the final source review;
  arm64, hardened runtime, exactly two sandbox/network entitlements, no coverage
  symbols, and no DEBUG profile-probe markers.
- Production blank-network audit: passed; 8 control packets, 0 outbound packets
  over 31 seconds, and 0 kernel drops. Artifacts:
  `.build/NetworkAudit.aG4SkM`.

The production tab open/close lifecycle does not exist yet, so the
creation/destruction leak and 100-cycle churn gate is explicitly owned by Phase
3 rather than measured against disposable Phase 1 scaffolding.

## Next action

Review this checkpoint and the risk report. Begin Phase 2 only after explicit
approval; its first deliverable is the fast single-page browser shell.
