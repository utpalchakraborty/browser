# Bookmarks sidebar

Approved for implementation on 2026-10-20.

## Behavior

- Show a 224-point native sidebar to the left of the page, below the address
  bar. Keep the tab strip across the top.
- Display one bookmark title per row in the existing library order. Scroll
  long lists; truncate long titles and expose the full title and URL in a tooltip.
- A single click opens and selects a new tab every time. Arrow keys move the
  list selection without opening pages; Return opens the selected bookmark.
- Show a toolbar toggle and a View menu command. Default to visible and remember
  the choice in the existing launch-mode-specific preferences.
- Keep the existing bookmark manager and Option-Command-B shortcut. Provide
  a Manage Bookmarks button at the bottom of the sidebar.
- Reflect additions, edits, deletions, loading, empty, failure, and recovery
  states through the existing BookmarkCoordinator.

## Implementation

Add a small AppKit sidebar view backed by NSTableView. BrowserChromeView owns its
layout and toggle; BrowserWindowController connects actions and coordinator
updates. Continue using BookmarkRepository unchanged. Native symbols require no
favicon downloads.

Web bookmarks use the existing foreground-tab navigation path. Local HTML
bookmarks create a new tab and use the existing folder-authorization path, with
the same tab identity checks and cancellation behavior. Never transfer a local
grant from another tab. Invalid URLs must not create tabs.

Use one new visibility preference. A hidden sidebar gives its full width back
to the page and moves focus out of the hidden controls when necessary.

## Validation

Use isolated, hidden native fixtures for sidebar activation, original-tab
preservation, local-file authorization, live coordinator changes, recovery and
empty states, keyboard navigation, visibility persistence, and layout at normal
and minimum window sizes. Run the standard background Debug/Release suites and
production Release verification. Inspect an offscreen rendering of the native
view; live interaction remains a separate owner smoke test.

Preserve the existing unrelated Makefile and README changes. The owner
subsequently authorized a local commit of the sidebar; no push was requested.

## Completed verification — 2026-10-20

- `make test`: 178 tests passed, zero failures. Result:
  `.build/TestResults.YEAc3o/Browser.xcresult`.
- `make release-test`: 178 tests passed, zero failures. Result:
  `.build/TestResults.0U0ysp/Browser.xcresult`.
- `make verify-release`: production Release build passed; arm64 architecture,
  signature, sandbox/hardened-runtime entitlements, and pinned blocker assets
  verified at `.build/DerivedData/Build/Products/Release/Browser.app`.
- Seven new background tests cover sidebar action routing and Return,
  arrow-key selection, preservation of the original page and shared profile,
  repeated opening, empty-area clicks, local grant isolation/cancellation/stale
  approval, invalid URLs, live coordinator mutations, recovered snapshots,
  loading/failure/empty states, visibility persistence/focus, and scrolling/layout.
- Inspected native offscreen light, dark, and 460×300 minimum-content-size
  renderings exported to `.build/SidebarPreviews`. Long titles truncate and the
  bottom management button remains accessible. Offscreen chrome outside the
  sidebar has transparency because the window itself is not captured.
- No new sidebar compiler warnings or Auto Layout constraint conflicts appeared
  in the passing Debug run. Existing unrelated test warnings remain.
- `git diff --check` passed. Existing Makefile changes and README launch
  instructions were retained.

The agent's native test windows stayed hidden. Click tests dispatch the
configured action with AppKit row metadata; they do not synthesize desktop
mouse input. Interactive suites and performance baselines were not run.

## Owner acceptance — 2026-10-20

The owner reported "nice looks good" and authorized committing the sidebar
locally. This records owner acceptance without claiming unreported manual
scenarios such as VoiceOver use or every local-file recovery case. The earlier
Makefile help/launch changes and matching README launch instructions are kept
outside the sidebar commit.
