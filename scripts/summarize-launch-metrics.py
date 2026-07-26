#!/usr/bin/python3

import argparse
import json
import math
import statistics
import sys
from pathlib import Path


APPLICATION_METRIC = "Duration (ApplicationFirstFramePresentationResponsive)"
WINDOW_METRIC = "Duration (InitialWindowPresentation)"
FOCUS_METRIC = "Duration (InitialAddressFieldFocus)"
DEFERRAL_METRIC = "Duration (InitialWebViewDeferral)"
CONSTRUCTION_METRIC = "Duration (InitialWebViewConstruction)"
NAVIGATION_METRIC = "Duration (FirstBlankNavigation)"
ADDRESS_SUBMISSION_METRIC = "Duration (AddressSubmission)"
BROWSER_COMMAND_METRIC = "Duration (BrowserCommand)"
LOCAL_NAVIGATION_METRIC = "Duration (LocalFixtureNavigation)"
LAUNCH_TEST = (
    "BrowserLaunchPerformanceTests/testFocusedSinglePageBrowserLaunch()"
)
LOCAL_NAVIGATION_TEST = (
    "BrowserLaunchPerformanceTests/"
    "testDeterministicLocalNavigationAndCommandResponse()"
)
BROWSER_COMMAND_TEST = (
    "BrowserLaunchPerformanceTests/testBackAndForwardCommandResponse()"
)
EXPECTED_LAUNCH_SAMPLE_COUNT = 20
EXPECTED_NAVIGATION_SAMPLE_COUNT = 20


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


def report_for_test(reports, test_identifier):
    matches = [
        report
        for report in reports
        if report.get("testIdentifier") == test_identifier
    ]
    if len(matches) != 1:
        raise ValueError(
            f"expected exactly one metrics report for {test_identifier}, "
            f"found {len(matches)}"
        )
    return matches[0]


def metrics_by_name(report, test_identifier):
    test_runs = report.get("testRuns", [])
    if len(test_runs) != 1:
        raise ValueError(
            f"expected exactly one measured run for {test_identifier}"
        )
    metrics = test_runs[0].get("metrics", [])
    by_name = {
        metric["displayName"]: metric["measurements"] for metric in metrics
    }
    if not by_name:
        raise ValueError(f"Xcode returned no metrics for {test_identifier}")
    return by_name


def require_metrics(by_name, names, sample_count, test_identifier):
    missing_metrics = [name for name in names if name not in by_name]
    if missing_metrics:
        raise ValueError(
            f"required metrics are missing for {test_identifier}: "
            + ", ".join(missing_metrics)
        )
    for name in names:
        actual_count = len(by_name[name])
        if actual_count != sample_count:
            raise ValueError(
                f"expected {sample_count} samples for {name}, "
                f"found {actual_count}"
            )


