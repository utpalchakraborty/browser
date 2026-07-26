# Browser

Browser is a small, native macOS browser for personal use. It uses AppKit and
WKWebView, targets Apple silicon and macOS 26 or later, stores no
application-owned browsing history, and includes no telemetry or third-party
runtime dependencies. Startup, CPU, and memory budgets are release gates.

Phase 3 adds explicit, local bookmarks to the single-page browser: use the
toolbar star or Command-D to add or edit the current page, and use the
searchable Bookmarks manager to add, edit, delete, or open saved pages. Opening
a bookmark replaces the current page until tabs arrive in Phase 4.

This is now a usable one-page pilot, not yet the daily-driver release. It also
remembers the main window's size and location across relaunch while continuing
to launch with a blank page. Privacy controls, downloads, and production
content blocking remain later phases. The Phase 3 live bookmark smoke test
passed, and its keyboard-first workflow is approved; the manual recovery
exercise is still pending. Debug and Release functional verification is green;
the latest interaction and bookmark performance checks pass, while the launch
gate needs a clean idle-desktop rerun.

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
it is not a tab benchmark. Tabs begin in Phase 4.

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
- Navigate > Search Provider selects DuckDuckGo, Google, or Bing.

Bookmarks intentionally use a flat searchable manager rather than a persistent
bookmarks bar. Folder hierarchy is deferred until ordinary use demonstrates a
real need for it.

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
still creates no visit history and contains no telemetry.

Start with [project status](docs/status.md), then see the approved
[architecture](docs/architecture.md), the phased
[implementation plan](docs/implementation-plan.md), the locked
[performance baseline](docs/performance-baseline.md), and the
[Phase 1 risk report](docs/phase-1-risk-report.md).

This repository is currently intended only for the owner's personal use. No
license or distribution grant is asserted.
