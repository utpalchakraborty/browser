# VPN connection reset: accepted experiment

Resumed at the user's request on 2026-10-22 after a machine restart.
The automated in-flight-reset blocker is resolved. Debug/Release tests and
Release packaging verification passed. The user then confirmed real-world
recovery: "yes, much better. This worked." They requested a local commit.

## Request and scope

Browser is fast until ExpressVPN is connected or disconnected while Browser
is running. After either transition, all websites in all tabs, including new
tabs, become extremely slow or fail. Quitting and reopening Browser fixes it.
Chrome continues to work. The user does not use Safari; do not ask for another
Safari comparison.

The user authorized a manual button/menu command to reset WebKit connections
as an experiment. Do not automate VPN changes, restart the user's Browser,
or claim the underlying VPN problem is diagnosed by the local tests.

## Implementation

- `Browser/WebKitConnectionReset.swift` isolates the private
  `WKWebsiteDataStore._terminateNetworkProcess` hook. It checks selector
  availability, method argument count, and void return type before invoking
  a correctly typed C function pointer. `NSObject.perform` is not used because
  its object-return convention is wrong for this void selector. Logging records
  only the reset request, without URLs or cookies.
- `Browser/BrowserWindowController.swift` adds the menu factory, action, and
  validation. The action **only resets the network process**. It does not call
  `stopLoading`, recreate views, clear data, or request reloads/retries.
- `Browser/AppDelegate.swift` installs **Navigate → Reset WebKit Connections
  (Experimental)** after Stop Loading. No keyboard shortcut. The command is
  disabled if the hook is unavailable or no profile is installed.
- `BrowserTests/WebKitConnectionResetTests.swift` contains five background
  integration tests. The Browser scheme explicitly selects this class.
- `README.md` documents the private hook, side effects, queued-request behavior,
  and manual ExpressVPN procedure.

The working tree was clean before the original work; `main` was one commit
ahead of `origin/main`. The user authorized committing this accepted experiment
locally on `main`; pushing was not requested. New Swift files are picked up by
Xcode's filesystem-synchronized groups.

## Resolved in-flight blocker

The original action called `tab.stopLoading()` in every tab immediately before
terminating the network process. On newly created views, `isLoading` became true
before the initial navigation had committed. This sequence stranded those
initial requests: the flags remained true, titles stayed empty, and Reload was
disabled. A second Stop after one second did not repair the state. Explicit
address submission did recover those tabs. Responses that had already committed
did not have the stuck-flag problem.

Removing the preceding Stop calls avoids the failure. Active network responses
fail when the network process exits. Requests still queued during WebContent
startup can proceed through the fresh process. This is not an app-requested
reload or retry; the reset action leaves navigation handling to WebKit.

The regression test resets two new tabs synchronously before yielding, then
requires both original queued requests to finish and verifies an explicit Reload
actually replaces the document. Restoring the old Stop loop makes this new test
fail with the same timeout; removing it makes the test pass. No timer, loading
flag override, automatic retry, or navigation-state workaround was added.

Diagnostic evidence:

- `.build/TestResults.yvGPGg/`: after restart, original suite reproduced the
  original failure (181 tests, two reports from the same failing test).
- `.build/TestResults.wvkvHe/`: an additional delayed Stop did not clear flags.
- `.build/TestResults.BpmelI/`: committed loads stopped normally; explicit
  address submissions recovered the stuck initial-load tabs.
- `.build/TestResults.veSqD8/`: without the initial Stop loop, queued slow loads
  progressed into actual responses and a subsequent explicit Stop worked.
- `.build/TestResults.WjL6Xv/`: all five final focused tests passed.
- `.build/TestResults.6Br9qS/`: negative control with the old Stop loop restored;
  the new queued-load/Reload regression failed as intended. The loop was removed
  again before final verification.

The original paused failure was recorded in `.build/TestResults.TiEZ1M/` at the
old test's line 110, waiting for both loading flags to clear. The XCTest helper
also reported an unexpected `InvalidTransition` when its timeout error was
thrown; the actionable failure was the loading-state timeout.

