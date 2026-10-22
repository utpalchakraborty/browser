#!/usr/bin/python3 -I
"""Reproduce or update the bundled AdGuard content-blocking rules (developer only).

The app never runs this, and no Make check depends on it. It needs network
access to download filter sources and, unless --converter is given, to fetch
and build the pinned AdGuard Safari Converter.

  --verify (default)        Rebuild every bundled rule file from the manifest's
                            recorded source and converter; require identical bytes.
  --registry-commit SHA     Regenerate from a newer FiltersRegistry commit with
                            the same pinned converter, then rewrite the rule
                            files and manifest.

After an update, scripts/verify-release.sh still pins the previous manifest
digest. Updating that digest is deliberately manual, so a changed manifest can
never approve its own assets.
"""

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RULES = ROOT / 'Browser' / 'ContentBlockerRules'
MANIFEST = RULES / 'ContentBlockerManifest.json'
CONVERTER_REPOSITORY = 'https://github.com/AdguardTeam/SafariConverterLib.git'
REGISTRY_RAW = 'https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry'
COMMIT = re.compile(r'^[0-9a-f]{40}$')
# Swift seeds hashing per process, so the converter otherwise emits rules in a
# different order on every run. Deterministic hashing makes output reproducible.
CONVERTER_ENVIRONMENT = {'SWIFT_DETERMINISTIC_HASHING': '1'}


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as file:
        for block in iter(lambda: file.read(1 << 20), b''):
            digest.update(block)
    return digest.hexdigest()


def run(command, **kwargs):
    print('+', ' '.join(str(part) for part in command), flush=True)
    subprocess.run([str(part) for part in command], check=True, **kwargs)


def download(url, destination):
    if not url.startswith('https://'):
        sys.exit(f'Refusing a non-HTTPS source: {url}')
    print(f'Downloading {url}', flush=True)
    with urllib.request.urlopen(url, timeout=60) as response, destination.open('wb') as file:
        shutil.copyfileobj(response, file)


def build_converter(converter, work):
    checkout = work / 'SafariConverterLib'
    run(['/usr/bin/git', 'clone', '--quiet', CONVERTER_REPOSITORY, checkout])
    run(['/usr/bin/git', '-C', checkout, 'checkout', '--quiet', converter['commit']])
    run(['/usr/bin/xcrun', 'swift', 'build', '--package-path', checkout,
         '--configuration', 'release', '--product', 'ConverterTool'])
    return checkout / '.build' / 'release' / 'ConverterTool'


def ordering_segments(path):
    """Rules grouped between `ignore-previous-rules` actions, the only WebKit
    action whose effect depends on order. Order within a segment is irrelevant."""
    segments, current = [], {}
    for rule in json.loads(path.read_text(encoding='utf-8')):
        key = json.dumps(rule, sort_keys=True)
        if rule.get('action', {}).get('type') == 'ignore-previous-rules':
            segments.append((current, key))
            current = {}
        else:
            current[key] = current.get(key, 0) + 1
    segments.append((current, None))
    return segments


def header_value(source, name):
    pattern = re.compile(rf'^!\s*{re.escape(name)}:\s*(.+?)\s*$')
    with source.open(encoding='utf-8', errors='replace') as file:
        for _, line in zip(range(100), file):
            if match := pattern.match(line):
                return match.group(1)
    return None


