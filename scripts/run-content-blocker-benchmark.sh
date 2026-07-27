#!/bin/sh

set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

mkdir -p "$project_root/.build"
output_directory=$(
    mktemp -d "$project_root/.build/ContentBlockerBenchmark.XXXXXX"
)
result_bundle="$output_directory/BrowserContentBlocker.xcresult"
build_log="$output_directory/xcodebuild.log"

if ! xcodebuild \
    -project "$project_root/Browser.xcodeproj" \
    -scheme Browser \
    -configuration Release \
    -destination "platform=macOS,arch=arm64" \
    -derivedDataPath "$project_root/.build/ContentBlockerDerivedData" \
    -resultBundlePath "$result_bundle" \
    -parallel-testing-enabled NO \
    -test-timeouts-enabled YES \
    -default-test-execution-time-allowance 120 \
    -maximum-test-execution-time-allowance 120 \
    -only-testing:BrowserTests/ContentBlockerPerformanceTests/testProductionCachedLookupAndSynchronousAttachmentPerformance \
    ENABLE_TESTABILITY=YES \
    ENABLE_HARDENED_RUNTIME=NO \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=YES \
    OTHER_CODE_SIGN_FLAGS= \
    CLANG_ENABLE_CODE_COVERAGE=NO \
    ENABLE_CODE_COVERAGE=NO \
    test >"$build_log" 2>&1
then
    cat "$build_log"
    exit 1
fi

benchmark_result=$(
    sed -n \
        's/.*BROWSER_BLOCKER_BENCHMARK=\({.*}\)$/\1/p' \
        "$build_log" | tail -n 1
)
if [ -z "$benchmark_result" ]; then
    echo "The blocker benchmark produced no parseable result." >&2
    echo "See $build_log" >&2
    exit 1
fi

echo "Content-blocker benchmark passed."
echo "$benchmark_result"
echo "Artifacts: $output_directory"
