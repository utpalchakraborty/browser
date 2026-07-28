# Phase 1 WebKit Risk Report

Status: GO — Phase 1 complete
Last updated: 2026-07-27

## Decision

WKWebView is an unconditional **go** for the native macOS browser architecture.
The final production blank-launch audit reported zero Browser-attributed
outbound packets over 31 seconds after an 8-packet positive attribution
control.

Public WebKit APIs meet the required profile, cookie, site-data, content-rule,
popup, download, authentication, and failure-observation needs. The measured
native launch and WebKit process footprint leave substantial room inside every
Phase-1-applicable performance gate. No alternate engine integration is
justified.

## Evidence

| Risk | Result | Evidence |
| --- | --- | --- |
| Local production build is insufficiently constrained | Pass | arm64-only, ad-hoc signed for local use, hardened runtime, App Sandbox, outgoing network client entitlement, no debugger entitlement, and no extra entitlements |
| WebKit profile is accidentally shared with another browser | Pass | one explicit stable named `WKWebsiteDataStore`; normal, hosted-test, performance, and persistence-probe identifiers are separated |
| Persistent data fails across real app relaunch | Pass | a DEBUG-only, localhost-restricted probe used three distinct, normally terminated Browser processes and proved Max-Age cookie and localStorage persistence, nonpersistent-store isolation, clear-all deletion, and deletion after another relaunch; `.build/ActualAppProfileProbe.SbYv5p` |
| Cookies cannot be managed precisely | Pass | persistent/session metadata and values enumerated; individual, host-domain, and global deletion verified; domain-boundary matching tested |
| Broader site data cannot be explained or cleared | Pass | local storage, IndexedDB, Fetch Cache, and service-worker registrations enumerated and deleted by record and globally |
| Declarative blocking cannot support a site exception | Pass | replacing the attached list and explicitly reloading the resident fixture toggled an ordered `ignore-previous-rules` exception on and off; Phase 4 keeps ordinary pending policy strengthen-only, applies the explicit current-site choice before reload so document matches remain recoverable, and covers stale/overlap, post-commit/unbound, and fragment action-only ordering regressions |
| Cached blocker mechanics are too expensive | Pass | Phase 1 isolated cached lookup p95 0.107666 ms and synchronous attachment p95 0.000125 ms; the Phase 4 two-production-list benchmark passes at 0.228416 ms and 0.000209 ms, respectively |
| Common WebKit delegate paths are missing | Pass with later UI work | target-blank and `window.open` supply a reusable configuration with the same store; HTTP Basic challenges can be answered; unsupported content becomes `WKDownload`; redirect loops report `NSURLErrorHTTPTooManyRedirects` |
| Web-content failure kills the browser | Pass with recovery gap | a temporally attributed exact WebContent helper received SIGTERM; Browser remained alive and no replacement appeared during the five-second observation, so a visible reload action is required in daily-driver hardening; `.build/WebContentTermination.isWVJb` |
| WebKit fixed cost makes the browser slow or bloated | Pass | first-frame p95 392.193 ms; one-view aggregate p95 65.6 MiB; ten-view p95 280.5 MiB; idle aggregate CPU averaged 0.020% |
| Blank launch performs application-owned networking | Pass | production pktap audit captured 8 intentional localhost control packets, then 0 Browser/effective-Browser outbound packets over 31 seconds idle with 0 kernel drops; `.build/NetworkAudit.aG4SkM` |

All web-content tests use the deterministic localhost fixture. Raw results are
local under ignored `.build` paths.

## Content-blocking source policy

