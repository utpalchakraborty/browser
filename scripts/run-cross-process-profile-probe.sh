#!/bin/sh

set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
fixture_port=18766

mkdir -p "$project_root/.build"
output_directory=$(
    mktemp -d "$project_root/.build/ActualAppProfileProbe.XXXXXX"
)
"$project_root/scripts/prune-results.sh" ActualAppProfileProbe
fixture_log="$output_directory/fixture-server.log"
fixture_token=${output_directory##*.}

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
until /usr/bin/curl --fail --silent --connect-timeout 1 --max-time 2 \
    "http://127.0.0.1:$fixture_port/health?token=$fixture_token" \
    >/dev/null 2>&1
do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 50 ]; then
        echo "Fixture server did not become ready. See $fixture_log" >&2
        exit 1
    fi
    sleep 0.1
done

derived_data="$project_root/.build/ActualAppProfileDerivedData"
build_log="$output_directory/build.log"
if ! xcodebuild \
    -project "$project_root/Browser.xcodeproj" \
    -scheme Browser \
    -configuration Debug \
    -destination "platform=macOS,arch=arm64" \
    -derivedDataPath "$derived_data" \
    build >"$build_log" 2>&1
then
    cat "$build_log"
    exit 1
fi

browser_executable="$derived_data/Build/Products/Debug/Browser.app/Contents/MacOS/Browser"
if [ ! -x "$browser_executable" ]; then
    echo "Debug Browser executable was not produced." >&2
    exit 1
fi

fixture_origin="http://127.0.0.1:$fixture_port/"
last_pid=""
last_cookie_result=""

field_from_line() {
    field_name=$1
    line=$2
    printf '%s\n' "$line" \
        | tr ' ' '\n' \
        | sed -n "s/^$field_name=//p" \
        | tail -n 1
}

run_step() {
    phase=$1
    step_log="$output_directory/$phase.log"
    timeout_marker="$output_directory/$phase.timeout"

    "$browser_executable" \
        --profile-persistence-probe \
        --profile-probe-phase "$phase" \
        --profile-probe-fixture-origin "$fixture_origin" \
        >"$step_log" 2>&1 &
    browser_pid=$!

    (
        sleep 30
        running_executable=$(
            ps -p "$browser_pid" -o comm= 2>/dev/null \
                | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
        )
        if [ "$running_executable" = "$browser_executable" ]; then
            : >"$timeout_marker"
            kill "$browser_pid" 2>/dev/null || true
        fi
    ) &
    watchdog_pid=$!

    if wait "$browser_pid"; then
        browser_status=0
    else
        browser_status=$?
    fi
    kill "$watchdog_pid" 2>/dev/null || true
    wait "$watchdog_pid" 2>/dev/null || true

    if [ -f "$timeout_marker" ]; then
        echo "Browser profile probe phase '$phase' timed out." >&2
        cat "$step_log"
        exit 1
    fi
    if [ "$browser_status" -ne 0 ]; then
        echo "Browser profile probe phase '$phase' exited with status $browser_status." >&2
        cat "$step_log"
        exit 1
    fi

    result_line=$(sed -n '/^BROWSER_PROFILE_PROBE /p' "$step_log" | tail -n 1)
    if [ -z "$result_line" ]; then
        echo "Browser profile probe phase '$phase' emitted no result." >&2
        cat "$step_log"
        exit 1
    fi

    reported_phase=$(field_from_line phase "$result_line")
    reported_pid=$(field_from_line pid "$result_line")
    reported_status=$(field_from_line status "$result_line")
    if [ "$reported_phase" != "$phase" ] \
        || [ "$reported_pid" != "$browser_pid" ] \
        || [ "$reported_status" != "passed" ]
    then
        echo "Browser profile probe phase '$phase' reported failure." >&2
        echo "$result_line" >&2
        exit 1
    fi

    last_pid=$reported_pid
    last_cookie_result=$(
        field_from_line cookie-survived "$result_line"
    )
}

run_step write
first_pid=$last_pid

run_step read-delete
second_pid=$last_pid
cookie_survived=$last_cookie_result
case "$cookie_survived" in
    true)
        ;;
    *)
        echo "The persistent Max-Age cookie did not survive relaunch." >&2
        exit 1
        ;;
esac

run_step verify-deleted
third_pid=$last_pid

if [ "$first_pid" = "$second_pid" ] \
    || [ "$first_pid" = "$third_pid" ] \
    || [ "$second_pid" = "$third_pid" ]
then
    echo "The profile probe did not use three distinct app processes." >&2
    exit 1
fi

echo "Actual-app cross-process profile probe passed."
echo "Browser process IDs: $first_pid, $second_pid, $third_pid"
echo "Persistent Max-Age cookie survived graceful relaunch: $cookie_survived"
echo "Artifacts: $output_directory"
