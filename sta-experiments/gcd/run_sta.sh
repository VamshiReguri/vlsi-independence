#!/usr/bin/env bash
# Run standalone OpenSTA on gcd with hand-written SDC.
# Day 3: override with SDC=gcd_mcp.sdc or SDC=gcd_false.sdc
# Prerequisites: Docker Desktop + openroad/orfs:latest, gcd flow done.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

ORFS_FLOW="${ORFS_FLOW:-$HOME/OpenROAD-flow-scripts/flow}"
PLATFORM="sky130hd"
DESIGN="gcd"
VARIANT="base"

RESULTS="$ORFS_FLOW/results/${PLATFORM}/${DESIGN}/${VARIANT}"
RPT_DIR="$SCRIPT_DIR/reports"
mkdir -p "$RPT_DIR"

SDC="${SDC:-$SCRIPT_DIR/gcd_hand.sdc}"
# Resolve to absolute path (handles relative SDC=gcd_mcp.sdc from cwd)
if [[ ! "$SDC" = /* ]]; then
  if [[ -f "$SCRIPT_DIR/$SDC" ]]; then
    SDC="$SCRIPT_DIR/$SDC"
  else
    SDC="$(cd "$(dirname "$SDC")" && pwd)/$(basename "$SDC")"
  fi
fi

for f in "$RESULTS/6_final.v" "$RESULTS/6_final.spef" "$SDC"; do
  if [[ ! -f "$f" ]]; then
    echo "ERROR: missing $f" >&2
    exit 1
  fi
done

# Map host SDC → /work/... for Docker (must live under repo root)
case "$SDC" in
  "$REPO_ROOT"/*) SDC_IN_DOCKER="/work/${SDC#"$REPO_ROOT"/}" ;;
  *)
    echo "ERROR: SDC must be under repo root for Docker mount: $SDC" >&2
    exit 1
    ;;
esac

echo "Using SDC: $SDC"

run_sta() {
  export NETLIST="$RESULTS/6_final.v"
  export SDC
  export SPEF="$RESULTS/6_final.spef"
  export LIBERTY="$ORFS_FLOW/platforms/${PLATFORM}/lib/sky130_fd_sc_hd__tt_025C_1v80.lib"
  sta "$SCRIPT_DIR/run_sta.tcl"
}

if command -v sta &>/dev/null; then
  echo "Using native sta"
  run_sta | tee "$RPT_DIR/opensta_full.rpt"
else
  echo "Using Docker openroad/orfs:latest"
  docker run --rm \
    -v "$ORFS_FLOW:/OpenROAD-flow-scripts/flow:ro" \
    -v "$REPO_ROOT:/work:rw" \
    -w /work \
    openroad/orfs:latest \
    bash -c "
      source /OpenROAD-flow-scripts/env.sh
      export NETLIST=/OpenROAD-flow-scripts/flow/results/${PLATFORM}/${DESIGN}/${VARIANT}/6_final.v
      export SDC=${SDC_IN_DOCKER}
      export SPEF=/OpenROAD-flow-scripts/flow/results/${PLATFORM}/${DESIGN}/${VARIANT}/6_final.spef
      export LIBERTY=/OpenROAD-flow-scripts/flow/platforms/${PLATFORM}/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
      sta /work/sta-experiments/gcd/run_sta.tcl
    " | tee "$RPT_DIR/opensta_full.rpt"
fi

# Extract setup report_checks section for notebook / archive
awk '/=== report_checks setup/{p=1;next} /=== report_checks hold/{p=0} p' \
  "$RPT_DIR/opensta_full.rpt" > "$RPT_DIR/report_checks.rpt"

echo ""
echo "WNS line:"
grep -E '^(wns|worst slack)' "$RPT_DIR/opensta_full.rpt" || true
echo ""
ls -la "$RPT_DIR/report_checks.rpt" "$RPT_DIR/opensta_full.rpt"
