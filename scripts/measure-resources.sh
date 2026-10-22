#!/bin/sh

set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
application="$project_root/.build/DerivedData/Build/Products/Release/Browser.app"
executable="$application/Contents/MacOS/Browser"
fixture_script="$project_root/TestSupport/fixture_server.py"
view_count=1
memory_samples=10
cpu_samples=30
settle_seconds=10

usage() {
    echo "usage: $0 [--views 1|10] [--memory-samples N] [--cpu-samples N]" >&2
}

require_nonnegative_integer() {
    case "$2" in
        "" | *[!0-9]*)
            echo "$1 must be a nonnegative integer." >&2
            exit 2
            ;;
    esac
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --views)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            view_count=$2
            shift 2
            ;;
        --memory-samples)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            memory_samples=$2
            shift 2
            ;;
        --cpu-samples)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            cpu_samples=$2
            shift 2
            ;;
        *)
            usage
            exit 2
            ;;
    esac
done

case "$view_count" in
    1 | 10)
        ;;
    *)
        echo "--views must be 1 or 10." >&2
        exit 2
        ;;
esac
require_nonnegative_integer "--memory-samples" "$memory_samples"
require_nonnegative_integer "--cpu-samples" "$cpu_samples"

if [ ! -x "$executable" ]; then
    echo "Release application not found; run 'make verify-release' first." >&2
    exit 1
fi

mkdir -p "$project_root/.build"
output_directory=$(
    mktemp -d "$project_root/.build/ResourceBaseline.v${view_count}.XXXXXX"
)
"$project_root/scripts/prune-results.sh" "ResourceBaseline.v${view_count}"
fixture_pid=""
browser_pid=""
helper_pids=""

webkit_pids() {
    /bin/ps -axo pid=,args= |
        /usr/bin/awk \
            '/\/com[.]apple[.]WebKit[.](GPU|Networking|WebContent)[.]xpc\// { print $1 }' |
        LC_ALL=C /usr/bin/sort
}

webkit_processes() {
    /bin/ps -axo pid=,args= |
        /usr/bin/awk \
            '/\/com[.]apple[.]WebKit[.](GPU|Networking|WebContent)[.]xpc\//'
}

new_pids() {
    /usr/bin/awk \
        'FILENAME == ARGV[1] { existing[$1] = 1; next }
         !existing[$1] { print $1 }' \
        "$1" "$2"
}

wait_for_exit() {
    target_pids=$1
    attempt=0
    while [ "$attempt" -lt 50 ]; do
        running=""
        for target_pid in $target_pids; do
            if kill -0 "$target_pid" 2>/dev/null; then
                running="$running $target_pid"
            fi
        done
        [ -n "$running" ] || return 0
        attempt=$((attempt + 1))
        sleep 0.1
    done
    return 1
}

is_browser_process() {
    candidate_pid=$1
    candidate_executable=$(
        /bin/ps -p "$candidate_pid" -o comm= 2>/dev/null |
            /usr/bin/sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
    )
    [ "$candidate_executable" = "$executable" ]
}

