# Unit Tests for Timing-Driven Optimization Subsystem

set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ".." ".."]]

source [file join $root_dir "tests" "framework.tcl"]
source [file join $root_dir "src" "core" "types.tcl"]
source [file join $root_dir "src" "core" "graph.tcl"]
source [file join $root_dir "src" "core" "netlist.tcl"]
source [file join $root_dir "src" "parsers" "liberty_model.tcl"]
source [file join $root_dir "src" "parsers" "sdc_model.tcl"]
source [file join $root_dir "src" "sta" "timing_graph.tcl"]
source [file join $root_dir "src" "sta" "delay_calc.tcl"]
source [file join $root_dir "src" "sta" "elmore.tcl"]
source [file join $root_dir "src" "sta" "clock_tree.tcl"]
source [file join $root_dir "src" "sta" "forward_prop.tcl"]
source [file join $root_dir "src" "sta" "backward_prop.tcl"]
source [file join $root_dir "src" "sta" "slack_calc.tcl"]
source [file join $root_dir "src" "opt" "drc.tcl"]
source [file join $root_dir "src" "opt" "gate_sizing.tcl"]
source [file join $root_dir "src" "opt" "buffer_insert.tcl"]
source [file join $root_dir "src" "opt" "hold_fix.tcl"]

# Mock standard cell library with multiple drive strengths
set lib [::tempo::liberty::Library new]
$lib add_cell "INV_X1" [dict create name "INV_X1" area 1.0 is_sequential 0 pins [dict create \
    A [dict create direction "input" capacitance 0.002] \
    Y [dict create direction "output" capacitance 0.0 max_capacitance 0.05 function "!A"]]]
$lib add_cell "INV_X2" [dict create name "INV_X2" area 1.8 is_sequential 0 pins [dict create \
    A [dict create direction "input" capacitance 0.004] \
    Y [dict create direction "output" capacitance 0.0 max_capacitance 0.10 function "!A"]]]
$lib add_cell "INV_X4" [dict create name "INV_X4" area 3.2 is_sequential 0 pins [dict create \
    A [dict create direction "input" capacitance 0.008] \
    Y [dict create direction "output" capacitance 0.0 max_capacitance 0.20 function "!A"]]]
$lib add_cell "BUF_X1" [dict create name "BUF_X1" area 1.2 is_sequential 0 pins [dict create \
    A [dict create direction "input" capacitance 0.002] \
    Y [dict create direction "output" capacitance 0.0 max_capacitance 0.06 function "A"]]]
$lib add_cell "BUF_X2" [dict create name "BUF_X2" area 2.0 is_sequential 0 pins [dict create \
    A [dict create direction "input" capacitance 0.004] \
    Y [dict create direction "output" capacitance 0.0 max_capacitance 0.12 function "A"]]]
$lib add_cell "DFF_X1" [dict create name "DFF_X1" area 6.0 is_sequential 1 pins [dict create \
    CK [dict create direction "input" capacitance 0.004 is_clock 1] \
    D  [dict create direction "input" capacitance 0.003 is_clock 0] \
    Q  [dict create direction "output" capacitance 0.0 function "IQ"]]]

::tempo::test::suite "Design Rule Checking (DRC)"

::tempo::test::test "Detect max capacitance and max fanout violations" {
    set nl [::tempo::netlist::Netlist new "drc_test"]
    $nl add_port "in" "INPUT"
    $nl add_port "out" "OUTPUT"

    $nl add_instance "u_driver" "INV_X1"
    $nl connect_pin "u_driver" "A" "in" "LOAD"
    $nl connect_pin "u_driver" "Y" "w_bigload" "DRIVER"

    # Add 25 load instances to trigger fanout and capacitance violations
    for {set i 0} {$i < 25} {incr i} {
        set lname "u_load_${i}"
        $nl add_instance $lname "INV_X2"
        $nl connect_pin $lname "A" "w_bigload" "LOAD"
        $nl connect_pin $lname "Y" "w_out_${i}" "DRIVER"
    }

    set c [::tempo::sdc::Constraints new]
    set tg [::tempo::sta::graph::TimingGraph new $nl $lib]
    $tg build

    set clk_an [::tempo::sta::clock::ClockTreeAnalyzer new $c $tg]
    set fwd [::tempo::sta::forward::ForwardPropagator new $tg $nl $lib $c "" $clk_an]
    $fwd propagate

    set drc [::tempo::opt::drc::DRCChecker new $nl $lib $c $fwd $tg]
    set viols [$drc check_all]

    ::tempo::test::assert_true [expr {[llength $viols] >= 2}] "Should report both fanout and cap violations"

    set has_cap_viol 0
    set has_fanout_viol 0
    foreach v $viols {
        if {[dict get $v rule] eq "max_capacitance"} { set has_cap_viol 1 }
        if {[dict get $v rule] eq "max_fanout"} { set has_fanout_viol 1 }
    }
    ::tempo::test::assert_true $has_cap_viol "Max capacitance violation detected"
    ::tempo::test::assert_true $has_fanout_viol "Max fanout violation detected"

    set report [$drc format_report]
    ::tempo::test::assert_true [regexp {TEMPO DESIGN RULE CHECK} $report]

    $drc destroy
    $fwd destroy
    $clk_an destroy
    $tg destroy
    $c destroy
    $nl destroy
}

