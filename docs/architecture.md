# Browser Architecture

Status: Approved; the first Phase 4 ad/tracker-blocking and popup-suppression
checkpoint is complete; website-data privacy controls remain Phase 4; tabs
remain Phase 5
Last updated: 2026-07-27

## 1. Purpose

This project is a personal, privacy-oriented browser for Apple silicon Macs. It
owns the browser interface and privacy policy while relying on Apple's WebKit
engine for standards-compliant page rendering, JavaScript, networking, media,
and web-process isolation.

The initial product must:

- display ordinary web pages;
- provide fast navigation and tab management;
- store and manage bookmarks;
- keep its browser profile separate from Chrome;
- let the user inspect and delete cookies and other website data;
- block common advertising and tracking resources efficiently;
- keep all application-owned data local;
- maintain no browsing history and send no telemetry; and
- make performance a release gate, not a later optimization exercise.

## 2. Architectural decisions

| Area | Decision | Reason |
| --- | --- | --- |
| Platform | Apple silicon and macOS 26 or later | This is a personal-use application for the current Mac, so compatibility layers are unnecessary. |
| Product identity | Browser, bundle identifier com.utpalchakraborty.browser | Simple local identity matching the repository; distribution naming is out of scope. |
| Language | Swift 6 | Native system APIs, strong concurrency checking, and no language bridge in the hot path. |
| Application UI | AppKit | Mature macOS window, keyboard, menu, and view-lifecycle control with predictable overhead. |
| Web engine | WKWebView from WebKit | A maintained, native, multiprocess engine rather than a new renderer or a bundled browser runtime. |
| Runtime dependencies | Apple system frameworks only for the first usable release | Reduces startup work, binary size, supply-chain surface, and maintenance. |
| Application structure | One application target plus unit, UI, and performance test targets | Keeps the small application understandable; split modules only when a measured need appears. |
| Normal browser storage | One explicit persistent WKWebsiteDataStore profile | Cookies and site data remain separate from other browsers while WebKit retains responsibility for its own storage. |
| Bookmarks | Versioned Codable JSON written atomically | The data set is small and does not justify a database or third-party library. |
| Window geometry | Use AppKit frame autosave for the main window only | Restores a useful size and location without retaining browsing or session state. |
| Content blocking | Compiled WKContentRuleList rules | Blocking happens inside WebKit without an application callback for every request. |
| History and sessions | Memory only | No visit database, recently closed list, persisted tabs, or automatic session restoration. |
| Security boundary | App Sandbox and hardened runtime | Limits damage if untrusted web content or application code is compromised. |
| Performance | Release-build benchmarks with explicit budgets | Every phase must demonstrate that it has not made the browser sluggish. |

### Alternatives not selected

- WebKit for SwiftUI is viable on macOS 26, but it is a newer API surface. The
  first version will use the mature AppKit and WKWebView APIs directly. This is
  a control and maturity decision, not a claim that SwiftUI is inherently slow.
- Electron would add another UI/runtime layer and bundle a large engine for a
  small native application.
- Qt WebEngine or CEF would make more sense for a committed cross-platform
  Chromium product, but would add engine packaging, update, and integration
  responsibilities that this personal macOS browser does not need.
- Building or forking a rendering engine is explicitly outside the project.
- A custom HTTP proxy, URLProtocol interception layer, or custom cookie
  database would duplicate WebKit responsibilities and risk compatibility,
  security, and performance.

## 3. Scope boundaries

### First usable release

- A native browser window and address field.
- Back, forward, reload, stop, and loading status.
- Bookmarks with add, edit, delete, search, and open operations.
- A normal persistent WebKit profile.
- Compiled ad and tracker blocking.
- Cookie inspection and individual, per-site, and global deletion.
- Visibility into other website-data categories and per-site/global deletion.
- A visible per-site blocking exception.
- Strict popup suppression independent of content-blocking rules.
- Multiple tabs with familiar keyboard shortcuts.
- Safe handling of common browser cases needed for daily use.
- Local-only performance measurements and regression tests.

### Explicit non-goals

- A new HTML, CSS, JavaScript, networking, or media engine.
- Cross-platform releases.
- Browsing history, recently closed tabs, or tab/session restoration.
- Telemetry, analytics, remote crash reporting, or application-operated
  services.
