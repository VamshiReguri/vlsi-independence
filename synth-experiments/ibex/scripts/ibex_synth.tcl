# =====================================================================
# Day 4 - Standalone Yosys synthesis of the Ibex RISC-V core to sky130hd
#
# This is a deliberately "textbook" flow that follows the stages the Yosys
# manual describes (frontend -> coarse RTLIL -> fine techmap -> ABC gate
# mapping), rather than the heavily tuned script ORFS ships. Keeping it
# vanilla is the point: it makes the diff against the ORFS run readable.
# =====================================================================

yosys -import

set FLOW      /flow
set PLATFORM  $FLOW/platforms/sky130hd
set LIB       $PLATFORM/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
set SRC       $FLOW/designs/src/ibex_sv
set OUT       /day4/out
set TOP       ibex_core

# Clock period from designs/sky130hd/ibex/constraint.sdc
set CLK_PERIOD_NS 10.0
set CLK_PERIOD_PS [expr { int($CLK_PERIOD_NS * 1000) }]

file mkdir $OUT

# sky130hd cells that ORFS marks unusable (probe + low-power-flow cells).
set DONT_USE_CELLS {
  sky130_fd_sc_hd__probe_p_8 sky130_fd_sc_hd__probec_p_8
  sky130_fd_sc_hd__lpflow_bleeder_1
  sky130_fd_sc_hd__lpflow_clkbufkapwr_1 sky130_fd_sc_hd__lpflow_clkbufkapwr_16
  sky130_fd_sc_hd__lpflow_clkbufkapwr_2 sky130_fd_sc_hd__lpflow_clkbufkapwr_4
  sky130_fd_sc_hd__lpflow_clkbufkapwr_8
  sky130_fd_sc_hd__lpflow_clkinvkapwr_1 sky130_fd_sc_hd__lpflow_clkinvkapwr_16
  sky130_fd_sc_hd__lpflow_clkinvkapwr_2 sky130_fd_sc_hd__lpflow_clkinvkapwr_4
  sky130_fd_sc_hd__lpflow_clkinvkapwr_8
  sky130_fd_sc_hd__lpflow_decapkapwr_12 sky130_fd_sc_hd__lpflow_decapkapwr_3
  sky130_fd_sc_hd__lpflow_decapkapwr_4 sky130_fd_sc_hd__lpflow_decapkapwr_6
  sky130_fd_sc_hd__lpflow_decapkapwr_8
  sky130_fd_sc_hd__lpflow_inputiso0n_1 sky130_fd_sc_hd__lpflow_inputiso0p_1
  sky130_fd_sc_hd__lpflow_inputiso1n_1 sky130_fd_sc_hd__lpflow_inputiso1p_1
  sky130_fd_sc_hd__lpflow_inputisolatch_1
  sky130_fd_sc_hd__lpflow_isobufsrc_1 sky130_fd_sc_hd__lpflow_isobufsrc_16
  sky130_fd_sc_hd__lpflow_isobufsrc_2 sky130_fd_sc_hd__lpflow_isobufsrc_4
  sky130_fd_sc_hd__lpflow_isobufsrc_8 sky130_fd_sc_hd__lpflow_isobufsrckapwr_16
  sky130_fd_sc_hd__lpflow_lsbuf_lh_hl_isowell_tap_1
  sky130_fd_sc_hd__lpflow_lsbuf_lh_hl_isowell_tap_2
  sky130_fd_sc_hd__lpflow_lsbuf_lh_hl_isowell_tap_4
  sky130_fd_sc_hd__lpflow_lsbuf_lh_isowell_4
  sky130_fd_sc_hd__lpflow_lsbuf_lh_isowell_tap_1
  sky130_fd_sc_hd__lpflow_lsbuf_lh_isowell_tap_2
  sky130_fd_sc_hd__lpflow_lsbuf_lh_isowell_tap_4
}
set dont_use_args [list]
foreach c $DONT_USE_CELLS { lappend dont_use_args -dont_use $c }

# ABC needs a driver/load model for the primary inputs and outputs, otherwise
# it optimises against an unloaded, infinitely strong environment.
set constr_file $OUT/abc.constr
set fh [open $constr_file w]
puts $fh "set_driving_cell sky130_fd_sc_hd__buf_1"
puts $fh "set_load 5"
close $fh

# ---------------------------------------------------------------------
# Stage 0 - the target cell library, loaded as blackboxes
# ---------------------------------------------------------------------
# Two reads: the first gives real functions/areas, the second (-unit_delay
# -wb) supplies whitebox models so later passes can reason through cells.
puts "\n>>> STAGE 0: read_liberty (sky130_fd_sc_hd)"
read_liberty -overwrite -setattr liberty_cell -lib $LIB
read_liberty -overwrite -setattr liberty_cell \
  -unit_delay -wb -ignore_miss_func -ignore_buses $LIB

