#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if [ "${BROWSER_VERIFICATION_SUPERVISED:-}" != 1 ]; then
    exec /usr/bin/python3 "$project_root/scripts/verification-session.py" "$0" "$@"
fi
if [ "$#" -gt 1 ]; then echo "usage: $0 [--build-only]" >&2; exit 2; fi
case "${1:-}" in
    ''|--build-only) ;;
    *) echo "usage: $0 [--build-only]" >&2; exit 2 ;;
esac
directory="$project_root/.build/BookmarkBenchmark"
mkdir -p "$directory"
xcrun --sdk macosx swiftc -O -whole-module-optimization -num-threads "$BROWSER_BUILD_JOBS" \
    -parse-as-library -swift-version 6 -strict-concurrency=complete -default-isolation MainActor \
    -module-cache-path "$directory/ModuleCache" -D BOOKMARK_REPOSITORY_BENCHMARK \
    "$project_root/Browser/Bookmark.swift" "$project_root/Browser/BookmarkSearch.swift" \
    "$project_root/Browser/LocalFileAccess.swift" "$project_root/Browser/BookmarkRepository.swift" \
    "$project_root/BrowserPerformanceTests/BookmarkRepositoryBenchmark.swift" \
    -o "$directory/BookmarkRepositoryBenchmark"
if [ "${1:-}" != --build-only ]; then
    echo 'Background bookmark benchmark. Desktop contention affects timings; no UI suite is launched.'
    "$directory/BookmarkRepositoryBenchmark"
fi