::tempo::test::suite "Gate Sizing Engine"

::tempo::test::test "Up-sizing and down-sizing within cell family" {
    set nl [::tempo::netlist::Netlist new "size_test"]
    $nl add_instance "u_inv" "INV_X1"

    set c [::tempo::sdc::Constraints new]
    set tg [::tempo::sta::graph::TimingGraph new $nl $lib]

    set sizer [::tempo::opt::sizing::GateSizer new $nl $lib $c $tg]

    ::tempo::test::assert_equal [$sizer get_upsize_candidate "INV_X1"] "INV_X2"
    ::tempo::test::assert_equal [$sizer get_upsize_candidate "INV_X2"] "INV_X4"
    ::tempo::test::assert_equal [$sizer get_upsize_candidate "INV_X4"] ""

    ::tempo::test::assert_equal [$sizer get_downsize_candidate "INV_X4"] "INV_X2"
    ::tempo::test::assert_equal [$sizer get_downsize_candidate "INV_X2"] "INV_X1"
    ::tempo::test::assert_equal [$sizer get_downsize_candidate "INV_X1"] ""

    set up_changes [$sizer optimize_setup_timing [list "u_inv"]]
    ::tempo::test::assert_equal [llength $up_changes] 1
    ::tempo::test::assert_equal [$nl get_instance_cell "u_inv"] "INV_X2"

    set down_changes [$sizer recover_area [list "u_inv"]]
    ::tempo::test::assert_equal [llength $down_changes] 1
    ::tempo::test::assert_equal [$nl get_instance_cell "u_inv"] "INV_X1"

    $sizer destroy
    $tg destroy
    $c destroy
    $nl destroy
}

::tempo::test::suite "Buffer Insertion and High-Fanout Net Splitting"

::tempo::test::test "Repeater tree insertion on high fanout nets" {
    set nl [::tempo::netlist::Netlist new "buf_test"]
    $nl add_port "pi" "INPUT"
    $nl add_instance "u_drv" "INV_X1"
    $nl connect_pin "u_drv" "A" "pi" "LOAD"
    $nl connect_pin "u_drv" "Y" "w_clk" "DRIVER"

    for {set i 0} {$i < 8} {incr i} {
        $nl add_instance "u_sink_${i}" "INV_X1"
        $nl connect_pin "u_sink_${i}" "A" "w_clk" "LOAD"
    }

    set inserter [::tempo::opt::buffer::BufferInserter new $nl $lib]
    set trees [$inserter split_high_fanout_net "w_clk" 4 "BUF_X2"]

    ::tempo::test::assert_equal [llength $trees] 2 "8 sinks with max_fanout 4 should generate 2 buffer branches"

    $inserter destroy
    $nl destroy
}

::tempo::test::suite "Hold Time Remediation"

::tempo::test::test "Remediate negative hold slack via delay buffer" {
    set nl [::tempo::netlist::Netlist new "hold_test"]
    $nl add_instance "u_src" "INV_X1"
    $nl connect_pin "u_src" "A" "pi" "LOAD"
    $nl connect_pin "u_src" "Y" "w_dat" "DRIVER"

    $nl add_instance "u_ff" "DFF_X1"
    $nl connect_pin "u_ff" "D" "w_dat" "LOAD"

    # Mock slack calculator with negative hold slack and generous setup slack
    oo::class create MockSlackCalc {
        method get_hold_slacks {} {
            return [dict create "pin:u_ff/D" -15.0]
        }
        method get_setup_slack {nid} {
            return 250.0
        }
    }

    set m_slk [MockSlackCalc new]
    set inserter [::tempo::opt::buffer::BufferInserter new $nl $lib]
    set fixer [::tempo::opt::hold::HoldFixer new $nl $lib $m_slk $inserter]

    set fixes [$fixer fix_hold_violations "BUF_X1" 5.0]
    ::tempo::test::assert_equal [llength $fixes] 1
    ::tempo::test::assert_equal [dict get [lindex $fixes 0] status] "FIXED"

    $fixer destroy
    $inserter destroy
    $m_slk destroy
    $nl destroy
}

$lib destroy

set code [::tempo::test::report]
exit $code