## Verified behavior and limitations

The isolated tests verify:

- Actual network-process PID replacement and a successful HTTP request in a
  new tab afterward.
- Persistent HTTP-only cookie sent to the server and retained local storage.
- Existing tab identities, selection, WKWebViews, history, zoom, loaded DOM,
  JavaScript sentinel, and unsent input text survive without automatic reload.
- Both queued initial loads finish after reset, and Reload works afterward.
- Immediate explicit address navigation during initial reset works in both tabs.
- Two active streaming responses are interrupted before their final marker;
  both tabs then load explicitly submitted addresses successfully.
- The test windows remain hidden.

Session-only cookies and `sessionStorage` were lost in these runs. Some sites
may sign out. Streams, WebSockets, and active requests are interrupted; unsaved
storage writes may be lost. No cookie snapshot/restore mechanism was added.
Saved website data is retained, but the test does not establish durability for
all possible writes interrupted at the instant of reset.

This private hook is a personal-use diagnostic, not an App Store-compatible API.
There is no production async completion or PID polling. Tests alone use the
private `_networkProcessIdentifier` getter to prove replacement; that getter
can start the next network process itself.

## Final verification

- `make test`: **183 tests passed**, zero failures.
  `.build/TestResults.ReOH67/Browser.xcresult`
- `make release-test`: **183 tests passed**, zero failures, including the typed
  private call under optimization. `.build/TestResults.0F5Zgy/Browser.xcresult`
- `make verify-release`: passed. Built and verified arm64 architecture,
  ad-hoc signing, hardened runtime, sandbox entitlements, and pinned assets.
  Log: `.build/vpn-reset-verify-release-2026-10-22.log`
- `git diff --check`: passed; complete source changes reviewed, including new
  untracked files. No temporary trace logging remains in the sources.

Built app: `.build/DerivedData/Build/Products/Release/Browser.app`.

All test runs used the isolated, nonactivating test host and local fixture
server. The normal Release verifier checked packaging without launching the
user's Browser. Automated verification did not toggle ExpressVPN or reset or
relaunch the production Browser. The user performed the real-world acceptance
test afterward.

## Manual acceptance and reproduction

On 2026-10-22 the user reported that the reset worked and browsing was much
better, then approved committing it. This confirms recovery in their test;
they did not separately report results for each VPN direction or tab scenario.
The underlying DNS/connection/routing cause remains unproven.

Procedure for future reproduction:

1. Quit and reopen Browser once to load the updated Release build after it is
   built. `make run-release` opens the existing build without rebuilding.
2. Connect ExpressVPN and reproduce the slowdown.
3. Choose **Navigate → Reset WebKit Connections (Experimental)**, then retry
   the same address without restarting Browser. If it still shows Stop, submit
   the address again. Some session-only logins may be lost.
4. Repeat for VPN disconnect separately.
5. Record whether recovery works for existing and newly opened tabs.

Recovery would support a problem in WebKit's process-local networking state;
it would not distinguish DNS, connections, or routing state. Do not add automatic
monitoring/retries, system DNS flushing, cache deletion, or broad process killing
to this small experiment.

## Sources and environment

Original host inspection: macOS 27.0.1 (26A434), Xcode selected at
`/Applications/Xcode.app/Contents/Developer`; deployment target 26.0.

Primary sources inspected again during resumption:

- https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/Cocoa/WKWebsiteDataStore.mm
  (`_terminateNetworkProcess` and `_networkProcessIdentifier`)
- https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/WebPageProxy.cpp
  (`stopLoading` sends messages to WebContent; local experiments establish the
  observed race, not the upstream source alone)

The original declaration is in
https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/Cocoa/WKWebsiteDataStorePrivate.h.

Memory used only for background/nonactivating verification preference:
`/Users/utpalrohan/.codex/memories/MEMORY.md`, line 72;
rollout ID `01a1588f-a52e-72e3-94bf-04a42699c784`.
