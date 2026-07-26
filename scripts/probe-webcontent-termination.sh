#!/bin/sh

set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
application=${1:-"$project_root/.build/DerivedData/Build/Products/Release/Browser.app"}
browser_executable="$application/Contents/MacOS/Browser"
webkit_services=/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices
normal_webcontent="$webkit_services/com.apple.WebKit.WebContent.xpc/Contents/MacOS/com.apple.WebKit.WebContent"
captive_webcontent="$webkit_services/com.apple.WebKit.WebContent.CaptivePortal.xpc/Contents/MacOS/com.apple.WebKit.WebContent.CaptivePortal"
development_webcontent="$webkit_services/com.apple.WebKit.WebContent.Development.xpc/Contents/MacOS/com.apple.WebKit.WebContent.Development"
enhanced_webcontent="$webkit_services/com.apple.WebKit.WebContent.EnhancedSecurity.xpc/Contents/MacOS/com.apple.WebKit.WebContent.EnhancedSecurity"

discovery_attempts=150
exit_attempts=50
replacement_attempts=50
browser_pid=""
target_pid=""
target_executable=""
output_directory=""

is_safe_pid() {
    case "$1" in
        "" | *[!0-9]*)
            return 1
            ;;
    esac
    [ "$1" -gt 1 ]
}

process_command() {
    /bin/ps -ww -p "$1" -o command= 2>/dev/null || true
}

