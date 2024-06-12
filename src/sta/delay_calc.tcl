# Tempo Static Timing Analysis Delay Calculation Engine
# Computes cell delay, output transition, and capacitive loads using Liberty NLDM
# Namespace: ::tempo::sta::delay

namespace eval ::tempo::sta::delay {

    # Calculate total capacitive load on a net (in femtofarads fF or library unit)
    proc calculate_net_load {netlist library spef constraints net_name} {
        set total_cap 0.0

        # 1. Sum load pin input capacitances from standard cell library
        set loads [$netlist get_net_loads $net_name]
        foreach lref $loads {
            set parts [split $lref "/"]
            set inst [lindex $parts 0]
            set pin [lindex $parts 1]
            if {[$netlist has_instance $inst]} {
                set cell_type [$netlist get_instance_cell $inst]
                if {[$library has_cell $cell_type]} {
                    set cinfo [$library get_cell $cell_type]
                    set pins [dict get $cinfo pins]
                    if {[dict exists $pins $pin]} {
                        set pcap [dict get [dict get $pins $pin] capacitance]
                        set total_cap [expr {$total_cap + $pcap}]
                    }
                }
            }
        }

        # 2. Add wire parasitic capacitance from SPEF if available
        if {$spef ne "" && [info object isa typeof $spef ::tempo::spef::SpefNetwork]} {
            if {[$spef has_net $net_name]} {
                set wire_cap [$spef get_net_cap $net_name]
                set total_cap [expr {$total_cap + $wire_cap}]
            }
        } else {
            # Add netlist intrinsic wire cap
            set total_cap [expr {$total_cap + [$netlist get_net_cap $net_name]}]
        }

        # 3. Add primary output external load if constrained
        if {$constraints ne "" && [$netlist has_port $net_name]} {
            set pinfo [$netlist get_port_info $net_name]
            if {[dict get $pinfo dir] eq "OUTPUT"} {
                set ext_load [$constraints get_load $net_name 0.0]
                set total_cap [expr {$total_cap + $ext_load}]
            }
        }

        return $total_cap
    }

    # Evaluate cell arc propagation delay and output slews
    # Returns dict: cell_rise, cell_fall, rise_slew, fall_slew, total_cap
    proc compute_cell_arc_delay {library cell_type out_pin in_pin in_trans_ps out_cap_ff} {
        # Check if library has cell
        if {![$library has_cell $cell_type]} {
            # Linear default delay model fallback
            set d_rise [expr {20.0 + 0.05 * $out_cap_ff}]
            set d_fall [expr {18.0 + 0.04 * $out_cap_ff}]
            set s_rise [expr {15.0 + 0.03 * $out_cap_ff}]
            set s_fall [expr {14.0 + 0.03 * $out_cap_ff}]
            return [dict create \
                cell_rise $d_rise \
                cell_fall $d_fall \
                rise_slew $s_rise \
                fall_slew $s_fall \
                total_cap $out_cap_ff]
        }

        set d_rise [$library lookup_delay $cell_type $out_pin $in_pin $in_trans_ps $out_cap_ff "cell_rise"]
        set d_fall [$library lookup_delay $cell_type $out_pin $in_pin $in_trans_ps $out_cap_ff "cell_fall"]
        set s_rise [$library lookup_slew  $cell_type $out_pin $in_pin $in_trans_ps $out_cap_ff "rise_transition"]
        set s_fall [$library lookup_slew  $cell_type $out_pin $in_pin $in_trans_ps $out_cap_ff "fall_transition"]

        # Ensure sensible positive values
        if {$d_rise <= 0.0} { set d_rise [expr {15.0 + 0.04 * $out_cap_ff}] }
        if {$d_fall <= 0.0} { set d_fall [expr {14.0 + 0.04 * $out_cap_ff}] }
        if {$s_rise <= 0.0} { set s_rise [expr {10.0 + 0.02 * $out_cap_ff}] }
        if {$s_fall <= 0.0} { set s_fall [expr {10.0 + 0.02 * $out_cap_ff}] }

        return [dict create \
            cell_rise $d_rise \
            cell_fall $d_fall \
            rise_slew $s_rise \
            fall_slew $s_fall \
            total_cap $out_cap_ff]
    }

    # Evaluate sequential setup and hold constraints for register D pin
    proc compute_seq_constraints {library cell_type data_trans_ps clk_trans_ps} {
        set setup_ps 30.0
        set hold_ps 10.0

        if {[$library has_cell $cell_type]} {
            set s_val [$library lookup_delay $cell_type "D" "CK" $data_trans_ps $clk_trans_ps "rise_constraint"]
            if {$s_val > 0.0} {
                set setup_ps $s_val
            }
        }

        return [dict create \
            setup_time $setup_ps \
            hold_time  $hold_ps]
    }
}