- Live search suggestions.
- Chrome data import.
- Account sync.
- Browser extensions.
- Password management.
- Multiple persistent profiles.
- Developer-controlled advertising or tracking.
- Matching all Safari or Chrome features.

Downloads, private windows, site permissions, find-in-page, and other browser
edge cases are daily-driver hardening work, not reasons to enlarge the first
vertical slice.

## 4. System shape

~~~mermaid
flowchart TD
    App[AppDelegate] --> Window[BrowserWindowController]
    App --> Profile[BrowserProfile]
    Profile --> Factory[WebViewFactory]
    Factory --> Web[WKWebView]
    Factory --> Store[WKWebsiteDataStore]
    Window --> Web

    App --> Repository[BookmarkRepository actor]
    Window --> Coordinator[BookmarkCoordinator]
    Window --> BookmarkUI[Bookmark editor and manager]
    BookmarkUI --> Coordinator
    Coordinator --> Repository
    Repository --> Files[Versioned JSON and backup]

    App --> Blocking[ContentBlockingCoordinator]
    Blocking --> Resolver[Bundle + resolver + last-valid state]
    Blocking --> SitePolicy[Exact-host policy store]
    Resolver --> RuleStore[WKContentRuleListStore]
    Window --> Blocking

    Profile -. Remaining Phase 4 .-> PrivacyUI[Website-data controls]
    Window -. Phase 5 .-> Tabs[TabManager]
    Tabs -. Phase 5 .-> Tab[TabController per resident tab]
~~~

The important boundary is between browser-owned behavior and WebKit-owned
behavior:

- The application owns windows, tabs, commands, bookmarks, privacy choices,
  blocker configuration, and the representation shown to the user.
- WebKit owns page loading, rendering, JavaScript execution, TLS processing,
  cookies, caches, local storage, IndexedDB, service workers, and its process
  model.
- The application uses only public WebKit APIs. It never reads or edits
  WebKit's private on-disk databases.

## 5. Components and responsibilities

### Application layer

AppDelegate owns process lifecycle, creates windows, installs application menus,
disables AppKit state restoration so macOS cannot reconstruct browser windows,
web content, or tab URLs, creates the production BookmarkRepository after the
native window has been presented, and prepares the production
ContentBlockingCoordinator after native chrome is interactive.

BrowserWindowController owns one browser window, including:

- address field and navigation buttons;
- the current single-page WKWebView container;
- keyboard focus and command routing;
- configuration of native frame autosave for the main window; and
- bookmark-button state and presentation of the bookmark editor and manager;
- strengthening blocker policy before ordinary navigation, relaxing exact-host
  policy only after the winning commit, and ignoring stale callbacks;
- applying a user-requested current-site exception before its explicit reload
  so document-level matches remain recoverable; and
- Privacy-menu status, exception toggling, explicit reload, and visible
  unavailable presentation.

There is no global navigation singleton. Phase 3 routes commands to the current
page in the key browser window; Phase 5 will route the same semantic commands
to the selected tab.

### Profile layer

BrowserProfile is the composition root for WebKit profile-scoped services:

- a stable persistent WKWebsiteDataStore;
- WebViewFactory.

Bookmarks are application-owned data rather than WebKit profile data.
AppDelegate constructs BookmarkRepository separately and injects it into the
window controller, which exposes only immutable snapshots through a main-actor
BookmarkCoordinator.

Blocking policy is also browser-owned rather than part of BrowserProfile.
AppDelegate composes ContentBlockerBundle, ContentBlockerRuleSetResolver,
ContentBlockerService, ContentBlockerStateStore, and
ContentBlockerSitePolicyStore behind one main-actor ContentBlockingCoordinator.
The coordinator prepares one complete rule set and applies its lists to each
WKWebView's WKUserContentController according to the current exact-host policy.
WebsiteDataController operates against BrowserProfile's data store; its user
interface remains the next Phase 4 slice.

The normal profile is intentionally persistent because the user wants cookies
that survive relaunch and can be inspected. A future private window would use a
separate nonpersistent WKWebsiteDataStore and would never share state with the
normal profile.

### Tab layer

Phase 5 introduces this layer. TabManager will own the ordered tab collection,
selected tab identifier, creation,
closure, reordering, and routing of popup/new-window requests.

