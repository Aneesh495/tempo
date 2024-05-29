# Unit Tests for Standard Parasitic Exchange Format (SPEF) Parser

set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ".." ".."]]

source [file join $root_dir "tests" "framework.tcl"]
source [file join $root_dir "src" "core" "types.tcl"]
source [file join $root_dir "src" "parsers" "spef_parser.tcl"]

::tempo::test::suite "SPEF Parasitics Parser and RC Network"

set sample_spef {
*SPEF "IEEE 1481-1999"
*DESIGN "demo_alu"
*DATE "18-OCT-2026"
*T_UNIT 1.0 PS
*C_UNIT 1.0 FF
*R_UNIT 1.0 OHM

*D_NET net_crit0 15.8
*CONN
*P u_stage0:Y O
*P u_stage1:A I
*CAP
1 net_crit0:1 6.2
2 net_crit0:2 9.6
*RES
1 u_stage0:Y net_crit0:1 22.5
2 net_crit0:1 net_crit0:2 45.0
3 net_crit0:2 u_stage1:A 18.0
*END

*D_NET net_clk 45.2
*CONN
*P clk I
*P u_dff0:CK I
*P u_dff1:CK I
*END
}

::tempo::test::test "Parse SPEF parasitics" {
    set spef_net [::tempo::spef::parse $sample_spef]

    ::tempo::test::assert_equal [$spef_net get_design_name] "demo_alu"
    ::tempo::test::assert_true [$spef_net has_net "net_crit0"]
    ::tempo::test::assert_true [$spef_net has_net "net_clk"]

    # Check lumped capacitance
    ::tempo::test::assert_almost_equal [$spef_net get_net_cap "net_crit0"] 15.8
    ::tempo::test::assert_almost_equal [$spef_net get_net_cap "net_clk"] 45.2

    # Check distributed node caps
    set node_caps [$spef_net get_net_node_caps "net_crit0"]
    ::tempo::test::assert_almost_equal [dict get $node_caps "net_crit0:1"] 6.2
    ::tempo::test::assert_almost_equal [dict get $node_caps "net_crit0:2"] 9.6

    # Check resistance segments
    set res_segs [$spef_net get_net_res_segments "net_crit0"]
    ::tempo::test::assert_equal [llength $res_segs] 3

    set seg0 [lindex $res_segs 0]
    ::tempo::test::assert_equal [dict get $seg0 node1] "u_stage0:Y"
    ::tempo::test::assert_equal [dict get $seg0 node2] "net_crit0:1"
    ::tempo::test::assert_almost_equal [dict get $seg0 res] 22.5

    $spef_net destroy
}

set code [::tempo::test::report]
exit $code
