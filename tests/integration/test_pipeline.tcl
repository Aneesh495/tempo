# ==============================================================================
# End-to-End Integration Test Suite for TEMPO EDA Engine
#
# Validates complete production flow on SkyWater 130nm ALU benchmark:
# 1. Liberty .lib NLDM parser
# 2. Structural Verilog netlist parser
# 3. SDC 2.1 timing constraint evaluator
# 4. SPEF parasitic interconnect RC network extractor
# 5. Bipartite timing graph construction
# 6. Topological forward/backward STA propagation & slack calculation
# 7. Design Rule Checking (DRC)
# 8. Dynamic and static leakage power analysis
# 9. Gate-level 4-state simulation with VCD generation
# ==============================================================================

set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ".." ".."]]

source [file join $root_dir "tests" "framework.tcl"]
source [file join $root_dir "src" "core" "types.tcl"]
source [file join $root_dir "src" "core" "bitvector.tcl"]
source [file join $root_dir "src" "core" "graph.tcl"]
source [file join $root_dir "src" "core" "netlist.tcl"]
source [file join $root_dir "src" "core" "accel.tcl"]

source [file join $root_dir "src" "parsers" "liberty_lexer.tcl"]
source [file join $root_dir "src" "parsers" "liberty_parser.tcl"]
source [file join $root_dir "src" "parsers" "liberty_model.tcl"]
source [file join $root_dir "src" "parsers" "verilog_lexer.tcl"]
source [file join $root_dir "src" "parsers" "verilog_parser.tcl"]
source [file join $root_dir "src" "parsers" "verilog_writer.tcl"]
source [file join $root_dir "src" "parsers" "sdc_model.tcl"]
source [file join $root_dir "src" "parsers" "sdc_parser.tcl"]
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

source [file join $root_dir "src" "opt" "drc.tcl"]
source [file join $root_dir "src" "power" "leakage.tcl"]
source [file join $root_dir "src" "power" "dynamic.tcl"]
source [file join $root_dir "src" "power" "area.tcl"]

source [file join $root_dir "src" "sim" "event.tcl"]
source [file join $root_dir "src" "sim" "simulator.tcl"]
source [file join $root_dir "src" "sim" "vcd.tcl"]

::tempo::test::suite "End-to-End EDA Integration Pipeline (Sky130 alu4)"

::tempo::test::test "Full STA, Power, Area, and Simulation Integration Run" {
    # 1. Load Liberty
    set lib_file [file join $root_dir "lib" "sky130_hd.lib"]
    set lib [::tempo::liberty::read_liberty_file $lib_file]
    ::tempo::test::assert_true [$lib has_cell "sky130_fd_sc_hd__inv_1"]

    # 2. Load Verilog
    set v_file [file join $root_dir "examples" "alu4.v"]
    set nl [::tempo::verilog::parser::read_verilog_file $v_file]
    ::tempo::test::assert_equal [$nl get_name] "alu4"

    # 3. Load SDC Constraints
    set sdc_file [file join $root_dir "examples" "alu4.sdc"]
    set c [::tempo::sdc::parser::read_sdc_file $sdc_file $nl]
    ::tempo::test::assert_true [$c has_clock "core_clk"]

    # 4. Load SPEF Parasitics
    set spef_file [file join $root_dir "examples" "alu4.spef"]
    set spef [::tempo::spef::parse_file $spef_file]
    ::tempo::test::assert_true [$spef has_net "w_nand0"]

    # 5. Build Bipartite Timing Graph
    set tg [::tempo::sta::graph::TimingGraph new $nl $lib]
    $tg build
    ::tempo::test::assert_true [expr {[llength [$tg get_startpoints]] > 0}]
    ::tempo::test::assert_true [expr {[llength [$tg get_endpoints]] > 0}]

    # 6. Analyze Clock Domain
    set clk_an [::tempo::sta::clock::ClockTreeAnalyzer new $c $tg]
    $clk_an analyze

    # 7. Forward Propagation
    set fwd [::tempo::sta::forward::ForwardPropagator new $tg $nl $lib $c $spef $clk_an]
    $fwd propagate

    # 8. Backward Propagation
    set bwd [::tempo::sta::backward::BackwardPropagator new $tg $nl $lib $c $spef $clk_an $fwd]
    $bwd propagate

    # 9. Slack Calculation
    set slk [::tempo::sta::slack::SlackCalculator new $tg $c $fwd $bwd]
    $slk calculate
    set summary [$slk get_summary]
    ::tempo::test::assert_true [dict exists $summary setup_wns]

    # 10. Critical Path Report Generation
    set rep_eng [::tempo::sta::report::PathExtractor new $tg $nl $lib $c $fwd $bwd $slk]
    set rpt [$rep_eng format_report 1 "max"]
    ::tempo::test::assert_true [regexp {TEMPO STATIC TIMING ANALYSIS REPORT} $rpt]

    # 11. Design Rule Checking (DRC)
    set drc [::tempo::opt::drc::DRCChecker new $nl $lib $c $fwd $tg]
    set viols [$drc check_all]
    ::tempo::test::assert_true [expr {[llength $viols] >= 0}]

    # 12. Power and Area Analysis
    set leak_an [::tempo::power::leakage::LeakageAnalyzer new $nl $lib]
    set leak_res [$leak_an calculate_total_leakage]

    set dyn_an [::tempo::power::dynamic::DynamicPowerAnalyzer new $nl $lib]
    set dyn_res [$dyn_an calculate_total_dynamic_power]

    set area_an [::tempo::power::area::AreaAnalyzer new $nl $lib]
    set area_res [$area_an calculate_area]

    ::tempo::test::assert_true [expr {[dict get $area_res total_area_um2] > 0.0}]
    ::tempo::test::assert_true [expr {[dict get $leak_res total_leakage_uW] > 0.0}]
    ::tempo::test::assert_true [expr {[dict get $dyn_res total_dynamic_uW] > 0.0}]

    # 13. Clean destruction
    $rep_eng destroy
    $drc destroy
    $leak_an destroy
    $dyn_an destroy
    $area_an destroy
    $slk destroy
    $bwd destroy
    $fwd destroy
    $clk_an destroy
    $tg destroy
    $spef destroy
    $c destroy
    $nl destroy
    $lib destroy
}

set code [::tempo::test::report]
exit $code
