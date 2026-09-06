#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if [ "${BROWSER_VERIFICATION_SUPERVISED:-}" != 1 ]; then
    exec /usr/bin/python3 "$project_root/scripts/verification-session.py" "$0" "$@"
fi
configuration=DebugTesting
scheme=Browser
build_only=0
mode=background
selection_count=0
for argument in "$@"; do
    case "$argument" in
        --release) configuration=ReleaseTesting ;;
        --unit-only) selection_count=$((selection_count + 1)) ;; # compatibility: the default already contains only background units
        --interactive) selection_count=$((selection_count + 1)); scheme=BrowserInteractive; mode=interactive ;;
        --ui-only) selection_count=$((selection_count + 1)); scheme=BrowserUITests; mode=interactive ;;
        --blocker-benchmark) selection_count=$((selection_count + 1)); scheme=BrowserBenchmarks; configuration=ReleaseTesting; mode=benchmark ;;
        --build-only) build_only=1 ;;
        *) echo "usage: $0 [--release] [--interactive | --ui-only | --blocker-benchmark] [--build-only]" >&2; exit 2 ;;
    esac
done
if [ "$selection_count" -gt 1 ]; then echo "Choose only one test mode." >&2; exit 2; fi
result_directory=$(mktemp -d "$project_root/.build/TestResults.XXXXXX")
echo "Verification: $mode; $configuration; ${BROWSER_BUILD_JOBS} build jobs, serial tests. Artifacts: $result_directory"
if [ "$mode" = background ]; then
    echo "Deferred: desktop UI, visible-window tests, and performance benchmarks (explicit commands only)."
fi
fixture_log="$result_directory/fixture-server.log"
if [ "$build_only" -eq 0 ]; then
    /usr/bin/python3 "$project_root/TestSupport/fixture_server.py" \
        --port 18765 --recovery-port 18769 --token "${result_directory##*.}" >"$fixture_log" 2>&1 &
    fixture_pid=$!
    cleanup() { kill "$fixture_pid" 2>/dev/null || true; wait "$fixture_pid" 2>/dev/null || true; }
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    attempt=0
    until /usr/bin/curl --fail --silent "http://127.0.0.1:18765/health?token=${result_directory##*.}" >/dev/null; do
        attempt=$((attempt + 1))
        if [ "$attempt" -ge 50 ]; then echo "Fixture unavailable: $fixture_log" >&2; exit 1; fi
        sleep 0.1
    done
fi
action=test
if [ "$build_only" -eq 1 ]; then action=build-for-testing; fi
xcodebuild -project "$project_root/Browser.xcodeproj" -scheme "$scheme" \
    -configuration "$configuration" -destination "platform=macOS,arch=arm64" \
    -derivedDataPath "$project_root/.build/TestingDerivedData" \
    -jobs "$BROWSER_BUILD_JOBS" -enableCodeCoverage NO -parallel-testing-enabled NO \
    -test-timeouts-enabled YES -default-test-execution-time-allowance 60 \
    -maximum-test-execution-time-allowance 120 \
    -resultBundlePath "$result_directory/Browser.xcresult" \
    SWIFT_USE_PARALLEL_WHOLE_MODULE_OPTIMIZATION=NO \
    "OTHER_SWIFT_FLAGS=\$(inherited) -num-threads 1 -driver-batch-count $BROWSER_BUILD_JOBS" "$action" \
    >"$result_directory/xcodebuild.log" 2>&1 &
build_pid=$!
if wait "$build_pid"; then
    sed -n '/Executed .* tests, with /p' "$result_directory/xcodebuild.log" | tail -n 3
    if [ "$mode" = benchmark ]; then
        sed -n '/BROWSER_BLOCKER_BENCHMARK=/p' "$result_directory/xcodebuild.log"
    fi
    tail -n 8 "$result_directory/xcodebuild.log"
else
    result=$?
    tail -n 60 "$result_directory/xcodebuild.log" >&2
    exit "$result"
fi
