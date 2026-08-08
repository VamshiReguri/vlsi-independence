# =====================================================================
# Day 4 - staged STA driver (OpenROAD's built-in OpenSTA)
#
# Driven by env vars so the same script can time the synth-stage netlist,
# the post-place database and the post-route database identically.
#
#   STA_MODE = synth_v | synth_odb | place | route
#
# Everything is written to stdout; the caller tees it into a report file.
# =====================================================================

set FLOW     /flow
set PLATFORM $FLOW/platforms/sky130hd
set LIB      $PLATFORM/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
set RESULTS  $FLOW/results/sky130hd/ibex/base
set MODE     $::env(STA_MODE)

puts "########## STA_MODE = $MODE ##########"

read_liberty $LIB

switch $MODE {
  synth_v {
    # My standalone Yosys netlist. No placement exists, so there are no
    # parasitics at all: numbers are cell delay + pin capacitance only.
    read_lef $PLATFORM/lef/sky130_fd_sc_hd.tlef
    read_lef $PLATFORM/lef/sky130_fd_sc_hd_merged.lef
    read_verilog /day4/out/ibex_yosys.v
    link_design ibex_core
    read_sdc $FLOW/designs/sky130hd/ibex/constraint.sdc
    source $PLATFORM/setRC.tcl
  }
  synth_odb {
    # ORFS's own synth-stage database: same stage as above, but produced by
    # the tuned ORFS script, so the comparison isolates the script.
    read_db $RESULTS/1_synth.odb
    read_sdc $RESULTS/1_synth.sdc
    source $PLATFORM/setRC.tcl
  }
  place {
    read_db $RESULTS/3_place.odb
    read_sdc $RESULTS/3_place.sdc
    source $PLATFORM/setRC.tcl
    estimate_parasitics -placement
  }
  route {
    read_db $RESULTS/6_final.odb
    read_sdc $RESULTS/6_final.sdc
    read_spef $RESULTS/6_final.spef
  }
  default { error "unknown STA_MODE: $MODE" }
}

puts "\n########## setup: 5 worst paths ##########"
report_checks -path_delay max -sort_by_slack -group_count 5 \
  -format full_clock_expanded -digits 4

puts "\n########## hold: 5 worst paths ##########"
report_checks -path_delay min -sort_by_slack -group_count 5 -digits 4

puts "\n########## WNS / TNS ##########"
report_worst_slack -max -digits 4
report_worst_slack -min -digits 4
report_tns -digits 4

puts "\n########## clock skew ##########"
report_clock_skew -digits 4

puts "\n########## design area ##########"
report_design_area

# Machine-readable one-liner that the driver greps into the summary table.
puts "METRIC $MODE setup_wns=[worst_slack -max] setup_tns=[total_negative_slack -max] hold_wns=[worst_slack -min]"