is_fixture_process() {
    candidate_pid=$1
    candidate_arguments=$(
        /bin/ps -p "$candidate_pid" -o args= 2>/dev/null || true
    )
    case "$candidate_arguments" in
        *"$fixture_script"*"--port $fixture_port"*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

stop_browser() {
    stopped_helper_pids=$helper_pids
    if [ -n "$browser_pid" ] && kill -0 "$browser_pid" 2>/dev/null; then
        if ! is_browser_process "$browser_pid"; then
            echo "Refusing to signal a Browser PID with a different executable: $browser_pid" >&2
            return 1
        fi
        kill -TERM "$browser_pid" 2>/dev/null || true
        if ! wait_for_exit "$browser_pid"; then
            if ! is_browser_process "$browser_pid"; then
                echo "Browser PID changed identity before force-stop: $browser_pid" >&2
                return 1
            fi
            kill -KILL "$browser_pid" 2>/dev/null || true
        fi
    fi
    [ -z "$browser_pid" ] || wait "$browser_pid" 2>/dev/null || true
    browser_pid=""
    if [ -n "$stopped_helper_pids" ] && ! wait_for_exit "$stopped_helper_pids"; then
        echo "WebKit helpers did not exit after Browser terminated: $stopped_helper_pids" >&2
        return 1
    fi
    helper_pids=""
}

cleanup() {
    stop_browser || true
    if [ -n "$fixture_pid" ]; then
        if kill -0 "$fixture_pid" 2>/dev/null && is_fixture_process "$fixture_pid"; then
            kill "$fixture_pid" 2>/dev/null || true
        fi
        wait "$fixture_pid" 2>/dev/null || true
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if /usr/bin/pgrep -f "$executable" >/dev/null; then
    echo "Browser is already running; close it before measuring." >&2
    exit 1
fi

fixture_url=""
if [ "$view_count" -eq 10 ]; then
    fixture_port=18765
    fixture_token=${output_directory##*.}
    fixture_url="http://127.0.0.1:$fixture_port/normal/"
    /usr/bin/python3 \
        "$fixture_script" \
        --port "$fixture_port" \
        --token "$fixture_token" \
        >"$output_directory/fixture-server.log" 2>&1 &
    fixture_pid=$!

    attempt=0
    until /usr/bin/curl --fail --silent --connect-timeout 1 --max-time 2 --show-error \
        "http://127.0.0.1:$fixture_port/health?token=$fixture_token" \
        >/dev/null
    do
        attempt=$((attempt + 1))
        if [ "$attempt" -ge 50 ]; then
            echo "Fixture server did not become ready." >&2
            exit 1
        fi
        sleep 0.1
    done
fi

launch_browser() {
    browser_log=$1
    if [ "$view_count" -eq 10 ]; then
        "$executable" \
            --performance-test \
            --performance-view-count "$view_count" \
            --performance-fixture-url "$fixture_url" \
            -ApplePersistenceIgnoreState YES \
            >"$browser_log" 2>&1 &
    else
        "$executable" \
            --performance-test \
            -ApplePersistenceIgnoreState YES \
            >"$browser_log" 2>&1 &
    fi
    browser_pid=$!
}

wait_for_fixture_views() {
    sample_prefix=$1
    attempt=0
    while [ "$attempt" -lt 100 ]; do
        if /usr/bin/curl --fail --silent --connect-timeout 1 --max-time 2 --show-error \
            "http://127.0.0.1:$fixture_port/stats" \
            >"$sample_prefix.fixture-stats.json" && \
            /usr/bin/python3 -c \
                'import json, sys
data = json.load(open(sys.argv[1]))
expected = int(sys.argv[2])
raise SystemExit(0 if data.get("/normal/", 0) >= expected and data.get("/assets/blocked.js", 0) >= expected else 1)' \
                "$sample_prefix.fixture-stats.json" "$view_count"
        then
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 0.1
    done
    echo "Expected fixture requests from all $view_count views were not observed." >&2
    return 1
}

verify_helper_set() {
    sample_prefix=$1
    webkit_pids >"$sample_prefix.webkit-measured.txt"
    measured_helper_pids=$(new_pids \
        "$sample_prefix.webkit-before.txt" \
        "$sample_prefix.webkit-measured.txt" | /usr/bin/tr '\n' ' ')
    if [ "$measured_helper_pids" != "$helper_pids" ]; then
        echo "WebKit helper set changed during measurement." >&2
        echo "Started with: $helper_pids" >&2
        echo "Ended with: $measured_helper_pids" >&2
        return 1
    fi
}

discover_helpers() {
    sample_prefix=$1
    webkit_pids >"${sample_prefix}.webkit-before.txt"
    webkit_processes >"${sample_prefix}.webkit-before-processes.txt"
    if [ "$view_count" -eq 10 ]; then
        /usr/bin/curl --fail --silent --connect-timeout 1 --max-time 2 --show-error \
            "http://127.0.0.1:$fixture_port/reset" >/dev/null
    fi
    launch_browser "${sample_prefix}.browser.log"

    if ! kill -0 "$browser_pid" 2>/dev/null; then
        echo "Browser exited before measurement; see ${sample_prefix}.browser.log" >&2
        exit 1
    fi

    if [ "$view_count" -eq 10 ]; then
        wait_for_fixture_views "$sample_prefix"
    fi
    sleep "$settle_seconds"

    webkit_pids >"${sample_prefix}.webkit-after.txt"
    webkit_processes >"${sample_prefix}.webkit-after-processes.txt"
    helper_pids=$(
        new_pids \
            "${sample_prefix}.webkit-before.txt" \
            "${sample_prefix}.webkit-after.txt" |
            /usr/bin/tr '\n' ' '
    )
    if [ -z "$helper_pids" ]; then
        echo "No new WebKit helper processes were discovered." >&2
        exit 1
    fi
    echo "$browser_pid $helper_pids" >"${sample_prefix}.pids.txt"
    for helper_pid in $helper_pids; do
        /bin/ps -p "$helper_pid" -o pid=,args=
    done >"${sample_prefix}.attributed-processes.txt"
}

# WebKit and the GPU stack perform one-time process and cache initialization on
# the first launch after a build. The settled-memory gate intentionally uses a
# recorded but excluded warm-up, matching the benchmark protocol in the plan.
if [ "$memory_samples" -gt 0 ] || [ "$cpu_samples" -gt 0 ]; then
    prefix="$output_directory/warmup"
    discover_helpers "$prefix"
    verify_helper_set "$prefix"
    stop_browser
fi

sample=1
while [ "$sample" -le "$memory_samples" ]; do
    prefix="$output_directory/memory-$sample"
    discover_helpers "$prefix"
    # Explicit PIDs are required because WebKit XPC helpers have launchd as parent.
    /usr/bin/footprint \
        -f bytes \
        -j "$prefix.footprint.json" \
        "$browser_pid" $helper_pids \
        >"$prefix.footprint.txt"
    verify_helper_set "$prefix"
    stop_browser
    sample=$((sample + 1))
done

if [ "$cpu_samples" -gt 0 ]; then
    prefix="$output_directory/cpu"
    discover_helpers "$prefix"
    set -- -pid "$browser_pid"
    for helper_pid in $helper_pids; do
        set -- "$@" -pid "$helper_pid"
    done
    /usr/bin/top \
        -l "$((cpu_samples + 1))" \
        -s 1 \
        -F \
        -R \
        -stats pid,command,cpu,mem \
        "$@" \
        >"$prefix.top.txt"
    verify_helper_set "$prefix"
    stop_browser
fi

/usr/bin/python3 "$project_root/scripts/summarize-resources.py" \
    --directory "$output_directory" \
    --views "$view_count" \
    --cpu-samples "$cpu_samples"
