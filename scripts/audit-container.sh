#!/bin/sh

set -u

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
bundle_identifier=com.utpalchakraborty.browser
container_root=${BROWSER_CONTAINER_AUDIT_ROOT:-"$HOME/Library/Containers/$bundle_identifier"}
artifact_root=${BROWSER_CONTAINER_AUDIT_OUTPUT_ROOT:-"$project_root/.build"}
search_history_inspector="$project_root/scripts/inspect-search-history.py"
data_root="$container_root/Data"
application_support_root="$data_root/Library/Application Support"
application_owned_root="$application_support_root/$bundle_identifier"
documents_root="$data_root/Documents"
preferences_root="$data_root/Library/Preferences"
production_preferences="$preferences_root/$bundle_identifier.plist"
webkit_root="$data_root/Library/WebKit"
website_data_store_root="$webkit_root/WebsiteDataStore"
content_rule_lists_root="$webkit_root/ContentRuleLists"
system_cache_root="$data_root/Library/Caches/$bundle_identifier"
system_http_storage_root="$data_root/Library/HTTPStorages/$bundle_identifier"
saved_state_tmp_root="$data_root/tmp/$bundle_identifier.savedState"
saved_state_library_root="$data_root/Library/Saved Application State/$bundle_identifier.savedState"

normal_store_identifier=5d1f8e17-6a12-4c9c-9b1d-b9e17a4c7110
ui_test_store_identifier=7b92bee3-7745-444a-a312-d787cb93db6e
performance_store_identifier=2272e2f6-c1d7-4f1e-b69c-e8e0325fb03c

timestamp_utc=$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')
artifact_timestamp=$(/bin/date -u '+%Y%m%dT%H%M%SZ')
/bin/mkdir -p "$artifact_root"
output_directory=$(
    /usr/bin/mktemp -d \
        "$artifact_root/ContainerAudit.$artifact_timestamp.XXXXXX"
)
report_path="$output_directory/report.txt"
findings_path="$output_directory/findings.txt"
warnings_path="$output_directory/warnings.txt"
app_inventory_path="$output_directory/app-owned-inventory.txt"
documents_inventory_path="$output_directory/documents-inventory.txt"
preference_keys_path="$output_directory/production-preference-keys.txt"
saved_state_inventory_path="$output_directory/saved-state-inventory.txt"
inspection_errors_path="$output_directory/inspection-errors.txt"

: >"$findings_path"
: >"$warnings_path"
: >"$app_inventory_path"
: >"$documents_inventory_path"
: >"$preference_keys_path"
: >"$saved_state_inventory_path"
: >"$inspection_errors_path"

add_failure() {
    /usr/bin/printf '%s\n' "$1" >>"$findings_path"
}

add_warning() {
    /usr/bin/printf '%s\n' "$1" >>"$warnings_path"
}

line_count() {
    /usr/bin/awk 'length($0) > 0 { count += 1 } END { print count + 0 }' "$1"
}

relative_inventory() {
    inventory_root=$1
    inventory_output=$2
    inventory_label=$3
    absolute_output="$inventory_output.absolute"

    if ! /usr/bin/find "$inventory_root" -mindepth 1 -print \
        >"$absolute_output" 2>>"$inspection_errors_path"
    then
        add_failure "$inventory_label could not be inspected completely"
        return
    fi
    /usr/bin/sed "s#^$inventory_root/##" "$absolute_output" |
        LC_ALL=C /usr/bin/sort >"$inventory_output"
}

count_entries() {
    count_root=$1
    shift
    count_output=$(
        /usr/bin/find "$count_root" "$@" -print \
            2>>"$inspection_errors_path"
    )
    count_status=$?
    if [ "$count_status" -ne 0 ]; then
        add_failure "could not inspect $count_root completely"
        /usr/bin/printf '%s\n' 0
        return
    fi
    /usr/bin/printf '%s\n' "$count_output" |
        /usr/bin/awk 'length($0) > 0 { count += 1 } END { print count + 0 }'
}

