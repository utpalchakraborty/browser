#!/bin/sh

set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
application="$project_root/.build/DerivedData/Build/Products/Release/Browser.app"
executable="$application/Contents/MacOS/Browser"
fixture_script="$project_root/TestSupport/fixture_server.py"
fixture_port=18767
idle_seconds=30
packet_snap_length=128
metadata_filter="(dir=out and (proc=Browser or eproc=Browser))"

usage() {
    echo "usage: $0" >&2
    echo "" >&2
    echo "Audits a verified Release Browser launch plus 30 seconds idle." >&2
    echo "Run this script from a normal interactive Terminal, not via sudo." >&2
}

if [ "$#" -gt 0 ]; then
    case "$1" in
        -h | --help)
            usage
            exit 0
            ;;
        *)
            usage
            exit 2
            ;;
    esac
fi

if [ "$(/usr/bin/id -u)" -eq 0 ]; then
    echo "Do not run the entire audit as root; it must launch Browser as you." >&2
    echo "The script invokes sudo only for packet capture." >&2
    exit 1
fi

for required_program in \
    /bin/ps \
    /usr/bin/awk \
    /usr/bin/curl \
    /usr/bin/python3 \
    /usr/bin/sudo \
    /usr/sbin/tcpdump
do
    if [ ! -x "$required_program" ]; then
        echo "Required program is unavailable: $required_program" >&2
        exit 1
    fi
done

if [ ! -x "$executable" ]; then
    echo "Release application not found; run 'make verify-release' first." >&2
    exit 1
fi

if ! "$project_root/scripts/verify-release.sh" "$application"; then
    echo "Release verification failed; run 'make verify-release' first." >&2
    exit 1
fi

# The pktap metadata expression keys on the effective application name. Another
# Browser process would make attribution ambiguous, so require a clean start.
if /usr/bin/pgrep -x Browser >/dev/null 2>&1; then
    echo "A process named Browser is already running; close it before auditing." >&2
    exit 1
fi

mkdir -p "$project_root/.build"
output_directory=$(mktemp -d "$project_root/.build/NetworkAudit.XXXXXX")
fixture_token=${output_directory##*.}
fixture_pid=""
browser_pid=""
browser_helper_pids=""
capture_job_pid=""
capture_process_pid=""
capture_path=""
capture_pid_path=""

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
    while [ "$attempt" -lt 100 ]; do
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
    stopped_helper_pids=$browser_helper_pids
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
    browser_helper_pids=""
}

is_tcpdump_process() {
    candidate_pid=$1
    case "$candidate_pid" in
        "" | *[!0-9]*)
            return 1
            ;;
    esac
    candidate_command=$(/bin/ps -p "$candidate_pid" -o comm= 2>/dev/null || true)
    case "$candidate_command" in
        tcpdump | */tcpdump)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

stop_capture() {
    capture_must_be_running=${1:-0}
    if [ "$capture_must_be_running" -eq 1 ]; then
        if [ -z "$capture_job_pid" ] || ! kill -0 "$capture_job_pid" 2>/dev/null; then
            echo "Packet-capture job exited before the measurement ended." >&2
            return 1
        fi
        if [ -z "$capture_process_pid" ] || \
            ! /usr/bin/sudo -n /bin/kill -0 "$capture_process_pid" 2>/dev/null
        then
            echo "tcpdump exited before the measurement ended." >&2
            return 1
        fi
        if ! is_tcpdump_process "$capture_process_pid"; then
            echo "Capture PID changed identity before measurement ended: $capture_process_pid" >&2
            return 1
        fi
    fi

    if [ -n "$capture_process_pid" ]; then
        if /usr/bin/sudo -n /bin/kill -0 "$capture_process_pid" 2>/dev/null; then
            if ! is_tcpdump_process "$capture_process_pid"; then
                echo "Refusing to signal a capture PID that is not tcpdump: $capture_process_pid" >&2
                return 1
            fi
            /usr/bin/sudo -n /bin/kill -INT "$capture_process_pid"

            attempt=0
            while /usr/bin/sudo -n /bin/kill -0 "$capture_process_pid" 2>/dev/null; do
                attempt=$((attempt + 1))
                if [ "$attempt" -ge 50 ]; then
                    if ! is_tcpdump_process "$capture_process_pid"; then
                        echo "Capture PID changed identity while stopping: $capture_process_pid" >&2
                        return 1
                    fi
                    /usr/bin/sudo -n /bin/kill -KILL "$capture_process_pid"
                    break
                fi
                sleep 0.1
            done
        fi
    fi

    capture_job_status=0
    if [ -n "$capture_job_pid" ]; then
        if wait "$capture_job_pid" 2>/dev/null; then
            capture_job_status=0
        else
            capture_job_status=$?
        fi
    fi

    if [ -n "$capture_path" ] || [ -n "$capture_pid_path" ]; then
        owner=$(/usr/bin/id -u):$(/usr/bin/id -g)
        for owned_path in "$capture_path" "$capture_pid_path"; do
            if [ -n "$owned_path" ] && [ -e "$owned_path" ]; then
                /usr/bin/sudo -n /usr/sbin/chown "$owner" "$owned_path"
            fi
        done
    fi

    capture_job_pid=""
    capture_process_pid=""
    capture_path=""
    capture_pid_path=""

    if [ "$capture_must_be_running" -eq 1 ] && [ "$capture_job_status" -ne 0 ]; then
        echo "tcpdump exited with status $capture_job_status." >&2
        return 1
    fi
}

