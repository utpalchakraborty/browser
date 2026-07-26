#!/usr/bin/python3

import argparse
import json
import math
import re
import statistics
import sys
from pathlib import Path


MEBIBYTE = 1024 * 1024


def nearest_rank(values, percentile):
    ordered = sorted(values)
    index = max(0, math.ceil(percentile * len(ordered)) - 1)
    return ordered[index]


def natural_sample_number(path):
    match = re.search(r"memory-(\d+)\.footprint\.json$", path.name)
    return int(match.group(1)) if match else 0


def memory_summary(output_directory, ceiling_bytes):
    paths = sorted(
        output_directory.glob("memory-*.footprint.json"),
        key=natural_sample_number,
    )
    totals = []
    process_counts = []
    for path in paths:
        report = json.loads(path.read_text())
        if report.get("errors"):
            raise ValueError(f"{path.name} contains footprint errors")
        totals.append(int(report["total footprint"]))
        process_counts.append(len(report["processes"]))

    if not totals:
        return None

    result = {
        "samples": len(totals),
        "totals_bytes": totals,
        "minimum_bytes": min(totals),
        "median_bytes": statistics.median(totals),
        "p95_bytes": nearest_rank(totals, 0.95),
        "maximum_bytes": max(totals),
        "minimum_process_count": min(process_counts),
        "maximum_process_count": max(process_counts),
        "ceiling_bytes": ceiling_bytes,
    }
    result["passed"] = result["p95_bytes"] <= ceiling_bytes
    return result


def cpu_blocks(top_output):
    blocks = []
    current = None
    for line in top_output.splitlines():
        if line.startswith("PID") and "%CPU" in line:
            current = {}
            blocks.append(current)
            continue
        if current is None or not line or line.startswith("Processes:"):
            continue
        fields = line.split()
        if len(fields) < 3 or not fields[0].isdigit():
            continue
        try:
            current[int(fields[0])] = float(fields[2].rstrip("%"))
        except ValueError:
            continue
    return blocks


def cpu_summary(output_directory, expected_samples, ceiling_percent):
    top_path = output_directory / "cpu.top.txt"
    if not top_path.exists():
        return None

    pid_path = output_directory / "cpu.pids.txt"
    expected_pids = {int(value) for value in pid_path.read_text().split()}
    blocks = cpu_blocks(top_path.read_text())
    if not blocks:
        raise ValueError("top produced no process samples")

    # macOS top's first sample is cumulative since process launch. The
    # remaining samples represent the requested one-second intervals.
    measured_blocks = blocks[1:]
    if len(measured_blocks) != expected_samples:
        raise ValueError(
            f"expected {expected_samples} CPU samples, found "
            f"{len(measured_blocks)}"
        )

    totals = []
    for index, block in enumerate(measured_blocks, start=1):
        missing = expected_pids.difference(block)
        if missing:
            raise ValueError(
                f"CPU sample {index} is missing PIDs: "
                + ", ".join(str(pid) for pid in sorted(missing))
            )
        totals.append(sum(block[pid] for pid in expected_pids))

    result = {
        "samples": len(totals),
        "aggregate_percent_samples": totals,
        "average_percent": statistics.mean(totals),
        "p95_percent": nearest_rank(totals, 0.95),
        "maximum_percent": max(totals),
        "ceiling_average_percent": ceiling_percent,
    }
    result["passed"] = result["average_percent"] < ceiling_percent
    return result


def format_bytes(value):
    return f"{value / MEBIBYTE:.1f} MiB"


def text_summary(report):
    lines = [
        f"Resource baseline: {report['scenario']}",
        f"Artifacts: {report['artifacts']}",
    ]
    memory = report.get("memory")
    if memory:
        lines.extend(
            [
                (
                    "Memory: "
                    f"min {format_bytes(memory['minimum_bytes'])}, "
                    f"median {format_bytes(memory['median_bytes'])}, "
                    f"p95 {format_bytes(memory['p95_bytes'])}, "
                    f"max {format_bytes(memory['maximum_bytes'])}"
                ),
                (
                    f"Memory gate: {'PASS' if memory['passed'] else 'FAIL'} "
                    f"(p95 <= {format_bytes(memory['ceiling_bytes'])})"
                ),
            ]
        )
    cpu = report.get("cpu")
    if cpu:
        lines.extend(
            [
                (
                    f"Idle CPU: average {cpu['average_percent']:.3f}%, "
                    f"p95 {cpu['p95_percent']:.3f}%, "
                    f"max {cpu['maximum_percent']:.3f}%"
                ),
                (
                    f"CPU gate: {'PASS' if cpu['passed'] else 'FAIL'} "
                    f"(average < {cpu['ceiling_average_percent']:.1f}%)"
                ),
            ]
        )
    lines.append(f"Overall: {'PASS' if report['passed'] else 'FAIL'}")
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--directory", required=True, type=Path)
    parser.add_argument("--views", required=True, choices=(1, 10), type=int)
    parser.add_argument("--cpu-samples", required=True, type=int)
    arguments = parser.parse_args()

    memory_ceiling = 300 * MEBIBYTE if arguments.views == 1 else 1024 * MEBIBYTE
    memory = memory_summary(arguments.directory, memory_ceiling)
    cpu = cpu_summary(arguments.directory, arguments.cpu_samples, 1.0)
    checks = [result["passed"] for result in (memory, cpu) if result]
    report = {
        "scenario": f"{arguments.views} resident view"
        + ("" if arguments.views == 1 else "s"),
        "artifacts": str(arguments.directory),
        "memory": memory,
        "cpu": cpu,
        "passed": bool(checks) and all(checks),
    }

    summary_text = text_summary(report)
    (arguments.directory / "summary.json").write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n"
    )
    (arguments.directory / "summary.txt").write_text(summary_text)
    print(summary_text, end="")
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (KeyError, OSError, ValueError, json.JSONDecodeError) as error:
        print(f"resource summary failed: {error}", file=sys.stderr)
        sys.exit(1)
