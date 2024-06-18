# Tempo Static Timing Analysis Forward Delay Propagation Engine
# Propagates early/late rise/fall arrival times and slews in topological order
# Namespace: ::tempo::sta::forward

namespace eval ::tempo::sta::forward {

    oo::class create ForwardPropagator {
        variable timing_graph   ;# ::tempo::sta::graph::TimingGraph
        variable netlist        ;# ::tempo::netlist::Netlist
        variable library        ;# ::tempo::liberty::Library
        variable constraints    ;# ::tempo::sdc::Constraints
        variable spef           ;# ::tempo::spef::SpefNetwork
        variable clock_analyzer ;# ::tempo::sta::clock::ClockTreeAnalyzer

        variable arrivals       ;# dict: node_id -> dict(early_r, early_f, late_r, late_f)
        variable slews          ;# dict: node_id -> dict(early_r, early_f, late_r, late_f)

        constructor {tg nl lib c spef_net clk_an} {
            set timing_graph $tg
            set netlist $nl
            set library $lib
            set constraints $c
            set spef $spef_net
            set clock_analyzer $clk_an
            my reset
        }

        method reset {} {
            set arrivals [dict create]
            set slews [dict create]
        }

        method get_arrivals {node_id} {
            if {[dict exists $arrivals $node_id]} {
                return [dict get $arrivals $node_id]
            }
            return [dict create early_r 0.0 early_f 0.0 late_r 0.0 late_f 0.0]
        }

        method get_slews {node_id} {
            if {[dict exists $slews $node_id]} {
                return [dict get $slews $node_id]
            }
            return [dict create early_r 10.0 early_f 10.0 late_r 10.0 late_f 10.0]
        }

        # Execute forward topological arrival time propagation
        method propagate {} {
            my reset
            set bg [$timing_graph get_graph]
            set topo_nodes [$bg topological_sort]

            # 1. Initialize all nodes with default values
            foreach nid $topo_nodes {
                dict set arrivals $nid [dict create early_r 1.0e30 early_f 1.0e30 late_r -1.0e30 late_f -1.0e30]
                dict set slews $nid [dict create early_r 10.0 early_f 10.0 late_r 10.0 late_f 10.0]
            }

            # 2. Initialize Path Startpoints
            foreach sp [$timing_graph get_startpoints] {
                set nid [$timing_graph get_node_by_pin $sp]
                if {$nid eq ""} { continue }

                if {[$netlist has_port $sp]} {
                    # Primary Input port
                    set in_delay [$constraints get_max_input_delay $sp]
                    set in_slew  [$constraints get_input_transition $sp 15.0]

                    dict set arrivals $nid [dict create \
                        early_r $in_delay \
                        early_f $in_delay \
                        late_r  $in_delay \
                        late_f  $in_delay]
                    dict set slews $nid [dict create \
                        early_r $in_slew \
                        early_f $in_slew \
                        late_r  $in_slew \
                        late_f  $in_slew]
                } else {
                    # Register Q pin: arrival = clock_latency + clk_to_q delay
                    set parts [split $sp "/"]
                    set inst [lindex $parts 0]
                    set ck_pin "$inst/CK"
                    set clk_lat [$clock_analyzer get_pin_latency $ck_pin "late"]
                    set clk_to_q 35.0 ;# typical clock to Q delay

                    set tot_arrival [expr {$clk_lat + $clk_to_q}]
                    dict set arrivals $nid [dict create \
                        early_r $tot_arrival \
                        early_f $tot_arrival \
                        late_r  $tot_arrival \
                        late_f  $tot_arrival]
                    dict set slews $nid [dict create \
                        early_r 12.0 \
                        early_f 12.0 \
                        late_r  12.0 \
                        late_f  12.0]
                }
            }

            # 3. Propagate forward in topological order
            foreach u $topo_nodes {
                set arr_u [my get_arrivals $u]
                set slew_u [my get_slews $u]

                # If node arrival uninitialized and has in-edges, skip
                if {[dict get $arr_u late_r] <= -1.0e29 && [llength [$bg get_in_edges $u]] > 0} {
                    continue
                }

                foreach eid [$bg get_out_edges $u] {
                    set einfo [$bg get_edge $eid]
                    set v [dict get $einfo dst]
                    set etype [dict get $einfo type]

                    if {$etype eq "CELL_ARC"} {
                        my _propagate_cell_arc $u $v $einfo $arr_u $slew_u
                    } elseif {$etype eq "NET_ARC"} {
                        my _propagate_net_arc $u $v $einfo $arr_u $slew_u
                    }
                }
            }
        }

        method _propagate_cell_arc {u v einfo arr_u slew_u} {
            set cell [dict get $einfo cell]
            set in_pin [dict get $einfo from_pin]
            set out_pin [dict get $einfo to_pin]
            set inst [dict get $einfo inst]

            set net_name [dict get [$netlist get_instance_pins $inst] $out_pin]
            set out_cap [::tempo::sta::delay::calculate_net_load $netlist $library $spef $constraints $net_name]

            set in_slew_late [expr {max([dict get $slew_u late_r], [dict get $slew_u late_f])}]
            set delay_pkg [::tempo::sta::delay::compute_cell_arc_delay $library $cell $out_pin $in_pin $in_slew_late $out_cap]

            set d_r [dict get $delay_pkg cell_rise]
            set d_f [dict get $delay_pkg cell_fall]
            set s_r [dict get $delay_pkg rise_slew]
            set s_f [dict get $delay_pkg fall_slew]

            # Determine timing sense (unateness)
            set is_neg_unate 0
            if {[string match "INV*" $cell] || [string match "NAND*" $cell] || [string match "NOR*" $cell]} {
                set is_neg_unate 1
            }

            set cur_arr_v [my get_arrivals $v]
            set cur_slew_v [my get_slews $v]

            if {$is_neg_unate} {
                # Inverting gate: input rise causes output fall; input fall causes output rise
                set cand_late_r [expr {[dict get $arr_u late_f] + $d_r}]
                set cand_late_f [expr {[dict get $arr_u late_r] + $d_f}]
                set cand_early_r [expr {[dict get $arr_u early_f] + $d_r}]
                set cand_early_f [expr {[dict get $arr_u early_r] + $d_f}]
            } else {
                # Non-inverting gate: input rise causes output rise; input fall causes output fall
                set cand_late_r [expr {[dict get $arr_u late_r] + $d_r}]
                set cand_late_f [expr {[dict get $arr_u late_f] + $d_f}]
                set cand_early_r [expr {[dict get $arr_u early_r] + $d_r}]
                set cand_early_f [expr {[dict get $arr_u early_f] + $d_f}]
            }

            # Update arrival times (max for late, min for early)
            dict set arrivals $v late_r  [expr {max([dict get $cur_arr_v late_r], $cand_late_r)}]
            dict set arrivals $v late_f  [expr {max([dict get $cur_arr_v late_f], $cand_late_f)}]
            dict set arrivals $v early_r [expr {min([dict get $cur_arr_v early_r], $cand_early_r)}]
            dict set arrivals $v early_f [expr {min([dict get $cur_arr_v early_f], $cand_early_f)}]

            # Update output slews
            dict set slews $v late_r $s_r
            dict set slews $v late_f $s_f
            dict set slews $v early_r $s_r
            dict set slews $v early_f $s_f
        }

        method _propagate_net_arc {u v einfo arr_u slew_u} {
            set net_name [dict get $einfo net]
            # Calculate wire delay from driver to sink
            set wire_pkg [::tempo::sta::elmore::compute_wire_delay $spef $net_name "driver" "sink"]
            set w_delay [dict get $wire_pkg delay]
            set slew_deg [dict get $wire_pkg slew_deg]

            set cur_arr_v [my get_arrivals $v]
            set cur_slew_v [my get_slews $v]

            set cand_late_r [expr {[dict get $arr_u late_r] + $w_delay}]
            set cand_late_f [expr {[dict get $arr_u late_f] + $w_delay}]
            set cand_early_r [expr {[dict get $arr_u early_r] + $w_delay}]
            set cand_early_f [expr {[dict get $arr_u early_f] + $w_delay}]

            dict set arrivals $v late_r  [expr {max([dict get $cur_arr_v late_r], $cand_late_r)}]
            dict set arrivals $v late_f  [expr {max([dict get $cur_arr_v late_f], $cand_late_f)}]
            dict set arrivals $v early_r [expr {min([dict get $cur_arr_v early_r], $cand_early_r)}]
            dict set arrivals $v early_f [expr {min([dict get $cur_arr_v early_f], $cand_early_f)}]

            # Degrade slews
            dict set slews $v late_r [expr {[dict get $slew_u late_r] + $slew_deg}]
            dict set slews $v late_f [expr {[dict get $slew_u late_f] + $slew_deg}]
            dict set slews $v early_r [expr {[dict get $slew_u early_r] + $slew_deg}]
            dict set slews $v early_f [expr {[dict get $slew_u early_f] + $slew_deg}]
        }
    }
}
