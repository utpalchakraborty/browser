# G03–G04: consistent bookmark saves and window-owned Close

Date: 2026-09-06. Authorized after the owner smoke-tested G01/G02, committed as `76f7c28` on local main.

## G03 decision and protocol

Choose rollback semantics: an operation that throws has not committed. Add/update/delete, explicit reset, and backup restore all use one transaction protocol. Preserve the existing schema-1 primary/backup files and successful edit/delete scrubbing of both active copies.

Before modifying either active file, atomically write `Bookmarks.transaction.json` containing the exact previous bytes (or absence) of primary and backup. Then update both active files. Removing the journal is the commit point; only afterward publish the new in-memory state. On any write/delete failure, restore both prior images and remove the journal, then report the original failure. Restoring an already matching image is a no-op. If rollback itself fails, retain the journal and report recovery-required; future loads and mutations must resolve it before interpreting either active file. A malformed journal fails closed without changing or trusting active files. The transaction uses fixed local filenames, not paths supplied by journal data.

This handles process interruption before/after each durable step. It does not claim sudden-power-loss guarantees beyond Foundation's atomic file replacement, or coordinate simultaneous independent writers (the app has one repository actor). Reset uses the same protocol with absent target files; restore uses the recovered valid backup for both targets. Reset preserves a corrupt primary even if no earlier load happened.

At most one transient journal exists. A successful commit leaves no journal and both active copies aligned. A failed/incomplete transaction may retain previous URLs in its recovery journal until rollback succeeds; the UI reports that storage recovery is required. Rollback to an older app build is safe only after the journal has been resolved by this version; do not manually delete an unresolved journal. No normal-data migration is required.

For corrupt-input preservation, use SHA-256 filenames, verify bytes before reusing a matching artifact, and reuse any byte-identical legacy UUID artifact. Preserve distinct input separately; do not delete existing artifacts. Unexpected name collisions create a new preserved file instead of overwriting an original.

## G04 Close ownership

Install a small menu-command owner that resolves `NSApp.keyWindow` at action and validation time. If that exact window is the main browser, close its selected tab through the existing tab lifecycle. Otherwise call the key auxiliary window's native `performClose`. With no key window, an attached sheet, or a sheet as key window, disable Close and do nothing if invoked. Keep explicit Close Window (Shift-Command-W) and title-bar window closure unchanged.

The menu title reflects Close Tab or Close Window. Retain sole-tab replacement, neighbor selection, page state, and local-grant teardown in the existing tab code. The command owner retains no windows and does not fall back to the background browser.

## Verification and limits

Use temporary repositories with injected failures at journal creation, each active write/delete, journal removal, rollback, and interrupted-transaction recovery. Cover first add, later add, edit, delete, reset, restore, cached/fresh loads, backup recovery, malformed journals, and three repeated corruption loads. Assert exact prior bytes after failed operations, no stale URLs/journal after success, and one preserved copy per distinct input.

For Close, dispatch real Command-W key equivalents through the production-created NSMenuItem in hidden AppKit fixtures. Inject only the active-window lookup; test browser address/content responders and Bookmarks/Privacy controllers, menu validation, no-window and simulated sheet ownership, queued tab state, sole-tab replacement, and neighbor selection. These checks verify native menu dispatch and action routing but do not establish desktop focus/visible sheet behavior. Add explicit XCUI acceptance cases and compile them; do not execute desktop-driving tests on the owner's active desktop. The owner-reported smoke acceptance applies to G01/G02, not these new changes.

Run the bounded Debug/Release background suites and production Release verification. No benchmark workload or live-data recovery run is authorized by this slice. Leave G03/G04 reviewable for their own smoke acceptance.

## Implemented outcome

G01/G02 were committed as `76f7c28`. G03/G04 are implemented, owner-smoke-accepted, and authorized for local commit. Final DebugTesting and ReleaseTesting each passed 159 background tests, including 23 mutation-failure cases and 18 interrupted-state fixtures. UI acceptance cases and the standalone bookmark benchmark compile without execution. Production Release signature/architecture/sandbox/hardened-runtime/pinned-asset verification passed. Exact artifacts and remaining visible/manual gates are recorded in [the audit](codebase-review-2026-09-06.md).

Owner acceptance (2026-09-06): user reported successful smoke testing and authorized committing this slice. Specific manual cases were not itemized; automated interactive and performance workloads remain unrun.
