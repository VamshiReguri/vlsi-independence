#!/usr/bin/env python3
"""Day 5 - reproduce a standard cell's NLDM delay lookup, then check the tool.

A Non-Linear Delay Model (NLDM) arc in a .lib is just a 2-D table: delay as a
function of (input transition, output capacitance). STA does nothing magic with
it -- it bilinearly interpolates. This script:

  1. parses the cell_rise / cell_fall tables out of an extracted .lib cell,
  2. bilinearly interpolates the delay at requested (slew, cap) points, and
  3. (optional) parses OpenSTA's measured arc delay and prints predicted vs
     measured so you can see the tool and the table agree.

Usage:
  python interp_check.py --cell reports/inv_2_cell.txt \
      --points 0.0531329,0.012873 0.20,0.05 \
      [--measured reports/arc_delays.rpt]
"""
from __future__ import annotations

import argparse
import re
from pathlib import Path


def parse_nldm(text: str, table: str) -> tuple[list[float], list[float], list[list[float]]]:
    """Pull index_1 (slew), index_2 (cap) and the value grid for one table."""
    m = re.search(table + r'\s*\("[^"]*"\)\s*\{(.*?)\}', text, re.DOTALL)
    if not m:
        raise ValueError(f"table {table!r} not found")
    block = m.group(1)
    idx1 = [float(x) for x in re.search(r'index_1\s*\("([^"]*)"\)', block).group(1).split(",")]
    idx2 = [float(x) for x in re.search(r'index_2\s*\("([^"]*)"\)', block).group(1).split(",")]
    vals_raw = re.search(r"values\s*\((.*?)\)\s*;", block, re.DOTALL).group(1)
    nums = [float(x) for x in re.findall(r"[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?", vals_raw)]
    grid = [nums[i * len(idx2):(i + 1) * len(idx2)] for i in range(len(idx1))]
    return idx1, idx2, grid


def _bracket(axis: list[float], v: float) -> tuple[int, int, float]:
    """Return (lo, hi, frac); clamps to the end interval so we extrapolate
    linearly outside the grid exactly like OpenSTA does."""
    if v <= axis[0]:
        lo, hi = 0, 1
    elif v >= axis[-1]:
        lo, hi = len(axis) - 2, len(axis) - 1
    else:
        hi = next(i for i in range(1, len(axis)) if axis[i] >= v)
        lo = hi - 1
    frac = (v - axis[lo]) / (axis[hi] - axis[lo])
    return lo, hi, frac


def bilinear(idx1: list[float], idx2: list[float], grid: list[list[float]],
             slew: float, cap: float) -> float:
    i0, i1, fs = _bracket(idx1, slew)   # slew axis (index_1)
    j0, j1, fc = _bracket(idx2, cap)    # cap axis  (index_2)
    v0 = grid[i0][j0] + fc * (grid[i0][j1] - grid[i0][j0])
    v1 = grid[i1][j0] + fc * (grid[i1][j1] - grid[i1][j0])
    return v0 + fs * (v1 - v0)


def parse_measured(text: str) -> dict[tuple[str, str, str], float]:
    """Map (slew, cap, dir) -> OpenSTA 'data arrival time' from arc_delays.rpt."""
    out: dict[tuple[str, str, str], float] = {}
    key = None
    for line in text.splitlines():
        h = re.match(r"##POINT slew=(\S+) cap=(\S+) dir=(\S+)", line)
        if h:
            key = h.groups()
            continue
        if key:
            a = re.search(r"([-+]?\d*\.?\d+)\s+data arrival time", line)
            if a:
                out[key] = float(a.group(1))
                key = None
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description="NLDM bilinear lookup vs OpenSTA")
    ap.add_argument("--cell", type=Path, required=True, help="extracted .lib cell block")
    ap.add_argument("--points", nargs="+", required=True, help='"slew,cap" pairs (ns,pF)')
    ap.add_argument("--measured", type=Path, default=None, help="OpenSTA arc_delays.rpt")
    args = ap.parse_args()

    text = args.cell.read_text(encoding="utf-8", errors="replace")
    r1, r2, rise = parse_nldm(text, "cell_rise")
    f1, f2, fall = parse_nldm(text, "cell_fall")

    measured = parse_measured(args.measured.read_text()) if args.measured else {}

    print(f"NLDM tables from {args.cell}")
    print(f"  slew grid (ns): {r1}")
    print(f"  cap  grid (pF): {r2}")
    print()
    hdr = f"{'slew(ns)':>10} {'cap(pF)':>9} {'dir':>4} {'predicted(ns)':>14}"
    if measured:
        hdr += f" {'measured(ns)':>13} {'|err|(ps)':>10}"
    print(hdr)
    print("-" * len(hdr))

    for pt in args.points:
        slew, cap = (float(x) for x in pt.split(","))
        for d, (a1, a2, grid) in (("rise", (r1, r2, rise)), ("fall", (f1, f2, fall))):
            pred = bilinear(a1, a2, grid, slew, cap)
            row = f"{slew:>10.5f} {cap:>9.5f} {d:>4} {pred:>14.5f}"
            if measured:
                key = (pt.split(",")[0], pt.split(",")[1], d)
                if key in measured:
                    meas = measured[key]
                    row += f" {meas:>13.5f} {abs(meas - pred) * 1000:>10.3f}"
                else:
                    row += f" {'--':>13} {'--':>10}"
            print(row)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