def main(arguments):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--verify', action='store_true', help='reproduce the bundled files (default)')
    mode.add_argument('--registry-commit', help='FiltersRegistry commit to regenerate from')
    parser.add_argument('--converter', type=Path, help='use an existing ConverterTool built from the pinned commit')
    parser.add_argument('--keep-work', action='store_true', help='keep the temporary work directory')
    options = parser.parse_args(arguments)
    if options.registry_commit and not COMMIT.match(options.registry_commit):
        parser.error('--registry-commit must be a full 40-character commit hash')

    manifest = json.loads(MANIFEST.read_text(encoding='utf-8'))
    if manifest.get('schema_version') != 1:
        sys.exit('Unsupported manifest schema; update this script first.')
    converter = manifest['converter']
    work = Path(tempfile.mkdtemp(prefix='browser-blocker-rules-'))
    try:
        tool = options.converter or build_converter(converter, work)
        tool_sha256 = sha256(tool)
        if tool_sha256 != converter['binary_sha256']:
            # Swift builds are not bit-for-bit reproducible across toolchains;
            # the converted output below is the authoritative check.
            print(f'Note: converter binary {tool_sha256} differs from recorded {converter["binary_sha256"]}.')

        mismatches = []
        for rule_set in manifest['rule_sets']:
            source_meta = rule_set['source']
            url = source_meta['url']
            if options.registry_commit:
                url = f'{REGISTRY_RAW}/{options.registry_commit}/{source_meta["path"]}'
            source = work / f'{rule_set["resource"]}.source.txt'
            download(url, source)
            source_sha256 = sha256(source)
            if not options.registry_commit and source_sha256 != source_meta['sha256']:
                mismatches.append(f'{rule_set["display_name"]}: source {source_sha256} != recorded {source_meta["sha256"]}')
                continue

            output = work / f'{rule_set["resource"]}.{rule_set["file_extension"]}'
            environment = dict(os.environ, **converter.get('environment', CONVERTER_ENVIRONMENT))
            run([tool, *converter['arguments'], '--input-path', source, '--safari-rules-json-path', output],
                env=environment)
            output_sha256 = sha256(output)
            rule_count = len(json.loads(output.read_text(encoding='utf-8')))

            if not options.registry_commit:
                bundled = RULES / output.name
                if output_sha256 == rule_set['sha256'] and rule_count == rule_set['rule_count']:
                    print(f'Reproduced {rule_set["display_name"]} byte-for-byte: {output_sha256}')
                elif (sha256(bundled) == rule_set['sha256']
                      and ordering_segments(output) == ordering_segments(bundled)):
                    # Bundles converted before deterministic hashing have an
                    # arbitrary order within segments; their effect is identical.
                    print(f'Reproduced {rule_set["display_name"]} equivalently: same {rule_count} rules and '
                          'ignore-previous-rules sequence; order differs only within segments.')
                else:
                    mismatches.append(
                        f'{rule_set["display_name"]}: output {output_sha256} ({rule_count} rules) '
                        f'!= bundled {rule_set["sha256"]} ({rule_set["rule_count"]} rules)')
                continue

            shutil.copyfile(output, RULES / output.name)
            rule_set.update(
                identifier=f'{rule_set["namespace"]}-{output_sha256}',
                sha256=output_sha256,
                rule_count=rule_count,
            )
            source_meta.update(
                url=url,
                commit=options.registry_commit,
                sha256=source_sha256,
                version=header_value(source, 'Version') or source_meta['version'],
                updated_at=header_value(source, 'TimeUpdated') or source_meta['updated_at'],
            )
            print(f'Updated {rule_set["display_name"]}: {rule_count} rules, {output_sha256}')

        if mismatches:
            print('\n'.join(['Rules did not reproduce:', *mismatches]), file=sys.stderr)
            return 1
        if options.registry_commit:
            converter.setdefault('environment', CONVERTER_ENVIRONMENT)
            MANIFEST.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
            print(f'\nWrote {MANIFEST.relative_to(ROOT)} (sha256 {sha256(MANIFEST)}).')
            print('Next: pin that digest in scripts/verify-release.sh, review the diff, then run '
                  'make test and make verify-release. The first launch recompiles the rules '
                  'and removes the superseded compiled lists.')
        else:
            print('All bundled rule files reproduce from the recorded inputs.')
        return 0
    finally:
        if options.keep_work:
            print(f'Work directory kept: {work}')
        else:
            shutil.rmtree(work, ignore_errors=True)


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
