# Day 3 — multicycle-path experiment (same base as gcd_hand.sdc)
# Predict before re-run: setup capture edge moves +1 period → WNS ≈ -1.495 + 1.1 = -0.395 ns

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

# --- Day 3 exception: 2-cycle setup between all core_clock flops ---
# Default hold edge follows the moved setup edge → would invent hold fails.
# -hold 1 restores the same-edge hold check (industry-standard companion).
set_multicycle_path 2 -setup -from [get_clocks core_clock] -to [get_clocks core_clock]
set_multicycle_path 1 -hold  -from [get_clocks core_clock] -to [get_clocks core_clock]
