#!/usr/bin/env bash
# =====================================================================
# Day 4 driver: standalone Yosys synthesis of ibex -> sky130hd, then
# staged STA (synth / post-place / post-route) for the comparison note.
#
# Runs everything inside the same openroad/orfs image the ibex flow used,
# so the tool versions match the results being compared against.
# =====================================================================
set -eu

WORK="$HOME/vlsi-day4"
FLOW="$HOME/OpenROAD-flow-scripts/flow"
IMAGE="openroad/orfs:latest"
WIN_SCRIPTS="/mnt/c/Users/regur/Downloads/day04-yosys/scripts"

YOSYS=/OpenROAD-flow-scripts/tools/install/yosys/bin/yosys
OPENROAD=/OpenROAD-flow-scripts/tools/install/OpenROAD/bin/openroad

mkdir -p "$WORK/scripts" "$WORK/out" "$WORK/logs" "$WORK/reports"
cp "$WIN_SCRIPTS"/ibex_synth.tcl "$WIN_SCRIPTS"/sta.tcl "$WORK/scripts/"

run_in_container() {
  docker run --rm \
    -u "$(id -u):$(id -g)" \
    -e HOME=/tmp \
    -e STA_MODE="${STA_MODE:-}" \
    -v "$FLOW":/flow \
    -v "$WORK":/day4 \
    "$IMAGE" bash -c "$1"
}

echo "=============================================================="
echo " STEP 1/5 : Yosys synthesis (ibex_core -> sky130_fd_sc_hd)"
echo "=============================================================="
start=$(date +%s)
run_in_container "$YOSYS -c /day4/scripts/ibex_synth.tcl" \
  2>&1 | tee "$WORK/logs/1_yosys_synth.log"
end=$(date +%s)
echo "Yosys wall time: $((end - start)) s" | tee "$WORK/logs/1_yosys_runtime.txt"

for mode in synth_v synth_odb place route; do
  case $mode in
    synth_v)   n="2/5"; label="synth stage (my Yosys netlist)" ;;
    synth_odb) n="3/5"; label="synth stage (ORFS netlist)" ;;
    place)     n="4/5"; label="post-place (estimated parasitics)" ;;
    route)     n="5/5"; label="post-route (SPEF)" ;;
  esac
  echo
  echo "=============================================================="
  echo " STEP $n : STA - $label"
  echo "=============================================================="
  STA_MODE=$mode run_in_container "$OPENROAD -no_init -exit /day4/scripts/sta.tcl" \
    2>&1 | tee "$WORK/reports/sta_${mode}.rpt"
done

echo
echo "=============================================================="
echo " SUMMARY"
echo "=============================================================="
grep -h '^METRIC' "$WORK"/reports/sta_*.rpt | tee "$WORK/reports/metrics.txt"
