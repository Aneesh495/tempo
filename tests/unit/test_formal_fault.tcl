# Unit Tests for Formal Equivalence Checking (CEC) and Fault Testing (ATPG)

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
source [file join $root_dir "src" "formal" "cec.tcl"]
source [file join $root_dir "src" "fault" "fault_model.tcl"]
source [file join $root_dir "src" "fault" "podem.tcl"]
source [file join $root_dir "src" "fault" "fault_sim.tcl"]

set lib [::tempo::liberty::Library new]
$lib add_cell "INV_X1" [dict create name "INV_X1" area 1.0 is_sequential 0 pins [dict create \
    A [dict create direction "input" capacitance 0.002] \
    Y [dict create direction "output" capacitance 0.0 function "!A"]]]
$lib add_cell "NAND2_X1" [dict create name "NAND2_X1" area 1.5 is_sequential 0 pins [dict create \
    A [dict create direction "input" capacitance 0.003] \
    B [dict create direction "input" capacitance 0.003] \
    Y [dict create direction "output" capacitance 0.0 function "!(A & B)"]]]
$lib add_cell "AND2_X1" [dict create name "AND2_X1" area 1.8 is_sequential 0 pins [dict create \
    A [dict create direction "input" capacitance 0.003] \
    B [dict create direction "input" capacitance 0.003] \
    Y [dict create direction "output" capacitance 0.0 function "A & B"]]]

::tempo::test::suite "Combinational Equivalence Checking (CEC)"

::tempo::test::test "Formally verify equivalent netlists: NAND-INV vs AND" {
    # Golden circuit: NAND2 -> INV (computes A & B)
    set nl_g [::tempo::netlist::Netlist new "golden_and"]
    $nl_g add_port "a" "INPUT"
    $nl_g add_port "b" "INPUT"
    $nl_g add_port "y" "OUTPUT"
    $nl_g add_instance "u_nand" "NAND2_X1"
    $nl_g connect_pin "u_nand" "A" "a" "LOAD"
    $nl_g connect_pin "u_nand" "B" "b" "LOAD"
    $nl_g connect_pin "u_nand" "Y" "w_mid" "DRIVER"
    $nl_g add_instance "u_inv" "INV_X1"
    $nl_g connect_pin "u_inv" "A" "w_mid" "LOAD"
    $nl_g connect_pin "u_inv" "Y" "y" "DRIVER"

    # Revised circuit: single AND2 gate (computes A & B)
    set nl_r [::tempo::netlist::Netlist new "revised_and"]
    $nl_r add_port "a" "INPUT"
    $nl_r add_port "b" "INPUT"
    $nl_r add_port "y" "OUTPUT"
    $nl_r add_instance "u_and" "AND2_X1"
    $nl_r connect_pin "u_and" "A" "a" "LOAD"
    $nl_r connect_pin "u_and" "B" "b" "LOAD"
    $nl_r connect_pin "u_and" "Y" "y" "DRIVER"

    set cec [::tempo::formal::cec::EquivalenceChecker new $nl_g $nl_r $lib]
    set res [$cec verify]

    ::tempo::test::assert_equal [dict get $res result] "EQUIVALENT"
    ::tempo::test::assert_equal [dict get $res verified_patterns] 4

    $cec destroy
    $nl_g destroy
    $nl_r destroy
}

::tempo::test::test "Detect non-equivalence and extract counter-example" {
    # Golden: computes A & B
    set nl_g [::tempo::netlist::Netlist new "golden_and"]
    $nl_g add_port "a" "INPUT"
    $nl_g add_port "b" "INPUT"
    $nl_g add_port "y" "OUTPUT"
    $nl_g add_instance "u_and" "AND2_X1"
    $nl_g connect_pin "u_and" "A" "a" "LOAD"
    $nl_g connect_pin "u_and" "B" "b" "LOAD"
    $nl_g connect_pin "u_and" "Y" "y" "DRIVER"

    # Mutated revised: computes !(A & B)
    set nl_r [::tempo::netlist::Netlist new "buggy_nand"]
    $nl_r add_port "a" "INPUT"
    $nl_r add_port "b" "INPUT"
    $nl_r add_port "y" "OUTPUT"
    $nl_r add_instance "u_nand" "NAND2_X1"
    $nl_r connect_pin "u_nand" "A" "a" "LOAD"
    $nl_r connect_pin "u_nand" "B" "b" "LOAD"
    $nl_r connect_pin "u_nand" "Y" "y" "DRIVER"

    set cec [::tempo::formal::cec::EquivalenceChecker new $nl_g $nl_r $lib]
    set res [$cec verify]

    ::tempo::test::assert_equal [dict get $res result] "NON_EQUIVALENT"
    ::tempo::test::assert_true [dict exists $res counter_example]

    $cec destroy
    $nl_g destroy
    $nl_r destroy
}

