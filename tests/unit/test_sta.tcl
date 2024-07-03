# Unit Tests for Static Timing Analysis (STA) Engine

set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ".." ".."]]

source [file join $root_dir "tests" "framework.tcl"]
source [file join $root_dir "src" "core" "types.tcl"]
source [file join $root_dir "src" "core" "graph.tcl"]
source [file join $root_dir "src" "core" "netlist.tcl"]
source [file join $root_dir "src" "parsers" "liberty_model.tcl"]
source [file join $root_dir "src" "parsers" "sdc_model.tcl"]
source [file join $root_dir "src" "parsers" "spef_parser.tcl"]
source [file join $root_dir "src" "sta" "timing_graph.tcl"]
source [file join $root_dir "src" "sta" "delay_calc.tcl"]
source [file join $root_dir "src" "sta" "elmore.tcl"]
source [file join $root_dir "src" "sta" "clock_tree.tcl"]
source [file join $root_dir "src" "sta" "forward_prop.tcl"]
source [file join $root_dir "src" "sta" "backward_prop.tcl"]
source [file join $root_dir "src" "sta" "slack_calc.tcl"]
source [file join $root_dir "src" "sta" "critical_path.tcl"]
source [file join $root_dir "src" "sta" "corner.tcl"]

::tempo::test::suite "STA Timing Graph Construction"

# Build realistic test environment
set lib [::tempo::liberty::Library new]
$lib add_cell "INV_X1" [dict create name "INV_X1" area 1.0 is_sequential 0 pins [dict create \
    A [dict create direction "input" capacitance 0.002] \
    Y [dict create direction "output" capacitance 0.0 function "!A"]]]
$lib add_cell "NAND2_X1" [dict create name "NAND2_X1" area 1.5 is_sequential 0 pins [dict create \
    A [dict create direction "input" capacitance 0.003] \
    B [dict create direction "input" capacitance 0.003] \
    Y [dict create direction "output" capacitance 0.0 function "!(A & B)"]]]
$lib add_cell "DFF_X1" [dict create name "DFF_X1" area 6.0 is_sequential 1 pins [dict create \
    CK [dict create direction "input" capacitance 0.004 is_clock 1] \
    D  [dict create direction "input" capacitance 0.003 is_clock 0] \
    Q  [dict create direction "output" capacitance 0.0 function "IQ"]]]

# Netlist: pi_in -> [u_nand] -> [u_inv] -> [u_reg/D]; clk -> u_reg/CK; u_reg/Q -> po_out
set nl [::tempo::netlist::Netlist new "sta_pipeline"]
$nl add_port "pi_in" "INPUT"
$nl add_port "clk"   "INPUT"
$nl add_port "po_out" "OUTPUT"

$nl add_net "w_nand"
$nl add_net "w_inv"
$nl add_net "w_q"

$nl add_instance "u_nand" "NAND2_X1"
$nl connect_pin "u_nand" "A" "pi_in" "LOAD"
$nl connect_pin "u_nand" "B" "pi_in" "LOAD"
$nl connect_pin "u_nand" "Y" "w_nand" "DRIVER"

$nl add_instance "u_inv" "INV_X1"
$nl connect_pin "u_inv" "A" "w_nand" "LOAD"
$nl connect_pin "u_inv" "Y" "w_inv" "DRIVER"

$nl add_instance "u_reg" "DFF_X1"
$nl connect_pin "u_reg" "D" "w_inv" "LOAD"
$nl connect_pin "u_reg" "CK" "clk" "LOAD"
$nl connect_pin "u_reg" "Q" "po_out" "DRIVER"

::tempo::test::test "Build bipartite timing graph" {
    set tg [::tempo::sta::graph::TimingGraph new $nl $lib]
    $tg build

    set sps [$tg get_startpoints]
    set eps [$tg get_endpoints]
    set cks [$tg get_clock_pins]

    ::tempo::test::assert_true [expr {"pi_in" in $sps}] "Primary input must be a startpoint"
    ::tempo::test::assert_true [expr {"u_reg/Q" in $sps}] "Register Q pin must be a startpoint"
    ::tempo::test::assert_true [expr {"u_reg/D" in $eps}] "Register D pin must be an endpoint"
    ::tempo::test::assert_true [expr {"po_out" in $eps}] "Primary output must be an endpoint"
    ::tempo::test::assert_true [expr {"u_reg/CK" in $cks}] "Register CK pin must be a clock pin"

    $tg destroy
}

::tempo::test::suite "End-to-End STA Propagation and Slack Calculation"

::tempo::test::test "Full STA pipeline: arrival, required, slack, and reporting" {
    # 1. Constraints
    set c [::tempo::sdc::Constraints new]
    $c add_clock "core_clk" 1000.0 [list 0.0 500.0] "clk"
    $c set_clock_uncertainty "core_clk" 50.0 20.0
    $c set_clock_latency "core_clk" 10.0 25.0
    $c set_input_delay "pi_in" 150.0 "core_clk" "max"
    $c set_input_transition "pi_in" 15.0
    $c set_load "po_out" 20.0

    # 2. Timing graph
    set tg [::tempo::sta::graph::TimingGraph new $nl $lib]
    $tg build

    # 3. Clock tree analyzer
    set clk_an [::tempo::sta::clock::ClockTreeAnalyzer new $c $tg]
    $clk_an analyze

    # 4. Forward propagation
    set fwd [::tempo::sta::forward::ForwardPropagator new $tg $nl $lib $c "" $clk_an]
    $fwd propagate

    # Check arrival at u_reg/D: must be > input_delay (150ps) + gate delays
    set d_nid [$tg get_node_by_pin "u_reg/D"]
    set arr_d [dict get [$fwd get_arrivals $d_nid] late_r]
    ::tempo::test::assert_true [expr {$arr_d > 175.0}] "Data arrival at D must include gate delays"

    # 5. Backward propagation
    set bwd [::tempo::sta::backward::BackwardPropagator new $tg $nl $lib $c "" $clk_an $fwd]
    $bwd propagate

    # 6. Slack calculation
    set slk [::tempo::sta::slack::SlackCalculator new $tg $c $fwd $bwd]
    $slk calculate

    set summary [$slk get_summary]
    set wns [dict get $summary setup_wns]
    ::tempo::test::assert_true [expr {$wns >= 0.0}] "Slack should be positive (timing met) for 1 GHz clock"

    # 7. Critical path report
    set rep_eng [::tempo::sta::report::PathExtractor new $tg $nl $lib $c $fwd $bwd $slk]
    set txt [$rep_eng format_report 1 "max"]
    ::tempo::test::assert_true [regexp {TEMPO STATIC TIMING ANALYSIS REPORT} $txt]
    ::tempo::test::assert_true [regexp {slack \(MET\)} $txt]

    $tg destroy
    $clk_an destroy
    $fwd destroy
    $bwd destroy
    $slk destroy
    $rep_eng destroy
    $c destroy
}

::tempo::test::suite "Multi-Corner PVT Analysis"

::tempo::test::test "Corner scaling metrics" {
    set cm [::tempo::sta::corner::CornerManager new]
    ::tempo::test::assert_almost_equal [$cm get_corner_scale "typical"] 1.00
    ::tempo::test::assert_almost_equal [$cm get_corner_scale "slow"]    1.35
    ::tempo::test::assert_almost_equal [$cm get_corner_scale "fast"]    0.75
    $cm destroy
}

$nl destroy
$lib destroy

set code [::tempo::test::report]
exit $code
