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
result_bundle="$result_directory/BrowserPerformance.xcresult"

xcodebuild \
    -project "$project_root/Browser.xcodeproj" \
    -scheme BrowserPerformance \
    -configuration Release \
    -destination "platform=macOS,arch=arm64" \
    -derivedDataPath "$derived_data" \
    -enableCodeCoverage NO \
    -parallel-testing-enabled NO \
    -only-testing:BrowserPerformanceTests/BrowserLaunchPerformanceTests/testScaffoldLaunch \
    -resultBundlePath "$result_bundle" \
    test-without-building

echo "Performance result bundle: $result_bundle" >&2
metrics_json="$result_directory/metrics.json"
xcrun xcresulttool get test-results metrics \
    --path "$result_bundle" \
    --compact \
    >"$metrics_json"
/usr/bin/python3 "$project_root/scripts/summarize-launch-metrics.py" \
    --metrics "$metrics_json"
