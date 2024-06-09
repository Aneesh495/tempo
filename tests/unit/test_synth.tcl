# Unit Tests for Logic Synthesis, AIG, Cut Enumeration, and Technology Mapping

set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ".." ".."]]

source [file join $root_dir "tests" "framework.tcl"]
source [file join $root_dir "src" "core" "types.tcl"]
source [file join $root_dir "src" "core" "graph.tcl"]
source [file join $root_dir "src" "core" "netlist.tcl"]
source [file join $root_dir "src" "parsers" "liberty_lexer.tcl"]
source [file join $root_dir "src" "parsers" "liberty_parser.tcl"]
source [file join $root_dir "src" "parsers" "liberty_model.tcl"]
source [file join $root_dir "src" "synth" "boolean.tcl"]
source [file join $root_dir "src" "synth" "aig.tcl"]
source [file join $root_dir "src" "synth" "cut.tcl"]
source [file join $root_dir "src" "synth" "techmap.tcl"]
source [file join $root_dir "src" "synth" "optimize.tcl"]

::tempo::test::suite "Boolean Algebra and Shannon Decomposition"

::tempo::test::test "Truth table generation and signature matching" {
    set tt_and [::tempo::synth::bool::truth_table "A & B" [list "A" "B"]]
    ::tempo::test::assert_equal $tt_and "0001" "AND2 truth table must be 0001"
    ::tempo::test::assert_equal [::tempo::synth::bool::match_signature $tt_and] "AND2"

    set tt_nand [::tempo::synth::bool::truth_table "!(A & B)" [list "A" "B"]]
    ::tempo::test::assert_equal $tt_nand "1110" "NAND2 truth table must be 1110"
    ::tempo::test::assert_equal [::tempo::synth::bool::match_signature $tt_nand] "NAND2"

    set tt_xor [::tempo::synth::bool::truth_table "A ^ B" [list "A" "B"]]
    ::tempo::test::assert_equal $tt_xor "0110" "XOR2 truth table must be 0110"
    ::tempo::test::assert_equal [::tempo::synth::bool::match_signature $tt_xor] "XOR2"
}

::tempo::test::test "Boolean difference for observability" {
    # f = (A & B) | C. Sensitizing fault on A: df/dA = f(A=1) ^ f(A=0)
    # When B=1 and C=0: f(A=1)=1, f(A=0)=0 => df/dA = 1 (observable!)
    set b_sens [dict create "B" 1 "C" 0]
    set sens [::tempo::synth::bool::boolean_difference "(A & B) | C" "A" $b_sens]
    ::tempo::test::assert_equal $sens 1 "A is observable when B=1, C=0"

    # When C=1: f is always 1 regardless of A => df/dA = 0 (unobservable)
    set b_mask [dict create "B" 1 "C" 1]
    set masked [::tempo::synth::bool::boolean_difference "(A & B) | C" "A" $b_mask]
    ::tempo::test::assert_equal $masked 0 "A is masked when C=1"
}

::tempo::test::suite "And-Inverter Graph (AIG) Engine"

::tempo::test::test "AIG constant folding and structural hashing" {
    set aig [::tempo::synth::aig::Aig new]
    set a [$aig add_pi "a"]
    set b [$aig add_pi "b"]

    # Constant folding rules
    ::tempo::test::assert_equal [$aig add_and $a 0] 0 "a AND 0 = 0"
    ::tempo::test::assert_equal [$aig add_and $a 1] $a "a AND 1 = a"
    ::tempo::test::assert_equal [$aig add_and $a $a] $a "a AND a = a"
    ::tempo::test::assert_equal [$aig add_and $a [$aig add_not $a]] 0 "a AND (NOT a) = 0"

    # Structural hashing (hash consing)
    set and1 [$aig add_and $a $b]
    set and2 [$aig add_and $b $a] ;# Commutative order swap
    ::tempo::test::assert_equal $and1 $and2 "a AND b must hash to identical literal as b AND a"
    ::tempo::test::assert_equal [$aig num_and_nodes] 1 "Only 1 physical AND node should be created"

    # XOR implementation: (a & ~b) | (~a & b)
    set xor_lit [$aig add_xor $a $b]
    $aig add_po "y" $xor_lit

    # Simulate truth table
    set sim00 [$aig simulate [dict create "a" 0 "b" 0]]
    set sim01 [$aig simulate [dict create "a" 0 "b" 1]]
    set sim10 [$aig simulate [dict create "a" 1 "b" 0]]
    set sim11 [$aig simulate [dict create "a" 1 "b" 1]]

    ::tempo::test::assert_equal [dict get $sim00 "y"] 0 "0 ^ 0 = 0"
    ::tempo::test::assert_equal [dict get $sim01 "y"] 1 "0 ^ 1 = 1"
    ::tempo::test::assert_equal [dict get $sim10 "y"] 1 "1 ^ 0 = 1"
    ::tempo::test::assert_equal [dict get $sim11 "y"] 0 "1 ^ 1 = 0"

    $aig destroy
}

