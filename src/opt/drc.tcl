# ==============================================================================
# Design Rule Checking (DRC) Engine for Static Timing & Physical Synthesis
#
# Audits electrical design rules across standard cell instances and nets:
# 1. Maximum Transition (Slew) Time
# 2. Maximum Load Capacitance
# 3. Maximum Fanout Limit
# ==============================================================================

namespace eval ::tempo::opt::drc {
    oo::class create DRCChecker {
        variable netlist
        variable library
        variable constraints
        variable forward_prop
        variable timing_graph
        variable violations

        constructor {nl lib c fwd tg} {
            set netlist $nl
            set library $lib
            set constraints $c
            set forward_prop $fwd
            set timing_graph $tg
            set violations [list]
        }

        # Run comprehensive DRC audit across all instances and ports
        method check_all {} {
            set violations [list]
            my check_max_transition
            my check_max_capacitance
            my check_max_fanout
            return $violations
        }

        # Check maximum transition (slew) limits
        method check_max_transition {} {
            set default_max_trans 100.0 ;# default 100 ps max slew if not specified

            foreach nid [$timing_graph get_nodes] {
                set slw [$forward_prop get_slews $nid]
                set max_slew [expr {max([dict get $slw late_r], [dict get $slw late_f])}]
                
                # In netlist, determine if port or pin
                set limit $default_max_trans
                set pin_name $nid
                if {[string match "port:*" $nid]} {
                    set pin_name [string range $nid 5 end]
                } elseif {[string match "pin:*" $nid]} {
                    set pin_name [string range $nid 4 end]
                }

                if {$max_slew > $limit} {
                    lappend violations [dict create \
                        rule "max_transition" \
                        pin $pin_name \
                        actual $max_slew \
                        limit $limit \
                        slack [expr {$limit - $max_slew}]]
                }
            }
        }

        # Check maximum capacitive load limits on driving pins
        method check_max_capacitance {} {
            set default_max_cap 0.15 ;# default 0.15 pF (150 fF) limit

            foreach inst_name [$netlist get_instance_names] {
                set cell_name [$netlist get_cell_name $inst_name]
                set cell_info [$library get_cell $cell_name]
                if {$cell_info eq ""} { continue }

                set pins [dict get $cell_info pins]
                foreach {pin_name pinfo} $pins {
                    if {[dict get $pinfo direction] ne "output"} { continue }

                    # Calculate total capacitive load driven by this pin
                    set total_cap 0.0
                    set net_name [$netlist get_pin_net $inst_name $pin_name]
                    if {$net_name ne ""} {
                        set loads [$netlist get_net_loads $net_name]
                        foreach ld $loads {
                            set parts [split $ld "/"]
                            set ld_inst [lindex $parts 0]
                            set ld_pin  [lindex $parts 1]
                            set ld_cell [$netlist get_cell_name $ld_inst]
                            set ld_cinfo [$library get_cell $ld_cell]
                            if {$ld_cinfo ne ""} {
                                set ld_pins [dict get $ld_cinfo pins]
                                if {[dict exists $ld_pins $ld_pin]} {
                                    set total_cap [expr {$total_cap + [dict get $ld_pins $ld_pin capacitance]}]
                                }
                            }
                        }
                    }

                    set limit $default_max_cap
                    if {[dict exists $pinfo max_capacitance]} {
                        set limit [dict get $pinfo max_capacitance]
                    }

                    if {$total_cap > $limit} {
                        lappend violations [dict create \
                            rule "max_capacitance" \
                            pin "$inst_name/$pin_name" \
                            actual $total_cap \
                            limit $limit \
                            slack [expr {$limit - $total_cap}]]
                    }
                }
            }
        }

        # Check maximum fanout count limits on driving pins
        method check_max_fanout {} {
            set default_max_fanout 16 ;# default max fanout of 16 loads

            foreach inst_name [$netlist get_instance_names] {
                set cell_name [$netlist get_cell_name $inst_name]
                set cell_info [$library get_cell $cell_name]
                if {$cell_info eq ""} { continue }

                set pins [dict get $cell_info pins]
                foreach {pin_name pinfo} $pins {
                    if {[dict get $pinfo direction] ne "output"} { continue }

                    set net_name [$netlist get_pin_net $inst_name $pin_name]
                    set fanout 0
                    if {$net_name ne ""} {
                        set fanout [llength [$netlist get_net_loads $net_name]]
                    }

                    set limit $default_max_fanout
                    if {$fanout > $limit} {
                        lappend violations [dict create \
                            rule "max_fanout" \
                            pin "$inst_name/$pin_name" \
                            actual $fanout \
                            limit $limit \
                            slack [expr {$limit - $fanout}]]
                    }
                }
            }
        }

        method get_violations {} {
            return $violations
        }

        # Format tabular DRC report
        method format_report {} {
            set lines [list]
            lappend lines "================================================================================"
            lappend lines "TEMPO DESIGN RULE CHECK (DRC) REPORT"
            lappend lines "================================================================================"
            lappend lines [format "%-18s %-30s %10s %10s %10s" "Rule" "Pin / Net" "Actual" "Limit" "Slack"]
            lappend lines "--------------------------------------------------------------------------------"

            if {[llength $violations] == 0} {
                lappend lines "No design rule violations detected. All electrical constraints MET."
            } else {
                foreach v $violations {
                    lappend lines [format "%-18s %-30s %10.3f %10.3f %10.3f" \
                        [dict get $v rule] \
                        [dict get $v pin] \
                        [dict get $v actual] \
                        [dict get $v limit] \
                        [dict get $v slack]]
                }
            }
            lappend lines "================================================================================"
            return [join $lines "\n"]
        }
    }
}