::tempo::test::suite "Stuck-At Fault Model and Fault Collapsing"

::tempo::test::test "Fault collapsing reduction ratio" {
    set nl [::tempo::netlist::Netlist new "inv_chain"]
    $nl add_port "in" "INPUT"
    $nl add_port "out" "OUTPUT"

    $nl add_instance "u_inv1" "INV_X1"
    $nl connect_pin "u_inv1" "A" "in" "LOAD"
    $nl connect_pin "u_inv1" "Y" "w_mid" "DRIVER"

    $nl add_instance "u_inv2" "INV_X1"
    $nl connect_pin "u_inv2" "A" "w_mid" "LOAD"
    $nl connect_pin "u_inv2" "Y" "out" "DRIVER"

    set fm [::tempo::fault::model::FaultManager new $nl $lib]
    set uncollapsed [$fm get_uncollapsed_faults]
    set collapsed [$fm get_collapsed_faults]

    ::tempo::test::assert_true [expr {[llength $collapsed] < [llength $uncollapsed]}] "Collapsed list should be smaller than uncollapsed"
    ::tempo::test::assert_true [expr {[$fm get_collapse_ratio] < 1.0}] "Collapse ratio should be less than 1.0"

    $fm destroy
    $nl destroy
}

::tempo::test::suite "PODEM ATPG Engine"

::tempo::test::test "Deterministic test vector generation for stuck-at faults" {
    set nl [::tempo::netlist::Netlist new "podem_test"]
    $nl add_port "a" "INPUT"
    $nl add_port "b" "INPUT"
    $nl add_port "y" "OUTPUT"

    $nl add_instance "u_and" "AND2_X1"
    $nl connect_pin "u_and" "A" "a" "LOAD"
    $nl connect_pin "u_and" "B" "b" "LOAD"
    $nl connect_pin "u_and" "Y" "y" "DRIVER"

    set podem [::tempo::fault::podem::PodemATPG new $nl $lib]

    # Target y SA0: needs a=1, b=1 -> y=1, good=1 faulty=0 -> y=D
    set res [$podem generate_test [dict create net "y" type "SA0"]]
    ::tempo::test::assert_equal [dict get $res status] "SUCCESS"

    set vec [dict get $res vector]
    ::tempo::test::assert_equal [dict get $vec "a"] "1"
    ::tempo::test::assert_equal [dict get $vec "b"] "1"

    $podem destroy
    $nl destroy
}

::tempo::test::suite "Parallel Fault Simulation and Test Coverage"

::tempo::test::test "Calculate test coverage with fault dropping" {
    set nl [::tempo::netlist::Netlist new "fsim_test"]
    $nl add_port "a" "INPUT"
    $nl add_port "b" "INPUT"
    $nl add_port "y" "OUTPUT"

    $nl add_instance "u_and" "AND2_X1"
    $nl connect_pin "u_and" "A" "a" "LOAD"
    $nl connect_pin "u_and" "B" "b" "LOAD"
    $nl connect_pin "u_and" "Y" "y" "DRIVER"

    set fm [::tempo::fault::model::FaultManager new $nl $lib]
    set faults [$fm get_uncollapsed_faults]

    # Exhaustive test set for 2-input AND
    set vectors [list \
        [dict create a "0" b "0"] \
        [dict create a "0" b "1"] \
        [dict create a "1" b "0"] \
        [dict create a "1" b "1"]]

    set fsim [::tempo::fault::sim::FaultSimulator new $nl $lib]
    set cov_summary [$fsim run_fault_simulation $vectors $faults]

    ::tempo::test::assert_almost_equal [dict get $cov_summary coverage_percent] 100.0 0.01

    set rep [$fsim format_coverage_report $cov_summary]
    ::tempo::test::assert_true [regexp {TEMPO MANUFACTURING ATPG} $rep]
    ::tempo::test::assert_true [regexp {100.00 %} $rep]

    $fsim destroy
    $fm destroy
    $nl destroy
}

$lib destroy

set code [::tempo::test::report]
exit $code
