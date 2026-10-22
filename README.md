# Browser

Browser is a small, native macOS browser for personal use. It uses AppKit and
WKWebView, targets Apple silicon and macOS 26 or later, stores no
application-owned browsing history, sends no application-owned telemetry, and
includes no third-party runtime dependencies. Startup, CPU, and memory budgets
are release gates.

Use the toolbar star or Command-D to add or edit the selected tab's web or local
HTML page. The left bookmarks sidebar shows one saved page per row; a single
click opens it in a new foreground tab. The toolbar sidebar button or View menu
hides/shows the sidebar and remembers your choice. Manage Bookmarks opens the
searchable editor; opening a bookmark from that manager navigates the selected tab.

This is now a usable native multi-tab pilot, not yet the daily-driver release.
It remembers the main window's size and location across relaunch while still
starting with one fresh blank tab and no restored browsing session. Phase 4 is
complete and accepted: pinned, bundled AdGuard Base and Tracking Protection
rules are enabled by default, popup suppression is independent of filter
coverage, and a native privacy window exposes website-data deletion plus
blocker reset controls. Its functional, Release-package, profile, blocker,
container, performance, resource, and fresh blank-network gates are green.

The minimal Phase 5 tab implementation is complete and accepted. It provides a
visible tab strip, new/select/close, Command-click
background tabs, direct target-blank foreground tabs, and independent per-tab
navigation and blocking state. Reordering, groups, pinned tabs, favicons,
previews, and session restoration remain deliberately deferred; downloads
remain later hardening work. Its automated gates are green, and the
normal-session hands-on tab smoke test passed on 2026-07-28.

The Phase 3 live bookmark smoke test passed, and its keyboard-first workflow is
approved; the manual recovery exercise is still pending. At the accepted Phase
4 checkpoint, final Debug and Release verification each passed 135 unit tests
and 12 UI tests. Production-list compilation, the blocker benchmark, Release
bundle verification, the cross-process profile probe, controlled scrolling,
one/ten-view resources, and the read-only container audit were also green.
Ordinary pending navigation may only strengthen protection; an exact-host
relaxation is applied only after the winning document commits, and stale
callbacks cannot weaken a newer page. On 2026-07-27, the user reported that the
blocker and popup checkpoint works in hands-on use and approved it.

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

## VPN connection-reset experiment

If every tab becomes slow after connecting or disconnecting a VPN, choose
**Navigate → Reset WebKit Connections (Experimental)**, then retry the stalled
address (or reload the page). This interrupts network activity across Browser's
tabs without closing or automatically reloading them. Saved cookies and local
storage stay in the existing profile. **Session-only cookies and sessionStorage
can be lost, so some sites may sign you out.** Streams, WebSockets, and other
active requests are interrupted and may need a page reload. Unsaved storage
writes may also be lost when the network process stops.

Requests still queued while a new tab starts may proceed through the fresh
network process. If a page is still loading, you can submit its address again;
the reset command does not wait for or automatically retry navigation.

