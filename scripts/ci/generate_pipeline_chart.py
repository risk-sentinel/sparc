#!/usr/bin/env python3
"""Generate an XmR (Individuals and Moving Range) control chart for SPARC CI.

Reads pipeline metrics from docs/ci/pipeline-metrics.csv and produces a
three-panel XmR control chart PNG at docs/ci/pipeline-performance.png.

Panel layout (matches sparc-iac reference):
  1. Individuals (X) chart — run durations with mean, UCL, LCL
  2. Moving Range (mR) chart — consecutive differences with UCL, mean
  3. Before/After bar chart — per-job duration comparison pre/post optimization
"""

import csv
import os
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.dates as mdates
import matplotlib.ticker as ticker
import numpy as np
from datetime import datetime


# --- Paths (relative to repo root) -------------------------------------------

REPO_ROOT = Path(__file__).resolve().parents[2]
CSV_PATH = REPO_ROOT / "docs" / "ci" / "pipeline-metrics.csv"
OUTPUT_PATH = REPO_ROOT / "docs" / "ci" / "pipeline-performance.png"

# --- Theme -------------------------------------------------------------------

GRID_COLOR = "#cccccc"
PRE_COLOR = "#e74c3c"       # red — before optimization
POST_COLOR = "#2ecc71"      # green — after optimization
MEAN_COLOR = "#999999"
UCL_COLOR = "#e74c3c"
OPT_LINE_COLOR = "#3498db"  # blue dashed — optimization deployed marker

TRACKED_JOBS = [
    "trivy_container_scan",
    "trivy_fs_scan",
    "codeql_scan",
    "brakeman_scan",
    "secrets_scan",
    "dependency_audit",
    "normalize_hdf",
    "bundle_results",
    "sbom_generation",
]


# --- Helpers ------------------------------------------------------------------

def read_metrics(path: Path):
    """Parse the CSV and return structured data.

    Returns:
        runs: list of dicts with keys: run_id, date, sha, jobs (dict of
              job_name -> duration), total_duration
    """
    raw = {}  # run_id -> {date, sha, jobs: {name: dur}, total}
    try:
        with open(path, newline="") as fh:
            reader = csv.DictReader(fh)
            for row in reader:
                try:
                    run_id = int(row["run_id"])
                    duration = float(row["duration_seconds"])
                    job_name = row.get("job_name", "unknown")
                    date_str = row.get("date", "")
                    sha = row.get("sha", "")
                except (ValueError, KeyError, TypeError):
                    continue

                try:
                    total_dur = float(row.get("total_duration", 0))
                except (ValueError, TypeError):
                    total_dur = 0.0

                if run_id not in raw:
                    raw[run_id] = {
                        "date": date_str,
                        "sha": sha,
                        "jobs": {},
                        "total": total_dur,
                    }
                raw[run_id]["jobs"][job_name] = duration
                # Use the CSV total_duration (true wall-clock) if available
                if total_dur > 0:
                    raw[run_id]["total"] = total_dur
    except FileNotFoundError:
        return []

    if not raw:
        return []

    sorted_ids = sorted(raw.keys())[-100:]
    runs = []
    for rid in sorted_ids:
        entry = raw[rid]
        try:
            dt = datetime.strptime(entry["date"], "%Y-%m-%d")
        except (ValueError, TypeError):
            dt = None
        runs.append({
            "run_id": rid,
            "date": entry["date"],
            "datetime": dt,
            "sha": entry["sha"],
            "jobs": entry["jobs"],
            "total": entry["total"],
        })
    return runs


def find_optimization_index(runs):
    """Find the index of the optimization commit (via OPTIMIZATION_SHA env var).

    Returns index into runs list, or None.
    """
    opt_sha = os.environ.get("OPTIMIZATION_SHA", "")
    if not opt_sha:
        return None
    for i, run in enumerate(runs):
        if run["sha"] == opt_sha:
            return i
    return None


