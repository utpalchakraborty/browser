#!/bin/sh

set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
derived_data="$project_root/.build/PerformanceDerivedData"

case "${1:-}" in
    "")
        build_only=0
        ;;
    --build-only)
        build_only=1
        ;;
    *)
        echo "usage: $0 [--build-only]" >&2
        exit 2
        ;;
esac

mkdir -p "$project_root/.build"

xcodebuild \
    -project "$project_root/Browser.xcodeproj" \
    -scheme BrowserPerformance \
    -configuration Release \
    -destination "platform=macOS,arch=arm64" \
    -derivedDataPath "$derived_data" \
    -enableCodeCoverage NO \
    -parallel-testing-enabled NO \
    build-for-testing

if [ "$build_only" -eq 1 ]; then
    exit 0
fi

result_directory=$(mktemp -d "$project_root/.build/PerformanceResults.XXXXXX")
launch_result_bundle="$result_directory/BrowserLaunchPerformance.xcresult"
interaction_result_bundle="$result_directory/BrowserInteractionPerformance.xcresult"
fixture_port=18768
fixture_token=${result_directory##*.}
fixture_origin="http://127.0.0.1:$fixture_port"
fixture_log="$result_directory/fixture-server.log"

/usr/bin/python3 \
    "$project_root/TestSupport/fixture_server.py" \
    --port "$fixture_port" \
    --token "$fixture_token" \
    >"$fixture_log" 2>&1 &
fixture_pid=$!

cleanup() {
    kill "$fixture_pid" 2>/dev/null || true
    wait "$fixture_pid" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

attempt=0
until /usr/bin/curl --fail --silent --show-error \
    "$fixture_origin/health?token=$fixture_token" >/dev/null
do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 50 ]; then
        echo "Performance fixture did not become ready. See $fixture_log" >&2
        exit 1
    fi
    sleep 0.1
done

xcodebuild \
    -project "$project_root/Browser.xcodeproj" \
    -scheme BrowserPerformance \
    -configuration Release \
    -destination "platform=macOS,arch=arm64" \
    -derivedDataPath "$derived_data" \
    -enableCodeCoverage NO \
    -parallel-testing-enabled NO \
    -only-testing:BrowserPerformanceTests/BrowserLaunchPerformanceTests/testFocusedSinglePageBrowserLaunch \
    -resultBundlePath "$launch_result_bundle" \
    test-without-building

xcodebuild \
    -project "$project_root/Browser.xcodeproj" \
    -scheme BrowserPerformance \
    -configuration Release \
    -destination "platform=macOS,arch=arm64" \
    -derivedDataPath "$derived_data" \
    -enableCodeCoverage NO \
    -parallel-testing-enabled NO \
    -only-testing:BrowserPerformanceTests/BrowserLaunchPerformanceTests/testDeterministicLocalNavigationAndCommandResponse \
    -only-testing:BrowserPerformanceTests/BrowserLaunchPerformanceTests/testBackAndForwardCommandResponse \
    -resultBundlePath "$interaction_result_bundle" \
    test-without-building

echo "Launch performance result bundle: $launch_result_bundle" >&2
echo "Interaction performance result bundle: $interaction_result_bundle" >&2
launch_metrics_json="$result_directory/launch-metrics.json"
interaction_metrics_json="$result_directory/interaction-metrics.json"
xcrun xcresulttool get test-results metrics \
    --path "$launch_result_bundle" \
    --compact \
    >"$launch_metrics_json"
xcrun xcresulttool get test-results metrics \
    --path "$interaction_result_bundle" \
    --compact \
    >"$interaction_metrics_json"
/usr/bin/python3 "$project_root/scripts/summarize-launch-metrics.py" \
    --metrics "$launch_metrics_json" "$interaction_metrics_json" \
    --baseline "$project_root/TestSupport/phase2_performance_baseline.json"
