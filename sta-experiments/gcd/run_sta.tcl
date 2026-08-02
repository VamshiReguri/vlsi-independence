# Standalone post-route STA on gcd (sky130hd)
# Outputs go to stdout — captured by run_sta.sh into reports/

set netlist $::env(NETLIST)
set sdc     $::env(SDC)
set spef    $::env(SPEF)
set liberty $::env(LIBERTY)

read_liberty $liberty
read_verilog $netlist
link_design gcd
read_sdc $sdc
read_spef $spef
set_propagated_clock [get_clocks core_clock]

puts "=== OpenSTA summary ==="
report_wns
report_tns
report_worst_slack

puts "\n=== report_checks setup (max) ==="
report_checks -path_delay max -fields {slew cap fanout} -digits 3 -group_count 100

puts "\n=== report_checks hold (min) ==="
report_checks -path_delay min -fields {slew cap fanout} -digits 3 -group_count 20

puts "\n=== done ==="