cleanup() {
    stop_capture 0 || true
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

echo "Network capture requires administrator permission for macOS pktap." >&2
echo "Authentication is handled by sudo; this script does not read or store it." >&2
if ! /usr/bin/sudo -n -v 2>/dev/null; then
    if [ ! -t 0 ]; then
        echo "No cached sudo authorization is available." >&2
        echo "Run '$0' from a normal interactive Terminal." >&2
        exit 1
    fi
    /usr/bin/sudo -v
fi

start_capture() {
    capture_name=$1
    capture_path="$output_directory/$capture_name.pcapng"
    capture_pid_path="$output_directory/$capture_name.tcpdump.pid"
    capture_log="$output_directory/$capture_name.tcpdump.log"

    # The privileged child writes its exact PID before exec. This lets cleanup
    # signal only this tcpdump instance, never a name-wide process set.
    /usr/bin/sudo -n /bin/sh -c '
        umask 022
        echo "$$" > "$1"
        exec /usr/sbin/tcpdump \
            --immediate-mode \
            -i pktap,all \
            -Q "$2" \
            -s "$3" \
            -U \
            -w "$4"
    ' audit-tcpdump \
        "$capture_pid_path" \
        "$metadata_filter" \
        "$packet_snap_length" \
        "$capture_path" \
        2>"$capture_log" &
    capture_job_pid=$!

    attempt=0
    while [ "$attempt" -lt 50 ]; do
        if [ -r "$capture_pid_path" ]; then
            capture_process_pid=$(sed -n '1p' "$capture_pid_path")
        fi
        if [ -n "$capture_process_pid" ] && \
            /usr/bin/grep -q "listening on pktap" "$capture_log" 2>/dev/null
        then
            if ! is_tcpdump_process "$capture_process_pid"; then
                echo "Capture PID is not the expected tcpdump process." >&2
                return 1
            fi
            return 0
        fi
        if ! kill -0 "$capture_job_pid" 2>/dev/null; then
            echo "tcpdump exited before capture became ready; see $capture_log" >&2
            return 1
        fi
        attempt=$((attempt + 1))
        sleep 0.1
    done

    echo "tcpdump did not become ready; see $capture_log" >&2
    return 1
}

decode_capture() {
    capture_name=$1
    "$project_root/scripts/decode-pktap-capture.sh" \
        "$output_directory/$capture_name.pcapng" \
        "$output_directory/$capture_name.tcpdump.log" \
        "$output_directory/$capture_name.packets.txt" \
        "$output_directory/$capture_name.read.log"
}

launch_browser() {
    browser_log=$1
    shift
    "$executable" \
        -ApplePersistenceIgnoreState YES \
        "$@" \
        >"$browser_log" 2>&1 &
    browser_pid=$!
}

record_new_helpers() {
    sample_name=$1
    before_path=$2
    after_path="$output_directory/$sample_name.webkit-after.txt"

    attempt=0
    browser_helper_pids=""
    while [ "$attempt" -lt 100 ]; do
        webkit_pids >"$after_path"
        browser_helper_pids=$(
            new_pids "$before_path" "$after_path" | /usr/bin/tr '\n' ' '
        )
        [ -z "$browser_helper_pids" ] || break
        if ! kill -0 "$browser_pid" 2>/dev/null; then
            echo "Browser exited before its WebKit helpers appeared." >&2
            return 1
        fi
        attempt=$((attempt + 1))
        sleep 0.1
    done

    if [ -z "$browser_helper_pids" ]; then
        echo "No Browser-owned WebKit helper processes were discovered." >&2
        return 1
    fi

    # Let the WebKit process set settle, then record every helper introduced by
    # this launch. eproc=Browser attributes delegated network work back to it.
    sleep 0.5
    webkit_pids >"$after_path"
    browser_helper_pids=$(
        new_pids "$before_path" "$after_path" | /usr/bin/tr '\n' ' '
    )
    webkit_processes >"$output_directory/$sample_name.webkit-processes-all.txt"
    for helper_pid in $browser_helper_pids; do
        /bin/ps -p "$helper_pid" -o pid=,args=
    done >"$output_directory/$sample_name.webkit-processes.txt"
}

fixture_url="http://127.0.0.1:$fixture_port/normal/"
/usr/bin/python3 \
    "$fixture_script" \
    --port "$fixture_port" \
    --token "$fixture_token" \
    >"$output_directory/fixture-server.log" 2>&1 &
fixture_pid=$!

attempt=0
until /usr/bin/curl --fail --silent --show-error \
    "http://127.0.0.1:$fixture_port/health?token=$fixture_token" \
    >/dev/null 2>&1
do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 50 ]; then
        echo "Fixture server did not become ready; see the audit artifacts." >&2
        exit 1
    fi
    sleep 0.1
