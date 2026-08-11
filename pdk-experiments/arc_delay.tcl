# =====================================================================
# Day 5 - reproduce the NLDM delay lookup for one standard-cell arc.
#
# We drive ONE cell (tiny_inv -> sky130_fd_sc_hd__inv_2) with a fixed input
# transition (slew) and a fixed output load (cap), then ask OpenSTA for the
# A -> Y arc delay.
#
# Trick: with input delay 0, no wire on either net, and a virtual clock, the
# reported "data arrival time" at Y IS the cell arc delay -- i.e. exactly the
# number OpenSTA interpolates out of the cell_rise / cell_fall tables in the
# .lib. That lets us compare tool output against a hand / Python interpolation
# of the very same table.
#
# Env vars (set by run_pdk.sh):
#   LIBERTY  full path to the .lib
#   NETLIST  path to tiny_inv.v
#   POINTS   space-separated "slew,cap" pairs   (slew in ns, cap in pF)
# =====================================================================

set liberty $::env(LIBERTY)
set netlist $::env(NETLIST)
set points  $::env(POINTS)

read_liberty $liberty
read_verilog $netlist
link_design tiny_inv

# A virtual clock + zero I/O delays turn the pure combinational A->Y into a
# reportable timing path without adding any delay of its own.
create_clock -name vclk -period 10
set_input_delay  0 -clock vclk [get_ports A]
set_output_delay 0 -clock vclk [get_ports Y]

puts "##LIBERTY $liberty"

foreach pt $points {
  lassign [split $pt ","] slew cap
  set_input_transition $slew [get_ports A]
  set_load             $cap  [get_ports Y]

  # inv is negative_unate:
  #   Y rising  <- A falling  -> uses the cell_rise table
  #   Y falling <- A rising   -> uses the cell_fall table
  puts "##POINT slew=$slew cap=$cap dir=rise"
  report_checks -from [get_ports A] -rise_to [get_ports Y] \
    -path_delay max -fields {input_pins slew cap fanout} \
    -format full -digits 5
  puts "##ENDPOINT"

  puts "##POINT slew=$slew cap=$cap dir=fall"
  report_checks -from [get_ports A] -fall_to [get_ports Y] \
    -path_delay max -fields {input_pins slew cap fanout} \
    -format full -digits 5
  puts "##ENDPOINT"
}

puts "##DONE"
exit
