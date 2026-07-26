#!/bin/sh

set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
fixture_port=18765
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

xcodebuild \
    -project "$project_root/Browser.xcodeproj" \
    -scheme Browser \
    -configuration Debug \
    -destination "platform=macOS,arch=arm64" \
    -derivedDataPath "$project_root/.build/DerivedData" \
    -resultBundlePath "$result_bundle" \
    -parallel-testing-enabled NO \
    test
