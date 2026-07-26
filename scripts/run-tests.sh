#!/bin/sh

set -eu

ui_only=0
unit_only=0
configuration=Debug

while [ "$#" -gt 0 ]; do
    case "$1" in
        --ui-only)
            ui_only=1
            ;;
        --unit-only)
            unit_only=1
            ;;
        --release)
            configuration=Release
            ;;
        *)
            echo "usage: $0 [--ui-only | --unit-only] [--release]" >&2
            exit 2
            ;;
    esac
    shift
done

if [ "$ui_only" -eq 1 ] && [ "$unit_only" -eq 1 ]; then
    echo "--ui-only and --unit-only are mutually exclusive" >&2
    exit 2
fi

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if [ "$configuration" = "Release" ]; then
    derived_data="$project_root/.build/ReleaseTestDerivedData"
else
    derived_data="$project_root/.build/DerivedData"
fi
fixture_port=18765
fixture_recovery_port=18769
fixture_log="$project_root/.build/fixture-server.log"

mkdir -p "$project_root/.build"

result_directory=$(
    mktemp -d "$project_root/.build/TestResults.XXXXXX"
)
result_bundle="$result_directory/Browser.xcresult"
fixture_token=${result_directory##*.}

/usr/bin/python3 \
    "$project_root/TestSupport/fixture_server.py" \
    --port "$fixture_port" \
    --token "$fixture_token" \
    --recovery-port "$fixture_recovery_port" \
    >"$fixture_log" 2>&1 &
fixture_pid=$!

cleanup() {
    kill "$fixture_pid" 2>/dev/null || true
    wait "$fixture_pid" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

attempt=0
until /usr/bin/curl --fail --silent --show-error \
    "http://127.0.0.1:$fixture_port/health?token=$fixture_token" >/dev/null
do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 50 ]; then
        echo "Fixture server did not become ready. See $fixture_log" >&2
        exit 1
    fi
    sleep 0.1
done

set -- xcodebuild \
    -project "$project_root/Browser.xcodeproj" \
    -scheme Browser \
    -configuration "$configuration" \
    -destination "platform=macOS,arch=arm64" \
    -derivedDataPath "$derived_data" \
    -enableCodeCoverage NO \
    -resultBundlePath "$result_bundle" \
    -parallel-testing-enabled NO

if [ "$configuration" = "Release" ]; then
    set -- "$@" ENABLE_TESTABILITY=YES
    if [ "$unit_only" -eq 1 ]; then
        set -- "$@" \
            ENABLE_HARDENED_RUNTIME=NO \
            OTHER_CODE_SIGN_FLAGS= \
            CODE_SIGN_INJECT_BASE_ENTITLEMENTS=YES
    fi
fi

if [ "$ui_only" -eq 1 ]; then
    set -- "$@" -only-testing:BrowserUITests
elif [ "$unit_only" -eq 1 ]; then
    set -- "$@" -only-testing:BrowserTests
fi

"$@" test