container_state=missing
application_owned_state=absent
application_owned_entry_count=0
application_owned_database_count=0
application_owned_forbidden_name_count=0
application_owned_unexpected_count=0
documents_entry_count=0
production_preferences_state=absent
production_preference_key_count=0
forbidden_preference_key_count=0
unexpected_preference_key_count=0
saved_state_root_count=0
saved_state_entry_count=0
saved_state_marker_count=0
webkit_state=absent
website_data_store_count=0
content_rule_list_file_count=0
normal_store_state=absent
normal_search_history_entry_count=0
normal_search_history_state=absent
ui_test_store_state=absent
ui_test_search_history_entry_count=0
ui_test_search_history_state=absent
performance_store_state=absent
performance_search_history_entry_count=0
performance_search_history_state=absent
system_cache_database_count=0
system_http_storage_database_count=0
unexpected_durable_database_count=0
unexpected_durable_name_count=0

if [ ! -d "$container_root" ]; then
    add_failure "Browser container is missing; launch Browser before auditing"
else
    container_state=present

    if [ -d "$application_owned_root" ]; then
        application_owned_state=present
        relative_inventory \
            "$application_owned_root" \
            "$app_inventory_path" \
            "application-owned persistence"
        application_owned_entry_count=$(line_count "$app_inventory_path")

        while IFS= read -r relative_path; do
            [ -n "$relative_path" ] || continue
            absolute_path="$application_owned_root/$relative_path"
            lower_path=$(
                /usr/bin/printf '%s' "$relative_path" |
                    /usr/bin/tr '[:upper:]' '[:lower:]'
            )
            case "$lower_path" in
                *history* | *visit* | *session* | *navigation* | \
                *recently*closed* | *recent*closed*)
                    add_failure \
                        "forbidden application-owned history/session name: $relative_path"
                    application_owned_forbidden_name_count=$((
                        application_owned_forbidden_name_count + 1
                    ))
                    ;;
            esac

            if [ -L "$absolute_path" ]; then
                add_failure \
                    "unexpected application-owned symbolic link: $relative_path"
                application_owned_unexpected_count=$((
                    application_owned_unexpected_count + 1
                ))
                continue
            fi

            if [ -d "$absolute_path" ]; then
                case "$relative_path" in
                    UITests)
                        ;;
                    *)
                        add_failure \
                            "unexpected application-owned directory: $relative_path"
                        application_owned_unexpected_count=$((
                            application_owned_unexpected_count + 1
                        ))
                        ;;
                esac
                continue
            fi

            if [ -f "$absolute_path" ]; then
                case "$relative_path" in
                    Bookmarks.json | \
                    Bookmarks.backup.json | \
                    Bookmarks.corrupt.*.json | \
                    UITests/Bookmarks.json | \
                    UITests/Bookmarks.backup.json | \
                    UITests/Bookmarks.corrupt.*.json)
                        ;;
                    *)
                        add_failure \
                            "unexpected application-owned file: $relative_path"
                        application_owned_unexpected_count=$((
                            application_owned_unexpected_count + 1
                        ))
                        ;;
                esac
            else
                add_failure \
                    "unexpected application-owned entry type: $relative_path"
                application_owned_unexpected_count=$((
                    application_owned_unexpected_count + 1
                ))
            fi

        done <"$app_inventory_path"

        app_database_output=$(
            /usr/bin/find "$application_owned_root" -type f \( \
                -iname '*.db' -o \
                -iname '*.db-*' -o \
                -iname '*.sqlite' -o \
                -iname '*.sqlite-*' -o \
                -iname '*.sqlite3' -o \
                -iname '*.realm' -o \
                -iname '*.ldb' -o \
                -iname '*.rdb' \
            \) -print 2>>"$inspection_errors_path"
        )
        app_database_status=$?
        if [ "$app_database_status" -ne 0 ]; then
            add_failure \
                "application-owned database-like files could not be inspected"
        else
            application_owned_database_count=$(
                /usr/bin/printf '%s\n' "$app_database_output" |
                    /usr/bin/awk \
                        'length($0) > 0 { count += 1 } END { print count + 0 }'
            )
            if [ "$application_owned_database_count" -gt 0 ]; then
                add_failure \
                    "unexpected application-owned database-like files: $application_owned_database_count"
            fi
        fi
    else
        add_warning \
            "application-owned bookmark directory is absent; no bookmarks are persisted"
    fi

    if [ -d "$documents_root" ]; then
        relative_inventory \
            "$documents_root" \
            "$documents_inventory_path" \
            "Documents persistence"
        documents_entry_count=$(line_count "$documents_inventory_path")
        if [ "$documents_entry_count" -gt 0 ]; then
            add_failure \
                "unexpected application-owned Documents entries: $documents_entry_count"
        fi
    fi

    if [ -f "$production_preferences" ]; then
        production_preferences_state=present
        if /usr/bin/plutil -lint "$production_preferences" \
            >/dev/null 2>>"$inspection_errors_path"
        then
            preference_dump=$(
                /usr/bin/plutil -p "$production_preferences" \
                    2>>"$inspection_errors_path"
            )
            preference_dump_status=$?
            if [ "$preference_dump_status" -ne 0 ]; then
                add_failure "production preference keys could not be inspected"
            else
                /usr/bin/printf '%s\n' "$preference_dump" |
                    /usr/bin/sed -n \
                        's/^  "\([^"]*\)" =>.*/\1/p' |
                    LC_ALL=C /usr/bin/sort >"$preference_keys_path"
            fi
            production_preference_key_count=$(
                line_count "$preference_keys_path"
            )
            while IFS= read -r preference_key; do
                [ -n "$preference_key" ] || continue
                case "$preference_key" in
                    searchProvider | \
                    contentBlocker.lastValidRuleSet | \
                    contentBlocker.uiTests.lastValidRuleSet | \
                    contentBlocker.sitePolicy | \
                    contentBlocker.uiTests.sitePolicy | \
                    "NSWindow Frame BrowserMainWindow" | \
                    "NSWindow Frame BrowserMainWindow.UITests" | \
                    "NSWindow Frame NSSpellCheckerSpellingPanel" | \
                    "NSWindow Frame NSSpellCheckerSubstitutionsPanel2")
                        ;;
                    *)
                        add_failure \
                            "unexpected production preference key: $preference_key"
                        unexpected_preference_key_count=$((
                            unexpected_preference_key_count + 1
                        ))
                        ;;
                esac
                lower_key=$(
                    /usr/bin/printf '%s' "$preference_key" |
                        /usr/bin/tr '[:upper:]' '[:lower:]'
                )
                case "$lower_key" in
                    *history* | *visit* | *session* | *navigation* | \
                    *recently*closed* | *recent*closed* | \
                    *last*url* | *url*last* | *restore*url* | \
                    *restore*page* | *restore*tab*)
                        add_failure \
                            "forbidden production preference key: $preference_key"
                        forbidden_preference_key_count=$((
                            forbidden_preference_key_count + 1
                        ))
                        ;;
                esac
            done <"$preference_keys_path"
        else
            add_failure "production preferences plist is not valid"
        fi
    else
        add_warning \
            "production preferences plist is absent; no app preferences are persisted"
    fi

    durable_scan_roots=""
    for durable_root in \
        "$application_support_root" \
        "$documents_root" \
        "$data_root/Library/Logs"
    do
        if [ -d "$durable_root" ]; then
            durable_scan_roots="$durable_scan_roots
