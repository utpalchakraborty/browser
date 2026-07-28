#!/bin/sh

set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
audit_script="$project_root/scripts/audit-container.sh"
bundle_identifier=com.utpalchakraborty.browser
ui_test_store_identifier=7b92bee3-7745-444a-a312-d787cb93db6e

fixture_root=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/BrowserContainerAuditTests.XXXXXX")
container_root="$fixture_root/container"
artifact_root="$fixture_root/artifacts"
data_root="$container_root/Data"
preferences_root="$data_root/Library/Preferences"
preferences="$preferences_root/$bundle_identifier.plist"
search_history_root="$data_root/Library/WebKit/WebsiteDataStore/$ui_test_store_identifier/SearchHistory"
recent_searches="$search_history_root/RecentSearches.plist"

cleanup() {
    /bin/rm -rf "$fixture_root"
}
trap cleanup EXIT HUP INT TERM

/bin/mkdir -p "$preferences_root" "$search_history_root" "$artifact_root"

write_empty_search_history() {
    /usr/bin/plutil -create xml1 "$recent_searches"
    /usr/bin/plutil -insert items -dictionary "$recent_searches"
}

run_audit() {
    BROWSER_CONTAINER_AUDIT_ROOT="$container_root" \
        BROWSER_CONTAINER_AUDIT_OUTPUT_ROOT="$artifact_root" \
        "$audit_script" 2>&1
}

expect_pass() {
    test_label=$1
    if ! test_output=$(run_audit); then
        echo "FAIL: expected pass for $test_label" >&2
        echo "$test_output" >&2
        exit 1
    fi
    echo "$test_output" | /usr/bin/grep -q '^result=PASS$'
}

expect_fail() {
    test_label=$1
    expected_finding=$2
    if test_output=$(run_audit); then
        echo "FAIL: expected failure for $test_label" >&2
        echo "$test_output" >&2
        exit 1
    fi
    echo "$test_output" | /usr/bin/grep -q "$expected_finding"
}

write_empty_search_history
/usr/bin/plutil -create xml1 "$preferences"
/usr/bin/plutil -insert 'NSWindow Frame BrowserMainWindow' \
    -string '100 100 900 700 0 0 1920 1080' "$preferences"
expect_pass "empty WebKit plist and allowlisted preference"

/usr/bin/plutil -insert items.fixture -array "$recent_searches"
/usr/bin/plutil -insert items.fixture.0 -string 'private fixture term' \
    "$recent_searches"
/usr/bin/plutil -insert items.fixture.1 -string 'second fixture term' \
    "$recent_searches"
expect_fail \
    "persisted search terms" \
    'ui_test store: 2 search terms'

write_empty_search_history
/usr/bin/touch "$search_history_root/UnknownHistory.db"
expect_fail \
    "unknown SearchHistory artifact" \
    'SearchHistory could not be validated for the ui_test store'
/bin/rm "$search_history_root/UnknownHistory.db"

/usr/bin/plutil -insert version -integer 1 "$recent_searches"
expect_fail \
    "unknown RecentSearches schema" \
    'SearchHistory could not be validated for the ui_test store'
/usr/bin/plutil -remove version "$recent_searches"

/usr/bin/plutil -insert UnexpectedPreference -string unsafe "$preferences"
expect_fail \
    "unknown production preference" \
    'unexpected production preference key: UnexpectedPreference'
/usr/bin/plutil -remove UnexpectedPreference "$preferences"

/usr/bin/plutil -insert RestoredPageURL -string 'https://private.invalid/' \
    "$preferences"
expect_fail \
    "forbidden production preference" \
    'forbidden production preference key: RestoredPageURL'

echo "PASS: container audit accepted empty history and rejected persisted or unknown state."