TabController is main-actor isolated and owns:

- one optional WKWebView;
- its WKNavigationDelegate and WKUIDelegate behavior;
- observations for URL, title, progress, loading, and back/forward capability;
- transient load errors; and
- lightweight memory-only state such as last activation time.

The selected tab's web view is created lazily. Once a resident tab has a web
view, switching tabs detaches and reattaches that same native view; it does not
reload the page. Background web views are not eagerly created.

Initial releases will not unload resident tabs. If controlled measurements show
that memory use is unacceptable, a later policy may discard least-recently-used
background tabs under memory pressure. Discarding loses page JavaScript, form,
media, and back/forward state, so it must be visible and never introduced only
as a hidden optimization.

WebKit chooses how web-content processes are shared. The application will not
try to create or tune process pools.

### WebKit construction

WebViewFactory is the only place that creates WKWebView configurations. Every
normal tab receives:

- the same normal-profile website data store;
- the current compiled content rules;
- conservative WebKit preferences;
- the browser's navigation and UI delegates; and
- no JavaScript-to-native message bridge.

Centralized construction prevents one tab from accidentally using a different
cookie store or weaker privacy settings. WebKit-specific types remain inside
the web and UI layers; bookmark, URL-policy, tab-summary, and site-policy
models do not import AppKit or WebKit.

This is a portability seam, not a large generic browser-engine abstraction.
WKWebView has a rich API that should not be hidden behind a speculative,
lowest-common-denominator protocol.

### Address interpretation

AddressInterpreter is a pure, independently tested value component:

1. Trim surrounding whitespace.
2. Accept a valid HTTP or HTTPS URL.
3. Treat plausible host names as HTTPS URLs.
4. Otherwise create a search URL using the configured provider.
5. Do not request remote search suggestions.

Changing the search provider changes who receives search terms. The first
implementation must make the provider visible and configurable. The approved
Phase 2 default is DuckDuckGo without live suggestions.

### Bookmarks

BookmarkRepository is a Swift actor that owns `Bookmarks.json`, a versioned
file containing stable identifiers, canonical HTTP/HTTPS URLs, titles, and
creation/update timestamps.

- Reads and writes do not run on the main actor.
- Writes use atomic replacement.
- Every successful mutation writes the latest validated snapshot to both
  `Bookmarks.backup.json` and the primary. This keeps recovery current and
  ensures an edited or deleted URL does not remain in the active backup.
- A malformed primary is copied to a uniquely named `Bookmarks.corrupt.*.json`
  file. A valid backup is shown read-only until the user explicitly restores it
  or resets the library; unrecoverable data remains a visible error.
- BookmarkCoordinator supplies immutable snapshots to the main-actor browser
  toolbar, editor sheet, and searchable nonmodal manager.
- The toolbar star and Command-D add or edit the current page;
  Option-Command-B opens the manager. Opening a bookmark replaces the current
  page until Phase 5 routes it to the selected tab.

Phase 3 deliberately has no persistent bookmarks bar and no folder hierarchy.
The searchable manager and keyboard commands keep the browsing surface compact;
folders can be added later without changing the repository boundary if a real
flat-library organization problem emerges.

Production files live in the sandbox's Application Support directory under
`com.utpalchakraborty.browser`. UI tests use an isolated `UITests` subdirectory.
Performance launches construct no repository and therefore touch no bookmark
store.

Bookmarks are deliberately saved URLs and therefore are not browsing history.

### Website data and cookies

WebsiteDataController is the sole API-facing layer for WebKit website data.

Cookie operations use WKHTTPCookieStore to:

- enumerate cookies;
- show domain, name, path, expiry/session status, Secure, and HttpOnly metadata
  when available;
- delete one cookie; and
- refresh the displayed snapshot after asynchronous deletion completes.

WKWebsiteDataStore records are used to show which domains retain other data,
including caches, local storage, IndexedDB, and service-worker data. The user
can delete selected site data, all data for a domain, or all website data.

The UI must not imply that deleting cookies also deletes every other storage
mechanism. It will expose both cookie-level controls and broader site-data
controls.

Persistent caching remains enabled because disabling it would significantly
hurt performance and compatibility. Private browsing or explicit clearing is
the correct mechanism for avoiding persistent website data.

