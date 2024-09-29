# ==============================================================================
# TEMPO EDA Command Palette and Shell Engine
#
# Exposes Synopsys PrimeTime / OpenSTA compatible command palette for
# interactive and scripted electronic design automation flows.
# ==============================================================================

namespace eval ::tempo::shell {
    variable current_library ""
    variable current_netlist ""
    variable current_constraints ""
    variable current_spef ""
    variable current_timing_graph ""
    variable current_clock_analyzer ""
    variable current_forward_prop ""
    variable current_backward_prop ""
    variable current_slack_calc ""

    namespace export *

    proc print_banner {} {
        puts "================================================================================"
        puts " TEMPO: Static Timing Analysis & Logic Synthesis Engine (v1.0.0)"
        puts " Native EDA Architecture in High-Performance Tcl with C Acceleration"
        puts " Type 'help' for command listing or 'exit' to terminate session."
        puts "================================================================================"
    }

    # read_liberty <path>
    proc read_liberty {filepath} {
        variable current_library
        if {![file exists $filepath]} {
            puts stderr "Error: Liberty file not found: $filepath"
            return
        }
        puts "Info: Reading Liberty timing library: $filepath"
        set current_library [::tempo::liberty::read_liberty_file $filepath]
        set c_count [llength [$current_library get_cells]]
        puts "Info: Loaded library '[$current_library get_name]' with $c_count standard cells."
    }

    # read_verilog <path>
    proc read_verilog {filepath} {
        variable current_netlist
        if {![file exists $filepath]} {
            puts stderr "Error: Verilog file not found: $filepath"
            return
        }
        puts "Info: Reading structural Verilog netlist: $filepath"
        set current_netlist [::tempo::verilog::parser::read_verilog_file $filepath]
        set stats [$current_netlist get_stats]
        puts [format "Info: Parsed module '%s' (%d inputs, %d outputs, %d instances, %d nets)." \
            [dict get $stats name] \
            [dict get $stats num_inputs] \
            [dict get $stats num_outputs] \
            [dict get $stats num_instances] \
            [dict get $stats num_nets]]
    }

    # read_sdc <path>
    proc read_sdc {filepath} {
        variable current_constraints
        if {![file exists $filepath]} {
            puts stderr "Error: SDC file not found: $filepath"
            return
        }
        puts "Info: Reading SDC constraints: $filepath"
        set current_constraints [::tempo::sdc::parser::read_sdc_file $filepath]
        puts "Info: Successfully evaluated timing constraints."
    }

    # read_spef <path>
    proc read_spef {filepath} {
        variable current_spef
        if {![file exists $filepath]} {
            puts stderr "Error: SPEF file not found: $filepath"
            return
        }
        puts "Info: Reading SPEF parasitic interconnects: $filepath"
        set current_spef [::tempo::spef::parse_file $filepath]
        puts [format "Info: Loaded SPEF parasitic network with %d nets." [llength [$current_spef all_nets]]]
    }

    # link_design
    proc link_design {{top_module ""}} {
        variable current_library
        variable current_netlist
        variable current_timing_graph

        if {$current_library eq "" || $current_netlist eq ""} {
            puts stderr "Error: Both Liberty library and Verilog netlist must be loaded prior to linking."
            return
        }

        puts "Info: Linking design and constructing bipartite timing graph..."
        set current_timing_graph [::tempo::sta::graph::TimingGraph new $current_netlist $current_library]
        $current_timing_graph build
        puts "Info: Design linking complete. Timing graph ready for propagation."
    }

    # report_timing ?-delay_type max|min? ?-nworst N?
    proc report_timing {args} {
        variable current_library
        variable current_netlist
        variable current_constraints
        variable current_spef
        variable current_timing_graph
        variable current_clock_analyzer
        variable current_forward_prop
        variable current_backward_prop
        variable current_slack_calc

        if {$current_timing_graph eq ""} {
            link_design
        }

        set delay_type "max"
        set nworst 1

        for {set i 0} {$i < [llength $args]} {incr i} {
            set arg [lindex $args $i]
            if {$arg eq "-delay_type" && $i + 1 < [llength $args]} {
                set delay_type [lindex $args [incr i]]
            } elseif {$arg eq "-nworst" && $i + 1 < [llength $args]} {
                set nworst [lindex $args [incr i]]
            }
        }

        # 1. Analyze clock network
        set current_clock_analyzer [::tempo::sta::clock::ClockTreeAnalyzer new $current_constraints $current_timing_graph]
        $current_clock_analyzer analyze

        # 2. Forward topological propagation
        set current_forward_prop [::tempo::sta::forward::ForwardPropagator new \
            $current_timing_graph $current_netlist $current_library $current_constraints $current_spef $current_clock_analyzer]
        $current_forward_prop propagate

        # 3. Backward reverse topological propagation
        set current_backward_prop [::tempo::sta::backward::BackwardPropagator new \
            $current_timing_graph $current_netlist $current_library $current_constraints $current_spef $current_clock_analyzer $current_forward_prop]
        $current_backward_prop propagate

        # 4. Slack calculation
        set current_slack_calc [::tempo::sta::slack::SlackCalculator new \
            $current_timing_graph $current_constraints $current_forward_prop $current_backward_prop]
        $current_slack_calc calculate

        # 5. Extract and format critical paths
        set rep_eng [::tempo::sta::report::PathExtractor new \
            $current_timing_graph $current_netlist $current_library $current_constraints $current_forward_prop $current_backward_prop $current_slack_calc]
        puts [$rep_eng format_report $nworst $delay_type]
        $rep_eng destroy
    }

