# Unit Tests for Gate-Level Simulator, VCD Writer, and Hazard Detector

set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ".." ".."]]

source [file join $root_dir "tests" "framework.tcl"]
source [file join $root_dir "src" "core" "types.tcl"]
source [file join $root_dir "src" "core" "bitvector.tcl"]
source [file join $root_dir "src" "core" "graph.tcl"]
source [file join $root_dir "src" "core" "netlist.tcl"]
source [file join $root_dir "src" "parsers" "liberty_model.tcl"]
source [file join $root_dir "src" "sim" "event.tcl"]
source [file join $root_dir "src" "sim" "simulator.tcl"]
source [file join $root_dir "src" "sim" "vcd.tcl"]
source [file join $root_dir "src" "sim" "hazard.tcl"]

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

::tempo::test::suite "Discrete Event Queue Engine"

::tempo::test::test "Event queue scheduling, sorting, and cancellation" {
    set q [::tempo::sim::event::EventQueue new]
    $q schedule 50 "netA" "1"
    $q schedule 20 "netB" "0"
    $q schedule 80 "netA" "0"
    $q schedule 20 "netC" "1"

    ::tempo::test::assert_equal [$q size] 4
    ::tempo::test::assert_equal [$q next_time] 20

    # Pop time 20 events
    lassign [$q pop_current_events] t evs
    ::tempo::test::assert_equal $t 20
    ::tempo::test::assert_equal [llength $evs] 2

    # Cancel pending events on netA
    set cancelled [$q cancel_pending_for "netA"]
    ::tempo::test::assert_equal [llength $cancelled] 2 "Both netA events (50 and 80) should be cancelled"
    ::tempo::test::assert_true [$q is_empty]

    $q destroy
}

::tempo::test::suite "4-State Logic Simulation"

::tempo::test::test "Simulate combinational logic pipeline" {
    set nl [::tempo::netlist::Netlist new "comb_pipe"]
    $nl add_port "a" "INPUT"
    $nl add_port "b" "INPUT"
    $nl add_port "y" "OUTPUT"

    $nl add_instance "u_nand" "NAND2_X1"
    $nl connect_pin "u_nand" "A" "a" "LOAD"
    $nl connect_pin "u_nand" "B" "b" "LOAD"
    $nl connect_pin "u_nand" "Y" "w_nand" "DRIVER"

    $nl add_instance "u_inv" "INV_X1"
    $nl connect_pin "u_inv" "A" "w_nand" "LOAD"
    $nl connect_pin "u_inv" "Y" "y" "DRIVER"

    set sim [::tempo::sim::Simulator new $nl $lib 10]
    $sim reset

    # Apply stimulus: at t=0, a=0, b=1 -> nand=1, inv=0
    $sim schedule_input 0 "a" "0"
    $sim schedule_input 0 "b" "1"
    $sim run 50

    ::tempo::test::assert_equal [$sim get_net_value "w_nand"] "1"
    ::tempo::test::assert_equal [$sim get_net_value "y"] "0"

    # At t=100, a=1, b=1 -> nand=0 (at 110), inv=1 (at 120)
    $sim schedule_input 100 "a" "1"
    $sim run 150

    ::tempo::test::assert_equal [$sim get_net_value "w_nand"] "0"
    ::tempo::test::assert_equal [$sim get_net_value "y"] "1"

    $sim destroy
    $nl destroy
}

::tempo::test::test "Simulate sequential register capture on clock edge" {
    set nl [::tempo::netlist::Netlist new "seq_pipe"]
    $nl add_port "clk" "INPUT"
    $nl add_port "d" "INPUT"
    $nl add_port "q" "OUTPUT"

    $nl add_instance "u_reg" "DFF_X1"
    $nl connect_pin "u_reg" "CK" "clk" "LOAD"
    $nl connect_pin "u_reg" "D" "d" "LOAD"
    $nl connect_pin "u_reg" "Q" "q" "DRIVER"

    set sim [::tempo::sim::Simulator new $nl $lib 15]
    $sim reset

    # Schedule clock: 50 ps half-period (100 ps cycle). Rising edges at 50, 150, 250...
    $sim schedule_clock "clk" 100 500

    # D input changes to 1 at t=20 (before rising edge at 50)
    $sim schedule_input 20 "d" "1"

    # Run past first clock edge at 50ps + 15ps clk-to-q delay
    $sim run 70
    ::tempo::test::assert_equal [$sim get_net_value "q"] "1"

    # D input changes to 0 at t=120 (before second rising edge at 150)
    $sim schedule_input 120 "d" "0"
    $sim run 170
    ::tempo::test::assert_equal [$sim get_net_value "q"] "0"

    $sim destroy
    $nl destroy
}

::tempo::test::suite "IEEE 1364 VCD Waveform Generator"

::tempo::test::test "Dump simulation waveforms to VCD format" {
    set nl [::tempo::netlist::Netlist new "vcd_test"]
    $nl add_port "in" "INPUT"
    $nl add_port "out" "OUTPUT"

    $nl add_instance "u_inv" "INV_X1"
    $nl connect_pin "u_inv" "A" "in" "LOAD"
    $nl connect_pin "u_inv" "Y" "out" "DRIVER"

    set sim [::tempo::sim::Simulator new $nl $lib 10]
    $sim reset
    $sim schedule_input 0 "in" "0"
    $sim schedule_input 50 "in" "1"
    $sim schedule_input 100 "in" "0"
    $sim run 150

    set vcd_gen [::tempo::sim::vcd::VCDWriter new $sim $nl]
    set vcd_txt [$vcd_gen generate]

    ::tempo::test::assert_true [regexp {\$timescale 1ps \$end} $vcd_txt]
    ::tempo::test::assert_true [regexp {\$scope module top \$end} $vcd_txt]
    ::tempo::test::assert_true [regexp {\$dumpvars} $vcd_txt]
    ::tempo::test::assert_true [regexp {#50} $vcd_txt]

    $vcd_gen destroy
    $sim destroy
    $nl destroy
}

::tempo::test::suite "Hazard and Glitch Detection"

::tempo::test::test "Detect Static-1 hazard pulse" {
    set nl [::tempo::netlist::Netlist new "haz_test"]
    $nl add_port "g_net" "OUTPUT"

    set sim [::tempo::sim::Simulator new $nl $lib 10]
    $sim reset

    # Manually schedule a static-1 glitch: 1 -> 0 -> 1 within 15 ps
    $sim schedule_input 0 "g_net" "1"
    $sim schedule_input 50 "g_net" "0"
    $sim schedule_input 65 "g_net" "1"
    $sim run 100

    set detector [::tempo::sim::hazard::HazardDetector new $sim 20]
    set hazards [$detector detect_hazards]

    ::tempo::test::assert_equal [llength $hazards] 1
    ::tempo::test::assert_equal [dict get [lindex $hazards 0] type] "STATIC_1_HAZARD"

    set rep [$detector format_report $hazards]
    ::tempo::test::assert_true [regexp {STATIC_1_HAZARD} $rep]

    $detector destroy
    $sim destroy
    $nl destroy
}

$lib destroy

set code [::tempo::test::report]
exit $code