# ---------------------------------------------------------------------
# Stage 1 - frontend: SystemVerilog -> AST -> RTLIL
# ---------------------------------------------------------------------
# Ibex is real SystemVerilog (packages, structs, interfaces), which the
# built-in read_verilog frontend cannot digest. Yosys >= 0.67 ships the
# slang frontend, which is what the ORFS ibex config selects too.
puts "\n>>> STAGE 1: read_slang (SystemVerilog frontend)"
set rtl_files [lsort [glob $SRC/*.sv]]
lappend rtl_files $SRC/syn/rtl/prim_clock_gating.v
lappend rtl_files $PLATFORM/cells_clkgate_hd.v

read_slang -D SYNTHESIS --keep-hierarchy --compat=vcs --ignore-assertions \
  --top $TOP -I$SRC/vendor/lowrisc_ip/prim/rtl/ {*}$rtl_files

# yosys-slang emits init attributes that the rest of the flow chokes on.
setattr -unset init

puts "\n>>> STAGE 1b: hierarchy check"
hierarchy -check -top $TOP
tee -o $OUT/stat_01_rtl.txt stat

# ---------------------------------------------------------------------
# Stage 2 - coarse-grain synthesis (word-level RTLIL optimisation)
# ---------------------------------------------------------------------
# `synth -run :fine` stops right before bit-level techmap, so the design is
# still made of word-level $add/$mux/$dff cells here. -noabc keeps the
# generic ABC pass out of the way; we do our own liberty-aware mapping.
puts "\n>>> STAGE 2: coarse synthesis (synth -run :fine)"
synth -top $TOP -flatten -run :fine
tee -o $OUT/stat_02_coarse.txt stat

# ---------------------------------------------------------------------
# Stage 3 - fine-grain synthesis: memories + word-level cells -> gates
# ---------------------------------------------------------------------
puts "\n>>> STAGE 3: fine synthesis (memory_map, techmap)"
synth -top $TOP -run fine: -noabc
opt -purge
tee -o $OUT/stat_03_fine.txt stat

# Logic depth has to be measured here, while the flops are still generic
# $_DFF_* cells. After dfflibmap they become liberty blackboxes, ltp stops
# recognising them as sequential, and every register loop is reported as a
# combinational loop instead.
tee -o $OUT/ltp.txt ltp -noff

# ---------------------------------------------------------------------
# Stage 4 - map sequential elements to real library cells
# ---------------------------------------------------------------------
# Latches first (sky130hd has no native async-set/reset latch, so ORFS
# emulates them from the cells in cells_latch_hd.v), then flip-flops.
puts "\n>>> STAGE 4: dfflibmap / latch mapping"
set latch_map $PLATFORM/cells_latch_hd.v
if { [file exists $latch_map] } {
  dfflegalize -cell {$_DLATCH_P_} x -cell {$_DLATCH_N_} x {t:$_DLATCH_*}
  techmap -map $latch_map
}
dfflibmap -liberty $LIB {*}$dont_use_args
opt

# ---------------------------------------------------------------------
# Stage 5 - combinational mapping with ABC against the liberty file
# ---------------------------------------------------------------------
# This is the step that actually turns Boolean logic into sky130 gates and
# does the timing-driven cell selection, so it is also where the first
# meaningful delay number in the whole flow appears.
puts "\n>>> STAGE 5: ABC technology mapping (-D $CLK_PERIOD_PS ps)"
setundef -zero
abc -liberty $LIB {*}$dont_use_args -constr $constr_file -D $CLK_PERIOD_PS

# ---------------------------------------------------------------------
# Stage 6 - cleanup and legalisation of the gate-level netlist
# ---------------------------------------------------------------------
puts "\n>>> STAGE 6: cleanup"
setundef -zero
splitnets
opt_clean -purge
hilomap -singleton \
  -hicell sky130_fd_sc_hd__conb_1 HI \
  -locell sky130_fd_sc_hd__conb_1 LO
insbuf -buf sky130_fd_sc_hd__buf_4 A X

check -assert -mapped

# ---------------------------------------------------------------------
# Stage 7 - reports and netlist output
# ---------------------------------------------------------------------
puts "\n>>> STAGE 7: reports"
tee -o $OUT/stat_04_mapped.txt stat -liberty $LIB
tee -o $OUT/check.txt check

write_verilog -nohex -nodec $OUT/ibex_yosys.v
write_json $OUT/ibex_yosys.json

puts "\n>>> DONE: netlist written to $OUT/ibex_yosys.v"
