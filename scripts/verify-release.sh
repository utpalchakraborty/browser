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
case "$signature" in
    *"runtime"*)
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
    *"com.apple.security.get-task-allow"*)
        echo "Release signature unexpectedly allows debugger attachment." >&2
        exit 1
        ;;
esac

entitlement_count=$(
    printf '%s' "$entitlements" |
        awk -F'<key>' '{ count += NF - 1 } END { print count + 0 }'
)
if [ "$entitlement_count" -ne 2 ]; then
    echo "Release signature contains entitlements beyond App Sandbox and outgoing network." >&2
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

echo "Verified arm64, sandboxed, hardened local Release build: $application"