The production inputs are AdGuard's optimized Safari exports for the Base and
Tracking Protection filters from pinned
[FiltersRegistry](https://github.com/AdguardTeam/FiltersRegistry) commit
`1429043fe73b7a16577966ff04afa7e5ba630925`. The underlying filters are
maintained in the
[official AdGuard filters repository](https://github.com/AdguardTeam/AdguardFilters)
under GPL-3.0. This project is personal-use only; any future distribution
decision must re-audit source, generated-data, attribution, and corresponding-
source obligations before shipping the rules.

Conversion used pinned release 4.3.0 of the GPL-3.0
[AdGuard Safari Converter](https://github.com/AdguardTeam/SafariConverterLib)
as a developer-only command-line tool. It is not linked into or shipped with
Browser. The Phase 4 checkpoint:

1. pins the source and converter commits and hashes;
2. records licenses, attribution, conversion arguments, and generated rule
   counts;
3. commits only deterministic generated WKContentRuleList JSON needed at
   runtime;
4. tests the generated lists against the deterministic localhost suite;
5. measures cold compilation and cached lookup/attachment; and
6. keeps updates manual and release-bound.

On 2026-07-27, the user confirmed that a Release launched with `make run` showed
no ads on an ad-heavy site, then reported that the blocker and popup checkpoint
works in hands-on use and approved it. The current manifest records generated output counts but does
not claim a discarded-rule count or unsupported-syntax category report; that
provenance gap must be closed before treating regeneration from canonical filter
sources as a distribution-ready pipeline.

There is no launch-time, scheduled, or silent filter update. A future updater
would require a separate privacy, integrity, rollback, and performance review.

## Phase 1 limitations and later ownership

- Phase 1 has disposable native chrome, not the Phase 2 address field or
  navigation controls. The address-field focus launch gate becomes directly
  enforceable in Phase 2.
- Popup creation works at the API boundary. Phase 2 suppressed scripted popup
  requests and routed a direct pointer-activated target-blank HTTP/HTTPS anchor
  into the current page. Phase 4 made denial of scripted `window.open`,
  target-blank forms, separate windows/WKWebViews, background contexts, and
  tab-unders an explicit regression gate independent of content blocking. Phase
  5 now routes an unmodified direct anchor to a foreground tab and an exact
  physical Command-click on an HTTP/HTTPS anchor to a background tab while
  retaining the scripted-popup denial boundary.
- Download and HTTP-authentication primitives work, but visible destination and
  credential UI remain daily-driver hardening.
- The content-process probe uses temporal before/after attribution and SIGTERM,
  not SIGKILL. No replacement appeared within five seconds; this does not claim
  that WebKit can never create one later. The tab must present a recoverable
  error and reload action.
- The production filter lists were not bundled in Phase 1. Phase 4 now bundles
  and verifies them, records licensing artifacts, measures roughly 4 to 7
  seconds for isolated cold compilation, and keeps cached lookup well below the
  50 ms budget. Real-site false-positive behavior remains a hands-on regression
  check when the pinned production package changes.
- The 548.9 MiB cold post-build GPU anomaly is retained in the baseline. The
  settled warm baseline is stable, but future GPU/WebKit or macOS updates must
  rerun it.
- WebKit and macOS may perform behavior outside application-owned code. The
  packet audit distinguishes Browser/effective-Browser traffic through pktap
  attribution instead of claiming the operating system is globally silent.
- A zero-match macOS pktap capture may leave a zero-byte pcapng. The audit's
  decoder accepts that case only after tcpdump stayed alive for the full
  interval, exited successfully, reported exactly zero captured/kernel-dropped
  packets, and reported equal received and metadata-filter-drop counts. Other
  malformed or inconsistent captures fail closed.
- Repeated view teardown and leak inspection moved to Phase 5's real
  TabController and 100-cycle churn gate. Phase 1's one- and ten-view results
  cover fixed/resident cost; an artificial disposable teardown path would not
  validate the production observer and delegate ownership graph.

## Commands

~~~sh
make test
make profile-probe
make blocker-benchmark
make performance
make resource-one
make resource-ten
make webcontent-termination
make network-audit
make verify-release
~~~

Phase 1 remains complete and approved. See [status.md](status.md) for the
current phase and outstanding acceptance work.
