# Tempo Wire Parasitic and Elmore Delay Calculation Engine
# Computes distributed RC interconnect delay and transition degradation
# Namespace: ::tempo::sta::elmore

namespace eval ::tempo::sta::elmore {

    # Compute Elmore delay (in picoseconds) from net driver pin to specified sink pin
    proc compute_wire_delay {spef net_name driver_pin sink_pin} {
        if {$spef eq "" || ![info object isa typeof $spef ::tempo::spef::SpefNetwork]} {
            return [dict create delay 0.0 slew_deg 0.0]
        }

        if {![$spef has_net $net_name]} {
            return [dict create delay 0.0 slew_deg 0.0]
        }

        set res_segs [$spef get_net_res_segments $net_name]
        set node_caps [$spef get_net_node_caps $net_name]
        set total_cap [$spef get_net_cap $net_name]

        if {[llength $res_segs] == 0} {
            # Lumped capacitor model, zero wire resistance
            return [dict create delay 0.0 slew_deg 0.0]
        }

        # Build local RC tree graph for the net
        set rc_graph [::tempo::graph::Graph new]
        set total_res 0.0

        foreach seg $res_segs {
            set n1 [dict get $seg node1]
            set n2 [dict get $seg node2]
            set r [dict get $seg res]
            set total_res [expr {$total_res + $r}]
            $rc_graph add_edge $n1 $n2 "RES" [dict create res $r]
            $rc_graph add_edge $n2 $n1 "RES" [dict create res $r] ;# undirected
        }

        # Find shortest resistance path from driver to sink using Dijkstra / BFS
        set queue [list $driver_pin]
        set dist [dict create $driver_pin 0.0]
        set parent [dict create]

        while {[llength $queue] > 0} {
            set curr [lindex $queue 0]
            set queue [lrange $queue 1 end]
            set d_cur [dict get $dist $curr]

            foreach eid [$rc_graph get_out_edges $curr] {
                set einfo [$rc_graph get_edge $eid]
                set nxt [dict get $einfo dst]
                set r [dict get $einfo res]
                set cand [expr {$d_cur + $r}]

                if {![dict exists $dist $nxt] || $cand < [dict get $dist $nxt]} {
                    dict set dist $nxt $cand
                    dict set parent $nxt $curr
                    lappend queue $nxt
                }
            }
        }

        $rc_graph destroy

        # If sink_pin not reached, fallback to lumped RC: tau = 0.5 * R_total * C_total
        if {![dict exists $dist $sink_pin]} {
            set elmore_delay [expr {0.5 * $total_res * $total_cap * 0.001}]
            set slew_deg [expr {2.2 * $elmore_delay}]
            return [dict create delay $elmore_delay slew_deg $slew_deg]
        }

        # Trace path from driver to sink and sum Elmore delays
        set path_res [dict get $dist $sink_pin]
        # Elmore approximation: tau = R_path * C_downstream
        set elmore_delay [expr {$path_res * $total_cap * 0.001}]
        set slew_deg [expr {2.2 * $elmore_delay}]

        return [dict create delay $elmore_delay slew_deg $slew_deg]
    }

    # Degradation of slew passing through an RC network
    proc degrade_slew {input_slew_ps wire_delay_ps} {
        set deg [expr {2.2 * $wire_delay_ps}]
        return [expr {sqrt($input_slew_ps * $input_slew_ps + $deg * $deg)}]
    }
}