$durable_root"
        fi
    done

    old_ifs=$IFS
    IFS='
'
    for durable_root in $durable_scan_roots; do
        [ -n "$durable_root" ] || continue
        durable_database_output=$(
            /usr/bin/find "$durable_root" \
                -path "$application_owned_root" -prune -o \
                -type f \( \
                    -iname '*.db' -o \
                    -iname '*.db-*' -o \
                    -iname '*.sqlite' -o \
                    -iname '*.sqlite-*' -o \
                    -iname '*.sqlite3' -o \
                    -iname '*.realm' -o \
                    -iname '*.ldb' -o \
                    -iname '*.rdb' \
                \) -print 2>>"$inspection_errors_path"
        )
        durable_database_status=$?
        if [ "$durable_database_status" -ne 0 ]; then
            add_failure "durable root could not be inspected: $durable_root"
            continue
        fi
        root_database_count=$(
            /usr/bin/printf '%s\n' "$durable_database_output" |
                /usr/bin/awk \
                    'length($0) > 0 { count += 1 } END { print count + 0 }'
        )
        unexpected_durable_database_count=$((
            unexpected_durable_database_count + root_database_count
        ))
        if [ "$root_database_count" -gt 0 ]; then
            add_failure \
                "unexpected database-like files outside known managed roots under $durable_root: $root_database_count"
        fi

        durable_name_paths=$(
            /usr/bin/find "$durable_root" \
                -path "$application_owned_root" -prune -o \
                -mindepth 1 -print 2>>"$inspection_errors_path"
        )
        durable_name_status=$?
        if [ "$durable_name_status" -ne 0 ]; then
            add_failure \
                "durable artifact names could not be inspected under $durable_root"
            continue
        fi
        durable_name_output=$(
            /usr/bin/printf '%s\n' "$durable_name_paths" |
                /usr/bin/awk '
                    {
                        value = tolower($0)
                        if (value ~ /history/ || value ~ /visit/ ||
                            value ~ /session/ || value ~ /navigation/ ||
                            value ~ /recently.*closed/ ||
                            value ~ /recent.*closed/) {
                            count += 1
                        }
                    }
                    END { print count + 0 }
                '
        )
        unexpected_durable_name_count=$((
            unexpected_durable_name_count + durable_name_output
        ))
        if [ "$durable_name_output" -gt 0 ]; then
            add_failure \
                "history/session-like artifact names outside known managed roots under $durable_root: $durable_name_output"
        fi
    done
    IFS=$old_ifs

    if [ -d "$system_cache_root" ]; then
        system_cache_database_count=$(
            count_entries "$system_cache_root" -type f \( \
                -iname '*.db' -o -iname '*.db-*' \
            \)
        )
    fi
    if [ -d "$system_http_storage_root" ]; then
        system_http_storage_database_count=$(
            count_entries "$system_http_storage_root" -type f \( \
                -iname '*.sqlite' -o -iname '*.sqlite-*' \
            \)
        )
    fi

    if [ -d "$webkit_root" ]; then
        webkit_state=present
        if [ -d "$website_data_store_root" ]; then
            website_data_store_count=$(
                count_entries \
                    "$website_data_store_root" \
                    -mindepth 1 -maxdepth 1 -type d
            )
        fi
        if [ -d "$content_rule_lists_root" ]; then
            content_rule_list_file_count=$(
                count_entries "$content_rule_lists_root" -type f
            )
        fi

        for store_specification in \
            "normal:$normal_store_identifier" \
            "ui_test:$ui_test_store_identifier" \
            "performance:$performance_store_identifier"
        do
            store_label=${store_specification%%:*}
            store_identifier=${store_specification#*:}
            store_root="$website_data_store_root/$store_identifier"
            store_state=absent
            search_history_entry_count=0
            search_history_state=absent
            if [ -d "$store_root" ]; then
                store_state=present
                search_history_root="$store_root/SearchHistory"
                if [ -d "$search_history_root" ]; then
                    search_history_state=valid
                    search_history_error_path="$output_directory/$store_label-search-history-errors.txt"
                    if ! search_history_entry_count=$(
                        /usr/bin/python3 \
                            "$search_history_inspector" \
                            "$search_history_root" \
                            2>"$search_history_error_path"
                    ); then
                        search_history_state=invalid
                        search_history_entry_count=unknown
                        add_failure \
                            "WebKit-managed SearchHistory could not be validated for the $store_label store"
                        /bin/cat "$search_history_error_path" \
                            >>"$inspection_errors_path"
                    fi
                fi
            fi

            case "$store_label" in
                normal)
                    normal_store_state=$store_state
                    normal_search_history_entry_count=$search_history_entry_count
                    normal_search_history_state=$search_history_state
                    ;;
                ui_test)
                    ui_test_store_state=$store_state
                    ui_test_search_history_entry_count=$search_history_entry_count
                    ui_test_search_history_state=$search_history_state
                    ;;
                performance)
                    performance_store_state=$store_state
                    performance_search_history_entry_count=$search_history_entry_count
                    performance_search_history_state=$search_history_state
                    ;;
            esac

            if [ "$search_history_entry_count" != unknown ] && \
                [ "$search_history_entry_count" -gt 0 ]
            then
                add_failure \
                    "WebKit-managed SearchHistory is nonempty for the $store_label store: $search_history_entry_count search terms"
            fi
        done
    else
        add_warning \
            "WebKit root is absent; no WebKit-managed website data is persisted"
    fi

    for saved_state_specification in \
        "tmp:$saved_state_tmp_root" \
        "library:$saved_state_library_root"
    do
        saved_state_label=${saved_state_specification%%:*}
        saved_state_root=${saved_state_specification#*:}
        [ -d "$saved_state_root" ] || continue
        saved_state_root_count=$((saved_state_root_count + 1))

        saved_state_absolute_inventory="$output_directory/saved-state-$saved_state_label.absolute"
        if ! /usr/bin/find "$saved_state_root" -mindepth 1 -print \
            >"$saved_state_absolute_inventory" 2>>"$inspection_errors_path"
        then
            add_failure \
                "saved-state root could not be inspected: $saved_state_label"
            continue
        fi

        while IFS= read -r saved_state_path; do
            [ -n "$saved_state_path" ] || continue
            saved_state_relative=${saved_state_path#"$saved_state_root/"}
            if [ -f "$saved_state_path" ]; then
                saved_state_type=file
                saved_state_size=$(
                    /usr/bin/stat -f '%z' "$saved_state_path" \
                        2>>"$inspection_errors_path" || /usr/bin/printf 'unknown'
                )
            elif [ -d "$saved_state_path" ]; then
                saved_state_type=directory
                saved_state_size=not-applicable
            else
                saved_state_type=other
                saved_state_size=unknown
            fi
            /usr/bin/printf '%s|%s|type=%s|bytes=%s\n' \
                "$saved_state_label" \
                "$saved_state_relative" \
                "$saved_state_type" \
                "$saved_state_size" >>"$saved_state_inventory_path"
            saved_state_entry_count=$((saved_state_entry_count + 1))

            lower_saved_name=$(
                /usr/bin/printf '%s' "$saved_state_relative" |
                    /usr/bin/tr '[:upper:]' '[:lower:]'
            )
            case "$lower_saved_name" in
                *history* | *visit* | *session* | *navigation* | \
                *recently*closed* | *recent*closed*)
                    add_failure \
                        "unexpected saved-state artifact name: $saved_state_label/$saved_state_relative"
                    saved_state_marker_count=$((
                        saved_state_marker_count + 1
                    ))
                    ;;
            esac

            if [ -f "$saved_state_path" ]; then
                case "$saved_state_path" in
                    *.plist)
                        if ! /usr/bin/plutil -lint "$saved_state_path" \
                            >/dev/null 2>>"$inspection_errors_path"
                        then
                            add_failure \
                                "invalid saved-state plist: $saved_state_label/$saved_state_relative"
                        fi
                        ;;
                esac

                marker_count=$(
                    /usr/bin/strings -a "$saved_state_path" \
                        2>>"$inspection_errors_path" |
                        /usr/bin/awk '
                            {
                                value = tolower($0)
                                if (value ~ /browsermainwindow/ ||
                                    value ~ /browseraddressfield/ ||
                                    value ~ /browserwebview/ ||
                                    value ~ /phase[0-9]+-history-sentinel/ ||
                                    value ~ /https:\/\// ||
                                    value ~ /http:\/\/(127[.]0[.]0[.]1|localhost)([:\/]|$)/) {
                                    count += 1
                                }
                            }
                            END { print count + 0 }
                        '
                )
                if [ "$marker_count" -gt 0 ]; then
                    add_failure \
                        "browser page/session markers found in saved state: $saved_state_label/$saved_state_relative ($marker_count markers)"
                    saved_state_marker_count=$((
                        saved_state_marker_count + marker_count
                    ))
                fi
            fi
        done <"$saved_state_absolute_inventory"
    done
