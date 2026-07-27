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
to launch with a blank page. The completed first Phase 4 checkpoint enables
pinned, bundled AdGuard Base and Tracking Protection rules by default, adds an
exact-host compatibility exception, and locks popup suppression down
independently of filter coverage. Website-data privacy controls remain the next
Phase 4 slice. Tabs follow in Phase 5; downloads remain later hardening work.

The Phase 3 live bookmark smoke test passed, and its keyboard-first workflow is
approved; the manual recovery exercise is still pending. Post-fix Debug and
Release unit and UI suites, production-list compilation, the blocker benchmark,
and Release bundle verification are green. Ordinary pending navigation may
only strengthen protection; an exact-host relaxation is applied only after the
winning document commits, and stale callbacks cannot weaken a newer page. The
explicit current-site switch applies its selected policy before reloading so it
can also recover a page matched by a document-level rule. On 2026-07-27, the
user reported that the Phase 4 blocker and popup checkpoint works in hands-on
use and approved it.

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
make network-audit
~~~

`make resource-ten` remains a synthetic ten-resident-view scalability probe;
it is not a tab benchmark. Tabs begin in Phase 5.

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
