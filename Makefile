PROJECT := Browser.xcodeproj
SCHEME := Browser
DERIVED_DATA := .build/DerivedData
DESTINATION := platform=macOS,arch=arm64

.PHONY: build release verify-release test performance-build performance \
	profile-probe blocker-benchmark resource-one resource-ten network-audit \
	webcontent-termination check clean

build:
	xcodebuild \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration Debug \
		-destination "$(DESTINATION)" \
		-derivedDataPath "$(DERIVED_DATA)" \
		build

release:
	xcodebuild \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration Release \
		-destination "$(DESTINATION)" \
		-derivedDataPath "$(DERIVED_DATA)" \
		ENABLE_CODE_COVERAGE=NO \
		build

verify-release: release
	./scripts/verify-release.sh

test:
	./scripts/run-tests.sh

performance-build:
	./scripts/run-performance-tests.sh --build-only

performance:
	./scripts/run-performance-tests.sh

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

webcontent-termination: verify-release
	./scripts/probe-webcontent-termination.sh

check: build test verify-release

clean:
	xcodebuild \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-derivedDataPath "$(DERIVED_DATA)" \
		clean
