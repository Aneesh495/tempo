# Tempo Standard Cell Technology Mapping Engine
# Dynamic programming DAG covering onto Liberty standard cell gates
# Namespace: ::tempo::synth::techmap

namespace eval ::tempo::synth::techmap {

    oo::class create Mapper {
        variable library        ;# ::tempo::liberty::Library
        variable cut_mgr        ;# ::tempo::synth::cut::CutManager
        variable best_match     ;# dict: node_id -> dict(cell: string, cut: list, cost: float, delay: float)
        variable mapped_netlist ;# ::tempo::netlist::Netlist
        variable node_to_net    ;# dict: "node_id,inv" -> net_name

        constructor {lib} {
            set library $lib
            set cut_mgr [::tempo::synth::cut::CutManager new 4]
            my reset
        }

        method reset {} {
            set best_match [dict create]
            set node_to_net [dict create]
        }

        # Main mapping entry point: converts AIG to standard cell Netlist
        method map_aig {aig {mode "area"}} {
            my reset

            # 1. Enumerate cuts across AIG
            $cut_mgr enumerate_cuts $aig

            # 2. Map primary inputs
            foreach piname [$aig get_pis] {
                set lit [$aig get_pi_lit $piname]
                set nid [::tempo::synth::aig::node_of $lit]
                dict set best_match $nid [dict create \
                    cell "PI" \
                    cut [list $nid] \
                    cost 0.0 \
                    delay 0.0 \
                    pin_name $piname]
            }

            # 3. Dynamic programming pass over AND nodes in topological order
            set and_nodes [$aig get_and_nodes]
            set all_nids [lsort -integer [dict keys $and_nodes]]

            foreach nid $all_nids {
                my _find_best_cell_for_node $aig $nid $mode
            }

            # 4. Synthesize structural Netlist from chosen covers
            return [my _generate_netlist $aig]
        }

        method _find_best_cell_for_node {aig nid mode} {
            set cuts [$cut_mgr get_cuts $nid]
            set best_cost 1.0e30
            set best_gate ""
            set best_cut [list]
            set best_delay 1.0e30

            foreach cut $cuts {
                # Skip trivial single-node cut if it's the node itself
                if {[llength $cut] == 1 && [lindex $cut 0] == $nid} {
                    continue
                }

                # Compute truth table of this cut
                set tt_bits [$cut_mgr compute_cut_truth_table $aig $nid $cut]
                set matched_gate_type [::tempo::synth::bool::match_signature $tt_bits]

                # Check inverted signature if direct match not found
                set need_inv 0
                if {$matched_gate_type eq ""} {
                    set inv_bits [string map {"0" "1" "1" "0"} $tt_bits]
                    set matched_gate_type [::tempo::synth::bool::match_signature $inv_bits]
                    if {$matched_gate_type ne ""} {
                        set need_inv 1
                    }
                }

                if {$matched_gate_type ne ""} {
                    # Check if cell exists in target library
                    set lib_cell [my _find_lib_cell $matched_gate_type]
                    if {$lib_cell ne ""} {
                        set cell_area 1.0
                        set cell_delay 10.0
                        if {[$library has_cell $lib_cell]} {
                            set cinfo [$library get_cell $lib_cell]
                            set cell_area [dict get $cinfo area]
                        }

                        # Sum cut leaf costs
                        set leaf_cost 0.0
                        set max_leaf_delay 0.0
                        foreach leaf $cut {
                            if {[dict exists $best_match $leaf]} {
                                set l_info [dict get $best_match $leaf]
                                set leaf_cost [expr {$leaf_cost + [dict get $l_info cost]}]
                                set ld [dict get $l_info delay]
                                if {$ld > $max_leaf_delay} { set max_leaf_delay $ld }
                            }
                        }

                        set total_cost [expr {$leaf_cost + $cell_area}]
                        set total_delay [expr {$max_leaf_delay + $cell_delay}]
                        if {$need_inv} {
                            set total_cost [expr {$total_cost + 1.0}]
                            set total_delay [expr {$total_delay + 5.0}]
                        }

                        set score [expr {$mode eq "delay" ? $total_delay : $total_cost}]
                        if {$score < $best_cost} {
                            set best_cost $score
                            set best_gate $lib_cell
                            set best_cut $cut
                            set best_delay $total_delay
                        }
                    }
                }
            }

            # Fallback if no macro cell matched: map to NAND2 + INV decomposition
            if {$best_gate eq ""} {
                set ainfo [dict get [$aig get_and_nodes] $nid]
                set l_lit [dict get $ainfo left]
                set r_lit [dict get $ainfo right]
                set l_node [::tempo::synth::aig::node_of $l_lit]
                set r_node [::tempo::synth::aig::node_of $r_lit]

                set best_gate "AND2_X1"
                set best_cut [list $l_node $r_node]
                set best_cost 2.0
                set best_delay 15.0
            }

            dict set best_match $nid [dict create \
                cell $best_gate \
                cut $best_cut \
                cost $best_cost \
                delay $best_delay]
        }

        method _find_lib_cell {gate_type} {
            # Try finding exact standard cell with drive strength X1
            set cand "${gate_type}_X1"
            if {[$library has_cell $cand]} {
                return $cand
            }
            # Search available cells starting with gate_type
            foreach cname [$library get_cells] {
                if {[string match "${gate_type}*" $cname]} {
                    return $cname
                }
            }
            return ""
        }

        # Generate mapped Netlist by traversing chosen covers from POs
        method _generate_netlist {aig} {
            set netlist [::tempo::netlist::Netlist new "synthesized_top"]

            # Add primary inputs
            foreach piname [$aig get_pis] {
                $netlist add_port $piname "INPUT"
                set lit [$aig get_pi_lit $piname]
                set nid [::tempo::synth::aig::node_of $lit]
                dict set node_to_net "${nid},0" $piname
            }

            # Add primary outputs
            foreach poname [$aig get_pos] {
                $netlist add_port $poname "OUTPUT"
            }

            # Instantiate gates from POs down to PIs
            set visited [dict create]
            set inst_counter 0

            foreach poname [$aig get_pos] {
                set po_lit [$aig get_po_lit $poname]
                set po_nid [::tempo::synth::aig::node_of $po_lit]
                set is_po_inv [::tempo::synth::aig::is_inv $po_lit]

                set out_net [my _materialize_node $aig $po_nid $netlist visited inst_counter]

                if {$is_po_inv} {
                    # Insert output inverter
                    incr inst_counter
                    set inv_name "u_out_inv_${inst_counter}"
                    $netlist add_instance $inv_name "INV_X1"
                    $netlist connect_pin $inv_name "A" $out_net "LOAD"
                    $netlist connect_pin $inv_name "Y" $poname "DRIVER"
                } else {
                    # Buffer or direct connection
                    incr inst_counter
                    set buf_name "u_out_buf_${inst_counter}"
                    $netlist add_instance $buf_name "BUF_X1"
                    $netlist connect_pin $buf_name "A" $out_net "LOAD"
                    $netlist connect_pin $buf_name "Y" $poname "DRIVER"
                }
            }

            return $netlist
        }

        method _materialize_node {aig nid netlist visited_var counter_var} {
            upvar 1 $visited_var visited
            upvar 1 $counter_var inst_counter

            if {[dict exists $node_to_net "${nid},0"]} {
                return [dict get $node_to_net "${nid},0"]
            }

            if {$nid == 0} {
                # Constant 0 net
                $netlist add_net "const_0"
                return "const_0"
            }

            if {![dict exists $best_match $nid]} {
                set net_name "net_n${nid}"
                $netlist add_net $net_name
                dict set node_to_net "${nid},0" $net_name
                return $net_name
            }

            set minfo [dict get $best_match $nid]
            set cell [dict get $minfo cell]
            set cut [dict get $minfo cut]

            # Primary input already handled
            if {$cell eq "PI"} {
                return [dict get $node_to_net "${nid},0"]
            }

            # Recursively materialize leaf inputs
            set leaf_nets [list]
            foreach leaf $cut {
                lappend leaf_nets [my _materialize_node $aig $leaf $netlist visited inst_counter]
            }

            incr inst_counter
            set inst_name "u_cell_${inst_counter}"
            set out_net "net_n${nid}"
            $netlist add_net $out_net

            $netlist add_instance $inst_name $cell
            $netlist connect_pin $inst_name "Y" $out_net "DRIVER"

            set pin_letters {A B C D E F}
            for {set i 0} {$i < [llength $leaf_nets]} {incr i} {
                set pletter [lindex $pin_letters $i]
                set lnet [lindex $leaf_nets $i]
                $netlist connect_pin $inst_name $pletter $lnet "LOAD"
            }

            dict set node_to_net "${nid},0" $out_net
            return $out_net
        }
    }
}
