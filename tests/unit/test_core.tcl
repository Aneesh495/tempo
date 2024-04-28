# Unit Tests for Tempo Core Modules: Types, Units, Logic, Bitvectors, Graph, Netlist

set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ".." ".."]]

source [file join $root_dir "tests" "framework.tcl"]
source [file join $root_dir "src" "core" "types.tcl"]
source [file join $root_dir "src" "core" "bitvector.tcl"]
source [file join $root_dir "src" "core" "graph.tcl"]
source [file join $root_dir "src" "core" "netlist.tcl"]

::tempo::test::suite "Core Units and Dimensional Types"

::tempo::test::test "Time unit conversions" {
    set ps_val [::tempo::units::to_ps 2.5 "ns"]
    ::tempo::test::assert_almost_equal $ps_val 2500.0 1e-6 "2.5 ns should be 2500 ps"

    set ns_val [::tempo::units::from_ps 1500.0 "ns"]
    ::tempo::test::assert_almost_equal $ns_val 1.5 1e-6 "1500 ps should be 1.5 ns"

    set fs_ps [::tempo::units::to_ps 500.0 "fs"]
    ::tempo::test::assert_almost_equal $fs_ps 0.5 1e-6 "500 fs should be 0.5 ps"
}

::tempo::test::test "Capacitance unit conversions" {
    set ff_val [::tempo::units::to_ff 0.05 "pf"]
    ::tempo::test::assert_almost_equal $ff_val 50.0 1e-6 "0.05 pF should be 50 fF"

    set pf_val [::tempo::units::from_ff 120.0 "pf"]
    ::tempo::test::assert_almost_equal $pf_val 0.12 1e-6 "120 fF should be 0.12 pF"
}

::tempo::test::test "Quantity string parsing" {
    set q [::tempo::units::parse_quantity "150.5ps"]
    ::tempo::test::assert_almost_equal [lindex $q 0] 150.5
    ::tempo::test::assert_equal [lindex $q 1] "ps"

    set q2 [::tempo::units::parse_quantity "0.02pF"]
    ::tempo::test::assert_almost_equal [lindex $q2 0] 0.02
    ::tempo::test::assert_equal [lindex $q2 1] "pF"
}

::tempo::test::test "Bilinear 2D interpolation" {
    # f(0,0)=0, f(0,10)=100, f(10,0)=200, f(10,10)=300
    # At (5, 5), expected is (0 + 100 + 200 + 300) / 4 = 150.0
    set val [::tempo::types::bilinear_interp 5.0 5.0 0.0 10.0 0.0 10.0 0.0 100.0 200.0 300.0]
    ::tempo::test::assert_almost_equal $val 150.0 1e-6 "Midpoint interpolation should be 150.0"

    # Corner test
    set val_corner [::tempo::types::bilinear_interp 10.0 0.0 0.0 10.0 0.0 10.0 0.0 100.0 200.0 300.0]
    ::tempo::test::assert_almost_equal $val_corner 200.0 1e-6 "Corner (10,0) should be 200.0"
}

::tempo::test::suite "4-State and 5-State Logic Engine"

