# G01–G02: address privacy and usable background verification

Date: 2026-09-06. Implementation authorized by the user for audit groups G01 and G02.
Baseline: main at ea6528921be27d8d0a3ef9a2c7df955daa2b591c.

## Intended behavior

A pasted magnet URI is an unsupported address, including mixed-case schemes and surrounding whitespace. Submission shows the existing Unsupported Address error, queues no navigation, and invokes no external opener. Direct ordinary pointer activation of a magnet link retains the existing NavigationPolicy behavior. Host:port addresses and colon-containing prose retain their existing interpretation.

Routine verification must leave the desktop usable. DebugTesting and ReleaseTesting build a separate `com.utpalchakraborty.browser.testhost` app. Its background startup sets prohibited activation before the run loop and creates no application window, bookmarks, profile, or content blocker. Launch configuration owns test/production identity, preferences, bookmarks, WebKit identifiers, geometry, and reset policy. Production Debug/Release retain their existing identity and behavior.

The default Browser test action selects an explicit list of reviewed background test classes. Classes that show windows and XCUI suites remain available through explicit interactive schemes/commands. A new hidden-window submission regression exercises the real address action without showing the window. Unknown/new test classes require review before admission to the background list. Tests cannot claim visible UI acceptance from hidden fixtures.

## Commands and resource ownership

`make test`, `make release-test`, and `make check` run background correctness checks only. Builds default to two jobs, configurable through BROWSER_BUILD_JOBS (positive integer, at most 8), and tests run serially. Swift batches use that limit; automatic whole-module compiler fan-out is disabled and an explicit `-num-threads 1` preserves per-file object emission (Xcode otherwise selected 32 threads even with two build jobs). Background runners lower scheduling priority (explicit interactive timing gates retain the caller's priority) and use a shared exclusive lock to prevent overlapping verification runs. Each run owns its fixture processes, logs, and result bundle. SIGINT/SIGTERM terminates its process groups; test-host cleanup is restricted to newly launched executables inside the dedicated Testing products directory, never process names or the production Browser path.

`make interactive-test` and `make ui-test` explicitly opt into desktop-driving tests. `make performance` requires INTERACTIVE=1; the script likewise requires --interactive. Performance builds are available without execution. The standalone bookmark benchmark and background blocker benchmark are separately invocable; neither invokes XCUI performance tests. Adding the missing LocalFileAccess.swift source to the bookmark compiler is necessary to deliver that G02 separation and overlaps IN-01/G06.

The background path is bounded concurrency, not a hard CPU/RAM quota. WebKit/compiler subprocesses still consume resources; timing during ordinary desktop use is diagnostic, and controlled UI timing remains a separate, deferred gate.

## Verification and acceptance

Run interpreter and real hidden-controller regressions, launch-configuration isolation tests, Debug/Release background suites, runner cancellation/lock tests with disposable child processes, and build-only checks of interactive targets. Verify built test identity and background activation policy. Inspect actual foreground application/window state during an isolated background run without activating another app. Do not run the interactive suites or performance workloads during this remediation session. Preserve production settings and existing audit evidence; report unexecuted gates explicitly.

## Toolchain detail

With this installed Xcode, disabling automatic parallel WMO alone omitted the thread flag, causing missing per-file objects on a fresh performance build and allowing stale objects in an incremental build. The final commands also specify `-num-threads 1`, consistent with the [Swift build compiler implementation](https://github.com/swiftlang/swift-build/blob/main/Sources/SWBCore/SpecImplementations/Tools/SwiftCompiler.swift). Generated outputs from the intermediate attempt were moved aside and the final products rebuilt fresh. Results from that intermediate attempt are not acceptance evidence.

## Implemented outcome

Implemented and verified for background use. Fresh DebugTesting and ReleaseTesting each pass 147 tests; four runner tests pass; build-only UI/performance and standalone benchmark compilation pass; production Release verification passes. Passive monitoring recorded 766 samples without a foreground change. Detailed artifacts, intermediate toolchain-check supersession, and deferred interactive gates are recorded in [the audit](codebase-review-2026-09-06.md#g01g02-remediation--2026-09-06-current-checkpoint). Subsequently committed on local main as `76f7c28` after owner smoke acceptance.

Owner acceptance (2026-09-06): user reported successful smoke testing and authorized committing this slice before G03/G04.
