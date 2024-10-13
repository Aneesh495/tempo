# ==============================================================================
# TEMPO Showcase Demo Script
#
# Runs full physical flow:
# 1. Load SkyWater 130nm Liberty library
# 2. Parse structural Verilog alu4 design
# 3. Read SDC timing constraints & SPEF parasitics
# 4. Link design into bipartite timing graph
# 5. Run full Static Timing Analysis & print critical path
# 6. Check electrical Design Rules (DRC)
# 7. Roll up chip power (leakage + dynamic) and silicon area
# ==============================================================================

set demo_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $demo_dir ".."]]

puts "================================================================================"
puts " TEMPO EDA: SkyWater 130nm Full Flow Demonstration"
puts "================================================================================"

read_liberty [file join $root_dir "lib" "sky130_hd.lib"]
read_verilog [file join $root_dir "examples" "alu4.v"]
read_sdc [file join $root_dir "examples" "alu4.sdc"]
read_spef [file join $root_dir "examples" "alu4.spef"]

link_design

puts ""
puts ">>> Running Static Timing Analysis (Max Delay)..."
report_timing -delay_type max -nworst 1

puts ""
puts ">>> Auditing Design Rules (DRC)..."
report_drc

puts ""
puts ">>> Calculating Full Chip Power & Physical Silicon Area..."
report_power
report_area

puts ""
puts "================================================================================"
puts " DEMO EXECUTION COMPLETE"
puts "================================================================================"
