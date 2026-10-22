.NOTPARALLEL:

PROJECT := Browser.xcodeproj
SCHEME := Browser
DERIVED_DATA := .build/DerivedData
BROWSER_BUILD_JOBS ?= 2
export BROWSER_BUILD_JOBS
# Validate before any recipe starts an unbounded build.
ifneq ($(words $(BROWSER_BUILD_JOBS)),1)
$(error BROWSER_BUILD_JOBS must be an integer from 1 to 8)
endif
ifeq ($(filter $(BROWSER_BUILD_JOBS),1 2 3 4 5 6 7 8),)
$(error BROWSER_BUILD_JOBS must be an integer from 1 to 8)
endif

DESTINATION := platform=macOS,arch=arm64

.PHONY: build release run run-release verify-release test release-test ui-test performance-build performance \
	interactive-test bookmark-benchmark profile-probe blocker-benchmark resource-one resource-ten network-audit \
	container-audit container-audit-test webcontent-termination check clean clean-results help

build: ## Build the Debug app (default target).
	nice -n 10 xcodebuild -jobs "$(BROWSER_BUILD_JOBS)" \
		SWIFT_USE_PARALLEL_WHOLE_MODULE_OPTIMIZATION=NO \
		'OTHER_SWIFT_FLAGS=$$(inherited) -num-threads 1 -driver-batch-count $(BROWSER_BUILD_JOBS)' \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration Debug \
		-destination "$(DESTINATION)" \
		-derivedDataPath "$(DERIVED_DATA)" \
		build

release: ## Build the Release app without code coverage.
	nice -n 10 xcodebuild -jobs "$(BROWSER_BUILD_JOBS)" \
		SWIFT_USE_PARALLEL_WHOLE_MODULE_OPTIMIZATION=NO \
		'OTHER_SWIFT_FLAGS=$$(inherited) -num-threads 1 -driver-batch-count $(BROWSER_BUILD_JOBS)' \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration Release \
		-destination "$(DESTINATION)" \
		-derivedDataPath "$(DERIVED_DATA)" \
		ENABLE_CODE_COVERAGE=NO \
		build

run: release ## Build and launch the Release app.
	open "$(DERIVED_DATA)/Build/Products/Release/Browser.app"

run-release: ## Launch the already-built Release app without rebuilding.
	@test -x "$(DERIVED_DATA)/Build/Products/Release/Browser.app/Contents/MacOS/Browser" || \
		{ echo "Release app not found. Run 'make release' first." >&2; exit 1; }
	open "$(DERIVED_DATA)/Build/Products/Release/Browser.app"

verify-release: release ## Build Release and verify signing, architecture, entitlements, and bundled assets.
	./scripts/verify-release.sh "$(DERIVED_DATA)/Build/Products/Release/Browser.app"

test: ## Run background Debug tests.
	./scripts/run-tests.sh

release-test: ## Run background Release tests.
	./scripts/run-tests.sh --release

interactive-test: ## Run visible-window AppKit tests and XCUI workflows (requires desktop input).
	./scripts/run-tests.sh --interactive
	./scripts/run-tests.sh --ui-only

bookmark-benchmark: ## Run the standalone background bookmark benchmark.
	./scripts/run-bookmark-benchmark.sh

ui-test: ## Run XCUI workflows only (requires desktop input).
	./scripts/run-tests.sh --ui-only

performance-build: ## Build the interactive performance tests without running them.
	./scripts/run-performance-tests.sh --build-only

performance: ## Run interactive performance tests; use make performance INTERACTIVE=1.
	@test "$(INTERACTIVE)" = 1 || (echo "Use make performance INTERACTIVE=1 when desktop input is available."; exit 2)
	./scripts/run-performance-tests.sh --interactive

profile-probe: ## Check profile persistence across actual app launches.
	./scripts/run-cross-process-profile-probe.sh

blocker-benchmark: ## Run the isolated background WebKit content-blocker benchmark.
	./scripts/run-content-blocker-benchmark.sh

resource-one: verify-release ## Build and verify Release, then measure resources with one resident tab.
	./scripts/measure-resources.sh --views 1

resource-ten: verify-release ## Build and verify Release, then measure resources with ten resident tabs.
	./scripts/measure-resources.sh --views 10

network-audit: verify-release ## Audit blank-launch and idle network traffic (requires Terminal and admin capture approval).
	./scripts/audit-blank-network.sh

container-audit: ## Inspect the Browser sandbox for persisted history or session data (read-only).
	./scripts/audit-container.sh

container-audit-test: ## Run the container-audit script's fixture tests.
	./scripts/test-audit-container.sh

webcontent-termination: verify-release ## Build and verify Release, then probe WebContent process termination handling.
	./scripts/probe-webcontent-termination.sh

check: build test release-test verify-release ## Build Debug, run background Debug/Release tests, and verify Release.

clean: ## Clean Xcode build products.
	nice -n 10 xcodebuild -jobs "$(BROWSER_BUILD_JOBS)" \
		SWIFT_USE_PARALLEL_WHOLE_MODULE_OPTIMIZATION=NO \
		'OTHER_SWIFT_FLAGS=$$(inherited) -num-threads 1 -driver-batch-count $(BROWSER_BUILD_JOBS)' \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-derivedDataPath "$(DERIVED_DATA)" \
		clean

clean-results: ## Keep only the newest BROWSER_KEEP_RESULTS (default 3) run-result directories of each kind.
	@for kind in TestResults PerformanceResults NetworkAudit ResourceBaseline.v1 ResourceBaseline.v10 \
		WebContentTermination ActualAppProfileProbe; do \
		./scripts/prune-results.sh "$$kind" || exit 1; \
	done

# Keep target descriptions in the ## comments above so help stays with each recipe.
help: ## List all targets and what they do.
	@printf 'Usage: make <target> [VARIABLE=value ...]\n\nTargets:\n'
	@awk 'BEGIN { FS = ":.*## " } /^[a-zA-Z0-9_-]+:.*## / { printf "  %-24s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