::tempo::test::test "IEEE 1364 4-State Truth Tables" {
    # AND with unknown
    ::tempo::test::assert_equal [::tempo::logic::gate_and "0" "X"] "0" "0 AND X must be 0"
    ::tempo::test::assert_equal [::tempo::logic::gate_and "1" "X"] "x" "1 AND X must be X"
    ::tempo::test::assert_equal [::tempo::logic::gate_and "1" "1"] "1" "1 AND 1 must be 1"

    # OR with unknown
    ::tempo::test::assert_equal [::tempo::logic::gate_or "1" "X"] "1" "1 OR X must be 1"
    ::tempo::test::assert_equal [::tempo::logic::gate_or "0" "X"] "x" "0 OR X must be X"

    # XOR
    ::tempo::test::assert_equal [::tempo::logic::gate_xor "0" "1"] "1" "0 XOR 1 must be 1"
    ::tempo::test::assert_equal [::tempo::logic::gate_xor "1" "1"] "0" "1 XOR 1 must be 0"
    ::tempo::test::assert_equal [::tempo::logic::gate_xor "1" "X"] "x" "1 XOR X must be X"

    # NOT and BUF
    ::tempo::test::assert_equal [::tempo::logic::gate_not "0"] "1"
    ::tempo::test::assert_equal [::tempo::logic::gate_not "1"] "0"
    ::tempo::test::assert_equal [::tempo::logic::gate_not "X"] "x"
    ::tempo::test::assert_equal [::tempo::logic::gate_not "Z"] "x"

    # MUX2
    ::tempo::test::assert_equal [::tempo::logic::gate_mux2 "0" "1" "0"] "1" "sel=0 picks d0"
    ::tempo::test::assert_equal [::tempo::logic::gate_mux2 "1" "1" "0"] "0" "sel=1 picks d1"
    ::tempo::test::assert_equal [::tempo::logic::gate_mux2 "X" "1" "1"] "1" "sel=X with identical data returns 1"
    ::tempo::test::assert_equal [::tempo::logic::gate_mux2 "X" "1" "0"] "x" "sel=X with differing data returns X"
}

::tempo::test::test "Roth 5-State D-Calculus for ATPG" {
    ::tempo::test::assert_equal [::tempo::logic::d_not "d"] "d_bar" "NOT(D) is D_BAR"
    ::tempo::test::assert_equal [::tempo::logic::d_not "d_bar"] "d" "NOT(D_BAR) is D"
    ::tempo::test::assert_equal [::tempo::logic::d_and "d" "1"] "d" "D AND 1 is D"
    ::tempo::test::assert_equal [::tempo::logic::d_and "d" "0"] "0" "D AND 0 is 0"
    ::tempo::test::assert_equal [::tempo::logic::d_and "d" "d_bar"] "0" "D AND D_BAR is 0"
    ::tempo::test::assert_equal [::tempo::logic::d_or "d" "d_bar"] "1" "D OR D_BAR is 1"
    ::tempo::test::assert_equal [::tempo::logic::d_xor "d" "1"] "d_bar" "D XOR 1 is D_BAR"
}

::tempo::test::suite "Arbitrary-Width Bitvectors"

::tempo::test::test "Bitvector creation and slicing" {
    set bv [::tempo::bv::create 8 "1"]
    ::tempo::test::assert_equal $bv "11111111"

    set bv_slice [::tempo::bv::slice $bv 0 3]
    ::tempo::test::assert_equal $bv_slice "1111"

    set bv_mod [::tempo::bv::set_bit $bv 0 "0"]
    ::tempo::test::assert_equal $bv_mod "01111111"
}

::tempo::test::test "Literal parsing" {
    set b1 [::tempo::bv::parse_literal "4'b1010"]
    ::tempo::test::assert_equal $b1 "1010"

    set b2 [::tempo::bv::parse_literal "8'hA5"]
    ::tempo::test::assert_equal $b2 "10100101"

    set b3 [::tempo::bv::parse_literal "8'd255"]
    ::tempo::test::assert_equal $b3 "11111111"

    set uint_val [::tempo::bv::to_uint "10100101"]
    ::tempo::test::assert_equal $uint_val 165

    set hex_str [::tempo::bv::to_hex "10100101"]
    ::tempo::test::assert_equal $hex_str "a5"
}

::tempo::test::test "Bitvector operations" {
    set b1 "1100"
    set b2 "1010"
    ::tempo::test::assert_equal [::tempo::bv::bv_and $b1 $b2] "1000"
    ::tempo::test::assert_equal [::tempo::bv::bv_or  $b1 $b2] "1110"
    ::tempo::test::assert_equal [::tempo::bv::bv_xor $b1 $b2] "0110"
    ::tempo::test::assert_equal [::tempo::bv::bv_not $b1]     "0011"
}

::tempo::test::suite "Graph and DAG Algorithms"

