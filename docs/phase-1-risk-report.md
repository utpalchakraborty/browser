# Phase 1 WebKit Risk Report

Status: GO — Phase 1 complete
Last updated: 2026-07-26

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
| Declarative blocking cannot support a site exception | Pass | replacing the attached list and explicitly reloading the resident fixture toggled an ordered `ignore-previous-rules` exception on and off; removing blocking restored the script |
| Cached blocker mechanics are too expensive | Pass | isolated cached lookup p95 0.107666 ms and synchronous attachment p95 0.000125 ms; integrated production-list launch overhead remains Phase 5 work |
| Common WebKit delegate paths are missing | Pass with later UI work | target-blank and `window.open` supply a reusable configuration with the same store; HTTP Basic challenges can be answered; unsupported content becomes `WKDownload`; redirect loops report `NSURLErrorHTTPTooManyRedirects` |
| Web-content failure kills the browser | Pass with recovery gap | a temporally attributed exact WebContent helper received SIGTERM; Browser remained alive and no replacement appeared during the five-second observation, so a visible reload action is required in daily-driver hardening; `.build/WebContentTermination.isWVJb` |
| WebKit fixed cost makes the browser slow or bloated | Pass | first-frame p95 392.193 ms; one-view aggregate p95 65.6 MiB; ten-view p95 280.5 MiB; idle aggregate CPU averaged 0.020% |
| Blank launch performs application-owned networking | Pass | production pktap audit captured 8 intentional localhost control packets, then 0 Browser/effective-Browser outbound packets over 31 seconds idle with 0 kernel drops; `.build/NetworkAudit.aG4SkM` |

All web-content tests use the deterministic localhost fixture. Raw results are
local under ignored `.build` paths.

## Content-blocking source policy

The first production ruleset will use the AdGuard Base Filter and AdGuard
Tracking Protection Filter from the
[official AdGuard filters repository](https://github.com/AdguardTeam/AdguardFilters).
The repository is GPL-3.0 licensed. This project is personal-use only; any
future distribution decision must re-audit source, generated-data, attribution,
and corresponding-source obligations before shipping the rules.

Conversion will use a pinned release of the GPL-3.0
[AdGuard Safari Converter](https://github.com/AdguardTeam/SafariConverterLib)
as a developer-only command-line tool. It will not be linked into or shipped
with Browser. Phase 5 will:

1. pin the source commit and converter release;
2. record hashes, licenses, attribution, conversion arguments, accepted and
   discarded rule counts, and unsupported-rule categories;
3. commit only deterministic generated WKContentRuleList JSON needed at
   runtime;
4. test the generated list against the localhost suite and agreed real-site
   compatibility smoke set;
5. measure cold compilation and cached lookup/attachment; and
6. keep updates manual and release-bound.

There is no launch-time, scheduled, or silent filter update. A future updater
would require a separate privacy, integrity, rollback, and performance review.

## Known limitations and later ownership

- Phase 1 has disposable native chrome, not the Phase 2 address field or
  navigation controls. The address-field focus launch gate becomes directly
  enforceable in Phase 2.
- Popup creation works at the API boundary, but user-activation policy and tab
  routing belong in Phases 2 and 3.
- Download and HTTP-authentication primitives work, but visible destination and
  credential UI remain daily-driver hardening.
- The content-process probe uses temporal before/after attribution and SIGTERM,
  not SIGKILL. No replacement appeared within five seconds; this does not claim
  that WebKit can never create one later. The tab must present a recoverable
  error and reload action.
- The production filter list is not bundled in Phase 1. Only mechanism and
  cached-attachment cost are proven; large-list conversion, false positives,
  compile time, and licensing artifacts are Phase 5 acceptance work.
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
- Repeated view teardown and leak inspection are intentionally moved to Phase
  4's real TabController and 100-cycle churn gate. Phase 1's one- and ten-view
  results cover fixed/resident cost; an artificial disposable teardown path
  would not validate the production observer and delegate ownership graph.

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

Phase 1 is complete. Phase 2 may begin after the user reviews and explicitly
approves this checkpoint.
