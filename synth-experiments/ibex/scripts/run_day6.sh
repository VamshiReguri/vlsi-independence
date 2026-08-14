#!/usr/bin/env bash
# =====================================================================
# Day 6 driver: full-flow staged STA across EVERY ORFS stage of the
# completed ibex run (synth -> floorplan -> place -> cts -> route).
#
# Day 4 timed synth / place / route. Day 6 closes the loop by filling in
# the two missing mid-stages (floorplan, cts) so the stage-by-stage table
# shows exactly WHERE the -16 ns synth slack turns into a closed design.
#
# Runs inside the same openroad/orfs image the ibex flow used, so the
# tool versions match the results being measured.
# =====================================================================
set -eu

# WSL invocations launched from Windows sometimes do not export HOME; derive it
# so the script works both interactively and via `wsl bash <script>`.
if [ -z "${HOME:-}" ]; then HOME="$(cd ~ && pwd)"; export HOME; fi

WORK="$HOME/vlsi-day6"
FLOW="$HOME/OpenROAD-flow-scripts/flow"
IMAGE="openroad/orfs:latest"
# Project root lives on D: after the C: -> D: move.
WIN_SCRIPTS="/mnt/d/vlsi-work/vlsi-independence/synth-experiments/ibex/scripts"
# Where the committed copies of the reports should land.
REPO_REPORTS="/mnt/d/vlsi-work/vlsi-independence/synth-experiments/ibex/reports/fullflow"

OPENROAD=/OpenROAD-flow-scripts/tools/install/OpenROAD/bin/openroad

mkdir -p "$WORK/scripts" "$WORK/reports"
# Copy the Tcl into the native WSL fs, stripping any CR so a CRLF checkout on
# the Windows side never trips the reader.
tr -d '\r' < "$WIN_SCRIPTS"/sta_fullflow.tcl > "$WORK/scripts/sta_fullflow.tcl"

run_in_container() {
  docker run --rm \
    -u "$(id -u):$(id -g)" \
    -e HOME=/tmp \
    -e STA_MODE="${STA_MODE:-}" \
    -v "$FLOW":/flow \
    -v "$WORK":/day6 \
    "$IMAGE" bash -c "$1"
}

i=0
stages=(synth floorplan place cts route)
for mode in "${stages[@]}"; do
  i=$((i + 1))
  echo
  echo "=============================================================="
  echo " STEP $i/${#stages[@]} : STA - stage '$mode'"
  echo "=============================================================="
  STA_MODE=$mode run_in_container "$OPENROAD -no_init -exit /day6/scripts/sta_fullflow.tcl" \
    2>&1 | tee "$WORK/reports/sta_${mode}.rpt"
done

echo
echo "=============================================================="
echo " SUMMARY (stage-by-stage WNS/TNS, ns)"
echo "=============================================================="
# Order the summary along the flow rather than alphabetically.
: > "$WORK/reports/metrics_fullflow.txt"
for mode in "${stages[@]}"; do
  grep -h "^METRIC $mode " "$WORK/reports/sta_${mode}.rpt" >> "$WORK/reports/metrics_fullflow.txt"
done
cat "$WORK/reports/metrics_fullflow.txt"

# Copy the reports into the repo so they can be committed.
mkdir -p "$REPO_REPORTS"
cp "$WORK"/reports/sta_*.rpt "$WORK/reports/metrics_fullflow.txt" "$REPO_REPORTS/"
echo
echo "Reports copied to: $REPO_REPORTS"