### Content blocking

ContentBlockerBundle validates the bundled manifest, resource names, immutable
identifiers, and hashes. ContentBlockerRuleSetResolver looks up every compiled
identifier first, loads and hashes JSON off the main actor only on cache miss,
asks ContentBlockerService to use WebKit's asynchronous compile API, and records
a complete current set only after every list succeeds. ContentBlockerStateStore
persists only last-valid identifiers. ContentBlockingCoordinator owns readiness,
exact-host policy, transactional fallback, and per-WKUserContentController
attachment state.

For a resident web view, policy application is strengthen-only while ordinary
navigation is pending. An exact-host relaxation occurs only after the winning
document commits, and stale, overlapping, or post-commit callbacks cannot
weaken the committed or newer page. The explicit current-site switch is a
deliberate exception: its chosen policy is applied before reload so even a
document-level rule match can be recovered.

The current production package uses pinned AdGuard Base and Tracking Protection
filter sources. Pinned AdGuard Safari Converter 4.3.0 ran only as a developer-
side command-line tool; it is not linked into or shipped with the browser.
Source and converter are GPL-3.0, which is acceptable for this personal-use
project but must be re-audited before any distribution. The bundled manifest
records exact source and converter commits, input and output hashes, conversion
arguments, output rule counts, attribution, and licenses. Normal launch never
downloads or converts a list.

Phase 1 proved WKContentRuleList rule ordering, cached attachment cost, and a
live exception sequence. The first Phase 4 checkpoint now bundles 119,512
generated rules under immutable content-addressed identifiers, validates the
manifest and hashes, compiles only on cache miss, persists an exact-host
exception, and exposes active, last-valid, preparing, disabled-host, and
unavailable states. Updates remain manual and release-bound; there is no
automatic filter network request. A package change becomes active only as a
complete set. If compilation fails, the complete last-valid set remains active;
if no valid set exists, remote navigation is held behind a visible fail-closed
state. Post-fix Debug and Release unit and UI suites, the production benchmark,
and Release-package verification are green. On 2026-07-27, the user reported
that the blocker and popup checkpoint works in hands-on use and approved it.

The browser will not proxy traffic or run arbitrary filter code for each
request.

## 6. State and persistence

### Persistent state inventory

| Data | Owner | Purpose | User deletion |
| --- | --- | --- | --- |
| Bookmarks | BookmarkRepository | Explicitly saved pages | Delete individually; reset active files; remove active and preserved corrupt files while Browser is quit for complete erasure |
| Required preferences | UserDefaults | Search provider | Reset settings |
| Main window frame | UserDefaults through AppKit frame autosave | Reopen at the last usable size and location | Reset settings |
| Last-valid blocker identifiers | ContentBlockerStateStore in UserDefaults | Transactional recovery bookkeeping; contains no navigated URL | Reset UI remains Phase 4 work |
| Per-site blocker exceptions | ContentBlockerSitePolicyStore in UserDefaults | Explicit exact-host user choices | Toggle current host; reset-all UI remains Phase 4 work |
| Cookies | WKWebsiteDataStore | Login and website behavior | Underlying deletion proven; Phase 4 privacy UI pending |
| Caches and other site data | WKWebsiteDataStore | Performance and website functionality | Underlying deletion proven; Phase 4 privacy UI pending |
| Compiled blocker data | WKContentRuleListStore | Fast local blocking | Reset UI remains Phase 4 work |
| Blocker manifest, rules, notices, and license | Signed app-bundle resources | Pinned local protection and provenance | Replace or remove the app |

No application-owned file may contain a passive list of navigated URLs.

### Memory-only state

- Open tab order and selection.
- Current tab URLs and titles.
- Back/forward lists.
- Navigation progress and errors.
- Popup routing state.
- Per-tab last-activation timestamps.

Window geometry is not browsing state. A normal quit and relaunch may restore
only the main-window frame through AppKit's native frame-autosave behavior.
AppKit constrains restored geometry for the current display environment; if it
cannot apply saved geometry, the browser retains its usable centered default.

Browser windows remain non-restorable through AppKit state restoration. Every
normal relaunch starts with one blank local tab and a focused address field; it
never restores a URL, title, web view, back/forward list, or tab collection.

### Meaning of no history

No history means the application does not create:

