# Browser

Browser is a small, native macOS browser for personal use. It uses AppKit and
WKWebView, targets Apple silicon and macOS 26 or later, stores no
application-owned browsing history, sends no application-owned telemetry, and
includes no third-party runtime dependencies. Startup, CPU, and memory budgets
are release gates.

Phase 3 adds explicit, local bookmarks to the single-page browser: use the
toolbar star or Command-D to add or edit the current page, and use the
searchable Bookmarks manager to add, edit, delete, or open saved pages. Opening
a bookmark replaces the current page until tabs arrive in Phase 5.

This is now a usable one-page pilot, not yet the daily-driver release. It also
remembers the main window's size and location across relaunch while continuing
to launch with a blank page. Phase 4 is complete: pinned,
bundled AdGuard Base and Tracking Protection rules are enabled by default,
popup suppression is independent of filter coverage, and a native privacy
window exposes website-data deletion plus blocker reset controls. Functional,
Release-package, profile, blocker, container, performance, resource, and fresh
blank-network gates are green. Phase 5 is next and has not begun; downloads
remain later hardening work.

The Phase 3 live bookmark smoke test passed, and its keyboard-first workflow is
approved; the manual recovery exercise is still pending. Final Debug and
Release verification each passes 135 unit tests and 12 UI tests. Production-
list compilation, the blocker benchmark, Release bundle verification, the
cross-process profile probe, controlled scrolling, one/ten-view resources, and
the read-only container audit are also green. Ordinary pending navigation may
only strengthen protection; an exact-host relaxation is applied only after the
winning document commits, and stale callbacks cannot weaken a newer page. On
2026-07-27, the user reported that the blocker and popup checkpoint works in
hands-on use and approved it.

The final privileged audit attributed 8 positive-control outbound packets to
Browser/WebKit, then observed 0 outbound packets during a 31-second blank
launch/idle interval. Artifact: `.build/NetworkAudit.HxyZ8u/result.txt`.

The controlled-scroll harness now proves that a real swipe changes a visible
top/moved marker and restores the fixture to the top before measuring. Ten
genuine samples reported zero hitch duration, count, and ratio in
`.build/PerformanceResults.j6rcfP`. Only test/fixture code changed after the
clean production-app acceptance run `.build/PerformanceResults.X3uvqP`, so that
run remains the Phase 4 release gate. Later outer XCTest launch medians were
bimodal and are documented transparently in the performance baseline; app-owned
window presentation remained about 93 ms.

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
production Release signature, architecture, entitlements, hardened runtime,
and independently pinned blocker manifest, generated rules, notices, and
license. Some specialized checks launch apps or take several minutes;
`make network-audit` also requests administrator authorization for an
attributed macOS packet capture.

~~~sh
make profile-probe
make blocker-benchmark
make performance
make resource-one
make resource-ten
make webcontent-termination
make container-audit
make network-audit
~~~

`make resource-ten` remains a synthetic ten-resident-view scalability probe;
it is not a tab benchmark. `make container-audit` is a read-only inspection of
the Browser sandbox. `make network-audit` must be run from a normal interactive
Terminal because it requests administrator authorization only for the scoped
packet capture. Phase 5 is next and has not begun.

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
- Command-D adds the current page as a bookmark, or edits it if already saved.
- Option-Command-B opens the searchable Bookmarks manager.
- Option-Command-Y opens the Website Data privacy window.
- Privacy shows whether ad and tracker blocking is active for the current site.
- Option-Command-P disables or enables blocking for the current exact host and
  reloads the page. The choice persists across relaunch and does not apply to
  subdomains or alternate hostnames.
- Navigate > Search Provider selects DuckDuckGo, Google, or Bing.

On a first install or after the bundled rules change, Browser compiles the
rules locally before permitting remote navigation. The native window remains
interactive and the latest submitted URL is queued; current measurements put
this one-time work at roughly 4 to 7 seconds. Cached launches reuse the compiled
rules. Browser never downloads or silently updates a filter list.

Blocking materially reduces common advertising and tracking requests; it does
not promise anonymity or eliminate first-party analytics, fingerprinting, CNAME
cloaking, or trackers introduced after the pinned lists were generated.

Bookmarks intentionally use a flat searchable manager rather than a persistent
bookmarks bar. Folder hierarchy is deferred until ordinary use demonstrates a
real need for it.

Browser does not permit a page to create a secondary app window, another
WKWebView, a background tab, or a tab-under. Scripted `window.open` requests and
forms targeting a new context are denied. Only a direct pointer click on an
HTTP or HTTPS anchor targeting a new context is routed; it replaces the current
page for now. Synthetic and keyboard target-blank activation is denied because
public WebKit API does not prove a direct pointer gesture. Phase 5 will route
the allowed pointer action to a foreground tab. Content blocking prevents
many advertising popup triggers and overlays before they run, but this popup
denial remains an independent backstop rather than relying on a filter-list
match.

## Website data and blocking resets

Privacy > Manage Website Data shows cookies separately from WebKit's broader
website-data records. Cookie rows use exact cookie-domain scopes; WebKit record
names may group data using public-suffix rules and are not presented as exact
cookie-domain identities. Cookie metadata is visible, values are masked by
default, and revealing a selected value is an explicit local action. Values are
not searched, logged, or copied automatically, and the revealed value is
scrubbed when the selection or mode changes or the window closes.

Cookie actions can delete one cookie, every cookie for the displayed exact
domain, or all cookies while leaving other website data intact. Full-data
actions can delete the selected WebKit record or every WebKit-exposed category,
including cookies, caches, local storage, databases, and service workers. Each
destructive action is confirmed and refreshed against WebKit; an open page may
recreate data and the window reports that instead of claiming success.

The same window can reset every exact-host blocking exception or delete locally
compiled blocking rules. Deleting compiled artifacts does not remove the pinned
rules from the signed app. Current pages remain protected by their in-memory
rules, and Browser rebuilds the local artifacts on the next launch before it
permits remote navigation.

## Bookmark data

Bookmarks are versioned JSON stored locally in the app's sandbox at:

~~~text
~/Library/Containers/com.utpalchakraborty.browser/Data/Library/Application Support/com.utpalchakraborty.browser/
~~~

`Bookmarks.json` is the primary file and `Bookmarks.backup.json` is the last
valid backup. Quit Browser before copying both files to export or back them up.
To reset the active library, quit Browser and remove those two files;
alternatively, use Restore Backup or Reset Bookmarks if Browser presents a
recovery state. A malformed primary is preserved as
`Bookmarks.corrupt.<identifier>.json` rather than silently overwritten, and the
in-app recovery reset deliberately keeps those preserved copies. For complete
bookmark erasure, quit Browser and also delete every preserved
`Bookmarks.corrupt.*.json` file from this directory.

Bookmarks are the only application-owned URLs written by this feature. Browser
still creates no visit history and sends no application-owned telemetry.

Start with [project status](docs/status.md), then see the approved
[architecture](docs/architecture.md), the phased
[implementation plan](docs/implementation-plan.md), the locked
[performance baseline](docs/performance-baseline.md), and the
[Phase 1 risk report](docs/phase-1-risk-report.md).

This repository is currently intended only for the owner's personal use. No
license or distribution grant is asserted for the project's own code. Bundled
third-party blocker data and tools retain the GPL-3.0 terms and attribution
recorded in the included notices and license files.
