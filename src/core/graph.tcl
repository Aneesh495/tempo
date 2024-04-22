# Tempo Core Graph and Network Topology Engine
# Supports hypergraphs, directed acyclic graphs (DAGs), cycle analysis,
# topological sorting, and shortest/longest path calculations.
# Namespace: ::tempo::graph

namespace eval ::tempo::graph {
    # Graph data structure represented as a TclOO class or namespace container.
    # We provide a clean TclOO class ::tempo::graph::Graph for high performance
    # and modular graph operations.

    oo::class create Graph {
        variable nodes
        variable edges
        variable in_edges
        variable out_edges
        variable node_types
        variable node_data
        variable edge_data
        variable edge_counter

        constructor {} {
            my reset
        }

        method reset {} {
            set nodes [dict create]
            set edges [dict create]
            set in_edges [dict create]
            set out_edges [dict create]
            set node_types [dict create]
            set node_data [dict create]
            set edge_data [dict create]
            set edge_counter 0
        }

        # Add a node with an optional type and user data dict
        method add_node {id {type "GENERIC"} {data {}}} {
            if {![dict exists $nodes $id]} {
                dict set nodes $id 1
                dict set in_edges $id [list]
                dict set out_edges $id [list]
                dict set node_types $id $type
                dict set node_data $id $data
            } else {
                # Merge data if node already exists
                set cur_data [dict get $node_data $id]
                dict set node_data $id [dict merge $cur_data $data]
                if {$type ne "GENERIC"} {
                    dict set node_types $id $type
                }
            }
            return $id
        }

        method has_node {id} {
            return [dict exists $nodes $id]
        }

        method get_node_type {id} {
            if {[dict exists $node_types $id]} {
                return [dict get $node_types $id]
            }
            return ""
        }

        method get_node_data {id} {
            if {[dict exists $node_data $id]} {
                return [dict get $node_data $id]
            }
            return [dict create]
        }

        method set_node_attr {id key val} {
            if {![dict exists $nodes $id]} {
                my add_node $id
            }
            dict set node_data $id $key $val
        }

        method get_node_attr {id key {default_val ""}} {
            if {[dict exists $node_data $id $key]} {
                return [dict get $node_data $id $key]
            }
            return $default_val
        }

        # Add directed edge from src to dst
        method add_edge {src dst {type "DEFAULT"} {data {}}} {
            if {![my has_node $src]} { my add_node $src }
            if {![my has_node $dst]} { my add_node $dst }

            incr edge_counter
            set edge_id "e_$edge_counter"

            set edge_info [dict create \
                id $edge_id \
                src $src \
                dst $dst \
                type $type]

            dict set edges $edge_id [dict merge $edge_info $data]
            dict lappend out_edges $src $edge_id
            dict lappend in_edges $dst $edge_id

            return $edge_id
        }

        method get_edge {edge_id} {
            if {[dict exists $edges $edge_id]} {
                return [dict get $edges $edge_id]
            }
            return [dict create]
        }

        method get_in_edges {node} {
            if {[dict exists $in_edges $node]} {
                return [dict get $in_edges $node]
            }
            return [list]
        }

        method get_out_edges {node} {
            if {[dict exists $out_edges $node]} {
                return [dict get $out_edges $node]
            }
            return [list]
        }

        method get_predecessors {node} {
            set preds [list]
            foreach eid [my get_in_edges $node] {
                set src [dict get [dict get $edges $eid] src]
                if {$src ni $preds} {
                    lappend preds $src
                }
            }
            return $preds
        }

        method get_successors {node} {
            set succs [list]
            foreach eid [my get_out_edges $node] {
                set dst [dict get [dict get $edges $eid] dst]
                if {$dst ni $succs} {
                    lappend succs $dst
                }
            }
            return $succs
        }

        method node_count {} {
            return [dict size $nodes]
        }

        method edge_count {} {
            return [dict size $edges]
        }

        method all_nodes {} {
            return [dict keys $nodes]
        }

        method all_edges {} {
            return [dict keys $edges]
        }

        # Kahn's algorithm for topological sorting
        # Returns ordered list of node IDs.
        # Throws error if cycle exists.
        method topological_sort {} {
            set in_degree [dict create]
            set zero_queue [list]

            foreach n [dict keys $nodes] {
                set deg [llength [my get_in_edges $n]]
                dict set in_degree $n $deg
                if {$deg == 0} {
                    lappend zero_queue $n
                }
            }

            set topo_order [list]

            while {[llength $zero_queue] > 0} {
                set curr [lindex $zero_queue 0]
                set zero_queue [lrange $zero_queue 1 end]
                lappend topo_order $curr

                foreach eid [my get_out_edges $curr] {
                    set dst [dict get [dict get $edges $eid] dst]
                    set cur_deg [dict get $in_degree $dst]
                    incr cur_deg -1
                    dict set in_degree $dst $cur_deg
                    if {$cur_deg == 0} {
                        lappend zero_queue $dst
                    }
                }
            }

            if {[llength $topo_order] != [dict size $nodes]} {
                set cycle_nodes [list]
                dict for {n deg} $in_degree {
                    if {$deg > 0} {
                        lappend cycle_nodes $n
                    }
                }
                return -code error "Graph contains directed cycles. Cycle members: \[[join $cycle_nodes {, }]\]"
            }

            return $topo_order
        }

        # Tarjan's Strongly Connected Components (SCC) algorithm
        # Useful for identifying cycles and feedback paths
        method tarjan_scc {} {
            set index 0
            set stack [list]
            set indices [dict create]
            set lowlinks [dict create]
            set on_stack [dict create]
            set sccs [list]

            foreach n [dict keys $nodes] {
                dict set indices $n -1
                dict set lowlinks $n -1
                dict set on_stack $n 0
            }

            foreach n [dict keys $nodes] {
                if {[dict get $indices $n] == -1} {
                    my _strongconnect $n index stack indices lowlinks on_stack sccs
                }
            }
            return $sccs
        }

        method _strongconnect {v index_var stack_var indices_var lowlinks_var on_stack_var sccs_var} {
            upvar 1 $index_var index
            upvar 1 $stack_var stack
            upvar 1 $indices_var indices
            upvar 1 $lowlinks_var lowlinks
            upvar 1 $on_stack_var on_stack
            upvar 1 $sccs_var sccs

            dict set indices $v $index
            dict set lowlinks $v $index
            incr index
            lappend stack $v
            dict set on_stack $v 1

            foreach eid [my get_out_edges $v] {
                set w [dict get [dict get $edges $eid] dst]
                if {[dict get $indices $w] == -1} {
                    my _strongconnect $w index stack indices lowlinks on_stack sccs
                    set lw [dict get $lowlinks $w]
                    set lv [dict get $lowlinks $v]
                    if {$lw < $lv} {
                        dict set lowlinks $v $lw
                    }
                } elseif {[dict get $on_stack $w]} {
                    set iw [dict get $indices $w]
                    set lv [dict get $lowlinks $v]
                    if {$iw < $lv} {
                        dict set lowlinks $v $iw
                    }
                }
            }

            if {[dict get $lowlinks $v] == [dict get $indices $v]} {
                set component [list]
                while {1} {
                    set w [lindex $stack end]
                    set stack [lrange $stack 0 end-1]
                    dict set on_stack $w 0
                    lappend component $w
                    if {$w eq $v} {
                        break
                    }
                }
                lappend sccs $component
            }
        }

        # Fanin cone (transitive backward dependencies)
        method get_fanin_cone {start_node} {
            set visited [dict create]
            set queue [list $start_node]
            dict set visited $start_node 1

            while {[llength $queue] > 0} {
                set curr [lindex $queue 0]
                set queue [lrange $queue 1 end]
                foreach p [my get_predecessors $curr] {
                    if {![dict exists $visited $p]} {
                        dict set visited $p 1
                        lappend queue $p
                    }
                }
            }
            return [dict keys $visited]
        }

        # Fanout cone (transitive forward dependencies)
        method get_fanout_cone {start_node} {
            set visited [dict create]
            set queue [list $start_node]
            dict set visited $start_node 1

            while {[llength $queue] > 0} {
                set curr [lindex $queue 0]
                set queue [lrange $queue 1 end]
                foreach s [my get_successors $curr] {
                    if {![dict exists $visited $s]} {
                        dict set visited $s 1
                        lappend queue $s
                    }
                }
            }
            return [dict keys $visited]
        }

        # Find longest path on a DAG (weighted by edge/node delay attribute)
        # Returns dict: [list path $nodes length $max_len]
        method longest_path {{weight_attr "weight"}} {
            set topo [my topological_sort]
            set dist [dict create]
            set parent [dict create]

            foreach n $topo {
                dict set dist $n -1.0e30
                dict set parent $n ""
            }

            # Initialize sources (in-degree == 0)
            foreach n $topo {
                if {[llength [my get_in_edges $n]] == 0} {
                    dict set dist $n 0.0
                }
            }

            foreach u $topo {
                set d_u [dict get $dist $u]
                if {$d_u <= -1.0e29} { continue }

                foreach eid [my get_out_edges $u] {
                    set einfo [dict get $edges $eid]
                    set v [dict get $einfo dst]
                    set w 0.0
                    if {[dict exists $einfo $weight_attr]} {
                        set w [dict get $einfo $weight_attr]
                    }
                    set cand [expr {$d_u + $w}]
                    if {$cand > [dict get $dist $v]} {
                        dict set dist $v $cand
                        dict set parent $v $u
                    }
                }
            }

            # Find maximum distance endpoint
            set best_node ""
            set max_val -1.0e30
            dict for {n d} $dist {
                if {$d > $max_val} {
                    set max_val $d
                    set best_node $n
                }
            }

            # Reconstruct path
            set path [list]
            set curr $best_node
            while {$curr ne ""} {
                set path [linsert $path 0 $curr]
                set curr [dict get $parent $curr]
            }

            return [dict create path $path length $max_val end_node $best_node]
        }
    }
}