command_starts_with_executable() {
    current_command=$(process_command "$1")
    case "$current_command" in
        "$2" | "$2 "*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

is_webcontent_executable() {
    case "$1" in
        "$normal_webcontent" | \
        "$captive_webcontent" | \
        "$development_webcontent" | \
        "$enhanced_webcontent")
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

snapshot_webcontent() {
    destination=$1
    /bin/ps -ww -axo pid=,ppid=,command= |
        /usr/bin/awk \
            -v normal="$normal_webcontent" \
            -v captive="$captive_webcontent" \
            -v development="$development_webcontent" \
            -v enhanced="$enhanced_webcontent" '
                {
                    pid = $1
                    ppid = $2
                    $1 = ""
                    $2 = ""
                    sub(/^[[:space:]]+/, "")
                    command = $0
                    split(command, fields, /[[:space:]]+/)
                    executable = fields[1]
                    if (executable == normal || executable == captive ||
                        executable == development || executable == enhanced) {
                        print pid "\t" ppid "\t" command
                    }
                }
            ' |
        LC_ALL=C /usr/bin/sort -n -k1,1 >"$destination"
}

snapshot_pids() {
    /usr/bin/awk '{ print $1 }' "$1" |
        LC_ALL=C /usr/bin/sort >"$2"
}

new_pids() {
    before_snapshot=$1
    after_snapshot=$2
    before_pids="$output_directory/before-pids.txt"
    after_pids="$output_directory/after-pids.txt"
    snapshot_pids "$before_snapshot" "$before_pids"
    snapshot_pids "$after_snapshot" "$after_pids"
    /usr/bin/comm -13 "$before_pids" "$after_pids"
}

record_process() {
    pid=$1
    destination=$2
    /bin/ps -ww -p "$pid" -o pid=,ppid=,lstart=,command= >"$destination"
}

wait_for_process_exit() {
    pid=$1
    attempts=$2
    attempt=0
    while [ "$attempt" -lt "$attempts" ]; do
        if ! kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 0.1
    done
    return 1
}

stop_browser() {
    [ -n "$browser_pid" ] || return 0
    if ! kill -0 "$browser_pid" 2>/dev/null; then
        wait "$browser_pid" 2>/dev/null || true
        browser_pid=""
        return 0
    fi

    if ! is_safe_pid "$browser_pid" || \
        ! command_starts_with_executable "$browser_pid" "$browser_executable"
    then
        echo "Refusing to signal unverified Browser PID $browser_pid during cleanup." >&2
        return 1
    fi

    kill -TERM "$browser_pid"
    if ! wait_for_process_exit "$browser_pid" "$exit_attempts"; then
        if ! command_starts_with_executable "$browser_pid" "$browser_executable"; then
            echo "Refusing to force-terminate reused or changed PID $browser_pid." >&2
            return 1
        fi
        kill -KILL "$browser_pid"
        wait_for_process_exit "$browser_pid" "$exit_attempts" || {
            echo "Browser PID $browser_pid did not exit during bounded cleanup." >&2
            return 1
        }
    fi
    wait "$browser_pid" 2>/dev/null || true
    browser_pid=""
}

cleanup() {
    stop_browser || true
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [ ! -x "$browser_executable" ]; then
    echo "Release application not found: $application" >&2
    exit 1
fi

for executable in \
    "$normal_webcontent" \
    "$captive_webcontent" \
    "$development_webcontent" \
    "$enhanced_webcontent"
do
    if [ ! -x "$executable" ]; then
        echo "Expected WebKit executable not found: $executable" >&2
        exit 1
    fi
done

"$project_root/scripts/verify-release.sh" "$application"

mkdir -p "$project_root/.build"
output_directory=$(mktemp -d "$project_root/.build/WebContentTermination.XXXXXX")
before_snapshot="$output_directory/webcontent-before.tsv"
discovery_snapshot="$output_directory/webcontent-discovery.tsv"
post_signal_snapshot="$output_directory/webcontent-post-signal.tsv"
final_snapshot="$output_directory/webcontent-final.tsv"
cleanup_snapshot="$output_directory/webcontent-after-cleanup.tsv"
result_file="$output_directory/result.txt"

snapshot_webcontent "$before_snapshot"

existing_browser_pids=$(
    /bin/ps -ww -axo pid=,command= |
        /usr/bin/awk -v executable="$browser_executable" '
            {
                pid = $1
                $1 = ""
                sub(/^[[:space:]]+/, "")
                if ($0 == executable || index($0, executable " ") == 1) {
                    print pid
                }
            }
        '
)
if [ -n "$existing_browser_pids" ]; then
    echo "Browser is already running with PID(s): $existing_browser_pids" >&2
    echo "Close it before running this probe so process attribution is unambiguous." >&2
    exit 1
fi

"$browser_executable" \
    --performance-test \
    -ApplePersistenceIgnoreState YES \
    >"$output_directory/browser.log" 2>&1 &
browser_pid=$!

if ! is_safe_pid "$browser_pid" || \
    ! command_starts_with_executable "$browser_pid" "$browser_executable"
then
    echo "Browser launch PID could not be verified: $browser_pid" >&2
    exit 1
fi
record_process "$browser_pid" "$output_directory/browser-process.txt"

attempt=0
new_webcontent_pids=""
while [ "$attempt" -lt "$discovery_attempts" ]; do
    if ! command_starts_with_executable "$browser_pid" "$browser_executable"; then
        echo "Browser exited before a WebContent process was discovered." >&2
        exit 1
    fi
    snapshot_webcontent "$discovery_snapshot"
    new_webcontent_pids=$(new_pids "$before_snapshot" "$discovery_snapshot")
    new_count=$(printf '%s\n' "$new_webcontent_pids" | /usr/bin/awk 'NF { count += 1 } END { print count + 0 }')
    if [ "$new_count" -gt 1 ]; then
        echo "Ambiguous attribution: $new_count new WebContent processes appeared." >&2
        echo "No WebContent process was signaled; inspect $discovery_snapshot." >&2
        exit 1
    fi
    if [ "$new_count" -eq 1 ]; then
        break
    fi
    attempt=$((attempt + 1))
    sleep 0.1
done

if [ -z "$new_webcontent_pids" ]; then
    echo "No new WebContent process appeared within the discovery timeout." >&2
    exit 1
fi
target_pid=$new_webcontent_pids
if ! is_safe_pid "$target_pid" || [ "$target_pid" -eq "$browser_pid" ]; then
    echo "Discovered WebContent PID is not safe to signal: $target_pid" >&2
    exit 1
fi

target_command=$(process_command "$target_pid")
target_executable=${target_command%% *}
if ! is_webcontent_executable "$target_executable" || \
    ! command_starts_with_executable "$target_pid" "$target_executable"
then
    echo "Refusing to signal PID $target_pid because its executable is not verified." >&2
    exit 1
fi
record_process "$target_pid" "$output_directory/target-process-before-signal.txt"

# TERM is sufficient to exercise WKWebView's content-process termination path
# while allowing the disposable XPC service an orderly exit.
if ! command_starts_with_executable "$target_pid" "$target_executable"; then
    echo "Refusing to signal PID $target_pid because it changed before SIGTERM." >&2
    exit 1
fi
kill -TERM "$target_pid"
if ! wait_for_process_exit "$target_pid" "$exit_attempts"; then
    echo "Verified WebContent PID $target_pid did not exit after SIGTERM." >&2
    exit 1
fi

replacement_pids=""
replacement_observations="$output_directory/replacement-observations.tsv"
observed_replacement_pids="$output_directory/replacement-pids.txt"
: >"$replacement_observations"
: >"$observed_replacement_pids"
attempt=0
while [ "$attempt" -lt "$replacement_attempts" ]; do
    if ! command_starts_with_executable "$browser_pid" "$browser_executable"; then
        echo "Browser did not remain alive for the bounded five-second interval." >&2
        exit 1
    fi
    snapshot_webcontent "$post_signal_snapshot"
    current_new_pids=$(new_pids "$before_snapshot" "$post_signal_snapshot")
    current_replacement_pids=$(
        printf '%s\n' "$current_new_pids" |
            /usr/bin/awk -v target="$target_pid" 'NF && $1 != target { print $1 }'
    )
    for replacement_pid in $current_replacement_pids; do
        echo "$replacement_pid" >>"$observed_replacement_pids"
        /bin/ps -ww -p "$replacement_pid" \
            -o pid=,ppid=,lstart=,command= \
            >>"$replacement_observations" 2>/dev/null || true
    done
    attempt=$((attempt + 1))
    sleep 0.1
done

snapshot_webcontent "$final_snapshot"
replacement_pids=$(LC_ALL=C /usr/bin/sort -u "$observed_replacement_pids")
replacement_count=$(printf '%s\n' "$replacement_pids" | /usr/bin/awk 'NF { count += 1 } END { print count + 0 }')
replacement_state=no
if [ "$replacement_count" -gt 0 ]; then
    replacement_state=yes
fi

{
    echo "application=$application"
    echo "browser_pid=$browser_pid"
    echo "target_pid=$target_pid"
    echo "target_executable=$target_executable"
    echo "signal=SIGTERM"
    echo "target_exited=yes"
    echo "browser_survived_5_seconds=yes"
    echo "replacement_observed_within_5_seconds=$replacement_state"
    echo "replacement_pids=${replacement_pids:-none}"
} >"$result_file"

stop_browser
for replacement_pid in $replacement_pids; do
    if ! wait_for_process_exit "$replacement_pid" "$exit_attempts"; then
        echo "Replacement WebContent PID $replacement_pid outlived Browser cleanup." >&2
        exit 1
    fi
done
snapshot_webcontent "$cleanup_snapshot"
{
    echo "browser_cleanup=complete"
    echo "observed_webcontent_cleanup=complete"
} >>"$result_file"

cat "$result_file"
echo "Evidence: $output_directory"

trap - EXIT
