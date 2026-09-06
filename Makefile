.NOTPARALLEL:

PROJECT := Browser.xcodeproj
SCHEME := Browser
DERIVED_DATA := .build/DerivedData
BROWSER_BUILD_JOBS ?= 2
export BROWSER_BUILD_JOBS

DESTINATION := platform=macOS,arch=arm64

.PHONY: build release run verify-release test release-test ui-test performance-build performance \
	interactive-test bookmark-benchmark profile-probe blocker-benchmark resource-one resource-ten network-audit \
	container-audit container-audit-test webcontent-termination check clean

build:
	nice -n 10 xcodebuild -jobs "$(BROWSER_BUILD_JOBS)" \
		SWIFT_USE_PARALLEL_WHOLE_MODULE_OPTIMIZATION=NO \
		'OTHER_SWIFT_FLAGS=$$(inherited) -num-threads 1 -driver-batch-count $(BROWSER_BUILD_JOBS)' \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration Debug \
		-destination "$(DESTINATION)" \
		-derivedDataPath "$(DERIVED_DATA)" \
		build

release:
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

run: release
	open "$(DERIVED_DATA)/Build/Products/Release/Browser.app"

verify-release: release
	./scripts/verify-release.sh "$(DERIVED_DATA)/Build/Products/Release/Browser.app"

test:
	./scripts/run-tests.sh

release-test:
	./scripts/run-tests.sh --release

interactive-test:
	./scripts/run-tests.sh --interactive
	./scripts/run-tests.sh --ui-only

bookmark-benchmark:
	./scripts/run-bookmark-benchmark.sh

ui-test:
	./scripts/run-tests.sh --ui-only

performance-build:
	./scripts/run-performance-tests.sh --build-only

performance:
	@test "$(INTERACTIVE)" = 1 || (echo "Use make performance INTERACTIVE=1 when desktop input is available."; exit 2)
	./scripts/run-performance-tests.sh --interactive

profile-probe:
	./scripts/run-cross-process-profile-probe.sh

blocker-benchmark:
	./scripts/run-content-blocker-benchmark.sh

resource-one: verify-release
	./scripts/measure-resources.sh --views 1

resource-ten: verify-release
	./scripts/measure-resources.sh --views 10

network-audit: verify-release
	./scripts/audit-blank-network.sh

container-audit:
	./scripts/audit-container.sh

container-audit-test:
	./scripts/test-audit-container.sh

webcontent-termination: verify-release
	./scripts/probe-webcontent-termination.sh

check: build test release-test verify-release

clean:
	nice -n 10 xcodebuild -jobs "$(BROWSER_BUILD_JOBS)" \
		SWIFT_USE_PARALLEL_WHOLE_MODULE_OPTIMIZATION=NO \
		'OTHER_SWIFT_FLAGS=$$(inherited) -num-threads 1 -driver-batch-count $(BROWSER_BUILD_JOBS)' \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-derivedDataPath "$(DERIVED_DATA)" \
		clean
