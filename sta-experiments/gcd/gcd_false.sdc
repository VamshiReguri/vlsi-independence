# Day 3 — false-path experiment (same base as gcd_hand.sdc)
# Waives only the Day-2 worst path. Predict: WNS → next path ≈ -1.490 ns (Δ ≈ +5 ps)

current_design gcd

# --- Clocks ---
set clk_period 1.1
set clk_io_pct 0.2

create_clock -name core_clock -period $clk_period [get_ports clk]
create_clock -name vclk_core_clock -period $clk_period

set_clock_latency 0.290 [get_clocks core_clock]
set_clock_latency 0.290 [get_clocks vclk_core_clock]

# --- I/O timing (virtual clock for pad-to-reg / reg-to-pad) ---
set io_delay [expr $clk_period * $clk_io_pct]

set_input_delay  $io_delay -clock vclk_core_clock [all_inputs -no_clocks]
set_output_delay $io_delay -clock vclk_core_clock [all_outputs]

# --- Day 3 exception: remove the single worst setup path from analysis ---
# Braces required: unbraced $_DFFE_PP_ / [8] are Tcl expansions.
set_false_path \
  -from [get_pins {dpath.a_reg.out[8]$_DFFE_PP_/CLK}] \
  -to   [get_pins {dpath.a_reg.out[6]$_DFFE_PP_/D}]
