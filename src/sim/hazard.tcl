# ==============================================================================
# Static and Dynamic Hazard Detection Engine
#
# Analyzes waveform transition histories to identify glitch hazards:
# 1. Static-1 Hazards (momentary 1 -> 0 -> 1 glitches)
# 2. Static-0 Hazards (momentary 0 -> 1 -> 0 glitches)
# 3. Dynamic Hazards (multiple transitions during a single logical edge)
# ==============================================================================

namespace eval ::tempo::sim::hazard {
    oo::class create HazardDetector {
        variable simulator
        variable glitch_window_ps

        constructor {sim {max_glitch_ps 30}} {
            set simulator $sim
            set glitch_window_ps $max_glitch_ps
        }

        # Scan simulation history and extract all hazards across all nets
        method detect_hazards {} {
            set history [$simulator get_history]
            set net_events [dict create]

            # Group events by net name
            foreach ev $history {
                dict lappend net_events [dict get $ev net] $ev
            }

            set hazards [list]

            dict for {net events} $net_events {
                set count [llength $events]
                if {$count < 2} { continue }

                # Scan consecutive transitions
                for {set i 0} {$i < [expr {$count - 1}]} {incr i} {
                    set ev1 [lindex $events $i]
                    set ev2 [lindex $events [expr {$i + 1}]]

                    set dt [expr {[dict get $ev2 time] - [dict get $ev1 time]}]
                    set v_initial [dict get $ev1 old_val]
                    set v_mid     [dict get $ev1 new_val]
                    set v_final   [dict get $ev2 new_val]

                    # Static-1 hazard: 1 -> 0 -> 1 within glitch window
                    if {$v_initial eq "1" && $v_mid eq "0" && $v_final eq "1" && $dt <= $glitch_window_ps} {
                        lappend hazards [dict create \
                            type "STATIC_1_HAZARD" \
                            net $net \
                            start_time [dict get $ev1 time] \
                            end_time [dict get $ev2 time] \
                            pulse_width_ps $dt]
                    }

                    # Static-0 hazard: 0 -> 1 -> 0 within glitch window
                    if {$v_initial eq "0" && $v_mid eq "1" && $v_final eq "0" && $dt <= $glitch_window_ps} {
                        lappend hazards [dict create \
                            type "STATIC_0_HAZARD" \
                            net $net \
                            start_time [dict get $ev1 time] \
                            end_time [dict get $ev2 time] \
                            pulse_width_ps $dt]
                    }

                    # Check for dynamic hazard: 3 transitions within 2 * glitch_window
                    if {$i + 2 < $count} {
                        set ev3 [lindex $events [expr {$i + 2}]]
                        set dt_total [expr {[dict get $ev3 time] - [dict get $ev1 time]}]
                        set v3 [dict get $ev3 new_val]

                        if {$v_initial ne $v3 && $v_mid eq $v3 && $dt_total <= [expr {2 * $glitch_window_ps}]} {
                            lappend hazards [dict create \
                                type "DYNAMIC_HAZARD" \
                                net $net \
                                start_time [dict get $ev1 time] \
                                end_time [dict get $ev3 time] \
                                total_duration_ps $dt_total]
                        }
                    }
                }
            }

            return $hazards
        }

        # Format human-readable hazard report
        method format_report {hazards} {
            set lines [list]
            lappend lines "================================================================================"
            lappend lines "TEMPO LOGIC HAZARD AND GLITCH AUDIT REPORT"
            lappend lines "================================================================================"
            lappend lines [format "%-20s %-25s %12s %12s" "Hazard Type" "Net Name" "Time (ps)" "Duration"]
            lappend lines "--------------------------------------------------------------------------------"

            if {[llength $hazards] == 0} {
                lappend lines "No logic hazards or glitch pulses detected. Circuit is race-free."
            } else {
                foreach h $hazards {
                    set dur [expr {[dict exists $h pulse_width_ps] ? [dict get $h pulse_width_ps] : [dict get $h total_duration_ps]}]
                    lappend lines [format "%-20s %-25s %12d %10d ps" \
                        [dict get $h type] \
                        [dict get $h net] \
                        [dict get $h start_time] \
                        $dur]
                }
            }
            lappend lines "================================================================================"
            return [join $lines "\n"]
        }
    }
}