::tempo::test::test "Topological sort on DAG" {
    set g [::tempo::graph::Graph new]
    $g add_node "A"
    $g add_node "B"
    $g add_node "C"
    $g add_node "D"

    $g add_edge "A" "B"
    $g add_edge "A" "C"
    $g add_edge "B" "D"
    $g add_edge "C" "D"

    set topo [$g topological_sort]
    # A must appear before B and C, and D must be last
    set idx_a [lsearch -exact $topo "A"]
    set idx_b [lsearch -exact $topo "B"]
    set idx_c [lsearch -exact $topo "C"]
    set idx_d [lsearch -exact $topo "D"]

    ::tempo::test::assert_true [expr {$idx_a < $idx_b && $idx_a < $idx_c}]
    ::tempo::test::assert_true [expr {$idx_b < $idx_d && $idx_c < $idx_d}]
    $g destroy
}

::tempo::test::test "Cycle detection and Tarjan SCC" {
    set g [::tempo::graph::Graph new]
    $g add_node "X"
    $g add_node "Y"
    $g add_node "Z"

    $g add_edge "X" "Y"
    $g add_edge "Y" "Z"
    $g add_edge "Z" "X"

    # Topological sort must throw error on cyclic graph
    ::tempo::test::assert_error {
        $g topological_sort
    } "Graph contains directed cycles"

    set sccs [$g tarjan_scc]
    ::tempo::test::assert_equal [llength $sccs] 1 "Entire 3-node cycle forms 1 SCC"
    $g destroy
}

::tempo::test::test "Longest path computation on DAG" {
    set g [::tempo::graph::Graph new]
    $g add_node "N0"
    $g add_node "N1"
    $g add_node "N2"
    $g add_node "N3"

    $g add_edge "N0" "N1" "TIMING" [dict create weight 10.0]
    $g add_edge "N1" "N3" "TIMING" [dict create weight 20.0]
    $g add_edge "N0" "N2" "TIMING" [dict create weight 15.0]
    $g add_edge "N2" "N3" "TIMING" [dict create weight 50.0]

    set lp [$g longest_path "weight"]
    # Path N0 -> N2 -> N3 has length 15 + 50 = 65.0
    ::tempo::test::assert_almost_equal [dict get $lp length] 65.0 1e-6
    ::tempo::test::assert_equal [dict get $lp path] [list "N0" "N2" "N3"]
    $g destroy
}

::tempo::test::suite "Netlist Representation"

::tempo::test::test "Netlist building, connectivity, and sanity" {
    set nl [::tempo::netlist::Netlist new "simple_alu"]
    $nl add_port "a" "INPUT"
    $nl add_port "b" "INPUT"
    $nl add_port "y" "OUTPUT"

    $nl add_net "wire_mid"

    $nl add_instance "u_and" "AND2_X1"
    $nl connect_pin "u_and" "A" "a" "LOAD"
    $nl connect_pin "u_and" "B" "b" "LOAD"
    $nl connect_pin "u_and" "Y" "wire_mid" "DRIVER"

    $nl add_instance "u_inv" "INV_X1"
    $nl connect_pin "u_inv" "A" "wire_mid" "LOAD"
    $nl connect_pin "u_inv" "Y" "y" "DRIVER"

    set stats [$nl get_stats]
    ::tempo::test::assert_equal [dict get $stats num_inputs] 2
    ::tempo::test::assert_equal [dict get $stats num_outputs] 1
    ::tempo::test::assert_equal [dict get $stats num_instances] 2

    set issues [$nl check_sanity]
    ::tempo::test::assert_equal [llength $issues] 0 "Clean netlist should have 0 sanity issues"

    # Clone verification
    set clone_nl [$nl clone "cloned_alu"]
    ::tempo::test::assert_equal [$clone_nl get_name] "cloned_alu"
    ::tempo::test::assert_equal [llength [$clone_nl get_instances]] 2

    $nl destroy
    $clone_nl destroy
}

# Run report
set code [::tempo::test::report]
exit $code
