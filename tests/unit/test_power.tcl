# Unit Tests for Power and Physical Area Subsystem

set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ".." ".."]]

source [file join $root_dir "tests" "framework.tcl"]
source [file join $root_dir "src" "core" "types.tcl"]
source [file join $root_dir "src" "core" "graph.tcl"]
source [file join $root_dir "src" "core" "netlist.tcl"]
source [file join $root_dir "src" "parsers" "liberty_model.tcl"]
source [file join $root_dir "src" "power" "leakage.tcl"]
source [file join $root_dir "src" "power" "dynamic.tcl"]
source [file join $root_dir "src" "power" "area.tcl"]

set lib [::tempo::liberty::Library new]
$lib add_cell "INV_X1" [dict create name "INV_X1" area 1.0 is_sequential 0 cell_leakage_power 0.04 pins [dict create \
    A [dict create direction "input" capacitance 0.002] \
    Y [dict create direction "output" capacitance 0.0 function "!A"]]]
$lib add_cell "NAND2_X1" [dict create name "NAND2_X1" area 1.5 is_sequential 0 cell_leakage_power 0.07 pins [dict create \
    A [dict create direction "input" capacitance 0.003] \
    B [dict create direction "input" capacitance 0.003] \
    Y [dict create direction "output" capacitance 0.0 function "!(A & B)"]]]
$lib add_cell "DFF_X1" [dict create name "DFF_X1" area 6.0 is_sequential 1 cell_leakage_power 0.25 pins [dict create \
    CK [dict create direction "input" capacitance 0.004 is_clock 1] \
    D  [dict create direction "input" capacitance 0.003 is_clock 0] \
    Q  [dict create direction "output" capacitance 0.0 function "IQ"]]]

set nl [::tempo::netlist::Netlist new "power_test_circuit"]
$nl add_port "in" "INPUT"
$nl add_port "clk" "INPUT"
$nl add_port "out" "OUTPUT"

$nl add_instance "u_nand" "NAND2_X1"
$nl connect_pin "u_nand" "A" "in" "LOAD"
$nl connect_pin "u_nand" "B" "in" "LOAD"
$nl connect_pin "u_nand" "Y" "w_mid" "DRIVER"

$nl add_instance "u_inv" "INV_X1"
$nl connect_pin "u_inv" "A" "w_mid" "LOAD"
$nl connect_pin "u_inv" "Y" "w_din" "DRIVER"

$nl add_instance "u_ff" "DFF_X1"
$nl connect_pin "u_ff" "D" "w_din" "LOAD"
$nl connect_pin "u_ff" "CK" "clk" "LOAD"
$nl connect_pin "u_ff" "Q" "out" "DRIVER"

::tempo::test::suite "Static Leakage Power Analysis"

::tempo::test::test "Total leakage and cell breakdown" {
    set leak_an [::tempo::power::leakage::LeakageAnalyzer new $nl $lib]
    set leak_res [$leak_an calculate_total_leakage]

    # Expected: NAND2 (0.07) + INV (0.04) + DFF (0.25) = 0.36 uW
    set total_leak [dict get $leak_res total_leakage_uW]
    ::tempo::test::assert_almost_equal $total_leak 0.36 0.001

    set breakdown [dict get $leak_res by_cell]
    ::tempo::test::assert_almost_equal [dict get $breakdown "INV_X1"] 0.04 0.001
    ::tempo::test::assert_almost_equal [dict get $breakdown "NAND2_X1"] 0.07 0.001
    ::tempo::test::assert_almost_equal [dict get $breakdown "DFF_X1"] 0.25 0.001

    $leak_an destroy
}

::tempo::test::suite "Dynamic Switching and Internal Power Analysis"

::tempo::test::test "Switching and internal power dissipation" {
    set dyn_an [::tempo::power::dynamic::DynamicPowerAnalyzer new $nl $lib 1.2 1.0e9 0.2]
    set dyn_res [$dyn_an calculate_total_dynamic_power]

    set p_switch [dict get $dyn_res switching_power_uW]
    set p_int    [dict get $dyn_res internal_power_uW]
    set p_dyn    [dict get $dyn_res total_dynamic_uW]

    ::tempo::test::assert_true [expr {$p_switch > 0.0}] "Switching power should be positive"
    ::tempo::test::assert_true [expr {$p_int > 0.0}] "Internal power should be positive"
    ::tempo::test::assert_almost_equal $p_dyn [expr {$p_switch + $p_int}] 0.0001

    $dyn_an destroy
}

::tempo::test::suite "Physical Area and Comprehensive Reporting"

::tempo::test::test "Silicon area, gate count, and report formatting" {
    set area_an [::tempo::power::area::AreaAnalyzer new $nl $lib 1.5]
    set area_res [$area_an calculate_area]

    # Total area: INV (1.0) + NAND2 (1.5) + DFF (6.0) = 8.5 um^2
    ::tempo::test::assert_almost_equal [dict get $area_res total_area_um2] 8.5 0.001
    ::tempo::test::assert_almost_equal [dict get $area_res combinational_area_um2] 2.5 0.001
    ::tempo::test::assert_almost_equal [dict get $area_res sequential_area_um2] 6.0 0.001
    ::tempo::test::assert_almost_equal [dict get $area_res nand2_gate_equivalents] [expr {8.5 / 1.5}] 0.01

    set leak_an [::tempo::power::leakage::LeakageAnalyzer new $nl $lib]
    set leak_res [$leak_an calculate_total_leakage]

    set dyn_an [::tempo::power::dynamic::DynamicPowerAnalyzer new $nl $lib 1.2 1.0e9 0.2]
    set dyn_res [$dyn_an calculate_total_dynamic_power]

    set rep [$area_an format_power_area_report $leak_res $dyn_res $area_res]
    ::tempo::test::assert_true [regexp {TEMPO POWER AND PHYSICAL AREA REPORT} $rep]
    ::tempo::test::assert_true [regexp {TOTAL CHIP POWER} $rep]

    $leak_an destroy
    $dyn_an destroy
    $area_an destroy
}

$nl destroy
$lib destroy

set code [::tempo::test::report]
exit $code