- a visit database or URL journal;
- frequency or recency rankings;
- recently closed tabs;
- address suggestions derived from prior navigation;
- persisted open tabs;
- page titles, URLs, or search terms in application logs; or
- performance reports containing browsing data.

It does not mean the disk contains no evidence of browsing. A persistent web
profile necessarily contains cookies, caches, local storage, and related data,
and explicitly saved bookmarks and site exceptions contain domains. Those
categories are documented and clearable. A later nonpersistent private window
can provide a stronger no-persistence mode.

## 7. Privacy and security invariants

- No analytics SDK, telemetry endpoint, remote crash reporter, advertising
  identifier, or application-operated web service.
- Code owned by the application initiates no network request on a blank launch.
  Only user navigation initiates app-intended network activity in the current
  build. Any future explicit blocker updater requires a separate decision.
  Operating-system and WebKit behavior is measured and reported separately
  rather than silently attributed to the app.
- Release logging never records URLs, query strings, search terms, cookie
  values, page content, form values, or bookmark contents.
- Performance signposts use opaque tab identifiers, never URLs.
- App Sandbox and hardened runtime are enabled.
- Initial entitlements are limited to outgoing network access. User-selected
  file write access is added only when downloads are implemented.
- Camera, microphone, location, notification, and similar privileges are absent
  until a visible permission policy is implemented and approved.
- WebKit performs TLS validation. The application never bypasses certificate
  errors or opts into deprecated TLS.
- HTTP and HTTPS are accepted. Other URL schemes are denied or explicitly
  handed to macOS under a small, tested allowlist and visible user action.
- No page may create a secondary app window, another WKWebView, a background
  tab, or a tab-under. Scripted `window.open` requests and forms targeting a new
  browsing context are denied, including requests triggered by page script in
  response to a click.
- Only a direct pointer-activated HTTP or HTTPS anchor targeting a new browsing
  context may be routed. WebKit exposes a nonzero mouse-button value for that
  action; JavaScript `anchor.click()` reports `linkActivated` but no mouse
  button and is denied. Keyboard/synthetic target-blank activation is also
  denied because public API does not prove a direct pointer gesture. The
  allowed pointer action replaces the current page and may become a new
  foreground tab only after Phase 5; it never becomes a background tab or
  separate app window.
- Ad/tracker blocking may prevent common advertising popup triggers and
  overlays before they execute, but delegate-level popup denial is an
  independent backstop and never depends on a filter-list match.
- No page-injected JavaScript bridge exists in the first release. If a later
  feature truly requires one, it must use an isolated content world, a narrow
  message schema, and a separate security review.
- The user agent is not customized without a demonstrated compatibility need.
- Web content is untrusted. Browser UI never renders untrusted strings as
  executable markup.
- The application does not read Chrome, Safari, or another application's data.

These controls reduce tracking but cannot promise anonymity. Visited sites,
the selected search provider, the operating system, and WebKit may make their
own network requests or retain data outside code controlled by this project.
Content blocking also cannot eliminate first-party analytics, every fingerprint,
CNAME cloaking, or a newly introduced tracker.

## 8. Performance architecture

### Rules

- Show the window and focus the address field before loading optional
  bookmarks, cookie snapshots, or blocker metadata. Bookmark startup is queued
  after native-window presentation and disabled entirely for performance-test
  launches.
- Do not synchronously read files or perform application-owned network work on
  the main actor. Prepare blocker JSON away from the main actor and call
  WebKit's asynchronous compilation API without delaying interactive chrome.
- AppKit and WKWebView operations stay on the main actor; storage and blocker
  preparation use structured concurrency.
- Observe WebKit state changes rather than polling.
- Reuse resident tab web views when switching.
- Load compiled blocker artifacts by identifier. Never compile a large list on
  an ordinary cached launch; treat first-install or changed-bundle compilation
  as a measured setup path and do not allow an unprotected remote navigation
  while it is pending.
- Keep the initial view hierarchy and visual effects simple.
- Do not fetch favicons, previews, suggestions, or remote start-page content in
  the first release.
- Add no third-party runtime framework without measuring launch, memory,
  privacy, and maintenance cost.
- Optimize only measured bottlenecks.

