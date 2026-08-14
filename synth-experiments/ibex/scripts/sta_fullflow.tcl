# =====================================================================
# Day 6 - full-flow staged STA (OpenROAD's built-in OpenSTA)
#
# Times every ORFS stage of the completed ibex RTL->GDS run on the SAME
# design, so the only thing changing between rows is the stage itself:
#
#   STA_MODE = synth | floorplan | place | cts | route
#
# Each stage is read together with ITS OWN stage SDC, so the clock model
# matches what that stage actually saw:
#   synth / floorplan / place -> ideal clock (SDC has no propagation)
#   cts / route               -> propagated clock (SDC sets it)
#
# Parasitics per stage:
#   synth      : none            (no placement -> pin capacitance only)
#   floorplan  : none            (std cells still unplaced; buffers stripped here)
#   place, cts : estimate_parasitics -placement  (RC from placed locations)
#   route      : read_spef       (real extracted parasitics from routing)
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
  synth {
    # ORFS synth-stage database: mapped netlist, no physical placement.
    read_db  $RESULTS/1_synth.odb
    read_sdc $RESULTS/1_synth.sdc
    source   $PLATFORM/setRC.tcl
  }
  floorplan {
    # Die/core area, IO pins, tapcells and PDN exist; std cells are NOT
    # placed yet. This is also where REMOVE_ABC_BUFFERS strips buffering,
    # so timing should still be wide open here.
    read_db  $RESULTS/2_floorplan.odb
    read_sdc $RESULTS/2_floorplan.sdc
    source   $PLATFORM/setRC.tcl
  }
  place {
    # Global + detailed placement done and the resizer has run.
    read_db  $RESULTS/3_place.odb
    read_sdc $RESULTS/3_place.sdc
    source   $PLATFORM/setRC.tcl
    estimate_parasitics -placement
  }
  cts {
    # First stage with a real clock tree; the stage SDC sets a propagated
    # clock, so clock latency/skew now comes from the built tree.
    read_db  $RESULTS/4_cts.odb
    read_sdc $RESULTS/4_cts.sdc
    source   $PLATFORM/setRC.tcl
    estimate_parasitics -placement
  }
  route {
    # Signoff database with real extracted parasitics from detailed routing.
    read_db   $RESULTS/6_final.odb
    read_sdc  $RESULTS/6_final.sdc
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

puts "\n########## min period / fmax ##########"
catch { report_clock_min_period } msg
puts $msg

puts "\n########## clock skew ##########"
catch { report_clock_skew -digits 4 } msg
puts $msg

puts "\n########## design area ##########"
report_design_area

# Machine-readable one-liner that the driver greps into the summary table.
puts "METRIC $MODE setup_wns=[worst_slack -max] setup_tns=[total_negative_slack -max] hold_wns=[worst_slack -min]"
