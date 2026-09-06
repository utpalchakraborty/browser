#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
echo 'Background blocker benchmark. Desktop contention affects timings; no UI suite is launched.'
exec "$project_root/scripts/run-tests.sh" --blocker-benchmark "$@"
