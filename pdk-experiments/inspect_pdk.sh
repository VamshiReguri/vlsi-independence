#!/usr/bin/env bash
# =====================================================================
# Day 5 - carve small, human-readable slices out of the sky130hd PDK.
#
# The liberty is ~12.8 MB and the merged LEF ~2.3 MB; you should never open
# them whole. This pulls just the pieces Day 5 studies into reports/*.txt:
#
#   lib_header.txt   library-level attributes (units, PVT, delay model)
#   inv_2_cell.txt   the full .lib timing model for one inverter
#   inv_2_macro.txt  the .lef physical abstraction for the same inverter
#   tlef_excerpt.txt SITE + one routing LAYER from the technology LEF
#
# Runs on the host (no Docker needed) -- it is pure awk text extraction.
#
# Env (all optional; defaults assume ~/OpenROAD-flow-scripts):
#   ORFS_FLOW  path to .../flow            CELL  cell to extract (default inv_2)
#   RPT        output dir (default ./reports)
# =====================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORFS_FLOW="${ORFS_FLOW:-$HOME/OpenROAD-flow-scripts/flow}"
PLATFORM="sky130hd"
CELL="${CELL:-sky130_fd_sc_hd__inv_2}"
RPT="${RPT:-$SCRIPT_DIR/reports}"

LIB="$ORFS_FLOW/platforms/$PLATFORM/lib/sky130_fd_sc_hd__tt_025C_1v80.lib"
TLEF="$ORFS_FLOW/platforms/$PLATFORM/lef/sky130_fd_sc_hd.tlef"
MERGED_LEF="$ORFS_FLOW/platforms/$PLATFORM/lef/sky130_fd_sc_hd_merged.lef"

mkdir -p "$RPT"
for f in "$LIB" "$TLEF" "$MERGED_LEF"; do
  [[ -f "$f" ]] || { echo "ERROR: missing $f" >&2; exit 1; }
done

echo "Cell under study: $CELL"
echo "Liberty : $LIB"
echo "Tech LEF: $TLEF"
echo "Cell LEF: $MERGED_LEF"
echo

# --- 1. library header: everything before the first cell ( ... ) block -------
awk '/^[[:space:]]*cell \(/{exit} {print}' "$LIB" > "$RPT/lib_header.txt"
echo "wrote $RPT/lib_header.txt         ($(wc -l < "$RPT/lib_header.txt") lines)"

# --- 2. the .lib timing model for one cell (brace-balanced extraction) --------
awk -v name="$CELL" '
  index($0, "cell (\"" name "\")") { inblk=1 }
  inblk {
    print
    for (i=1;i<=length($0);i++){ c=substr($0,i,1); if(c=="{")d++; else if(c=="}")d-- }
    if (started && d==0) exit
    if (d>0) started=1
  }
' "$LIB" > "$RPT/inv_2_cell.txt"
echo "wrote $RPT/inv_2_cell.txt         ($(wc -l < "$RPT/inv_2_cell.txt") lines)"

# --- 3. the .lef physical abstraction for the same cell -----------------------
awk -v name="$CELL" '
  $0 == "MACRO " name { f=1 }
  f { print }
  f && $0 == "END " name { exit }
' "$MERGED_LEF" > "$RPT/inv_2_macro.txt"
echo "wrote $RPT/inv_2_macro.txt        ($(wc -l < "$RPT/inv_2_macro.txt") lines)"

# --- 4. technology LEF: the placement site + one routing layer ----------------
{
  echo "# ---- UNITS / MANUFACTURINGGRID ----"
  awk '/^UNITS/,/^END UNITS/' "$TLEF"
  echo
  awk '/^MANUFACTURINGGRID/{print}' "$TLEF"
  echo
  echo "# ---- SITE unithd (the placement row this cell snaps to) ----"
  awk '/^SITE unithd$/,/^END unithd$/' "$TLEF"
  echo
  echo "# ---- LAYER li1 (first routing layer, carries the cell pins) ----"
  awk '/^LAYER li1$/,/^END li1$/' "$TLEF"
} > "$RPT/tlef_excerpt.txt"
echo "wrote $RPT/tlef_excerpt.txt       ($(wc -l < "$RPT/tlef_excerpt.txt") lines)"

echo
echo "Done. Open the four files in $RPT to study the cell two ways:"
echo "  timing  -> inv_2_cell.txt   (what STA and synthesis consume)"
echo "  physical-> inv_2_macro.txt  (what place & route consume)"