def compare_to_baseline(
    current,
    baseline,
    maximum_regression_percent,
    explained_regression=None,
):
    comparisons = {}
    for statistic in ("median_ms", "p95_ms"):
        baseline_value = baseline[statistic]
        current_value = current[statistic]
        change_percent = (
            (current_value - baseline_value) / baseline_value * 100
        )
        within_unexplained_limit = (
            change_percent <= maximum_regression_percent
        )
        comparisons[statistic] = {
            "baseline_ms": baseline_value,
            "current_ms": current_value,
            "change_percent": change_percent,
            "maximum_regression_percent": maximum_regression_percent,
            "within_unexplained_limit": within_unexplained_limit,
            "passed": (
                within_unexplained_limit
                or isinstance(explained_regression, str)
                and bool(explained_regression.strip())
            ),
        }
    comparisons["explained_regression"] = explained_regression
    comparisons["passed"] = all(
        comparison["passed"]
        for comparison in comparisons.values()
        if isinstance(comparison, dict)
    )
    return comparisons


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--metrics", required=True, nargs="+", type=Path)
    parser.add_argument("--baseline", required=True, type=Path)
    arguments = parser.parse_args()

    reports = []
    for metrics_path in arguments.metrics:
        metrics_reports = json.loads(metrics_path.read_text())
        if not isinstance(metrics_reports, list):
            raise ValueError(
                f"expected a list of Xcode metrics reports in {metrics_path}"
            )
        reports.extend(metrics_reports)
    baseline = json.loads(arguments.baseline.read_text())

    launch_report = report_for_test(reports, LAUNCH_TEST)
    local_navigation_report = report_for_test(
        reports,
        LOCAL_NAVIGATION_TEST,
    )
    browser_command_report = report_for_test(reports, BROWSER_COMMAND_TEST)
    launch_by_name = metrics_by_name(launch_report, LAUNCH_TEST)
    local_navigation_by_name = metrics_by_name(
        local_navigation_report,
        LOCAL_NAVIGATION_TEST,
    )
    browser_command_by_name = metrics_by_name(
        browser_command_report,
        BROWSER_COMMAND_TEST,
    )

    required_launch_metric_names = (
        APPLICATION_METRIC,
        WINDOW_METRIC,
        FOCUS_METRIC,
        DEFERRAL_METRIC,
        CONSTRUCTION_METRIC,
        NAVIGATION_METRIC,
    )
    required_local_navigation_metric_names = (
        ADDRESS_SUBMISSION_METRIC,
        LOCAL_NAVIGATION_METRIC,
    )
    require_metrics(
        launch_by_name,
        required_launch_metric_names,
        EXPECTED_LAUNCH_SAMPLE_COUNT,
        LAUNCH_TEST,
    )
    require_metrics(
        local_navigation_by_name,
        required_local_navigation_metric_names,
        EXPECTED_NAVIGATION_SAMPLE_COUNT,
        LOCAL_NAVIGATION_TEST,
    )
    require_metrics(
        browser_command_by_name,
        (BROWSER_COMMAND_METRIC,),
        EXPECTED_NAVIGATION_SAMPLE_COUNT,
        BROWSER_COMMAND_TEST,
    )

    launch_summaries = {
        name: summarize_seconds(values)
        for name, values in launch_by_name.items()
    }
    local_navigation_summaries = {
        name: summarize_seconds(values)
        for name, values in local_navigation_by_name.items()
    }
    browser_command_summaries = {
        name: summarize_seconds(values)
        for name, values in browser_command_by_name.items()
    }
    application = launch_summaries.get(APPLICATION_METRIC)
    if application is None:
        raise ValueError("application first-frame metric is missing")
    application["p50_ceiling_ms"] = 500.0
    application["p95_ceiling_ms"] = 800.0
    application["passed"] = (
        application["median_ms"] <= application["p50_ceiling_ms"]
        and application["p95_ms"] <= application["p95_ceiling_ms"]
    )

    deferral = launch_by_name[DEFERRAL_METRIC]
    construction = launch_by_name[CONSTRUCTION_METRIC]
    navigation = launch_by_name[NAVIGATION_METRIC]
    application_values = launch_by_name[APPLICATION_METRIC]
    # WebKit construction and first navigation are deliberately deferred until
    # after native chrome. Their sum, including the measured deferral, with
    # Xcode's first-frame metric is a conservative readiness proxy; it is not
    # presented as a direct end-to-end signpost measurement.
    proxy_values = [
        application_value
        + deferral_value
        + construction_value
        + navigation_value
        for (
            application_value,
            deferral_value,
            construction_value,
            navigation_value,
        ) in zip(application_values, deferral, construction, navigation)
    ]
    derived = summarize_seconds(proxy_values)
    derived["description"] = (
        "first-frame + WebKit deferral + construction + first blank navigation"
    )
    derived["p95_ceiling_ms"] = 1200.0
    derived["passed"] = derived["p95_ms"] <= derived["p95_ceiling_ms"]

    command_summaries = [
        local_navigation_summaries[ADDRESS_SUBMISSION_METRIC],
        browser_command_summaries[BROWSER_COMMAND_METRIC],
    ]
    for command in command_summaries:
        command["p95_ceiling_ms"] = 50.0
        command["maximum_ceiling_ms"] = 100.0
        command["passed"] = (
            command["p95_ms"] <= command["p95_ceiling_ms"]
            and command["maximum_ms"] <= command["maximum_ceiling_ms"]
        )

    maximum_regression_percent = baseline[
        "maximum_unexplained_regression_percent"
    ]
    baseline_label = baseline.get("label", "Baseline")
    explained_regressions = baseline.get("explained_regressions", {})
    regression_comparison = {
        "baseline_label": baseline_label,
        "baseline_source_revision": baseline["source_revision"],
        "application_first_frame": compare_to_baseline(
            application,
            baseline["metrics"]["application_first_frame"],
            maximum_regression_percent,
            explained_regressions.get("application_first_frame"),
        ),
        "initial_webview_readiness_proxy": compare_to_baseline(
            derived,
            baseline["metrics"]["initial_webview_readiness_proxy"],
            maximum_regression_percent,
            explained_regressions.get("initial_webview_readiness_proxy"),
        ),
    }
    regression_comparison["passed"] = all(
        regression_comparison[name]["passed"]
        for name in (
            "application_first_frame",
            "initial_webview_readiness_proxy",
        )
    )

    report = {
        "launch_metrics": launch_summaries,
        "local_navigation_metrics": local_navigation_summaries,
        "browser_command_metrics": browser_command_summaries,
        "address_field_focus_asserted_for_each_launch": True,
        "initial_webview_readiness_proxy": derived,
        "expected_launch_samples_per_metric": EXPECTED_LAUNCH_SAMPLE_COUNT,
        "expected_navigation_samples_per_metric": (
            EXPECTED_NAVIGATION_SAMPLE_COUNT
        ),
        "regression_comparison": regression_comparison,
        "passed": (
            application["passed"]
            and derived["passed"]
            and all(command["passed"] for command in command_summaries)
            and regression_comparison["passed"]
        ),
    }
    summary_path = arguments.metrics[0].with_name("summary.json")
    summary_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")

    for name, summary in launch_summaries.items():
        print(
            f"{name}: min {summary['minimum_ms']:.3f} ms, "
            f"median {summary['median_ms']:.3f} ms, "
            f"mean {summary['mean_ms']:.3f} ms, "
            f"p95 {summary['p95_ms']:.3f} ms, "
            f"max {summary['maximum_ms']:.3f} ms "
            f"({summary['samples']} samples)"
        )
    for name, summary in local_navigation_summaries.items():
        print(
            f"{name}: min {summary['minimum_ms']:.3f} ms, "
            f"median {summary['median_ms']:.3f} ms, "
            f"mean {summary['mean_ms']:.3f} ms, "
            f"p95 {summary['p95_ms']:.3f} ms, "
            f"max {summary['maximum_ms']:.3f} ms "
            f"({summary['samples']} samples)"
        )
    for name, summary in browser_command_summaries.items():
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
    for name in (
        "application_first_frame",
        "initial_webview_readiness_proxy",
    ):
        comparison = regression_comparison[name]
        explanation = comparison["explained_regression"]
        has_explained_delta = bool(explanation) and any(
            not comparison[statistic]["within_unexplained_limit"]
            for statistic in ("median_ms", "p95_ms")
        )
        outcome = "PASS"
        if has_explained_delta:
            outcome += "; explained checkpoint regression"
        elif not comparison["passed"]:
            outcome = "FAIL"
        print(
            f"{baseline_label} comparison for {name}: "
            f"median {comparison['median_ms']['change_percent']:+.2f}%, "
            f"p95 {comparison['p95_ms']['change_percent']:+.2f}% "
            f"({outcome})"
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
