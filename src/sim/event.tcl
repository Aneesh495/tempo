# ==============================================================================
# Discrete Event Queue for Gate-Level Logic Simulation
#
# Implements a min-priority event scheduler ordered by simulation timestamp (ps).
# Supports event insertion, peak extraction, event cancellation for inertial
# glitch filtering, and query operations.
# ==============================================================================

namespace eval ::tempo::sim::event {
    oo::class create EventQueue {
        variable events     ;# list of dicts: [dict create time $t target $pin value $v id $id]
        variable event_id_counter

        constructor {} {
            my reset
        }

        method reset {} {
            set events [list]
            set event_id_counter 0
        }

        method is_empty {} {
            return [expr {[llength $events] == 0}]
        }

        method size {} {
            return [llength $events]
        }

        # Schedule an event at a future simulation time (in ps)
        method schedule {sim_time target value} {
            incr event_id_counter
            set ev [dict create \
                id $event_id_counter \
                time [expr {$sim_time + 0}] \
                target $target \
                value $value]

            # Linear insertion into sorted list (efficient for discrete event STA/sim)
            set inserted 0
            set new_events [list]
            set len [llength $events]

            for {set i 0} {$i < $len} {incr i} {
                set cur [lindex $events $i]
                if {!$inserted && [dict get $ev time] < [dict get $cur time]} {
                    lappend new_events $ev
                    set inserted 1
                }
                lappend new_events $cur
            }
            if {!$inserted} {
                lappend new_events $ev
            }

            set events $new_events
            return $event_id_counter
        }

        # Cancel any pending events scheduled for a specific target pin/net
        # Used for inertial delay glitch suppression
        method cancel_pending_for {target} {
            set remaining [list]
            set cancelled [list]
            foreach ev $events {
                if {[dict get $ev target] eq $target} {
                    lappend cancelled $ev
                } else {
                    lappend remaining $ev
                }
            }
            set events $remaining
            return $cancelled
        }

        # Peek at next timestamp
        method next_time {} {
            if {[llength $events] == 0} { return -1 }
            return [dict get [lindex $events 0] time]
        }

        # Pop all events occurring at the earliest timestamp
        method pop_current_events {} {
            if {[llength $events] == 0} { return [list] }

            set earliest_time [dict get [lindex $events 0] time]
            set ready [list]
            set remaining [list]

            foreach ev $events {
                if {[dict get $ev time] == $earliest_time} {
                    lappend ready $ev
                } else {
                    lappend remaining $ev
                }
            }

            set events $remaining
            return [list $earliest_time $ready]
        }
    }
}