This personal-use diagnostic invokes WebKit's private
`WKWebsiteDataStore._terminateNetworkProcess` hook, guarded by runtime
availability and signature checks. The command is disabled if unsupported.
It is not an App Store-compatible API. The user confirmed recovery from the
VPN slowdown with this command on 2026-10-22; it remains an experimental
workaround, and the underlying cause is not established.
The next request can start a fresh network process; the existing profile stays
in use. See [WebKit's implementation](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/Cocoa/WKWebsiteDataStore.mm).

To test: launch the updated app, toggle ExpressVPN, confirm the slowdown, use
the reset command, and retry the same address without restarting Browser.
Repeat for the opposite VPN transition. Recovery would support a problem with
WebKit's process-local networking state, but would not distinguish DNS state
from cached connections or routing state.

## Requirements

- Apple silicon Mac running macOS 26 or later
- Xcode 26.6 or a compatible newer release
- Xcode command-line tools selected with `xcode-select`

## Build and verify

~~~sh
make check                          # background Debug/Release checks + Release verification
BROWSER_BUILD_JOBS=1 make test       # default is 2 jobs; tests always run serially
make bookmark-benchmark             # standalone, no app or UI automation
make blocker-benchmark              # isolated background WebKit benchmark
make performance-build              # compile interactive tests without launching them
make clean-results                  # keep only the newest 3 result directories of each kind
~~~

Routine checks use a separate `com.utpalchakraborty.browser.testhost` identity
and a nonactivating host with no startup window or production services.
The Browser scheme explicitly selects reviewed background test classes. New test
classes must be reviewed and added to its SelectedTests list (or to the
BrowserInteractive or BrowserBenchmarks list); every run first checks that each
`XCTestCase` class is selected by exactly one of these schemes and fails if not.
Each run keeps only the newest three result directories of its kind under
`.build/` (`BROWSER_KEEP_RESULTS=n` to change), and the last background test
removes test-created WebKit profiles from the isolated test host. Visible-window
AppKit tests, XCUI automation, and timing benchmarks are excluded from routine
checks; a passing `make check` does not claim those interactive gates passed.

The test/benchmark runners serialize runs, lower scheduling priority, and limit
build concurrency (`BROWSER_BUILD_JOBS=1..8`), bound Swift batches, and disable
Swift's automatic multithreaded whole-module optimization. Ctrl-C stops the run and its owned
fixtures/test products without terminating the user's Browser. Avoid simultaneous
runs of these test schemes from Xcode while the CLI runner owns them. Explicit
interactive performance runs retain the caller's priority; their test build identity
and signing differ from the production app, so packaged performance remains a
separate acceptance check. Concurrency is
bounded, not a hard memory or CPU cap. Standalone timings taken while other
work is running should be treated as diagnostic.

Run the following only when desktop input is available for automation:

~~~sh
make interactive-test               # visible-window AppKit tests, then XCUI workflows
make ui-test                        # XCUI workflows only
make performance INTERACTIVE=1      # repeated app launches, typing, clicks, scrolling
~~~

`make check` also verifies the production Release signature, architecture,
entitlements, hardened runtime, and independently pinned blocker assets.
Other specialized gates remain explicit; some launch apps or take several minutes:

~~~sh
make profile-probe
make resource-one
make resource-ten
make webcontent-termination
make container-audit
make network-audit
~~~

With Phase 5, `make resource-ten` launches ten real resident tabs through the
normal tab manager and profile. `make container-audit` is a read-only inspection
of the Browser sandbox. `make network-audit` must be run from a normal
interactive Terminal because it requests administrator authorization only for
the scoped packet capture.

Final Phase 5 automation passed 149 Debug unit tests, 13 Debug UI tests, 149
Release unit tests, and all 13 Release UI workflows. Release tab creation p95
was 6.514 ms against 100 ms; selection with ten loaded resident tabs was
2.983 ms against 50 ms. Ten-tab aggregate memory was 186.8 MiB p95 against
1 GiB, with 0.013% mean idle CPU. A full-app 100-cycle Command-T/Command-W
probe also settled from a 62,932 kB first-half median to 55,985 kB in the
second half. Raw artifact paths are recorded in
[docs/status.md](docs/status.md).

## Use

~~~sh
make run                            # build and launch Release
make run-release                    # launch the existing Release build without rebuilding
~~~

Both commands open `.build/DerivedData/Build/Products/Release/Browser.app`.
`make run` builds the Release configuration first; `make run-release` requires
an existing Release build (create one with `make release`). Enter an explicit HTTP
or HTTPS URL, a plausible hostname such as `example.com`, or search text in the
address field and press Return. You can also paste an absolute `.html` or `.htm`
path such as `/Users/example/site/index.html`, or its `file:///` URL. Browser
then asks you to approve that file's exact containing folder so local images,
scripts, styles, and sibling pages can load.

- Command-L focuses the address field.
- Command-T creates and selects a fresh blank tab, then focuses the address
  field. The `+` button performs the same action.
- Click a tab to select it, or use its close control to close it.
- Right-click a link and choose **Open Link in New Tab** to open it in a
  background tab, like Command-click. WebKit's new-window and download menu
  items are removed because Browser does not create page windows or downloads.
- Highlight a web address in page text, right-click, and choose **Open Selected
  URL in New Tab** to open and select a new tab. Full HTTP(S) addresses and bare
  hostnames such as `example.com/path` work; ordinary text is not searched.
- Command-W closes the selected tab. Closing the sole remaining tab replaces it
  with a fresh blank tab and focuses the address field.
- Shift-Command-W closes the browser window.
- A direct, unmodified click on a `magnet:` link opens it with the application
  registered for magnet links in macOS.
- A submitted or bookmarked local HTML path opens after you approve its
  containing folder. Access is read-only, stays in memory only for that tab,
  and ends when the tab closes; it is not restored on relaunch.
- Command-[ and Command-] navigate Back and Forward.
- Command-R reloads.
- Command-period stops an active load.
- Command-D adds the current page as a bookmark, or edits it if already saved.
- Option-Command-B opens the searchable Bookmarks manager.
- Click a sidebar bookmark to open it in a new tab. Arrow keys select a row;
  Return opens it. Hover over a truncated title to see its full title and URL.
- Use the leftmost toolbar button or View > Hide/Show Bookmarks Sidebar to
  toggle the sidebar. Its visibility is remembered across launches.
- Option-Command-Y opens the Website Data privacy window.
- Privacy shows whether ad and tracker blocking is active for the current site.
- Option-Command-P disables or enables blocking for the current exact host and
  reloads the page. The choice persists across relaunch and does not apply to
  subdomains or alternate hostnames. If a main page fails to load, Privacy can
  instead offer **Disable Blocking for <host> and Retry Failed Page**, naming
  the failed destination even in a new tab. This is an explicit persistent
  exception; it does not bypass certificate errors. Affected tabs must finish
  navigating before the command is available.
- Navigate > Search Provider selects DuckDuckGo, Google, or Bing.

On a first install or after the bundled rules change, Browser compiles the
rules locally before permitting remote navigation. The native window remains
interactive and the latest submitted URL is queued; current measurements put
this one-time work at roughly 4 to 7 seconds. Cached launches reuse the compiled
rules. Browser never downloads or silently updates a filter list. After a
bundled-rule update compiles, the superseded compiled lists are deleted.

Rule updates are a developer step: `scripts/update-blocker-rules.py` (network
required; never run by the app or `make check`) rebuilds the pinned AdGuard
converter and checks the bundled files against the manifest's recorded
sources, or with `--registry-commit <sha>` regenerates them from a newer
FiltersRegistry commit and rewrites the manifest. The converter runs with
deterministic Swift hashing so new output is byte-reproducible. The current
files predate that, so they are checked for the same rules and the same
`ignore-previous-rules` order, the only ordering WebKit depends on. The release verifier's pinned manifest digest
must then be updated by hand.

Blocking materially reduces common advertising and tracking requests; it does
not promise anonymity or eliminate first-party analytics, fingerprinting, CNAME
cloaking, or trackers introduced after the pinned lists were generated.

Bookmarks use a flat sidebar and a searchable manager. Both update when the
library changes. Folder hierarchy is deferred until ordinary use demonstrates a
real need for it. Local HTML bookmarks opened in a new tab request that tab's
own folder permission.

Browser does not permit a page to create a secondary app window, another
WKWebView, or a tab-under on its own. Scripted `window.open` requests and forms
targeting a new context are denied. A physical Command-click on an HTTP or HTTPS
anchor is an explicit user request to load that URL in a new background tab;
the source tab remains selected and unchanged. A direct, unmodified pointer
click on an HTTP or HTTPS anchor with `target="_blank"` opens a foreground tab.
Synthetic and keyboard target-blank activation remains denied because public
WebKit API does not prove a direct pointer gesture. Every created tab uses the
same normal profile and receives the current compiled blocking rules and exact-
host site policy. Content blocking prevents many advertising popup triggers and
overlays before they run, but popup denial remains an independent backstop
rather than relying on a filter-list match.

Magnet handoff is limited to direct, unmodified primary clicks targeting the
top-level page or a new context. Browser cancels the WebKit navigation and gives
the original URL to macOS without logging or persisting it. Address-field entry,
scripted or subframe navigation, modified clicks, and every other external
scheme remain blocked.

Local-file access is limited to `.html` and `.htm` pages submitted in the
address field or explicitly opened from the Bookmarks manager. Browser uses
macOS's folder-selection consent flow and grants WebKit read access only to the
approved containing folder. A matching grant is reused only within that live
tab. Local same-frame links within the folder, reload, and back/forward work;
remote pages and unapproved file URLs cannot trigger access.

Explicitly adding a local page to Bookmarks stores its absolute file URL, just
as saving a web bookmark stores its URL. Browser never stores the folder grant,
a security-scoped bookmark, or a recent-file list. Opening that bookmark in a
different tab or after relaunch therefore asks for folder approval again.

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
valid backup. Changes, backup restoration, and reset use a temporary
`Bookmarks.transaction.json` rollback journal. A failed operation restores the
previous library; an interrupted rollback is completed before either active
copy is read on the next attempt. Successful operations remove the journal.

Quit Browser before copying bookmark data. Export both active files **and the
journal if present**; do not discard a pending journal on its own. To reset the
active library, use the in-app recovery Reset Bookmarks action, or quit Browser
and intentionally remove both active files and the transaction journal together.
A malformed primary is preserved as `Bookmarks.corrupt.<identifier>.json` rather
than silently overwritten. Identical corrupt input reuses its existing preserved
copy, and in-app reset keeps these preserved originals. For complete bookmark
erasure, quit Browser and remove the two active files, any transaction journal,
and every `Bookmarks.corrupt.*.json` file from this directory.

Bookmarks are the only application-owned URLs written by this feature. They may
include an explicitly saved local HTML path, but never its filesystem grant.
Browser still creates no visit history and sends no application-owned
telemetry.

Start with [project status](docs/status.md), then see the approved
[architecture](docs/architecture.md), the phased
[implementation plan](docs/implementation-plan.md), the locked
[performance baseline](docs/performance-baseline.md), and the
[Phase 1 risk report](docs/phase-1-risk-report.md).

This repository is currently intended only for the owner's personal use. No
license or distribution grant is asserted for the project's own code. Bundled
third-party blocker data and tools retain the GPL-3.0 terms and attribution
recorded in the included notices and license files.