App-shell cost and web-content cost are reported separately. Arbitrary page
CPU, memory, and rendering behavior belongs largely to the site and WebKit; the
project owns the overhead it adds around WebKit.

The concrete benchmark protocol and provisional budgets are defined in
implementation-plan.md. A failed performance gate blocks the next phase unless
the budget is deliberately revised with recorded evidence.

## 9. Concurrency and event flow

- AppKit controllers, TabManager, TabController, and WKWebView integration are
  main-actor isolated.
- BookmarkRepository and blocker-source preparation are actor-isolated.
- WebKit callback APIs are converted into state changes at the boundary.
- Each tab publishes a small immutable UI snapshot rather than exposing
  writable WebKit state to the window controller.
- Asynchronous deletion, compilation, and persistence operations expose
  explicit in-progress and error states; the UI never assumes completion.
- Cancellation is required when a window, tab, or management view closes.

A typical navigation flow is:

1. BrowserWindowController sends submitted text to AddressInterpreter.
2. The result is either a valid URL or a visible validation error.
3. The selected TabController asks its WKWebView to load.
4. Delegate and observed WebKit state update the tab snapshot.
5. The window renders title, progress, and navigation capability from that
   snapshot.

Navigation completion is never treated as a signal to persist a visit.

## 10. Failure and recovery behavior

- A content-process termination shows a recoverable tab error with a reload
  action; it must not crash the browser process.
- A failed page load shows the failing host and useful error without logging the
  full URL.
- A corrupt bookmark file preserves the bad input for manual recovery and
  offers the last valid backup read-only until explicit restore or reset.
- A failed blocker update leaves the last compiled list active.
- A failed cookie/site-data deletion remains visible and refreshes from WebKit
  before reporting success.
- Unsupported permissions and schemes fail closed with understandable UI.
- Closing a tab releases observers and delegates; churn tests check for
  monotonic memory growth.

## 11. Planned source layout

Phase 1 deliberately keeps its validation scaffold flat. Starting with the
Phase 2 browser shell, the repository should remain one small Xcode application
and grow toward this ownership-oriented layout as components are introduced:

~~~text
Browser.xcodeproj
Browser/
  App/
  UI/
    BrowserWindow/
    Tabs/
    Bookmarks/
    Privacy/
  Web/
  Model/
  Storage/
  Privacy/
  Resources/
BrowserTests/
BrowserUITests/
BrowserPerformanceTests/
TestSupport/
docs/
~~~

Folder boundaries communicate ownership without adding framework targets or
dependency-injection infrastructure.

## 12. Testing boundaries

### Unit tests

- Address and search interpretation.
- Native frame-autosave configuration and launch-mode isolation.
- Tab selection, closure, and ordering rules.
- Navigation, external-scheme, and popup policy.
- Bookmark encoding, atomic replacement, recovery, and migrations.
- Privacy-default configuration.
- Blocker manifest/hash validation, cache/fallback state, exact-host policy,
  production-list compilation, and attachment behavior. The pinned converter
  remains an offline developer tool rather than runtime code.

### WebKit integration and UI tests

A test-only localhost server built with system frameworks supplies deterministic
pages for:

- navigation, redirects, failures, and back/forward;
- popup and target-blank routing;
- cookie creation, enumeration, and deletion;
- local storage and broader website-data deletion;
- content-rule request blocking and exceptions;
- downloads and authentication;
- relaunch with restored window geometry but no restored browsing state;
- bookmark add, edit, title/URL search, open-in-current-page, delete, and
  relaunch persistence;
- tab switching without reload; and
- web-content process recovery where automation permits.

The test server is not shipped in the application.

### Performance tests

- Launch to first interactive browser chrome.
- First WKWebView readiness.
- New-tab and resident-tab switching latency.
- Browser command response.
- Idle CPU.
- App process and WebKit child-process memory.
- Rule-list lookup and attachment.
- Repeated tab open/close churn.
- Controlled-page scrolling and UI hitches.

The project tests its integration and overhead. It does not attempt to retest
WebKit's HTML, CSS, or JavaScript implementation.

## 13. Cross-platform implications

A cross-platform browser would not require three completely independent
products, but it would require a different foundational choice.

### Option A: shared core with native shells

| Platform | Typical shell and engine |
| --- | --- |
| macOS | AppKit and WKWebView |
| Windows | WinUI or another native shell and WebView2 |
| Linux | GTK and WebKitGTK |

