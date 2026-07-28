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
TAB_CREATION_METRIC = "Duration (TabCreation)"
TAB_SELECTION_METRIC = "Duration (TabSelection)"
TAB_CHURN_ABSOLUTE_MEMORY_METRIC = "Absolute Memory Physical (browser)"
TAB_CHURN_PEAK_MEMORY_METRIC = "Memory Peak Physical (browser)"
TAB_CHURN_DELTA_MEMORY_METRIC = "Memory Physical (browser)"
SCROLL_HITCH_DURATION_METRIC = "Hitches Total Duration (browser)"
SCROLL_HITCH_COUNT_METRIC = "Number of Hitches (browser)"
SCROLL_HITCH_RATIO_METRIC = "Hitch Time Ratio (browser)"
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
SCROLL_TEST = (
    "BrowserLaunchPerformanceTests/testControlledScrollingResponsiveness()"
)
TAB_CREATION_TEST = (
    "BrowserLaunchPerformanceTests/testNewBlankTabChromeResponse()"
)
TAB_SELECTION_TEST = (
    "BrowserLaunchPerformanceTests/testSwitchBetweenTenResidentTabs()"
)
TAB_CHURN_TEST = (
    "BrowserLaunchPerformanceTests/"
    "testOneHundredBlankTabOpenCloseCycles()"
)
EXPECTED_LAUNCH_SAMPLE_COUNT = 20
EXPECTED_NAVIGATION_SAMPLE_COUNT = 20
EXPECTED_SCROLL_SAMPLE_COUNT = 10
EXPECTED_TAB_CREATION_SAMPLE_COUNT = 20
EXPECTED_TAB_SELECTION_SAMPLE_COUNT = 50
EXPECTED_TAB_CHURN_SAMPLE_COUNT = 10


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