def compute_xmr(values):
    """Compute XmR chart statistics.

    Returns:
        mr: moving range values (len = n, first is NaN)
        x_bar: mean of individuals
        mr_bar: mean of moving ranges
        ucl_x: UCL for individuals (x_bar + 2.66 * mr_bar)
        lcl_x: LCL for individuals (x_bar - 2.66 * mr_bar, floor 0)
        ucl_mr: UCL for moving range (3.267 * mr_bar)
    """
    vals = np.array(values, dtype=float)
    diffs = np.abs(np.diff(vals))
    x_bar = float(np.mean(vals))
    mr_bar = float(np.mean(diffs)) if len(diffs) > 0 else 0.0

    ucl_x = x_bar + 2.66 * mr_bar
    lcl_x = max(0.0, x_bar - 2.66 * mr_bar)
    ucl_mr = 3.267 * mr_bar  # D4 = 3.267 for n=2

    mr = [float("nan")] + diffs.tolist()
    return mr, x_bar, mr_bar, ucl_x, lcl_x, ucl_mr


def to_minutes(seconds):
    """Convert seconds to minutes."""
    return seconds / 60.0


def generate_placeholder(output_path: Path):
    """Generate a placeholder chart when insufficient data is available."""
    fig, axes = plt.subplots(3, 1, figsize=(14, 10), gridspec_kw={"height_ratios": [3, 2, 2]})
    fig.suptitle(
        "Pipeline Performance XmR Control Chart\nSPARC Security Scanning \u2014 Total Workflow Duration (wall-clock)",
        fontsize=14, fontweight="bold",
    )
    for ax in axes:
        ax.text(
            0.5, 0.5,
            "Collecting data\u2026\nXmR chart will render after 2+ pipeline runs.",
            transform=ax.transAxes, fontsize=16, fontweight="bold",
            color="#999999", ha="center", va="center", linespacing=1.6,
        )
        ax.set_xticks([])
        ax.set_yticks([])
    fig.tight_layout()
    fig.savefig(output_path, dpi=150)
    plt.close(fig)


