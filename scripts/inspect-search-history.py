#!/usr/bin/python3

"""Inspect WebKit's SearchHistory directory without exposing saved terms."""

from __future__ import annotations

import argparse
import os
import plistlib
import stat
import sys
from pathlib import Path


class InspectionError(Exception):
    pass


def inspect_search_history(root: Path) -> int:
    try:
        root_stat = root.lstat()
    except OSError as error:
        raise InspectionError(
            f"directory metadata is unreadable: {error.strerror}"
        ) from error

    if stat.S_ISLNK(root_stat.st_mode):
        raise InspectionError("SearchHistory root is a symbolic link")
    if not stat.S_ISDIR(root_stat.st_mode):
        raise InspectionError("SearchHistory root is not a directory")

    try:
        entries = list(os.scandir(root))
    except OSError as error:
        raise InspectionError(f"directory contents are unreadable: {error.strerror}") from error

    unexpected_count = sum(entry.name != "RecentSearches.plist" for entry in entries)
    expected_entries = [entry for entry in entries if entry.name == "RecentSearches.plist"]
    if unexpected_count:
        raise InspectionError(
            f"SearchHistory contains {unexpected_count} unrecognized artifact(s)"
        )
    if not expected_entries:
        return 0

    recent_searches = expected_entries[0]
    try:
        descriptor = os.open(
            recent_searches.path,
            os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0),
        )
    except OSError as error:
        raise InspectionError(
            f"RecentSearches.plist could not be opened safely: {error.strerror}"
        ) from error

    try:
        file_stat = os.fstat(descriptor)
        if not stat.S_ISREG(file_stat.st_mode):
            raise InspectionError("RecentSearches.plist is not a regular file")
        with os.fdopen(descriptor, "rb") as plist_file:
            descriptor = -1
            payload = plistlib.load(plist_file)
    except (OSError, plistlib.InvalidFileException, ValueError) as error:
        raise InspectionError("RecentSearches.plist is not a readable property list") from error
    finally:
        if descriptor >= 0:
            os.close(descriptor)

    if not isinstance(payload, dict) or set(payload) != {"items"}:
        raise InspectionError("RecentSearches.plist has an unrecognized top-level schema")

    items = payload["items"]
    if not isinstance(items, dict):
        raise InspectionError("RecentSearches.plist items is not a dictionary")

    search_term_count = 0
    for autosave_name, recent_terms in items.items():
        if not isinstance(autosave_name, str) or not isinstance(recent_terms, list):
            raise InspectionError(
                "RecentSearches.plist items has an unrecognized entry schema"
            )
        if not all(isinstance(term, str) for term in recent_terms):
            raise InspectionError("RecentSearches.plist contains a non-string search term")
        search_term_count += len(recent_terms)

    return search_term_count


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("search_history_root", type=Path)
    arguments = parser.parse_args()

    try:
        count = inspect_search_history(arguments.search_history_root)
    except InspectionError as error:
        print(f"search-history inspection failed: {error}", file=sys.stderr)
        return 1

    print(count)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