done
/usr/bin/curl --fail --silent --show-error \
    "http://127.0.0.1:$fixture_port/reset" >/dev/null

echo "Validating process attribution with an intentional localhost load..."
webkit_pids >"$output_directory/control.webkit-before.txt"
start_capture control
launch_browser \
    "$output_directory/control.browser.log" \
    --performance-test \
    --performance-fixture-url "$fixture_url"

attempt=0
while [ "$attempt" -lt 100 ]; do
    if /usr/bin/curl --fail --silent --show-error \
        "http://127.0.0.1:$fixture_port/stats" \
        >"$output_directory/control.fixture-stats.json" && \
        /usr/bin/python3 -c \
            'import json, sys
data = json.load(open(sys.argv[1]))
raise SystemExit(0 if data.get("/normal/", 0) >= 1 and data.get("/assets/blocked.js", 0) >= 1 else 1)' \
            "$output_directory/control.fixture-stats.json"
    then
        break
    fi
    if ! kill -0 "$browser_pid" 2>/dev/null; then
        echo "Browser exited during the attribution control." >&2
        exit 1
    fi
    attempt=$((attempt + 1))
    sleep 0.1
done
if [ "$attempt" -ge 100 ]; then
    echo "Browser did not load the intentional control fixture." >&2
    exit 1
fi
record_new_helpers control "$output_directory/control.webkit-before.txt"
stop_capture 1
control_packet_count=$(decode_capture control)
if [ "$control_packet_count" -lt 1 ]; then
    echo "Attribution control failed: tcpdump saw no Browser-owned packet." >&2
    echo "The zero-packet idle result would not be trustworthy." >&2
    exit 1
fi
if ! stop_browser; then
    echo "Attribution-control helpers remained alive; refusing a contaminated audit." >&2
    exit 1
fi

if /usr/bin/pgrep -x Browser >/dev/null 2>&1; then
    echo "The control Browser process did not exit cleanly." >&2
    exit 1
fi

echo "Auditing a production about:blank launch plus ${idle_seconds}s idle..."
webkit_pids >"$output_directory/idle.webkit-before.txt"
start_capture idle
audit_start=$(/bin/date +%s)
launch_browser "$output_directory/idle.browser.log"
record_new_helpers idle "$output_directory/idle.webkit-before.txt"

sleep "$idle_seconds"
if ! kill -0 "$browser_pid" 2>/dev/null; then
    echo "Browser exited before the idle interval completed." >&2
    exit 1
fi
audit_end=$(/bin/date +%s)
stop_capture 1
idle_packet_count=$(decode_capture idle)
stop_browser

audit_elapsed=$((audit_end - audit_start))
result_path="$output_directory/result.txt"
{
    echo "release_application=$application"
    echo "metadata_filter=$metadata_filter"
    echo "packet_snap_length=$packet_snap_length"
    echo "control_outbound_packets=$control_packet_count"
    echo "idle_elapsed_seconds=$audit_elapsed"
    echo "idle_outbound_packets=$idle_packet_count"
    if [ "$idle_packet_count" -eq 0 ] && [ "$audit_elapsed" -ge "$idle_seconds" ]; then
        echo "result=PASS"
    else
        echo "result=FAIL"
    fi
} >"$result_path"

echo "Control packets attributed to Browser/WebKit: $control_packet_count"
echo "Blank-launch outbound packets over ${audit_elapsed}s: $idle_packet_count"
echo "Artifacts: $output_directory"

if [ "$audit_elapsed" -lt "$idle_seconds" ]; then
    echo "Audit interval was shorter than ${idle_seconds}s." >&2
    exit 1
fi
if [ "$idle_packet_count" -ne 0 ]; then
    echo "FAIL: application-attributed outbound traffic was captured." >&2
    echo "Inspect $output_directory/idle.packets.txt" >&2
    exit 1
fi

echo "PASS: no Browser-owned outbound packets during launch and idle."
