#!/usr/bin/python3

import argparse
import json
import math
import statistics
import sys
from pathlib import Path


APPLICATION_METRIC = "Duration (ApplicationFirstFramePresentationResponsive)"
WINDOW_METRIC = "Duration (InitialWindowPresentation)"
CONSTRUCTION_METRIC = "Duration (InitialWebViewConstruction)"
NAVIGATION_METRIC = "Duration (FirstBlankNavigation)"
EXPECTED_SAMPLE_COUNT = 20


def nearest_rank(values, percentile):
    ordered = sorted(values)
    return ordered[max(0, math.ceil(percentile * len(ordered)) - 1)]


def summarize_seconds(values):
    milliseconds = [value * 1000 for value in values]
    return {
        "samples": len(milliseconds),
        "minimum_ms": min(milliseconds),
        "median_ms": statistics.median(milliseconds),
        "mean_ms": statistics.mean(milliseconds),
        "p95_ms": nearest_rank(milliseconds, 0.95),
        "maximum_ms": max(milliseconds),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--metrics", required=True, type=Path)
    arguments = parser.parse_args()

    reports = json.loads(arguments.metrics.read_text())
    if len(reports) != 1 or len(reports[0].get("testRuns", [])) != 1:
        raise ValueError("expected exactly one measured test run")
    metrics = reports[0]["testRuns"][0].get("metrics", [])
    by_name = {
        metric["displayName"]: metric["measurements"] for metric in metrics
    }
    if not by_name:
        raise ValueError("Xcode returned no performance metrics")

    required_metric_names = (
        APPLICATION_METRIC,
        WINDOW_METRIC,
        CONSTRUCTION_METRIC,
        NAVIGATION_METRIC,
    )
    missing_metrics = [
        name for name in required_metric_names if name not in by_name
    ]
    if missing_metrics:
        raise ValueError(
            "required launch metrics are missing: " + ", ".join(missing_metrics)
        )
    for name in required_metric_names:
        sample_count = len(by_name[name])
        if sample_count != EXPECTED_SAMPLE_COUNT:
            raise ValueError(
                f"expected {EXPECTED_SAMPLE_COUNT} samples for {name}, "
                f"found {sample_count}"
            )

    summaries = {
        name: summarize_seconds(values) for name, values in by_name.items()
    }
    application = summaries.get(APPLICATION_METRIC)
    if application is None:
        raise ValueError("application first-frame metric is missing")
    application["p50_ceiling_ms"] = 500.0
    application["p95_ceiling_ms"] = 800.0
    application["passed"] = (
        application["median_ms"] <= application["p50_ceiling_ms"]
        and application["p95_ms"] <= application["p95_ceiling_ms"]
    )

    construction = by_name[CONSTRUCTION_METRIC]
    navigation = by_name[NAVIGATION_METRIC]
    application_values = by_name[APPLICATION_METRIC]
    # WebKit construction and first navigation are deliberately deferred until
    # after native chrome. Their sum with Xcode's first-frame metric is a
    # conservative readiness proxy; it is not presented as a direct end-to-end
    # signpost measurement.
    proxy_values = [
        application_value + construction_value + navigation_value
        for application_value, construction_value, navigation_value in zip(
            application_values, construction, navigation
        )
    ]
    derived = summarize_seconds(proxy_values)
    derived["description"] = (
        "first-frame + WebKit construction + first blank navigation"
    )
    derived["p95_ceiling_ms"] = 1200.0
    derived["passed"] = derived["p95_ms"] <= derived["p95_ceiling_ms"]

    report = {
        "metrics": summaries,
        "initial_webview_readiness_proxy": derived,
        "expected_samples_per_metric": EXPECTED_SAMPLE_COUNT,
        "passed": application["passed"] and derived["passed"],
    }
    summary_path = arguments.metrics.with_name("summary.json")
    summary_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")

    for name, summary in summaries.items():
        print(
            f"{name}: min {summary['minimum_ms']:.3f} ms, "
            f"median {summary['median_ms']:.3f} ms, "
            f"mean {summary['mean_ms']:.3f} ms, "
            f"p95 {summary['p95_ms']:.3f} ms, "
            f"max {summary['maximum_ms']:.3f} ms "
            f"({summary['samples']} samples)"
        )
    print(
        "Initial web-view readiness proxy: "
        f"median {derived['median_ms']:.3f} ms, "
        f"p95 {derived['p95_ms']:.3f} ms, "
        f"max {derived['maximum_ms']:.3f} ms"
    )
    print(f"Launch gates: {'PASS' if report['passed'] else 'FAIL'}")
    print(f"Summary: {summary_path}")
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (KeyError, OSError, ValueError, json.JSONDecodeError) as error:
        print(f"launch metric summary failed: {error}", file=sys.stderr)
        sys.exit(1)
