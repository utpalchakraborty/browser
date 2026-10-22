#!/usr/bin/python3 -I
"""Fail unless every hosted BrowserTests class is selected by exactly one scheme.

Background, interactive, and benchmark schemes use explicit allowlists, so a
new or renamed class would otherwise silently never run.
"""

import re
import sys
import xml.etree.ElementTree as ElementTree
from pathlib import Path

SELECTING_SCHEMES = ('Browser', 'BrowserInteractive', 'BrowserBenchmarks')
TEST_TARGET = 'BrowserTests'
CLASS_DECLARATION = re.compile(r'^\s*(?:final\s+)?class\s+(\w+)\s*:\s*XCTestCase\b', re.MULTILINE)


def declared_classes(root):
    classes = {}
    for path in sorted((root / TEST_TARGET).glob('*.swift')):
        for name in CLASS_DECLARATION.findall(path.read_text(encoding='utf-8')):
            classes.setdefault(name, []).append(path.name)
    return classes


def selected_classes(scheme_path):
    selected = []
    for testable in ElementTree.parse(scheme_path).getroot().iter('TestableReference'):
        reference = testable.find('BuildableReference')
        if reference is None or reference.get('BlueprintName') != TEST_TARGET:
            continue
        if testable.get('skipped', 'NO') == 'YES':
            continue
        for test in testable.iter('Test'):
            identifier = test.get('Identifier', '')
            selected.append(identifier.split('/', 1)[0])
    return selected


def problems(root):
    schemes = root / 'Browser.xcodeproj' / 'xcshareddata' / 'xcschemes'
    declared = declared_classes(root)
    owners = {}
    issues = []
    for name, files in declared.items():
        if len(files) > 1:
            issues.append(f'{name} is declared more than once: {", ".join(files)}')
    for scheme in SELECTING_SCHEMES:
        for name in selected_classes(schemes / f'{scheme}.xcscheme'):
            owners.setdefault(name, []).append(scheme)
    for name in sorted(declared):
        scheme_names = owners.get(name, [])
        if not scheme_names:
            issues.append(f'{name} is not selected by any scheme ({", ".join(SELECTING_SCHEMES)})')
        elif len(scheme_names) > 1:
            issues.append(f'{name} is selected more than once: {", ".join(scheme_names)}')
    for name in sorted(set(owners) - set(declared)):
        issues.append(f'{name} is selected by {", ".join(owners[name])} but no such class exists')
    return issues


def main(arguments):
    if len(arguments) > 1:
        print('usage: check-test-selection.py [project-root]', file=sys.stderr)
        return 2
    root = Path(arguments[0]) if arguments else Path(__file__).resolve().parent.parent
    issues = problems(root)
    for issue in issues:
        print(f'Test selection: {issue}', file=sys.stderr)
    return 1 if issues else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
