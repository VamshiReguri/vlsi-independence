#!/usr/bin/env python3
"""Parse OpenSTA report_checks output → WNS/TNS + per-path DataFrame + chart.

Handles:
  - Standalone OpenSTA redirect output (report_checks_setup.rpt)
  - ORFS finish-stage reports (6_finish.rpt with section headers)

Usage:
  python parse_timing_report.py sta-experiments/gcd/reports/report_checks_setup.rpt
  python parse_timing_report.py --orfs ~/OpenROAD-flow-scripts/flow/reports/sky130hd/gcd/base/6_finish.rpt
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd


@dataclass
class TimingPath:
    startpoint: str = ""
    endpoint: str = ""
    path_group: str = ""
    path_type: str = ""
    slack: float | None = None
    violated: bool = False
    stages: list[dict] = field(default_factory=list)


def _parse_slack(line: str) -> tuple[float | None, bool]:
    # OpenSTA formats: "slack -1.48 (VIOLATED)" or "-1.48   slack (VIOLATED)"
    m = re.search(
        r"([-+]?\d*\.?\d+(?:[eE][-+]?\d+)?)\s+slack\s*(?:\((MET|VIOLATED)\))?",
        line,
    )
    if not m:
        m = re.search(
            r"slack\s+\(?\s*([-+]?\d*\.?\d+(?:[eE][-+]?\d+)?)\s*\)?\s*(?:\((MET|VIOLATED)\))?",
            line,
        )
    if not m:
        return None, False
    slack = float(m.group(1))
    violated = m.group(2) == "VIOLATED" if m.lastindex and m.group(2) else slack < 0
    return slack, violated


def parse_report_checks(text: str) -> list[TimingPath]:
    """Split report_checks text into individual timing paths."""
    # ORFS wraps sections; strip headers but keep path bodies.
    text = re.sub(
        r"={10,}\nfinish report_checks[^\n]*\n-{10,}\n",
        "",
        text,
    )

    paths: list[TimingPath] = []
    current = TimingPath()
    in_path = False

    for raw_line in text.splitlines():
        line = raw_line.rstrip()
        stripped = line.strip()

        if stripped.startswith("Startpoint:"):
            if in_path and current.startpoint:
                paths.append(current)
            current = TimingPath()
            current.startpoint = stripped.removeprefix("Startpoint:").strip()
            in_path = True
            continue

        if not in_path:
            continue

        if stripped.startswith("Endpoint:"):
            current.endpoint = stripped.removeprefix("Endpoint:").strip()
        elif stripped.startswith("Path Group:"):
            current.path_group = stripped.removeprefix("Path Group:").strip()
        elif stripped.startswith("Path Type:"):
            current.path_type = stripped.removeprefix("Path Type:").strip()
        elif "slack" in stripped and re.search(r"slack\s", stripped):
            slack, violated = _parse_slack(stripped)
            if slack is not None:
                current.slack = slack
                current.violated = violated
        elif re.match(r"^\s*\d", line) and "/" in stripped:
            # Stage row: ends with cell/pin (description column)
            parts = stripped.split()
            if len(parts) >= 2:
                try:
                    delay = float(parts[-3]) if len(parts) >= 4 else None
                    time = float(parts[-2]) if len(parts) >= 3 else None
                    desc = parts[-1] if parts else ""
                    current.stages.append(
                        {"delay": delay, "time": time, "description": desc}
                    )
                except (ValueError, IndexError):
                    pass

    if in_path and current.startpoint:
        paths.append(current)

    return paths


def parse_orfs_summary(text: str) -> dict[str, float]:
    """Extract WNS/TNS from ORFS metric lines."""
    summary: dict[str, float] = {}
    for key, pattern in {
        "wns": r"wns max\s+([-+]?\d*\.?\d+)",
        "tns": r"tns max\s+([-+]?\d*\.?\d+)",
        "setup_violations": r"setup violation count\s+(\d+)",
        "hold_violations": r"hold violation count\s+(\d+)",
        "min_period": r"core_clock period_min\s*=\s*([-+]?\d*\.?\d+)",
    }.items():
        m = re.search(pattern, text)
        if m:
            summary[key] = float(m.group(1))
    return summary


def paths_to_dataframe(paths: list[TimingPath]) -> pd.DataFrame:
    rows = []
    for i, p in enumerate(paths):
        rows.append(
            {
                "path_id": i,
                "startpoint": p.startpoint,
                "endpoint": p.endpoint,
                "path_group": p.path_group,
                "path_type": p.path_type,
                "slack_ns": p.slack,
                "violated": p.violated,
                "num_stages": len(p.stages),
            }
        )
    return pd.DataFrame(rows)


def compute_wns_tns(df: pd.DataFrame) -> tuple[float, float]:
    if df.empty or df["slack_ns"].isna().all():
        return float("nan"), float("nan")
    slacks = df["slack_ns"].dropna()
    wns = float(slacks.min())
    tns = float(slacks[slacks < 0].sum()) if (slacks < 0).any() else 0.0
    return wns, tns


def plot_slack_histogram(df: pd.DataFrame, out_path: Path, title: str) -> None:
    slacks = df["slack_ns"].dropna()
    if slacks.empty:
        print("No slack data to plot.", file=sys.stderr)
        return

    fig, axes = plt.subplots(1, 2, figsize=(12, 4))

    axes[0].hist(slacks, bins=30, edgecolor="black", alpha=0.75)
    axes[0].axvline(0, color="red", linestyle="--", linewidth=1, label="zero slack")
    axes[0].axvline(slacks.min(), color="orange", linestyle=":", label=f"WNS={slacks.min():.3f}")
    axes[0].set_xlabel("Slack (ns)")
    axes[0].set_ylabel("Path count")
    axes[0].set_title("Slack distribution")
    axes[0].legend(fontsize=8)

    # Per clock group WNS
    if "path_group" in df.columns and df["path_group"].notna().any():
        wns_by_clk = df.groupby("path_group")["slack_ns"].min().sort_values()
        wns_by_clk.plot(kind="barh", ax=axes[1], color="steelblue")
        axes[1].axvline(0, color="red", linestyle="--", linewidth=1)
        axes[1].set_xlabel("WNS (ns)")
        axes[1].set_title("WNS by clock group")
    else:
        axes[1].text(0.5, 0.5, "No clock groups", ha="center", va="center")
        axes[1].set_axis_off()

    fig.suptitle(title, fontsize=11)
    fig.tight_layout()
    fig.savefig(out_path, dpi=120)
    plt.close(fig)
    print(f"Chart saved: {out_path}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Parse OpenSTA timing reports")
    parser.add_argument("report", type=Path, help="report_checks or ORFS finish .rpt file")
    parser.add_argument(
        "-o", "--output-dir", type=Path, default=None, help="output directory for CSV/chart"
    )
    parser.add_argument(
        "--orfs", action="store_true", help="input is full ORFS 6_finish.rpt (extract summary)"
    )
    args = parser.parse_args()

    text = args.report.read_text(encoding="utf-8", errors="replace")
    out_dir = args.output_dir or args.report.parent
    out_dir.mkdir(parents=True, exist_ok=True)

    orfs_summary = parse_orfs_summary(text) if args.orfs else {}
    paths = parse_report_checks(text)
    df = paths_to_dataframe(paths)
    wns, tns = compute_wns_tns(df)

    # Prefer ORFS ground-truth metrics when available (covers all violating endpoints)
    if orfs_summary:
        wns = orfs_summary.get("wns", wns)
        tns = orfs_summary.get("tns", tns)

    print("=" * 50)
    print(f"Report: {args.report}")
    print(f"Paths parsed: {len(paths)}")
    print(f"WNS (setup): {wns:.3f} ns")
    print(f"TNS (setup): {tns:.3f} ns")
    if orfs_summary:
        print(f"Setup violations (ORFS): {int(orfs_summary.get('setup_violations', 0))}")
        if "min_period" in orfs_summary:
            fmax = 1000.0 / orfs_summary["min_period"]
            print(
                f"Min period (core_clock): {orfs_summary['min_period']:.2f} ns "
                f"(~{fmax:.0f} MHz)"
            )
    print("=" * 50)

    if not df.empty:
        df["slack_ns"] = pd.to_numeric(df["slack_ns"], errors="coerce")
        csv_path = out_dir / "paths.csv"
        df.to_csv(csv_path, index=False)
        print(f"Paths CSV: {csv_path}")
        worst = df.dropna(subset=["slack_ns"]).nsmallest(5, "slack_ns")
        if not worst.empty:
            print(worst[
                ["startpoint", "endpoint", "path_group", "slack_ns", "violated"]
            ].to_string(index=False))

    chart_path = out_dir / "slack_histogram.png"
    plot_slack_histogram(df, chart_path, title=f"gcd post-route STA — WNS={wns:.3f} ns")

    summary_path = out_dir / "summary.txt"
    with summary_path.open("w") as f:
        f.write(f"wns_setup_ns {wns}\n")
        f.write(f"tns_setup_ns {tns}\n")
        f.write(f"paths_parsed {len(paths)}\n")
    print(f"Summary: {summary_path}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
