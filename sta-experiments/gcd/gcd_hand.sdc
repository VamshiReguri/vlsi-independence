# Hand-written SDC for gcd post-route STA (Day 2)
# Matches ORFS constraint intent: 1.1 ns clock, 20% I/O delays, 0.29 ns latency

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
