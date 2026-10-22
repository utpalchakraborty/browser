#!/bin/sh

set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
application=${1:-"$project_root/.build/DerivedData/Build/Products/Release/Browser.app"}

if [ ! -d "$application" ]; then
    echo "Release application not found: $application" >&2
    exit 1
fi

/usr/bin/codesign --verify --deep --strict --verbose=2 "$application"

signature=$(/usr/bin/codesign --display --verbose=4 "$application" 2>&1)
case "$signature" in
    *"Signature=adhoc"*)
        ;;
    *)
        echo "Release signature is not ad-hoc." >&2
        echo "$signature" >&2
        exit 1
        ;;
esac
# Read only the CodeDirectory flag names; the full output also contains paths.
code_directory_flags=$(
    printf '%s\n' "$signature" \
        | /usr/bin/sed -n 's/^CodeDirectory .* flags=0x[0-9a-fA-F]*(\([^)]*\)).*/,\1,/p'
)
case "$code_directory_flags" in
    *",runtime,"*)
        ;;
    *)
        echo "Release signature is missing the hardened-runtime flag." >&2
        echo "$signature" >&2
        exit 1
        ;;
esac

entitlements=$(
    /usr/bin/codesign --display --entitlements :- "$application" 2>/dev/null
)
case "$entitlements" in
    *"<key>com.apple.security.app-sandbox</key><true/>"*)
        ;;
    *)
        echo "Release signature is missing the App Sandbox entitlement." >&2
        echo "$entitlements" >&2
        exit 1
        ;;
esac
case "$entitlements" in
    *"<key>com.apple.security.network.client</key><true/>"*)
        ;;
    *)
        echo "Release signature is missing the outgoing-network entitlement." >&2
        echo "$entitlements" >&2
        exit 1
        ;;
esac
case "$entitlements" in
    *"<key>com.apple.security.files.user-selected.read-only</key><true/>"*)
        ;;
    *)
        echo "Release signature is missing the user-selected read-only file entitlement." >&2
        echo "$entitlements" >&2
        exit 1
        ;;
esac

case "$entitlements" in
    *"com.apple.security.get-task-allow"*)
        echo "Release signature unexpectedly allows debugger attachment." >&2
        exit 1
        ;;
esac

entitlement_count=$(
    printf '%s' "$entitlements" |
        awk -F'<key>' '{ count += NF - 1 } END { print count + 0 }'
)
if [ "$entitlement_count" -ne 3 ]; then
    echo "Release signature contains entitlements beyond App Sandbox, outgoing network, and user-selected read-only files." >&2
    echo "$entitlements" >&2
    exit 1
fi

architectures=$(/usr/bin/lipo -archs "$application/Contents/MacOS/Browser")
if [ "$architectures" != "arm64" ]; then
    echo "Release architecture is '$architectures', expected 'arm64'." >&2
    exit 1
fi

symbols=$(/usr/bin/nm "$application/Contents/MacOS/Browser")
case "$symbols" in
    *"___llvm_profile"*)
        echo "Release binary unexpectedly contains coverage instrumentation." >&2
        exit 1
        ;;
esac

if /usr/bin/strings "$application/Contents/MacOS/Browser" |
    /usr/bin/grep -Eq 'BROWSER_PROFILE_PROBE|profile-persistence-probe'
then
    echo "Release binary unexpectedly contains the DEBUG profile probe." >&2
    exit 1
fi

resources="$application/Contents/Resources"
manifest="$resources/ContentBlockerManifest.json"
if [ ! -f "$manifest" ]; then
    echo "Release application is missing ContentBlockerManifest.json." >&2
    exit 1
fi

assert_sha256() {
    file=$1
    expected=$2
    actual=$(
        /usr/bin/shasum -a 256 "$file" | /usr/bin/awk '{ print $1 }'
    )
    if [ "$actual" != "$expected" ]; then
        echo "Release resource hash mismatch: $file" >&2
        exit 1
    fi
}

# This digest is deliberately independent of the manifest being inspected.
# Updating the production package therefore requires an explicit verifier
# update rather than allowing a changed manifest to approve its own assets.
assert_sha256 \
    "$manifest" \
    328c4deb1f586d69d718f46092e413f99b9893306150c2b0fca7bb21aeb7adfe

for index in 0 1; do
    resource=$(
        /usr/bin/plutil -extract "rule_sets.$index.resource" raw -o - "$manifest"
    )
    file_extension=$(
        /usr/bin/plutil -extract "rule_sets.$index.file_extension" raw -o - "$manifest"
    )
    expected_sha256=$(
        /usr/bin/plutil -extract "rule_sets.$index.sha256" raw -o - "$manifest"
    )
    rules="$resources/$resource.$file_extension"
    if [ ! -f "$rules" ]; then
        echo "Release application is missing $resource.$file_extension." >&2
        exit 1
    fi
    actual_sha256=$(
        /usr/bin/shasum -a 256 "$rules" | /usr/bin/awk '{ print $1 }'
    )
    if [ "$actual_sha256" != "$expected_sha256" ]; then
        echo "Release content-blocker hash mismatch for $resource." >&2
        exit 1
    fi
done

notices="$resources/AdGuardContentBlockerThirdPartyNotices.md"
license="$resources/AdGuard-Filters-GPL-3.0.txt"
for required_file in "$notices" "$license"; do
    if [ ! -f "$required_file" ]; then
        echo "Release application is missing $(basename "$required_file")." >&2
        exit 1
    fi
done
assert_sha256 \
    "$notices" \
    1721cb96a2958945f85ea3389f8373a3d7938b9a2e4d447faa2cf118aa37de40
assert_sha256 \
    "$license" \
    3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986

if /usr/bin/find "$resources" -type f \( \
    -name '*_optimized.txt' -o -name 'ConverterTool' \
\) | /usr/bin/grep -q .
then
    echo "Release application unexpectedly ships filter inputs or converter tooling." >&2
    exit 1
fi

echo "Verified arm64, sandboxed, hardened Release with pinned blocker assets: $application"