def generate_chart(output_path: Path, runs):
    """Generate the 3-panel XmR control chart."""
    totals_sec = [r["total"] for r in runs]
    totals_min = [to_minutes(t) for t in totals_sec]

    # Use datetime x-axis if available, otherwise sequential index
    has_dates = all(r["datetime"] is not None for r in runs)
    if has_dates:
        x_values = [r["datetime"] for r in runs]
    else:
        x_values = list(range(len(runs)))

    opt_idx = find_optimization_index(runs)

    # Compute XmR on total durations (in minutes)
    mr, x_bar, mr_bar, ucl_x, lcl_x, ucl_mr = compute_xmr(totals_min)

    fig, (ax_x, ax_mr, ax_bar) = plt.subplots(
        3, 1, figsize=(14, 10),
        gridspec_kw={"height_ratios": [3, 2, 2]},
    )
    fig.suptitle(
        "Pipeline Performance XmR Control Chart\n"
        "SPARC Security Scanning \u2014 Total Workflow Duration (wall-clock)",
        fontsize=13, fontweight="bold",
    )

    # ── Panel 1: Individuals (X) Chart ────────────────────────────────────────

    if opt_idx is not None and opt_idx < len(runs) - 1:
        # Split pre/post
        pre_x = x_values[:opt_idx + 1]
        pre_y = totals_min[:opt_idx + 1]
        post_x = x_values[opt_idx:]
        post_y = totals_min[opt_idx:]

        pre_mr, pre_xbar, pre_mrbar, pre_ucl, pre_lcl, _ = compute_xmr(pre_y)
        post_mr, post_xbar, post_mrbar, post_ucl, post_lcl, _ = compute_xmr(post_y)

        ax_x.plot(pre_x, pre_y, "o-", color=PRE_COLOR, markersize=4, linewidth=1.2,
                  label=f"Pre (n={len(pre_y)}, X\u0304={pre_xbar:.1f}m)")
        ax_x.plot(post_x, post_y, "o-", color=POST_COLOR, markersize=4, linewidth=1.2,
                  label=f"Post (n={len(post_y)}, X\u0304={post_xbar:.1f}m)")

        ax_x.axhline(pre_xbar, color=MEAN_COLOR, linewidth=1, linestyle="--",
                     label=f"X\u0304={pre_xbar:.1f}m")
        ax_x.axhline(pre_ucl, color=UCL_COLOR, linewidth=0.8, linestyle="--", alpha=0.6,
                     label=f"UCL={pre_ucl:.1f}m")
        if pre_lcl > 0:
            ax_x.axhline(pre_lcl, color=MEAN_COLOR, linewidth=0.8, linestyle="--", alpha=0.6,
                         label=f"LCL={pre_lcl:.1f}m")

        ax_x.axvline(x_values[opt_idx], color=OPT_LINE_COLOR, linewidth=1.5,
                     linestyle="--", label="Optimization deployed")
    else:
        # No optimization split — single series
        colors = [PRE_COLOR] * len(runs)
        ax_x.plot(x_values, totals_min, "o-", color=PRE_COLOR, markersize=4,
                  linewidth=1.2, label=f"n={len(runs)}, X\u0304={x_bar:.1f}m")
        ax_x.axhline(x_bar, color=MEAN_COLOR, linewidth=1, linestyle="--",
                     label=f"X\u0304={x_bar:.1f}m")
        ax_x.axhline(ucl_x, color=UCL_COLOR, linewidth=0.8, linestyle="--", alpha=0.6,
                     label=f"UCL={ucl_x:.1f}m")
        if lcl_x > 0:
            ax_x.axhline(lcl_x, color=MEAN_COLOR, linewidth=0.8, linestyle="--", alpha=0.6,
                         label=f"LCL={lcl_x:.1f}m")

    ax_x.set_ylabel("Duration (minutes)", fontsize=10)
    ax_x.set_title("Individuals (X) Chart", fontsize=11, fontweight="bold", loc="left")
    ax_x.legend(fontsize=8, loc="upper right")
    ax_x.grid(True, color=GRID_COLOR, linewidth=0.3, alpha=0.5)

    # ── Panel 2: Moving Range (mR) Chart ──────────────────────────────────────

    if opt_idx is not None and opt_idx < len(runs) - 1:
        pre_mr_vals = mr[:opt_idx + 1]
        post_mr_vals = mr[opt_idx:]
        pre_mr_x = x_values[:opt_idx + 1]
        post_mr_x = x_values[opt_idx:]

        pre_mr_clean = [v for v in pre_mr_vals if not np.isnan(v)]
        post_mr_clean = [v for v in post_mr_vals if not np.isnan(v)]
        pre_mr_mean = float(np.mean(pre_mr_clean)) if pre_mr_clean else 0
        post_mr_mean = float(np.mean(post_mr_clean)) if post_mr_clean else 0

        ax_mr.plot(pre_mr_x, pre_mr_vals, "o-", color=PRE_COLOR, markersize=3,
                   linewidth=1, label=f"Pre mR\u0304={pre_mr_mean:.2f}m")
        ax_mr.plot(post_mr_x, post_mr_vals, "o-", color=POST_COLOR, markersize=3,
                   linewidth=1, label=f"Post mR\u0304={post_mr_mean:.2f}m")
        ax_mr.axhline(pre_mr_mean, color=MEAN_COLOR, linewidth=0.8, linestyle="--")
        ax_mr.axhline(3.267 * pre_mr_mean, color=UCL_COLOR, linewidth=0.8,
                      linestyle="--", alpha=0.6, label=f"UCL={3.267 * pre_mr_mean:.1f}m")
        ax_mr.axvline(x_values[opt_idx], color=OPT_LINE_COLOR, linewidth=1.5, linestyle="--")
    else:
        ax_mr.plot(x_values, mr, "o-", color=PRE_COLOR, markersize=3, linewidth=1,
                   label=f"mR\u0304={mr_bar:.2f}m")
        ax_mr.axhline(mr_bar, color=MEAN_COLOR, linewidth=0.8, linestyle="--")
        ax_mr.axhline(ucl_mr, color=UCL_COLOR, linewidth=0.8, linestyle="--", alpha=0.6,
                      label=f"UCL={ucl_mr:.1f}m")

    ax_mr.set_ylabel("Moving Range (min)", fontsize=10)
    ax_mr.set_title("Moving Range (mR) Chart", fontsize=11, fontweight="bold", loc="left")
    ax_mr.legend(fontsize=8, loc="upper right")
    ax_mr.grid(True, color=GRID_COLOR, linewidth=0.3, alpha=0.5)

    # ── Panel 3: Before/After Bar Chart ───────────────────────────────────────

    if opt_idx is not None and opt_idx < len(runs) - 1:
        pre_runs = runs[:opt_idx + 1]
        post_runs = runs[opt_idx + 1:]
    else:
        # No split — show all runs as "pre" only
        pre_runs = runs
        post_runs = []

    # Aggregate average per-job durations
    job_names = []
    pre_avgs = []
    post_avgs = []

    for job in TRACKED_JOBS:
        pre_vals = [r["jobs"].get(job, 0) for r in pre_runs if job in r["jobs"]]
        post_vals = [r["jobs"].get(job, 0) for r in post_runs if job in r["jobs"]]
        if pre_vals or post_vals:
            job_names.append(job.replace("_", " ").title())
            pre_avgs.append(to_minutes(float(np.mean(pre_vals))) if pre_vals else 0)
            post_avgs.append(to_minutes(float(np.mean(post_vals))) if post_vals else 0)

    if job_names:
        bar_x = np.arange(len(job_names))
        bar_width = 0.35

        bars_pre = ax_bar.bar(bar_x - bar_width / 2, pre_avgs, bar_width,
                              color=PRE_COLOR, alpha=0.85, label="Before")
        if post_runs:
            bars_post = ax_bar.bar(bar_x + bar_width / 2, post_avgs, bar_width,
                                   color=POST_COLOR, alpha=0.85, label="After")

        # Value labels on bars
        for bar in bars_pre:
            h = bar.get_height()
            if h > 0:
                ax_bar.text(bar.get_x() + bar.get_width() / 2, h + 0.02,
                            f"{h:.1f}m", ha="center", va="bottom", fontsize=7)
        if post_runs:
            for bar in bars_post:
                h = bar.get_height()
                if h > 0:
                    ax_bar.text(bar.get_x() + bar.get_width() / 2, h + 0.02,
                                f"{h:.1f}m", ha="center", va="bottom", fontsize=7)

        ax_bar.set_xticks(bar_x)
        ax_bar.set_xticklabels(job_names, rotation=30, ha="right", fontsize=8)
        ax_bar.set_ylabel("Avg (min)", fontsize=10)
        ax_bar.legend(fontsize=8, loc="upper right")
    else:
        ax_bar.text(0.5, 0.5, "No per-job data available",
                    transform=ax_bar.transAxes, fontsize=14, color="#999",
                    ha="center", va="center")

    ax_bar.grid(True, axis="y", color=GRID_COLOR, linewidth=0.3, alpha=0.5)

    # ── X-axis date formatting ────────────────────────────────────────────────

    if has_dates:
        for ax in (ax_x, ax_mr):
            ax.xaxis.set_major_formatter(mdates.DateFormatter("%m/%d %H:%M"))
            ax.tick_params(axis="x", rotation=30, labelsize=8)

    fig.tight_layout()
    fig.savefig(output_path, dpi=150)
    plt.close(fig)


# --- Main ---------------------------------------------------------------------

def main():
    runs = read_metrics(CSV_PATH)

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)

    if len(runs) < 2:
        generate_placeholder(OUTPUT_PATH)
        print(f"Placeholder chart written to {OUTPUT_PATH}")
    else:
        generate_chart(OUTPUT_PATH, runs)
        print(f"XmR chart written to {OUTPUT_PATH} ({len(runs)} runs)")


if __name__ == "__main__":
    main()
