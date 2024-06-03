# Tempo Priority Cut Enumeration Engine
# Enumerates k-feasible cuts (up to k=4 or k=6) for DAG technology mapping
# Namespace: ::tempo::synth::cut

namespace eval ::tempo::synth::cut {

    oo::class create CutManager {
        variable k_max          ;# Maximum cut size (typically 4)
        variable node_cuts      ;# dict: node_id -> list of cuts (each cut is a sorted list of leaf node IDs)
        variable cut_signatures ;# dict: "node_id,cut_index" -> truth_table_bitstring

        constructor {{max_k 4}} {
            set k_max $max_k
            my reset
        }

        method reset {} {
            set node_cuts [dict create]
            set cut_signatures [dict create]
        }

        # Enumerate all k-feasible cuts for the given AIG
        method enumerate_cuts {aig} {
            my reset

            # 1. Primary Inputs have only the trivial cut {PI_node}
            foreach piname [$aig get_pis] {
                set lit [$aig get_pi_lit $piname]
                set nid [::tempo::synth::aig::node_of $lit]
                dict set node_cuts $nid [list [list $nid]]
            }

            # 2. Iterate through AND nodes in topological order
            # In our AIG, node IDs are assigned in topological order
            # So iterating in increasing node_id order is topologically sorted!
            set all_nids [lsort -integer [dict keys [$aig get_and_nodes]]]

            foreach nid $all_nids {
                set ainfo [dict get [$aig get_and_nodes] $nid]
                set l_lit [dict get $ainfo left]
                set r_lit [dict get $ainfo right]

                set l_node [::tempo::synth::aig::node_of $l_lit]
                set r_node [::tempo::synth::aig::node_of $r_lit]

                set l_cuts [my get_cuts $l_node]
                set r_cuts [my get_cuts $r_node]

                set combined_cuts [list]
                # Trivial cut: {nid}
                lappend combined_cuts [list $nid]

                # Pairwise union of cuts from left and right children
                foreach c_left $l_cuts {
                    foreach c_right $r_cuts {
                        set merged [lsort -unique -integer [concat $c_left $c_right]]
                        if {[llength $merged] <= $k_max} {
                            # Check if cut is already present
                            if {$merged ni $combined_cuts} {
                                # Check dominance
                                if {![my _is_dominated $merged $combined_cuts]} {
                                    lappend combined_cuts $merged
                                }
                            }
                        }
                    }
                }

                # Keep only top non-dominated cuts
                dict set node_cuts $nid $combined_cuts
            }
        }

        method get_cuts {nid} {
            if {[dict exists $node_cuts $nid]} {
                return [dict get $node_cuts $nid]
            }
            return [list [list $nid]]
        }

        # Returns true if cand_cut contains any existing cut as a proper subset
        method _is_dominated {cand_cut existing_cuts} {
            foreach ec $existing_cuts {
                if {[llength $ec] < [llength $cand_cut]} {
                    # Check if ec is subset of cand_cut
                    set is_sub 1
                    foreach leaf $ec {
                        if {$leaf ni $cand_cut} {
                            set is_sub 0
                            break
                        }
                    }
                    if {$is_sub} { return 1 }
                }
            }
            return 0
        }

        # Compute truth table for node with respect to cut leaves
        method compute_cut_truth_table {aig nid cut_leaves} {
            set num_leaves [llength $cut_leaves]
            set num_rows [expr {1 << $num_leaves}]
            set tt_bits ""

            for {set r 0} {$r < $num_rows} {incr r} {
                set leaf_vals [dict create]
                for {set i 0} {$i < $num_leaves} {incr i} {
                    set leaf_node [lindex $cut_leaves $i]
                    set bit_val [expr {($r >> $i) & 1}]
                    dict set leaf_vals $leaf_node $bit_val
                }

                # Evaluate subgraph from leaves up to nid
                set out_bit [my _eval_node_subgraph $aig $nid $leaf_vals]
                append tt_bits $out_bit
            }

            return $tt_bits
        }

        method _eval_node_subgraph {aig target_nid leaf_vals} {
            if {[dict exists $leaf_vals $target_nid]} {
                return [dict get $leaf_vals $target_nid]
            }
            if {$target_nid == 0} { return 0 }

            set and_nodes [$aig get_and_nodes]
            if {![dict exists $and_nodes $target_nid]} {
                return 0
            }

            set ainfo [dict get $and_nodes $target_nid]
            set l_lit [dict get $ainfo left]
            set r_lit [dict get $ainfo right]

            set l_node [::tempo::synth::aig::node_of $l_lit]
            set r_node [::tempo::synth::aig::node_of $r_lit]

            set l_val [my _eval_node_subgraph $aig $l_node $leaf_vals]
            if {[::tempo::synth::aig::is_inv $l_lit]} { set l_val [expr {!$l_val}] }

            set r_val [my _eval_node_subgraph $aig $r_node $leaf_vals]
            if {[::tempo::synth::aig::is_inv $r_lit]} { set r_val [expr {!$r_val}] }

            return [expr {$l_val & $r_val}]
        }
    }
}