def summarize_values(values, unit):
    return {
        "samples": len(values),
        "unit": unit,
        "minimum": min(values),
        "median": statistics.median(values),
        "mean": statistics.mean(values),
        "p95": nearest_rank(values, 0.95),
        "maximum": max(values),
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


def metric_units_by_name(report, test_identifier):
    test_runs = report.get("testRuns", [])
    if len(test_runs) != 1:
        raise ValueError(
            f"expected exactly one measured run for {test_identifier}"
        )
    return {
        metric["displayName"]: metric.get("unitOfMeasurement", "")
        for metric in test_runs[0].get("metrics", [])
    }


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
    scroll_report = report_for_test(reports, SCROLL_TEST)
    tab_creation_report = report_for_test(reports, TAB_CREATION_TEST)
    tab_selection_report = report_for_test(reports, TAB_SELECTION_TEST)
    tab_churn_report = report_for_test(reports, TAB_CHURN_TEST)
    launch_by_name = metrics_by_name(launch_report, LAUNCH_TEST)
    local_navigation_by_name = metrics_by_name(
        local_navigation_report,
        LOCAL_NAVIGATION_TEST,
    )
    browser_command_by_name = metrics_by_name(
        browser_command_report,
        BROWSER_COMMAND_TEST,
    )
    scroll_by_name = metrics_by_name(scroll_report, SCROLL_TEST)
    tab_creation_by_name = metrics_by_name(
        tab_creation_report,
        TAB_CREATION_TEST,
    )
    tab_selection_by_name = metrics_by_name(
        tab_selection_report,
        TAB_SELECTION_TEST,
    )
    tab_churn_by_name = metrics_by_name(tab_churn_report, TAB_CHURN_TEST)
    tab_churn_units_by_name = metric_units_by_name(
        tab_churn_report,
        TAB_CHURN_TEST,
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
    required_scroll_metric_names = (
        SCROLL_HITCH_DURATION_METRIC,
        SCROLL_HITCH_COUNT_METRIC,
        SCROLL_HITCH_RATIO_METRIC,
    )
    require_metrics(
        scroll_by_name,
        required_scroll_metric_names,
        EXPECTED_SCROLL_SAMPLE_COUNT,
        SCROLL_TEST,
    )
    require_metrics(
        tab_creation_by_name,
        (TAB_CREATION_METRIC,),
        EXPECTED_TAB_CREATION_SAMPLE_COUNT,
        TAB_CREATION_TEST,
    )
    require_metrics(
        tab_selection_by_name,
        (TAB_SELECTION_METRIC,),
        EXPECTED_TAB_SELECTION_SAMPLE_COUNT,
        TAB_SELECTION_TEST,
    )
    required_tab_churn_metric_names = (
        TAB_CHURN_ABSOLUTE_MEMORY_METRIC,
        TAB_CHURN_PEAK_MEMORY_METRIC,
        TAB_CHURN_DELTA_MEMORY_METRIC,
    )
    require_metrics(
        tab_churn_by_name,
        required_tab_churn_metric_names,
        EXPECTED_TAB_CHURN_SAMPLE_COUNT,
        TAB_CHURN_TEST,
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
    tab_creation = summarize_seconds(
        tab_creation_by_name[TAB_CREATION_METRIC]
    )
    tab_creation["p95_ceiling_ms"] = 100.0
    tab_creation["passed"] = (
        tab_creation["p95_ms"] <= tab_creation["p95_ceiling_ms"]
    )
    tab_selection = summarize_seconds(
        tab_selection_by_name[TAB_SELECTION_METRIC]
    )
    tab_selection["resident_tab_count"] = 10
    tab_selection["p95_ceiling_ms"] = 50.0
    tab_selection["passed"] = (
        tab_selection["p95_ms"] <= tab_selection["p95_ceiling_ms"]
    )
    tab_churn_memory_summaries = {}
    for name in required_tab_churn_metric_names:
        unit = tab_churn_units_by_name[name]
        if unit != "kB":
            raise ValueError(
                f"expected kB samples for {name}, found {unit or 'no unit'}"
            )
        summary = summarize_values(tab_churn_by_name[name], unit)
        summary["measurements"] = tab_churn_by_name[name]
        tab_churn_memory_summaries[name] = summary

    absolute_memory_values = tab_churn_by_name[
        TAB_CHURN_ABSOLUTE_MEMORY_METRIC
    ]
    half_sample_count = len(absolute_memory_values) // 2
    first_half_median = statistics.median(
        absolute_memory_values[:half_sample_count]
    )
    second_half_median = statistics.median(
        absolute_memory_values[half_sample_count:]
    )
    growth_percent = (
        (second_half_median - first_half_median)
        / first_half_median
        * 100
    )
    monotonic_growth = (
        absolute_memory_values[-1] > absolute_memory_values[0]
        and all(
            current >= previous
            for previous, current in zip(
                absolute_memory_values,
                absolute_memory_values[1:],
            )
        )
    )
    tab_churn_growth = {
        "criterion": (
            "second-half median absolute footprint is within 10% of the "
            "first-half median"
        ),
        "scope": (
            "bounded churn trend; the external ten-tab resource gate remains "
            "the hard absolute-memory ceiling"
        ),
        "first_half_median_kb": first_half_median,
        "second_half_median_kb": second_half_median,
        "growth_percent": growth_percent,
        "maximum_growth_percent": 10.0,
        "monotonic_growth": monotonic_growth,
        "monotonic_growth_enforced": False,
        "monotonic_growth_note": (
            "diagnostic only because allocator and cache settling can produce "
            "monotonic batch endpoints without proving retained tab state"
        ),
        "passed": growth_percent <= 10.0,
    }
    scroll_hitch_duration = summarize_seconds(
        scroll_by_name[SCROLL_HITCH_DURATION_METRIC]
    )
    scroll_hitch_duration["maximum_ceiling_ms"] = 100.0
    scroll_hitch_duration["criterion"] = (
        "aggregate hitch duration per measured scrolling interaction"
    )
    scroll_hitch_duration["passed"] = (
        scroll_hitch_duration["maximum_ms"]
        <= scroll_hitch_duration["maximum_ceiling_ms"]
    )
    scroll_hitch_count = summarize_values(
        scroll_by_name[SCROLL_HITCH_COUNT_METRIC],
        "hitches",
    )
    scroll_hitch_count["maximum_ceiling"] = 0.0
    scroll_hitch_count["criterion"] = (
        "no detected hitches in any measured scrolling interaction"
    )
    scroll_hitch_count["passed"] = (
        scroll_hitch_count["maximum"]
        <= scroll_hitch_count["maximum_ceiling"]
    )
    scroll_hitch_ratio = summarize_values(
        scroll_by_name[SCROLL_HITCH_RATIO_METRIC],
        "ms per s",
    )
    scroll_hitch_ratio["maximum_ceiling"] = 0.0
    scroll_hitch_ratio["criterion"] = (
        "zero hitch time in every measured scrolling interaction"
    )
    scroll_hitch_ratio["passed"] = (
        scroll_hitch_ratio["maximum"]
        <= scroll_hitch_ratio["maximum_ceiling"]
    )
    scrolling_summaries = {
        SCROLL_HITCH_DURATION_METRIC: scroll_hitch_duration,
        SCROLL_HITCH_COUNT_METRIC: scroll_hitch_count,
        SCROLL_HITCH_RATIO_METRIC: scroll_hitch_ratio,
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
        "controlled_scrolling_metrics": scrolling_summaries,
        "tab_creation_metrics": {TAB_CREATION_METRIC: tab_creation},
        "ten_resident_tab_selection_metrics": {
            TAB_SELECTION_METRIC: tab_selection,
        },
        "blank_tab_churn": {
            "cycles": 100,
            "cycles_per_batch": 10,
            "measured_batches": EXPECTED_TAB_CHURN_SAMPLE_COUNT,
            "memory_metrics": tab_churn_memory_summaries,
            "growth_check": tab_churn_growth,
        },
        "address_field_focus_asserted_for_each_launch": True,
        "initial_webview_readiness_proxy": derived,
        "expected_launch_samples_per_metric": EXPECTED_LAUNCH_SAMPLE_COUNT,
        "expected_navigation_samples_per_metric": (
            EXPECTED_NAVIGATION_SAMPLE_COUNT
        ),
        "expected_scroll_samples_per_metric": EXPECTED_SCROLL_SAMPLE_COUNT,
        "expected_tab_creation_samples": EXPECTED_TAB_CREATION_SAMPLE_COUNT,
        "expected_tab_selection_samples": (
            EXPECTED_TAB_SELECTION_SAMPLE_COUNT
        ),
        "expected_tab_churn_samples_per_metric": (
            EXPECTED_TAB_CHURN_SAMPLE_COUNT
        ),
        "regression_comparison": regression_comparison,
        "passed": (
            application["passed"]
            and derived["passed"]
            and all(command["passed"] for command in command_summaries)
            and tab_creation["passed"]
            and tab_selection["passed"]
            and tab_churn_growth["passed"]
            and scroll_hitch_duration["passed"]
            and scroll_hitch_count["passed"]
            and scroll_hitch_ratio["passed"]
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
    for name, summary in (
        (TAB_CREATION_METRIC, tab_creation),
        (TAB_SELECTION_METRIC, tab_selection),
    ):
        print(
            f"{name}: min {summary['minimum_ms']:.3f} ms, "
            f"median {summary['median_ms']:.3f} ms, "
            f"mean {summary['mean_ms']:.3f} ms, "
            f"p95 {summary['p95_ms']:.3f} ms, "
            f"max {summary['maximum_ms']:.3f} ms "
            f"({summary['samples']} samples; "
            f"p95 ceiling {summary['p95_ceiling_ms']:.0f} ms)"
        )
    for name, summary in tab_churn_memory_summaries.items():
        print(
            f"{name}: min {summary['minimum']:.3f} {summary['unit']}, "
            f"median {summary['median']:.3f} {summary['unit']}, "
            f"mean {summary['mean']:.3f} {summary['unit']}, "
            f"p95 {summary['p95']:.3f} {summary['unit']}, "
            f"max {summary['maximum']:.3f} {summary['unit']} "
            f"({summary['samples']} batches)"
        )
    print(
        "Blank-tab churn growth: "
        f"first-half median {tab_churn_growth['first_half_median_kb']:.3f} "
        "kB, "
        f"second-half median "
        f"{tab_churn_growth['second_half_median_kb']:.3f} kB, "
        f"change {tab_churn_growth['growth_percent']:+.2f}%, "
        f"monotonic {'yes' if tab_churn_growth['monotonic_growth'] else 'no'} "
        f"({'PASS' if tab_churn_growth['passed'] else 'FAIL'})"
    )
    print(
        f"{SCROLL_HITCH_DURATION_METRIC}: "
        f"min {scroll_hitch_duration['minimum_ms']:.3f} ms, "
        f"median {scroll_hitch_duration['median_ms']:.3f} ms, "
        f"mean {scroll_hitch_duration['mean_ms']:.3f} ms, "
        f"p95 {scroll_hitch_duration['p95_ms']:.3f} ms, "
        f"max {scroll_hitch_duration['maximum_ms']:.3f} ms "
        f"({scroll_hitch_duration['samples']} samples; "
        f"ceiling {scroll_hitch_duration['maximum_ceiling_ms']:.0f} ms)"
    )
    for name in (SCROLL_HITCH_COUNT_METRIC, SCROLL_HITCH_RATIO_METRIC):
        summary = scrolling_summaries[name]
        print(
            f"{name}: min {summary['minimum']:.3f} {summary['unit']}, "
            f"median {summary['median']:.3f} {summary['unit']}, "
            f"mean {summary['mean']:.3f} {summary['unit']}, "
            f"p95 {summary['p95']:.3f} {summary['unit']}, "
            f"max {summary['maximum']:.3f} {summary['unit']} "
            f"({summary['samples']} samples; "
            f"ceiling {summary['maximum_ceiling']:.3f} "
            f"{summary['unit']})"
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
