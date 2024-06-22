# Tempo Static Timing Analysis Slack Calculation and Summary Engine
# Computes setup and hold slacks, WNS, TNS, and Failing Endpoint count
# Namespace: ::tempo::sta::slack

namespace eval ::tempo::sta::slack {

    oo::class create SlackCalculator {
        variable timing_graph   ;# ::tempo::sta::graph::TimingGraph
        variable constraints    ;# ::tempo::sdc::Constraints
        variable forward_prop   ;# ::tempo::sta::forward::ForwardPropagator
        variable backward_prop  ;# ::tempo::sta::backward::BackwardPropagator

        variable setup_slacks   ;# dict: node_id -> float
        variable hold_slacks    ;# dict: node_id -> float

        constructor {tg c fwd_prop bwd_prop} {
            set timing_graph $tg
            set constraints $c
            set forward_prop $fwd_prop
            set backward_prop $bwd_prop
            my reset
        }

        method reset {} {
            set setup_slacks [dict create]
            set hold_slacks [dict create]
        }

        # Calculate slacks across all nodes
        method calculate {} {
            my reset
            set bg [$timing_graph get_graph]

            foreach nid [$bg all_nodes] {
                set arr [$forward_prop get_arrivals $nid]
                set rat [$backward_prop get_rats $nid]

                # Setup slack: RAT(late) - AT(late)
                set slk_setup_r [expr {[dict get $rat setup_r] - [dict get $arr late_r]}]
                set slk_setup_f [expr {[dict get $rat setup_f] - [dict get $arr late_f]}]
                set worst_setup [expr {min($slk_setup_r, $slk_setup_f)}]

                # Hold slack: AT(early) - RAT(hold)
                set slk_hold_r [expr {[dict get $arr early_r] - [dict get $rat hold_r]}]
                set slk_hold_f [expr {[dict get $arr early_f] - [dict get $rat hold_f]}]
                set worst_hold [expr {min($slk_hold_r, $slk_hold_f)}]

                dict set setup_slacks $nid $worst_setup
                dict set hold_slacks  $nid $worst_hold
            }
        }

        method get_setup_slack {node_id} {
            if {[dict exists $setup_slacks $node_id]} {
                return [dict get $setup_slacks $node_id]
            }
            return 0.0
        }

        method get_hold_slack {node_id} {
            if {[dict exists $hold_slacks $node_id]} {
                return [dict get $hold_slacks $node_id]
            }
            return 0.0
        }

        # Compute summary metrics across endpoints (WNS, TNS, FEP)
        method get_summary {} {
            set wns_setup 0.0
            set tns_setup 0.0
            set fep_setup 0

            set wns_hold 0.0
            set tns_hold 0.0
            set fep_hold 0

            set endpoint_reports [dict create]

            foreach ep [$timing_graph get_endpoints] {
                set nid [$timing_graph get_node_by_pin $ep]
                if {$nid eq ""} { continue }

                set s_setup [my get_setup_slack $nid]
                set s_hold  [my get_hold_slack $nid]

                dict set endpoint_reports $ep [dict create \
                    endpoint $ep \
                    setup_slack $s_setup \
                    hold_slack $s_hold]

                # Setup metrics
                if {$s_setup < 0.0} {
                    incr fep_setup
                    set tns_setup [expr {$tns_setup + $s_setup}]
                    if {$s_setup < $wns_setup} {
                        set wns_setup $s_setup
                    }
                }

                # Hold metrics
                if {$s_hold < 0.0} {
                    incr fep_hold
                    set tns_hold [expr {$tns_hold + $s_hold}]
                    if {$s_hold < $wns_hold} {
                        set wns_hold $s_hold
                    }
                }
            }

            return [dict create \
                setup_wns $wns_setup \
                setup_tns $tns_setup \
                setup_fep $fep_setup \
                hold_wns  $wns_hold \
                hold_tns  $tns_hold \
                hold_fep  $fep_hold \
                endpoints $endpoint_reports]
        }
    }
}