    # report_drc
    proc report_drc {} {
        variable current_library
        variable current_netlist
        variable current_constraints
        variable current_timing_graph
        variable current_forward_prop

        if {$current_forward_prop eq ""} {
            report_timing
        }

        set drc [::tempo::opt::drc::DRCChecker new $current_netlist $current_library $current_constraints $current_forward_prop $current_timing_graph]
        $drc check_all
        puts [$drc format_report]
        $drc destroy
    }

    # report_power
    proc report_power {} {
        variable current_library
        variable current_netlist

        if {$current_netlist eq "" || $current_library eq ""} {
            puts stderr "Error: Design must be loaded to report power."
            return
        }

        set leak_an [::tempo::power::leakage::LeakageAnalyzer new $current_netlist $current_library]
        set leak_res [$leak_an calculate_total_leakage]

        set dyn_an [::tempo::power::dynamic::DynamicPowerAnalyzer new $current_netlist $current_library]
        set dyn_res [$dyn_an calculate_total_dynamic_power]

        set area_an [::tempo::power::area::AreaAnalyzer new $current_netlist $current_library]
        set area_res [$area_an calculate_area]

        puts [$area_an format_power_area_report $leak_res $dyn_res $area_res]

        $leak_an destroy
        $dyn_an destroy
        $area_an destroy
    }

    # report_area
    proc report_area {} {
        variable current_library
        variable current_netlist

        if {$current_netlist eq "" || $current_library eq ""} {
            puts stderr "Error: Design must be loaded to report area."
            return
        }

        set area_an [::tempo::power::area::AreaAnalyzer new $current_netlist $current_library]
        set area_res [$area_an calculate_area]

        puts "================================================================================"
        puts "TEMPO PHYSICAL AREA REPORT"
        puts "================================================================================"
        puts [format "%-35s: %15.3f um^2" "Total Standard Cell Area" [dict get $area_res total_area_um2]]
        puts [format "%-35s: %15.3f um^2" "  Combinational Area" [dict get $area_res combinational_area_um2]]
        puts [format "%-35s: %15.3f um^2" "  Sequential Area" [dict get $area_res sequential_area_um2]]
        puts [format "%-35s: %15.1f" "NAND2 Equivalent Gate Count" [dict get $area_res nand2_gate_equivalents]]
        puts "--------------------------------------------------------------------------------"
        puts "Cell Histogram:"
        dict for {c count} [dict get $area_res cell_histogram] {
            puts [format "  %-25s: %5d instances" $c $count]
        }
        puts "================================================================================"
        $area_an destroy
    }

    # run_atpg
    proc run_atpg {} {
        variable current_library
        variable current_netlist

        if {$current_netlist eq "" || $current_library eq ""} {
            puts stderr "Error: Design must be loaded to run ATPG."
            return
        }

        puts "Info: Initializing single stuck-at fault model..."
        set fm [::tempo::fault::model::FaultManager new $current_netlist $current_library]
        set faults [$fm get_collapsed_faults]
        puts [format "Info: Fault collapsing reduced target faults from %d to %d (ratio: %.2f)." \
            [llength [$fm get_uncollapsed_faults]] [llength $faults] [$fm get_collapse_ratio]]

        puts "Info: Generating deterministic test patterns via PODEM ATPG..."
        set podem [::tempo::fault::podem::PodemATPG new $current_netlist $current_library]
        set test_vectors [list]

        foreach f $faults {
            set res [$podem generate_test $f]
            if {[dict get $res status] eq "SUCCESS"} {
                lappend test_vectors [dict get $res vector]
            }
        }
        puts [format "Info: Generated %d test patterns." [llength $test_vectors]]

        puts "Info: Simulating fault coverage with parallel fault dropping..."
        set fsim [::tempo::fault::sim::FaultSimulator new $current_netlist $current_library]
        set cov_res [$fsim run_fault_simulation $test_vectors [$fm get_uncollapsed_faults]]
        puts [$fsim format_coverage_report $cov_res]

        $fsim destroy
        $podem destroy
        $fm destroy
    }

    # help command
    proc help {} {
        puts {TEMPO EDA Shell Command Palette:}
        puts {  read_liberty <filepath>      Load Liberty (.lib) standard cell timing library}
        puts {  read_verilog <filepath>      Load structural Verilog-2005 netlist}
        puts {  read_sdc <filepath>          Load SDC 2.1 design constraints}
        puts {  read_spef <filepath>         Load IEEE 1481 SPEF parasitic RC network}
        puts {  link_design                  Construct bipartite timing graph and link objects}
        puts {  report_timing [-delay_type]  Run full STA propagation and report critical path}
        puts {  report_drc                   Check maximum transition, capacitance, and fanout}
        puts {  report_power                 Analyze static leakage, dynamic, and total chip power}
        puts {  report_area                  Compute silicon area and NAND2 gate equivalents}
        puts {  run_atpg                     Run PODEM deterministic ATPG and fault simulation}
        puts {  exit / quit                  Terminate interactive shell session}
    }
}

# Export top-level EDA commands
namespace eval :: {
    namespace import ::tempo::shell::read_liberty
    namespace import ::tempo::shell::read_verilog
    namespace import ::tempo::shell::read_sdc
    namespace import ::tempo::shell::read_spef
    namespace import ::tempo::shell::link_design
    namespace import ::tempo::shell::report_timing
    namespace import ::tempo::shell::report_drc
    namespace import ::tempo::shell::report_power
    namespace import ::tempo::shell::report_area
    namespace import ::tempo::shell::run_atpg
    namespace import ::tempo::shell::help
}
