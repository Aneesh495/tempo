# Unit Tests for Verilog Lexer, Parser, and Serializer

set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ".." ".."]]

source [file join $root_dir "tests" "framework.tcl"]
source [file join $root_dir "src" "core" "types.tcl"]
source [file join $root_dir "src" "core" "bitvector.tcl"]
source [file join $root_dir "src" "core" "graph.tcl"]
source [file join $root_dir "src" "core" "netlist.tcl"]
source [file join $root_dir "src" "parsers" "verilog_lexer.tcl"]
source [file join $root_dir "src" "parsers" "verilog_parser.tcl"]
source [file join $root_dir "src" "parsers" "verilog_writer.tcl"]

::tempo::test::suite "Structural Verilog Lexer and Parser"

set sample_v {
// 4-bit ALU Slice Demo Netlist
module alu_slice (
    input [3:0] op_a,
    input [3:0] op_b,
    input clk,
    output [3:0] res_y,
    output carry_out
);

    wire w_and0, w_xor0, w_or0;
    wire [3:0] mid_bus;

    NAND2_X1 u_nand0 (.A(op_a[0]), .B(op_b[0]), .Y(w_and0));
    INV_X1   u_inv0  (.A(w_and0), .Y(res_y[0]));
    XOR2_X1  u_xor0  (.A(op_a[1]), .B(op_b[1]), .Y(w_xor0));
    DFF_X1   u_reg0  (.D(w_xor0), .CK(clk), .Q(res_y[1]));

    and g_and_prim (carry_out, op_a[3], op_b[3]);

endmodule
}

::tempo::test::test "Tokenize and parse Verilog netlist" {
    set tokens [::tempo::verilog::lexer::tokenize $sample_v]
    ::tempo::test::assert_true [expr {[llength $tokens] > 40}] "Should produce tokens"

    set nl [::tempo::verilog::parser::parse $tokens]
    ::tempo::test::assert_equal [$nl get_name] "alu_slice"

    # Ports check
    ::tempo::test::assert_true [$nl has_port "op_a"]
    ::tempo::test::assert_true [$nl has_port "op_b"]
    ::tempo::test::assert_true [$nl has_port "clk"]
    ::tempo::test::assert_true [$nl has_port "res_y"]
    ::tempo::test::assert_true [$nl has_port "carry_out"]

    set p_info [$nl get_port_info "op_a"]
    ::tempo::test::assert_equal [dict get $p_info width] 4
    ::tempo::test::assert_equal [dict get $p_info dir] "INPUT"

    # Check instances
    ::tempo::test::assert_true [$nl has_instance "u_nand0"]
    ::tempo::test::assert_true [$nl has_instance "u_inv0"]
    ::tempo::test::assert_true [$nl has_instance "u_xor0"]
    ::tempo::test::assert_true [$nl has_instance "u_reg0"]
    ::tempo::test::assert_true [$nl has_instance "g_and_prim"]

    ::tempo::test::assert_equal [$nl get_instance_cell "u_nand0"] "NAND2_X1"
    ::tempo::test::assert_equal [$nl get_instance_cell "g_and_prim"] "AND"

    # Check net connectivity
    # w_and0 is driven by u_nand0/Y and loaded by u_inv0/A
    set drivers [$nl get_net_drivers "w_and0"]
    set loads [$nl get_net_loads "w_and0"]
    ::tempo::test::assert_equal $drivers [list "u_nand0/Y"]
    ::tempo::test::assert_equal $loads [list "u_inv0/A"]

    # Serialization round-trip test
    set serialized [::tempo::verilog::writer::serialize $nl]
    ::tempo::test::assert_true [regexp {module alu_slice} $serialized] "Serialized text should have module alu_slice"

    set roundtrip_tokens [::tempo::verilog::lexer::tokenize $serialized]
    set roundtrip_nl [::tempo::verilog::parser::parse $roundtrip_tokens]
    ::tempo::test::assert_equal [$roundtrip_nl get_name] "alu_slice"
    ::tempo::test::assert_equal [llength [$roundtrip_nl get_instances]] [llength [$nl get_instances]]

    $nl destroy
    $roundtrip_nl destroy
}

::tempo::test::test "Parse continuous assignment and bus vector expansion" {
    set snippet_v {
        module bus_assign_test (
            input [7:0] a_bus,
            output [7:0] b_bus,
            output flag
        );
            wire intermediate;
            assign intermediate = a_bus[0];
            assign flag = intermediate;
        endmodule
    }
    set toks [::tempo::verilog::lexer::tokenize $snippet_v]
    set nl [::tempo::verilog::parser::parse $toks]

    ::tempo::test::assert_equal [$nl get_name] "bus_assign_test"
    ::tempo::test::assert_true [$nl has_port "a_bus"]
    ::tempo::test::assert_true [$nl has_port "b_bus"]
    ::tempo::test::assert_true [$nl has_port "flag"]

    # Check vector nets were expanded
    ::tempo::test::assert_true [$nl has_net "a_bus\[0\]"]
    ::tempo::test::assert_true [$nl has_net "a_bus\[7\]"]

    # Check assign buffer instances were synthesized
    set insts [$nl get_instances]
    ::tempo::test::assert_true [expr {[llength $insts] >= 2}] "Should synthesize assign buffer instances"

    $nl destroy
}

set code [::tempo::test::report]
exit $code
