# Tempo Netlist Logic Restructuring and Peephole Optimization Engine
# Performs inverter-pair cancellation, buffer collapse, and dead gate elimination
# Namespace: ::tempo::synth::opt

namespace eval ::tempo::synth::opt {

    # Main netlist cleanup and optimization routine
    proc optimize_netlist {netlist} {
        set total_removed 0

        # Iteratively apply transformations until convergence (fixed point)
        set changed 1
        set passes 0
        while {$changed && $passes < 10} {
            set changed 0
            incr passes

            # 1. Eliminate dead gates (gates with 0 loads that are not primary outputs)
            set dead_count [_eliminate_dead_gates $netlist]
            if {$dead_count > 0} {
                set changed 1
                incr total_removed $dead_count
            }

            # 2. Cancel back-to-back inverters (INV -> INV)
            set inv_count [_cancel_inverter_pairs $netlist]
            if {$inv_count > 0} {
                set changed 1
                incr total_removed $inv_count
            }

            # 3. Collapse redundant single-fanout buffers
            set buf_count [_collapse_redundant_buffers $netlist]
            if {$buf_count > 0} {
                set changed 1
                incr total_removed $buf_count
            }
        }

        return [dict create \
            passes $passes \
            gates_eliminated $total_removed \
            final_stats [$netlist get_stats]]
    }

    # Eliminate gates with 0 fanout loads
    proc _eliminate_dead_gates {netlist} {
        set removed 0
        set po_list [$netlist get_ports "OUTPUT"]

        foreach inst [$netlist get_instances] {
            set pins [$netlist get_instance_pins $inst]
            if {![dict exists $pins "Y"]} { continue }

            set out_net [dict get $pins "Y"]
            # If out_net is a primary output, cannot remove
            if {$out_net in $po_list} { continue }

            set loads [$netlist get_net_loads $out_net]
            if {[llength $loads] == 0} {
                $netlist remove_instance $inst
                incr removed
            }
        }
        return $removed
    }

    # Cancel back-to-back inverters: A -> [INV1] -> mid -> [INV2] -> Y
    # Turns into A -> Y directly if mid has fanout == 1
    proc _cancel_inverter_pairs {netlist} {
        set removed 0
        set po_list [$netlist get_ports "OUTPUT"]

        foreach inst1 [$netlist get_instances] {
            if {![$netlist has_instance $inst1]} { continue }
            set cell1 [$netlist get_instance_cell $inst1]
            if {![string match "INV*" $cell1]} { continue }

            set pins1 [$netlist get_instance_pins $inst1]
            if {![dict exists $pins1 "A"] || ![dict exists $pins1 "Y"]} { continue }

            set in_net [dict get $pins1 "A"]
            set mid_net [dict get $pins1 "Y"]

            # If mid_net is primary output, cannot collapse
            if {$mid_net in $po_list} { continue }

            set loads [$netlist get_net_loads $mid_net]
            # Only collapse if mid_net drives exactly 1 gate
            if {[llength $loads] != 1} { continue }

            set load_ref [lindex $loads 0]
            set parts [split $load_ref "/"]
            set inst2 [lindex $parts 0]
            set pin2 [lindex $parts 1]

            if {![$netlist has_instance $inst2]} { continue }
            set cell2 [$netlist get_instance_cell $inst2]
            if {![string match "INV*" $cell2]} { continue }

            set pins2 [$netlist get_instance_pins $inst2]
            if {![dict exists $pins2 "Y"]} { continue }
            set out_net [dict get $pins2 "Y"]

            # Rewire all loads of out_net to in_net
            set out_loads [$netlist get_net_loads $out_net]
            foreach lref $out_loads {
                set lparts [split $lref "/"]
                set l_inst [lindex $lparts 0]
                set l_pin [lindex $lparts 1]
                $netlist disconnect_pin $l_inst $l_pin
                $netlist connect_pin $l_inst $l_pin $in_net "LOAD"
            }

            # If out_net is a primary output, insert a buffer from in_net to out_net
            if {$out_net in $po_list} {
                set buf_inst "u_bypass_${inst1}_${inst2}"
                $netlist add_instance $buf_inst "BUF_X1"
                $netlist connect_pin $buf_inst "A" $in_net "LOAD"
                $netlist connect_pin $buf_inst "Y" $out_net "DRIVER"
            }

            $netlist remove_instance $inst1
            $netlist remove_instance $inst2
            incr removed 2
        }
        return $removed
    }

    # Collapse simple buffer: in -> [BUF] -> out
    proc _collapse_redundant_buffers {netlist} {
        set removed 0
        set po_list [$netlist get_ports "OUTPUT"]

        foreach inst [$netlist get_instances] {
            if {![$netlist has_instance $inst]} { continue }
            set cell [$netlist get_instance_cell $inst]
            if {![string match "BUF*" $cell]} { continue }

            set pins [$netlist get_instance_pins $inst]
            if {![dict exists $pins "A"] || ![dict exists $pins "Y"]} { continue }

            set in_net [dict get $pins "A"]
            set out_net [dict get $pins "Y"]

            if {$out_net in $po_list} { continue }

            set out_loads [$netlist get_net_loads $out_net]
            foreach lref $out_loads {
                set lparts [split $lref "/"]
                set l_inst [lindex $lparts 0]
                set l_pin [lindex $lparts 1]
                $netlist disconnect_pin $l_inst $l_pin
                $netlist connect_pin $l_inst $l_pin $in_net "LOAD"
            }

            $netlist remove_instance $inst
            incr removed
        }
        return $removed
    }
}
