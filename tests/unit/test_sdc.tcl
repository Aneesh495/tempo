# Unit Tests for Synopsys Design Constraints (SDC) Model and Parser

set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ".." ".."]]

source [file join $root_dir "tests" "framework.tcl"]
source [file join $root_dir "src" "core" "types.tcl"]
source [file join $root_dir "src" "core" "graph.tcl"]
source [file join $root_dir "src" "core" "netlist.tcl"]
source [file join $root_dir "src" "parsers" "sdc_model.tcl"]
source [file join $root_dir "src" "parsers" "sdc_parser.tcl"]

::tempo::test::suite "SDC Constraints Parser and Model"

set sample_sdc {
# System clock constraint (1 GHz = 1000 ps period)
create_clock -name core_clk -period 1000.0 -waveform {0.0 500.0} [get_ports clk]

# Clock uncertainty and latency
set_clock_uncertainty -setup 50.0 -hold 20.0 [get_clocks core_clk]
set_clock_latency -early 10.0 -late 30.0 [get_clocks core_clk]

# I/O timing constraints
set_input_delay -clock core_clk -max 150.0 [all_inputs]
set_output_delay -clock core_clk -max 200.0 [all_outputs]

# Electrical constraints
set_load 25.0 [all_outputs]
set_input_transition 15.0 [all_inputs]
set_driving_cell -lib_cell INV_X1 -pin Y [get_ports in_data]

# Timing exceptions
set_false_path -from [get_ports rst_n]
set_multicycle_path 2 -setup -from [get_pins u_mul/Q] -to [get_pins u_acc/D]
}

::tempo::test::test "Parse SDC constraint script" {
    set nl [::tempo::netlist::Netlist new "test_top"]
    $nl add_port "clk" "INPUT"
    $nl add_port "rst_n" "INPUT"
    $nl add_port "in_data" "INPUT"
    $nl add_port "out_data" "OUTPUT"

    set constraints [::tempo::sdc::Constraints new]
    ::tempo::sdc::parser::evaluate $sample_sdc $constraints $nl

    # Clocks check
    ::tempo::test::assert_true [$constraints has_clock "core_clk"]
    ::tempo::test::assert_almost_equal [$constraints get_clock_period "core_clk"] 1000.0

    # Uncertainty check
    ::tempo::test::assert_almost_equal [$constraints get_clock_uncertainty "core_clk" "setup"] 50.0
    ::tempo::test::assert_almost_equal [$constraints get_clock_uncertainty "core_clk" "hold"] 20.0

    # Latency check
    ::tempo::test::assert_almost_equal [$constraints get_clock_latency "core_clk" "early"] 10.0
    ::tempo::test::assert_almost_equal [$constraints get_clock_latency "core_clk" "late"] 30.0

    # Input delay check
    ::tempo::test::assert_almost_equal [$constraints get_max_input_delay "in_data"] 150.0
    ::tempo::test::assert_almost_equal [$constraints get_max_output_delay "out_data"] 200.0

    # Electrical load and transition
    ::tempo::test::assert_almost_equal [$constraints get_load "out_data"] 25.0
    ::tempo::test::assert_almost_equal [$constraints get_input_transition "in_data"] 15.0

    # Driving cell
    set drv [$constraints get_driving_cell "in_data"]
    ::tempo::test::assert_equal [dict get $drv lib_cell] "INV_X1"

    # Timing exceptions
    ::tempo::test::assert_true [$constraints is_false_path "rst_n" "any_internal_reg"]
    ::tempo::test::assert_true [expr {![$constraints is_false_path "in_data" "out_data"]}]
    ::tempo::test::assert_equal [$constraints get_multicycle_setup "u_mul/Q" "u_acc/D"] 2
    ::tempo::test::assert_equal [$constraints get_multicycle_setup "u_other/Q" "u_acc/D"] 1

    $nl destroy
    $constraints destroy
}

set code [::tempo::test::report]
exit $code
