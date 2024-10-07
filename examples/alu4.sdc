# ==============================================================================
# SDC 2.1 Design Constraints for alu4
# ==============================================================================

# Target Clock: 1.0 GHz (period = 1000.0 ps = 1.0 ns)
create_clock -name core_clk -period 1000.0 -waveform {0.0 500.0} [get_ports clk]

# Clock Uncertainty: 50 ps setup, 20 ps hold
set_clock_uncertainty -setup 50.0 [get_clocks core_clk]
set_clock_uncertainty -hold 20.0 [get_clocks core_clk]

# Clock Latency: 30 ps source, 15 ps network
set_clock_latency -source 30.0 [get_clocks core_clk]
set_clock_latency 15.0 [get_clocks core_clk]

# Input Delays: 150 ps max, 40 ps min
set_input_delay -clock core_clk -max 150.0 [get_ports a]
set_input_delay -clock core_clk -min 40.0 [get_ports a]
set_input_delay -clock core_clk -max 150.0 [get_ports b]
set_input_delay -clock core_clk -min 40.0 [get_ports b]

# Input Transition (Slew)
set_input_transition -max 25.0 [get_ports a]
set_input_transition -max 25.0 [get_ports b]

# Output Delays: 100 ps max, 25 ps min
set_output_delay -clock core_clk -max 100.0 [get_ports result]
set_output_delay -clock core_clk -min 25.0 [get_ports result]

# Output Capacitive Load: 0.015 pF (15 fF)
set_load -pin_load 0.015 [get_ports result]
