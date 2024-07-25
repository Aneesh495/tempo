# ==============================================================================
# Hold Violation Remediation Engine
#
# Fixes hold-time race conditions by inserting delay buffers on timing endpoints
# that exhibit negative early slack. Verifies that inserted buffer delay does
# not degrade late arrival time beyond setup slack limits.
# ==============================================================================

namespace eval ::tempo::opt::hold {
    oo::class create HoldFixer {
        variable netlist
        variable library
        variable slack_calc
        variable buffer_inserter
        variable fix_counter

        constructor {nl lib slk buf_ins} {
            set netlist $nl
            set library $lib
            set slack_calc $slk
            set buffer_inserter $buf_ins
            set fix_counter 0
        }

        # Scan all timing endpoints for negative hold slack and remediate
        method fix_hold_violations {{delay_buffer_cell "BUF_X1"} {margin_ps 10.0}} {
            set fixes [list]
            set hold_slacks [$slack_calc get_hold_slacks]

            dict for {nid hslk} $hold_slacks {
                if {$hslk < 0.0} {
                    # Check available setup slack at this node
                    set sslk [$slack_calc get_setup_slack $nid]
                    set needed_delay [expr {abs($hslk) + $margin_ps}]

                    # Only insert if setup slack can tolerate the delay insertion
                    if {$sslk > $needed_delay} {
                        # Resolve endpoint pin
                        set pin_name $nid
                        if {[string match "pin:*" $nid]} {
                            set pin_name [string range $nid 4 end]
                        }

                        set parts [split $pin_name "/"]
                        if {[llength $parts] == 2} {
                            set inst [lindex $parts 0]
                            set pin  [lindex $parts 1]

                            set net_name [$netlist get_pin_net $inst $pin]
                            if {$net_name ne ""} {
                                # Insert delay buffer
                                incr fix_counter
                                set new_buf "u_tempo_hold_fix_${fix_counter}"
                                set fix_net "${net_name}_holdfix_${fix_counter}"

                                $netlist add_net $fix_net
                                $netlist add_instance $new_buf $delay_buffer_cell

                                # Disconnect only this load pin from original net
                                $netlist disconnect_pin $inst $pin

                                # Connect buffer input to original net
                                $netlist connect_pin $new_buf "A" $net_name "LOAD"

                                # Connect buffer output to new net
                                $netlist connect_pin $new_buf "Y" $fix_net "DRIVER"

                                # Connect register D pin to new net
                                $netlist connect_pin $inst $pin $fix_net "LOAD"

                                lappend fixes [dict create \
                                    endpoint $pin_name \
                                    original_hold_slack $hslk \
                                    buffer_instance $new_buf \
                                    buffer_cell $delay_buffer_cell \
                                    status "FIXED"]
                            }
                        }
                    } else {
                        lappend fixes [dict create \
                            endpoint $nid \
                            original_hold_slack $hslk \
                            status "SKIPPED_SETUP_VIOLATION_RISK"]
                    }
                }
            }

            return $fixes
        }
    }
}