::tempo::test::suite "Priority Cut Enumeration and Technology Mapping"

::tempo::test::test "Cut enumeration and standard cell mapping" {
    # Build minimal library
    set lib [::tempo::liberty::Library new]
    # Add INV_X1
    $lib add_cell "INV_X1" [dict create name "INV_X1" area 1.0 is_sequential 0 pins [dict create \
        A [dict create direction "input" capacitance 0.002] \
        Y [dict create direction "output" capacitance 0.0 function "!A"]]]
    # Add AND2_X1
    $lib add_cell "AND2_X1" [dict create name "AND2_X1" area 2.0 is_sequential 0 pins [dict create \
        A [dict create direction "input" capacitance 0.003] \
        B [dict create direction "input" capacitance 0.003] \
        Y [dict create direction "output" capacitance 0.0 function "A & B"]]]
    # Add NAND2_X1
    $lib add_cell "NAND2_X1" [dict create name "NAND2_X1" area 1.5 is_sequential 0 pins [dict create \
        A [dict create direction "input" capacitance 0.003] \
        B [dict create direction "input" capacitance 0.003] \
        Y [dict create direction "output" capacitance 0.0 function "!(A & B)"]]]
    # Add BUF_X1
    $lib add_cell "BUF_X1" [dict create name "BUF_X1" area 1.2 is_sequential 0 pins [dict create \
        A [dict create direction "input" capacitance 0.002] \
        Y [dict create direction "output" capacitance 0.0 function "A"]]]

    # Build AIG for a & b
    set aig [::tempo::synth::aig::Aig new]
    set in0 [$aig add_pi "in0"]
    set in1 [$aig add_pi "in1"]
    set and_lit [$aig add_and $in0 $in1]
    $aig add_po "out0" $and_lit

    set mapper [::tempo::synth::techmap::Mapper new $lib]
    set mapped_nl [$mapper map_aig $aig "area"]

    ::tempo::test::assert_true [$mapped_nl has_port "in0"]
    ::tempo::test::assert_true [$mapped_nl has_port "in1"]
    ::tempo::test::assert_true [$mapped_nl has_port "out0"]

    set insts [$mapped_nl get_instances]
    ::tempo::test::assert_true [expr {[llength $insts] >= 1}] "Must instantiate standard cells"

    $aig destroy
    $mapper destroy
    $mapped_nl destroy
    $lib destroy
}

::tempo::test::suite "Netlist Peephole Optimization"

::tempo::test::test "Inverter pair cancellation and dead gate removal" {
    set nl [::tempo::netlist::Netlist new "opt_test"]
    $nl add_port "pi_a" "INPUT"
    $nl add_port "po_y" "OUTPUT"

    $nl add_net "wire_mid"
    $nl add_net "wire_dead"

    # Add back-to-back inverters: pi_a -> [u_inv1] -> wire_mid -> [u_inv2] -> po_y
    $nl add_instance "u_inv1" "INV_X1"
    $nl connect_pin "u_inv1" "A" "pi_a" "LOAD"
    $nl connect_pin "u_inv1" "Y" "wire_mid" "DRIVER"

    $nl add_instance "u_inv2" "INV_X1"
    $nl connect_pin "u_inv2" "A" "wire_mid" "LOAD"
    $nl connect_pin "u_inv2" "Y" "po_y" "DRIVER"

    # Add dead gate whose output is never connected to any load
    $nl add_instance "u_dead_gate" "AND2_X1"
    $nl connect_pin "u_dead_gate" "A" "pi_a" "LOAD"
    $nl connect_pin "u_dead_gate" "B" "pi_a" "LOAD"
    $nl connect_pin "u_dead_gate" "Y" "wire_dead" "DRIVER"

    ::tempo::test::assert_equal [llength [$nl get_instances]] 3

    set opt_report [::tempo::synth::opt::optimize_netlist $nl]

    # Dead gate should be eliminated!
    ::tempo::test::assert_true [expr {![$nl has_instance "u_dead_gate"]}] "Dead gate must be removed"

    # Inverter pair should be cancelled!
    ::tempo::test::assert_true [expr {![$nl has_instance "u_inv1"]}] "u_inv1 must be cancelled"
    ::tempo::test::assert_true [expr {![$nl has_instance "u_inv2"]}] "u_inv2 must be cancelled"

    $nl destroy
}

set code [::tempo::test::report]
exit $code
