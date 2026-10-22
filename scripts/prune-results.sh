#!/bin/sh

# Keep only the newest run-output directories of one kind under .build.
# Callers prune after creating their own mktemp directory, so the current run
# is always the newest and is never removed.

set -eu

usage() {
    echo "usage: $0 <prefix> [keep]   (removes .build/<prefix>.* beyond the newest keep; default BROWSER_KEEP_RESULTS or 3)" >&2
    exit 2
}

[ "$#" -ge 1 ] && [ "$#" -le 2 ] || usage
prefix=$1
keep=${2:-${BROWSER_KEEP_RESULTS:-3}}
case "$prefix" in
    '' | .* | */* | *[!A-Za-z0-9.]*) usage ;;
esac
case "$keep" in
    '' | *[!0-9]*)
        echo "keep must be a non-negative integer: $keep" >&2
        exit 2
        ;;
esac

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build_root="$project_root/.build"
[ -d "$build_root" ] || exit 0

# mktemp names (prefix.XXXXXX) contain no whitespace or newlines. Symlinks and
# files are neither counted nor removed.
/bin/ls -1dt "$build_root/$prefix".* 2>/dev/null \
    | while IFS= read -r directory; do
        if [ ! -d "$directory" ] || [ -L "$directory" ]; then
            continue
        fi
        if [ "$keep" -gt 0 ]; then
            keep=$((keep - 1))
            continue
        fi
        /bin/rm -rf -- "$directory"
    done
