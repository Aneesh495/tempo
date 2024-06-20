# Tempo Static Timing Analysis Backward Required Arrival Time (RAT) Engine
# Traverses timing graph in reverse topological order from endpoints to startpoints
# Namespace: ::tempo::sta::backward

namespace eval ::tempo::sta::backward {

    oo::class create BackwardPropagator {
        variable timing_graph   ;# ::tempo::sta::graph::TimingGraph
        variable netlist        ;# ::tempo::netlist::Netlist
        variable library        ;# ::tempo::liberty::Library
        variable constraints    ;# ::tempo::sdc::Constraints
        variable spef           ;# ::tempo::spef::SpefNetwork
        variable clock_analyzer ;# ::tempo::sta::clock::ClockTreeAnalyzer
        variable forward_prop   ;# ::tempo::sta::forward::ForwardPropagator

        variable rats           ;# dict: node_id -> dict(setup_r, setup_f, hold_r, hold_f)

        constructor {tg nl lib c spef_net clk_an fwd_prop} {
            set timing_graph $tg
            set netlist $nl
            set library $lib
            set constraints $c
            set spef $spef_net
            set clock_analyzer $clk_an
            set forward_prop $fwd_prop
            my reset
        }

        method reset {} {
            set rats [dict create]
        }

        method get_rats {node_id} {
            if {[dict exists $rats $node_id]} {
                return [dict get $rats $node_id]
            }
            return [dict create setup_r 1.0e30 setup_f 1.0e30 hold_r -1.0e30 hold_f -1.0e30]
        }

        # Execute backward required arrival time propagation
        method propagate {} {
            my reset
            set bg [$timing_graph get_graph]
            set topo_nodes [$bg topological_sort]
            set rev_topo [lreverse $topo_nodes]

            # 1. Initialize all nodes
            foreach nid $topo_nodes {
                dict set rats $nid [dict create setup_r 1.0e30 setup_f 1.0e30 hold_r -1.0e30 hold_f -1.0e30]
            }

            # 2. Initialize Path Endpoints
            set clk_names [$constraints get_clocks]
            set default_clk [expr {[llength $clk_names] > 0 ? [lindex $clk_names 0] : ""}]
            set t_clk [expr {$default_clk ne "" ? [$constraints get_clock_period $default_clk] : 1000.0}]
            set setup_unc [$clock_analyzer get_uncertainty $default_clk 1]
            set hold_unc  [$clock_analyzer get_uncertainty $default_clk 0]

            foreach ep [$timing_graph get_endpoints] {
                set nid [$timing_graph get_node_by_pin $ep]
                if {$nid eq ""} { continue }

                if {[$netlist has_port $ep]} {
                    # Primary Output port
                    set out_delay [$constraints get_max_output_delay $ep]
                    set req_setup [expr {$t_clk - $out_delay - $setup_unc}]
                    set req_hold  [expr {$out_delay + $hold_unc}]

                    dict set rats $nid [dict create \
                        setup_r $req_setup \
                        setup_f $req_setup \
                        hold_r  $req_hold \
                        hold_f  $req_hold]
                } else {
                    # Register D pin
                    set parts [split $ep "/"]
                    set inst [lindex $parts 0]
                    set ck_pin "$inst/CK"
                    set cell_type [$netlist get_instance_cell $inst]

                    set skew [$clock_analyzer compute_skew "any_launch" $ck_pin 1]
                    set seq_limits [::tempo::sta::delay::compute_seq_constraints $library $cell_type 15.0 15.0]
                    set t_setup [dict get $seq_limits setup_time]
                    set t_hold  [dict get $seq_limits hold_time]

                    set m_setup [$constraints get_multicycle_setup "any_launch" $ep]
                    set eff_t_clk [expr {$m_setup * $t_clk}]

                    set req_setup [expr {$eff_t_clk - $t_setup - $setup_unc + $skew}]
                    set req_hold  [expr {$t_hold + $hold_unc + $skew}]

                    dict set rats $nid [dict create \
                        setup_r $req_setup \
                        setup_f $req_setup \
                        hold_r  $req_hold \
                        hold_f  $req_hold]
                }
            }

            # 3. Propagate backward in reverse topological order
            foreach v $rev_topo {
                set rat_v [my get_rats $v]
                if {[dict get $rat_v setup_r] >= 1.0e29 && [llength [$bg get_out_edges $v]] > 0} {
                    continue
                }

                foreach eid [$bg get_in_edges $v] {
                    set einfo [$bg get_edge $eid]
                    set u [dict get $einfo src]
                    set etype [dict get $einfo type]

                    if {$etype eq "CELL_ARC"} {
                        my _backward_cell_arc $u $v $einfo $rat_v
                    } elseif {$etype eq "NET_ARC"} {
                        my _backward_net_arc $u $v $einfo $rat_v
                    }
                }
            }
        }

        method _backward_cell_arc {u v einfo rat_v} {
            set cell [dict get $einfo cell]
            set in_pin [dict get $einfo from_pin]
            set out_pin [dict get $einfo to_pin]
            set inst [dict get $einfo inst]

            set net_name [dict get [$netlist get_instance_pins $inst] $out_pin]
            set out_cap [::tempo::sta::delay::calculate_net_load $netlist $library $spef $constraints $net_name]
            set delay_pkg [::tempo::sta::delay::compute_cell_arc_delay $library $cell $out_pin $in_pin 15.0 $out_cap]

            set d_r [dict get $delay_pkg cell_rise]
            set d_f [dict get $delay_pkg cell_fall]

            set is_neg_unate 0
            if {[string match "INV*" $cell] || [string match "NAND*" $cell] || [string match "NOR*" $cell]} {
                set is_neg_unate 1
            }

            set cur_rat_u [my get_rats $u]

            if {$is_neg_unate} {
                set cand_setup_r [expr {[dict get $rat_v setup_f] - $d_f}]
                set cand_setup_f [expr {[dict get $rat_v setup_r] - $d_r}]
                set cand_hold_r  [expr {[dict get $rat_v hold_f]  + $d_f}]
                set cand_hold_f  [expr {[dict get $rat_v hold_r]  + $d_r}]
            } else {
                set cand_setup_r [expr {[dict get $rat_v setup_r] - $d_r}]
                set cand_setup_f [expr {[dict get $rat_v setup_f] - $d_f}]
                set cand_hold_r  [expr {[dict get $rat_v hold_r]  + $d_r}]
                set cand_hold_f  [expr {[dict get $rat_v hold_f]  + $d_f}]
            }

            # Setup RAT is minimized along converging paths (most restrictive)
            dict set rats $u setup_r [expr {min([dict get $cur_rat_u setup_r], $cand_setup_r)}]
            dict set rats $u setup_f [expr {min([dict get $cur_rat_u setup_f], $cand_setup_f)}]

            # Hold RAT is maximized along converging paths (most restrictive)
            dict set rats $u hold_r  [expr {max([dict get $cur_rat_u hold_r], $cand_hold_r)}]
            dict set rats $u hold_f  [expr {max([dict get $cur_rat_u hold_f], $cand_hold_f)}]
        }

        method _backward_net_arc {u v einfo rat_v} {
            set net_name [dict get $einfo net]
            set wire_pkg [::tempo::sta::elmore::compute_wire_delay $spef $net_name "driver" "sink"]
            set w_delay [dict get $wire_pkg delay]

            set cur_rat_u [my get_rats $u]

            set cand_setup_r [expr {[dict get $rat_v setup_r] - $w_delay}]
            set cand_setup_f [expr {[dict get $rat_v setup_f] - $w_delay}]
            set cand_hold_r  [expr {[dict get $rat_v hold_r]  + $w_delay}]
            set cand_hold_f  [expr {[dict get $rat_v hold_f]  + $w_delay}]

            dict set rats $u setup_r [expr {min([dict get $cur_rat_u setup_r], $cand_setup_r)}]
            dict set rats $u setup_f [expr {min([dict get $cur_rat_u setup_f], $cand_setup_f)}]
            dict set rats $u hold_r  [expr {max([dict get $cur_rat_u hold_r], $cand_hold_r)}]
            dict set rats $u hold_f  [expr {max([dict get $cur_rat_u hold_f], $cand_hold_f)}]
        }
    }
}
