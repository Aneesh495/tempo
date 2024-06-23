# Tempo Static Timing Analysis Critical Path Extractor and Report Formatter
# Backtracks critical timing paths and renders industry-standard timing reports
# Namespace: ::tempo::sta::report

namespace eval ::tempo::sta::report {

    oo::class create PathExtractor {
        variable timing_graph   ;# ::tempo::sta::graph::TimingGraph
        variable netlist        ;# ::tempo::netlist::Netlist
        variable library        ;# ::tempo::liberty::Library
        variable constraints    ;# ::tempo::sdc::Constraints
        variable forward_prop   ;# ::tempo::sta::forward::ForwardPropagator
        variable backward_prop  ;# ::tempo::sta::backward::BackwardPropagator
        variable slack_calc     ;# ::tempo::sta::slack::SlackCalculator

        constructor {tg nl lib c fwd_prop bwd_prop slk_calc} {
            set timing_graph $tg
            set netlist $nl
            set library $lib
            set constraints $c
            set forward_prop $fwd_prop
            set backward_prop $bwd_prop
            set slack_calc $slk_calc
        }

        # Extract top-N critical paths (sorted by worst slack)
        method get_critical_paths {{num_paths 1} {delay_type "max"}} {
            set bg [$timing_graph get_graph]
            set summary [$slack_calc get_summary]
            set endpoints_dict [dict get $summary endpoints]

            # Sort endpoints by worst slack
            set ep_list [dict keys $endpoints_dict]
            set sorted_eps [lsort -command [list my _compare_slacks $endpoints_dict $delay_type] $ep_list]

            set path_reports [list]
            set count 0

            foreach ep $sorted_eps {
                if {$count >= $num_paths} { break }
                set pinfo [my _backtrack_path $ep $delay_type]
                lappend path_reports $pinfo
                incr count
            }

            return $path_reports
        }

        method _compare_slacks {endpoints_dict delay_type ep1 ep2} {
            set s1 0.0
            set s2 0.0
            if {$delay_type eq "max"} {
                set s1 [dict get [dict get $endpoints_dict $ep1] setup_slack]
                set s2 [dict get [dict get $endpoints_dict $ep2] setup_slack]
            } else {
                set s1 [dict get [dict get $endpoints_dict $ep1] hold_slack]
                set s2 [dict get [dict get $endpoints_dict $ep2] hold_slack]
            }
            if {$s1 < $s2} { return -1 }
            if {$s1 > $s2} { return 1 }
            return 0
        }

        method _backtrack_path {endpoint delay_type} {
            set bg [$timing_graph get_graph]
            set curr_nid [$timing_graph get_node_by_pin $endpoint]

            set path_nodes [list $curr_nid]
            set visited [dict create $curr_nid 1]

            # Backtrack to startpoint along worst slack in-edge
            while {1} {
                set in_edges [$bg get_in_edges $curr_nid]
                if {[llength $in_edges] == 0} { break }

                set best_pred ""
                set worst_pred_slack 1.0e30

                foreach eid $in_edges {
                    set pred [$bg get_edge $eid]
                    set u [dict get $pred src]
                    set slk [expr {$delay_type eq "max" ? [$slack_calc get_setup_slack $u] : [$slack_calc get_hold_slack $u]}]

                    if {$slk < $worst_pred_slack} {
                        set worst_pred_slack $slk
                        set best_pred $u
                    }
                }

                if {$best_pred eq "" || [dict exists $visited $best_pred]} {
                    break
                }

                set curr_nid $best_pred
                dict set visited $curr_nid 1
                set path_nodes [linsert $path_nodes 0 $curr_nid]
            }

            # Gather detailed segment data along path
            set start_nid [lindex $path_nodes 0]
            set end_nid [lindex $path_nodes end]

            set start_pin [my _node_to_pin_name $start_nid]
            set end_pin   [my _node_to_pin_name $end_nid]

            set total_arr [expr {$delay_type eq "max" ? [dict get [$forward_prop get_arrivals $end_nid] late_r] : [dict get [$forward_prop get_arrivals $end_nid] early_r]}]
            set total_req [expr {$delay_type eq "max" ? [dict get [$backward_prop get_rats $end_nid] setup_r] : [dict get [$backward_prop get_rats $end_nid] hold_r]}]
            set slack [expr {$delay_type eq "max" ? [$slack_calc get_setup_slack $end_nid] : [$slack_calc get_hold_slack $end_nid]}]

            return [dict create \
                endpoint $end_pin \
                startpoint $start_pin \
                path_type $delay_type \
                arrival_time $total_arr \
                required_time $total_req \
                slack $slack \
                nodes $path_nodes]
        }

        # Format human-readable ASCII timing report
        method format_report {{num_paths 1} {delay_type "max"}} {
            set paths [my get_critical_paths $num_paths $delay_type]
            set lines [list]

            lappend lines "================================================================================"
            lappend lines "TEMPO STATIC TIMING ANALYSIS REPORT"
            lappend lines "Delay Type: $delay_type"
            lappend lines "================================================================================"

            set path_idx 1
            foreach p $paths {
                set slk [dict get $p slack]
                set status [expr {$slk >= 0.0 ? "MET" : "VIOLATED"}]

                lappend lines [format "Path %d: \[%s\] Slack = %.3f ps (%.4f ns)" $path_idx $status $slk [expr {$slk / 1000.0}]]
                lappend lines [format "  Startpoint: %s" [dict get $p startpoint]]
                lappend lines [format "  Endpoint:   %s" [dict get $p endpoint]]
                lappend lines [format "  Data Arrival Time:  %.3f ps" [dict get $p arrival_time]]
                lappend lines [format "  Data Required Time: %.3f ps" [dict get $p required_time]]
                lappend lines "--------------------------------------------------------------------------------"
                lappend lines [format "%-35s %-12s %-10s %-10s" "Pin" "Type" "Incr" "Total"]
                lappend lines "--------------------------------------------------------------------------------"

                set prev_arr 0.0
                foreach nid [dict get $p nodes] {
                    set pname [my _node_to_pin_name $nid]
                    set cur_arr [expr {$delay_type eq "max" ? [dict get [$forward_prop get_arrivals $nid] late_r] : [dict get [$forward_prop get_arrivals $nid] early_r]}]
                    set incr_d [expr {max(0.0, $cur_arr - $prev_arr)}]
                    set prev_arr $cur_arr

                    lappend lines [format "%-35s %-12s %10.3f %10.3f" $pname "pin" $incr_d $cur_arr]
                }

                lappend lines "--------------------------------------------------------------------------------"
                lappend lines [format "%-35s %34.3f" "slack ($status)" $slk]
                lappend lines "================================================================================"
                incr path_idx
            }

            return [join $lines "\n"]
        }

        method _node_to_pin_name {nid} {
            if {[string match "port:*" $nid]} {
                return [string range $nid 5 end]
            }
            if {[string match "pin:*" $nid]} {
                return [string range $nid 4 end]
            }
            return $nid
        }
    }

    proc _node_to_pin_name {nid} {
        if {[string match "port:*" $nid]} {
            return [string range $nid 5 end]
        }
        if {[string match "pin:*" $nid]} {
            return [string range $nid 4 end]
        }
        return $nid
    }
}
