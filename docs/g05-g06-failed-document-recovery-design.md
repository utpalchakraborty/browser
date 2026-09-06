# G05–G06: failed-document recovery and benchmark acceptance

Date: 2026-09-06. Owner requested continuing G05/G06 after interruption. Starting checkout: clean local main at `8350f3d`, with G01–G04 already committed and smoke accepted.

## G05 design

Retain a transient, uniquely identified recovery destination only for the current failed provisional main-document navigation. Use WebKit's failing URL when supplied, otherwise the latest approved attempt URL; the blocked-redirect case below requires special handling. The existing navigation-token state rejects superseded failures. Cancelled, TLS, non-web, post-commit, and unsupported navigation errors do not offer this exception recovery. Clear the recovery identity on replacement navigation, commit, other errors, and close.

When that failure is selected, the Privacy site command explicitly says `Disable Blocking for <exact host> and Retry Failed Page`. Bind menu validation to the tab and failure identity, and reject stale menu actions. Preserve the committed-page toggle otherwise. An exception is an explicit user choice; failure alone changes no persistent policy. Disable recovery if protection is unavailable, the site is already excepted, or any affected tab is navigating.

Apply the failed host's exception before retrying its exact URL so a main-document rule can be bypassed. Ordinary navigation and redirects continue to strengthen protection only until commit. Restore committed-page policy if starting the retry fails. Reuse the existing exact-host cross-tab synchronization: idle committed same-host tabs reload under the chosen policy; unrelated tabs stay untouched. A background failed tab is not silently retried. Do not bypass TLS or scheme validation.

## Verification

Add hidden, nonactivating AppKit/WebKit fixtures using disposable rules, defaults, and website data. Exercise first-load document blocking, a block after another host, redirect destination, stale failure/menu actions, replacement navigation, and same-host background synchronization through the actual controller action. Run isolated DebugTesting and ReleaseTesting suites plus production Release package verification. Keep visible desktop-driving acceptance separate.

G06's source dependency fix is already committed. Rebuild the standalone benchmark and supported performance build path, then run the 10,000-bookmark workload by itself at the existing reduced scheduling priority and unchanged 100 ms load / 50 ms search p95 budgets. Record current measurements without replacing the historical interactive performance baseline. No production data or desktop input is required.

## Runtime refinement

The hidden redirect fixture exposed WebKitErrorDomain/104 with the **original** URL and navigation token after the final destination action, with no redirect callback. That action is an unbound successor in the existing state machine. After yielding to queued callbacks, recover the final approved URL only if WebKit is idle, the failed token was the immediate provisional predecessor, and the same generation, URL, and unbound approved action remain. A newer request, bound navigation, committed predecessor, closed tab, or active load rejects settlement. This sets error/recovery presentation only; the user must still explicitly choose the named host before any exception is written or protection relaxed. Ordinary failure handling continues to reject stale tokens.

The public SDK does not expose a server-redirect flag or action navigation token; WebKit exposes those through private interfaces, which this change does not use ([WebKit implementation](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/Cocoa/WKNavigationAction.mm)). The idle settlement is deliberately scoped to the runtime-observed content-blocking error; other ambiguous failures remain guarded.

Controller installation is factored out of the visible-window startup wrapper so hidden tests execute the production installation and command paths. Normal startup retains its existing visible-window precondition.

## Verification outcome

Final DebugTesting and ReleaseTesting each pass 167 background tests, including six hidden recovery runtime cases and two additional state-machine cases. The supported performance build and clean standalone compilation pass. The 10,000-bookmark workload passes unchanged gates: 56.974 ms load p95, 17.184 ms repository search p95, and 16.869 ms manager filter p95. See [audit evidence](codebase-review-2026-09-06.md) for artifacts and scope. The owner subsequently accepted G05/G06 and authorized local commit/merge on 2026-09-06. The slice is integrated directly on the existing `main` branch. Specific manual smoke scenarios were not reported; interactive automation remains a separate follow-up. No remote push was requested.