A portable Rust or C++ core could share bookmark formats, settings, tab rules,
URL interpretation, privacy policy, filter-list intermediate data, and
benchmark definitions. Each platform would still need a real shell and engine
adapter for:

- browser windows, menus, keyboard behavior, and accessibility;
- navigation events and popup handling;
- cookies, profiles, and private browsing;
- content blocking;
- downloads, authentication, and permissions;
- process and memory-pressure behavior;
- packaging, signing, updates, and installation; and
- platform-specific performance testing.

This is one shared product core plus three platform integrations, not three
from-scratch browsers. It normally uses platform-provided or separately
installed shared engine runtimes rather than bundling a private Chromium copy,
but page behavior and privacy APIs differ by platform.

### Option B: one cross-platform Chromium stack

Qt WebEngine can provide a shared C++/QML or Widgets interface and a
Chromium-based engine on macOS, Windows, and Linux. CEF provides lower-level
Chromium embedding with more host work.

This approach shares more UI and engine integration and gives more consistent
page behavior, but it still needs three packages and test pipelines. Chromium
rendering can be fast and GPU accelerated; the tradeoffs to verify are a larger
distribution and potentially higher cold-start or idle-memory cost. It also
means shipping browser helper processes and engine resources, tracking
security updates, and reviewing licensing. CEF in particular leaves substantial
windowing, message-loop, sandbox, packaging, and signing work to the host
application.

### Decision for this project

Cross-platform support would materially change the language, UI framework,
engine strategy, build system, and test matrix. Trying to pay that cost now
would work against the personal-use and performance goals.

The macOS design will preserve sensible seams:

- WebKit creation stays behind WebViewFactory.
- Browser-owned models avoid AppKit and WebKit imports where natural.
- Bookmark and blocker source formats are versioned.
- Deterministic behavior and benchmark fixtures are documented.

It will not add Rust/C++ FFI, Qt, CEF, or a broad browser-engine protocol for a
hypothetical port. If cross-platform becomes a real requirement, the project
should make an explicit new architecture decision rather than pretending the
native Swift UI is portable.

## 14. Product defaults and remaining evidence

Approved defaults:

1. Product name: Browser.
2. Bundle identifier: com.utpalchakraborty.browser.
3. Default search provider: DuckDuckGo, configurable, with no live suggestions.
4. Private windows are deferred to daily-driver hardening.
5. Cross-platform support is not planned.

Phase 1 established:

1. AdGuard Base and Tracking Protection as the selected filter sources, with a
   pinned AdGuard Safari Converter command-line conversion in Phase 4;
2. manual, release-bound filter updates with no silent network request; and
3. locked absolute CPU, memory, launch, and cached-rule attachment budgets in
   [performance-baseline.md](performance-baseline.md).

The completed first Phase 4 checkpoint converted and bundled those pinned
sources, verified their hashes and production semantics, and implemented the
exact-host exception plus popup backstop. Website-data UI, global blocker reset
controls, and full Phase 4 resource and network gates remain.

The measured WebKit API and platform risk decision is recorded in
[phase-1-risk-report.md](phase-1-risk-report.md).

## 15. Primary references

- [WKWebView](https://developer.apple.com/documentation/webkit/wkwebview/)
- [WKWebsiteDataStore](https://developer.apple.com/documentation/webkit/wkwebsitedatastore)
- [WKHTTPCookieStore](https://developer.apple.com/documentation/webkit/wkhttpcookiestore)
- [WKContentRuleList](https://developer.apple.com/documentation/webkit/wkcontentrulelist)
- [WKNavigationDelegate](https://developer.apple.com/documentation/webkit/wknavigationdelegate)
- [Apple App Sandbox](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox)
- [Apple performance and metrics](https://developer.apple.com/documentation/xcode/performance-and-metrics)
- [Microsoft WebView2](https://learn.microsoft.com/en-us/microsoft-edge/webview2/)
- [WebKitGTK WebView](https://webkitgtk.org/reference/webkit2gtk/stable/class.WebView.html)
- [Qt WebEngine overview](https://doc.qt.io/qt-6/qtwebengine-overview.html)
- [CEF general usage](https://chromiumembedded.github.io/cef/general_usage.html)