fi

if [ -s "$inspection_errors_path" ]; then
    add_failure \
        "one or more container paths could not be inspected; see inspection-errors.txt"
fi

LC_ALL=C /usr/bin/sort -o "$findings_path" "$findings_path"
LC_ALL=C /usr/bin/sort -o "$warnings_path" "$warnings_path"
LC_ALL=C /usr/bin/sort \
    -o "$saved_state_inventory_path" "$saved_state_inventory_path"

failure_count=$(line_count "$findings_path")
warning_count=$(line_count "$warnings_path")
result=PASS
if [ "$failure_count" -ne 0 ]; then
    result=FAIL
fi

{
    echo "audit=Browser container no-history invariant"
    echo "timestamp_utc=$timestamp_utc"
    echo "mode=read-only container inspection"
    echo "container_root=$container_root"
    echo "container_state=$container_state"
    echo "application_owned_root=$application_owned_root"
    echo "application_owned_state=$application_owned_state"
    echo "application_owned_entry_count=$application_owned_entry_count"
    echo "application_owned_database_like_count=$application_owned_database_count"
    echo "application_owned_forbidden_name_count=$application_owned_forbidden_name_count"
    echo "application_owned_unexpected_entry_count=$application_owned_unexpected_count"
    echo "documents_entry_count=$documents_entry_count"
    echo "production_preferences_state=$production_preferences_state"
    echo "production_preference_key_count=$production_preference_key_count"
    echo "forbidden_preference_key_count=$forbidden_preference_key_count"
    echo "unexpected_preference_key_count=$unexpected_preference_key_count"
    echo "saved_state_root_count=$saved_state_root_count"
    echo "saved_state_entry_count=$saved_state_entry_count"
    echo "saved_state_browser_or_session_marker_count=$saved_state_marker_count"
    echo "webkit_root_state=$webkit_state"
    echo "webkit_website_data_store_count=$website_data_store_count"
    echo "webkit_content_rule_list_file_count=$content_rule_list_file_count"
    echo "normal_store_state=$normal_store_state"
    echo "normal_search_history_state=$normal_search_history_state"
    echo "normal_search_history_entry_count=$normal_search_history_entry_count"
    echo "ui_test_store_state=$ui_test_store_state"
    echo "ui_test_search_history_state=$ui_test_search_history_state"
    echo "ui_test_search_history_entry_count=$ui_test_search_history_entry_count"
    echo "performance_store_state=$performance_store_state"
    echo "performance_search_history_state=$performance_search_history_state"
    echo "performance_search_history_entry_count=$performance_search_history_entry_count"
    echo "system_managed_cache_database_count=$system_cache_database_count"
    echo "system_managed_http_storage_database_count=$system_http_storage_database_count"
    echo "unexpected_durable_database_like_count=$unexpected_durable_database_count"
    echo "unexpected_durable_history_or_session_name_count=$unexpected_durable_name_count"
    echo "failure_count=$failure_count"
    echo "warning_count=$warning_count"
    echo "result=$result"
} >"$report_path"

/bin/cat "$report_path"
if [ "$warning_count" -gt 0 ]; then
    echo "Warnings:"
    /bin/cat "$warnings_path"
fi
echo "Artifacts: $output_directory"

if [ "$result" = FAIL ]; then
    echo "Container audit findings:" >&2
    /bin/cat "$findings_path" >&2
    exit 1
fi

echo "PASS: no application-owned visit, history, session, or recently-closed persistence was found."
