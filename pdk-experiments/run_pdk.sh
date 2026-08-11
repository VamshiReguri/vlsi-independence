#!/usr/bin/env bash
# =====================================================================
# Day 5 driver - "the PDK is your characterization edge".
#
# Three steps:
#   1. inspect_pdk.sh  - carve readable slices out of the .lib and .lef
#   2. arc_delay.tcl   - OpenSTA looks up one inverter arc at chosen (slew,cap)
#   3. interp_check.py - our own bilinear lookup of the same table, side by side
#
# No native OpenSTA on this box, so step 2 runs inside openroad/orfs:latest,
# mounting the ORFS flow read-only at /flow and this repo read-write at /work
# (same pattern as sta-experiments/gcd/run_sta.sh).
#
# Prereqs: Docker + openroad/orfs:latest, ORFS checkout at ~/OpenROAD-flow-scripts.
# =====================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ORFS_FLOW="${ORFS_FLOW:-$HOME/OpenROAD-flow-scripts/flow}"
PLATFORM="sky130hd"
LIB_REL="platforms/$PLATFORM/lib/sky130_fd_sc_hd__tt_025C_1v80.lib"
RPT="$SCRIPT_DIR/reports"
mkdir -p "$RPT"

# Two probe points, chosen on purpose (see day5_explanation.md):
#   - an exact grid node   -> tool must return the raw table value, no interp
#   - an off-grid point    -> forces a real 2-D (bilinear) interpolation
POINTS="0.0531329,0.012873 0.20,0.05"

echo "=============================================================="
echo " STEP 1/3 : extract readable .lib / .lef slices (host awk)"
echo "=============================================================="
ORFS_FLOW="$ORFS_FLOW" RPT="$RPT" bash "$SCRIPT_DIR/inspect_pdk.sh"

echo
echo "=============================================================="
echo " STEP 2/3 : OpenSTA arc-delay lookup inside openroad/orfs"
echo "=============================================================="
docker run --rm \
  -v "$ORFS_FLOW:/flow:ro" \
  -v "$REPO_ROOT:/work:rw" \
  -w /work \
  openroad/orfs:latest \
  bash -c "
    source /OpenROAD-flow-scripts/env.sh
    export LIBERTY=/flow/$LIB_REL
    export NETLIST=/work/pdk-experiments/tiny_inv.v
    export POINTS='$POINTS'
    sta /work/pdk-experiments/arc_delay.tcl
  " 2>&1 | tee "$RPT/arc_delays.rpt"

echo
echo "=============================================================="
echo " STEP 3/3 : our bilinear lookup vs OpenSTA (predicted vs measured)"
echo "=============================================================="
python3 "$SCRIPT_DIR/interp_check.py" \
  --cell "$RPT/inv_2_cell.txt" \
  --points $POINTS \
  --measured "$RPT/arc_delays.rpt" | tee "$RPT/comparison.txt"

echo
echo "Artifacts in $RPT:"
echo "  lib_header.txt inv_2_cell.txt inv_2_macro.txt tlef_excerpt.txt"
echo "  arc_delays.rpt (OpenSTA)   comparison.txt (predicted vs measured)"
