# ==============================================================================
# Event-Driven 4-State Gate-Level Logic Simulator
#
# Simulates IEEE 1364 4-state (0, 1, X, Z) digital logic with inertial and
# transport gate delays, rising-edge D flip-flops, testbench stimulus injection,
# and value change history tracking.
# ==============================================================================

namespace eval ::tempo::sim {
    oo::class create Simulator {
        variable netlist
        variable library
        variable queue
        variable current_time
        variable net_values         ;# dict: net_name -> "0"|"1"|"X"|"Z"
        variable reg_states         ;# dict: inst_name -> "0"|"1"|"X"
        variable clk_prev           ;# dict: clk_pin -> "0"|"1"
        variable change_history     ;# list of [dict create time $t net $net old_val $o new_val $n]
        variable default_gate_delay ;# in ps
        variable clamped_nets       ;# dict: net_name -> stuck_val

        constructor {nl lib {def_delay 15}} {
            set netlist $nl
            set library $lib
            set default_gate_delay $def_delay
            set queue [::tempo::sim::event::EventQueue new]
            my reset
        }

        destructor {
            if {[info exists queue] && [info object is object $queue]} {
                $queue destroy
            }
        }

        # Initialize or reset all nets and flip-flops to unknown state X
        method reset {} {
            set current_time 0
            set net_values [dict create]
            set reg_states [dict create]
            set clk_prev [dict create]
            set change_history [list]
            set clamped_nets [dict create]
            $queue reset

            foreach net [$netlist get_nets] {
                dict set net_values $net "X"
            }
            foreach port [$netlist get_ports] {
                dict set net_values $port "X"
            }
            foreach inst [$netlist get_instance_names] {
                dict set reg_states $inst "X"
            }
        }

        method get_current_time {} {
            return $current_time
        }

        method get_net_value {net_name} {
            if {[dict exists $net_values $net_name]} {
                return [dict get $net_values $net_name]
            }
            return "X"
        }

        method get_history {} {
            return $change_history
        }

        # Inject input stimulus from testbench
        method schedule_input {sim_time port_name val} {
            $queue schedule $sim_time $port_name $val
        }

        # Schedule periodic clock signal
        method schedule_clock {port_name period_ps {stop_time_ps 10000}} {
            set half_period [expr {$period_ps / 2}]
            set t 0
            set val "0"
            while {$t <= $stop_time_ps} {
                $queue schedule $t $port_name $val
                set val [expr {$val eq "0" ? "1" : "0"}]
                incr t $half_period
            }
        }

        # Evaluate 4-state Boolean logic function for a combinational standard cell
        method _eval_cell_function {cell_type pin_inputs} {
            set cinfo [$library get_cell $cell_type]
            set func ""
            if {$cinfo ne ""} {
                set pins [dict get $cinfo pins]
                foreach {pname pinfo} $pins {
                    if {[dict get $pinfo direction] eq "output" && [dict exists $pinfo function]} {
                        set func [dict get $pinfo function]
                        break
                    }
                }
            }

            # Normalize function string and evaluate common primitives
            if {[string match "*!*A*" $func] && ![string match "*&*" $func] && ![string match "*|*" $func]} {
                # Inverter
                set a [dict get $pin_inputs "A"]
                if {$a eq "0"} { return "1" }
                if {$a eq "1"} { return "0" }
                return "X"
            }

            if {[string match "*!(A & B)*" $func] || [string match "*!*A*&*B*" $func]} {
                # NAND2
                set a [dict get $pin_inputs "A"]
                set b [dict get $pin_inputs "B"]
                if {$a eq "0" || $b eq "0"} { return "1" }
                if {$a eq "1" && $b eq "1"} { return "0" }
                return "X"
            }

            if {[string match "*!(A | B)*" $func]} {
                # NOR2
                set a [dict get $pin_inputs "A"]
                set b [dict get $pin_inputs "B"]
                if {$a eq "1" || $b eq "1"} { return "0" }
                if {$a eq "0" && $b eq "0"} { return "1" }
                return "X"
            }

            if {[string match "*A & B*" $func]} {
                # AND2
                set a [dict get $pin_inputs "A"]
                set b [dict get $pin_inputs "B"]
                if {$a eq "0" || $b eq "0"} { return "0" }
                if {$a eq "1" && $b eq "1"} { return "1" }
                return "X"
            }

            if {[string match "*A | B*" $func]} {
                # OR2
                set a [dict get $pin_inputs "A"]
                set b [dict get $pin_inputs "B"]
                if {$a eq "1" || $b eq "1"} { return "1" }
                if {$a eq "0" && $b eq "0"} { return "0" }
                return "X"
            }

            if {[string match "*A ^ B*" $func]} {
                # XOR2
                set a [dict get $pin_inputs "A"]
                set b [dict get $pin_inputs "B"]
                if {$a in {X Z} || $b in {X Z}} { return "X" }
                return [expr {$a ne $b ? "1" : "0"}]
            }

            # Buffer fallback: output follows input A
            if {[dict exists $pin_inputs "A"]} {
                return [dict get $pin_inputs "A"]
            }
            return "X"
        }

        # Clamp a net permanently to a stuck-at value (for fault simulation)
        method clamp_net {net_name val} {
            dict set clamped_nets $net_name $val
            dict set net_values $net_name $val
            my _propagate_net_event $net_name
        }

        # Execute simulation up to stop_time_ps
        method run {stop_time_ps} {
            while {![$queue is_empty]} {
                set next_t [$queue next_time]
                if {$next_t > $stop_time_ps} {
                    break
                }

                lassign [$queue pop_current_events] sim_t current_events
                set current_time $sim_t

                foreach ev $current_events {
                    set target [dict get $ev target]
                    if {[dict exists $clamped_nets $target]} {
                        continue
                    }
                    set new_val [dict get $ev value]
                    set old_val "X"
                    if {[dict exists $net_values $target]} {
                        set old_val [dict get $net_values $target]
                    }

                    if {$old_val ne $new_val} {
                        dict set net_values $target $new_val
                        lappend change_history [dict create \
                            time $current_time \
                            net $target \
                            old_val $old_val \
                            new_val $new_val]

                        # Propagate change to fanout load instances
                        my _propagate_net_event $target
                    }
                }
            }
        }

        # Propagate an updated net value through driven standard cells
        method _propagate_net_event {net_name} {
            set loads [$netlist get_net_loads $net_name]
            foreach ld $loads {
                set parts [split $ld "/"]
                set inst [lindex $parts 0]
                set in_pin [lindex $parts 1]

                set cell_type [$netlist get_cell_name $inst]
                set cinfo [$library get_cell $cell_type]
                set is_seq 0
                if {$cinfo ne "" && [dict exists $cinfo is_sequential]} {
                    set is_seq [dict get $cinfo is_sequential]
                }

                if {$is_seq} {
                    # Sequential cell: check if trigger pin is clock
                    set is_clock_pin 0
                    if {$in_pin eq "CK" || $in_pin eq "CLK"} {
                        set is_clock_pin 1
                    }

                    if {$is_clock_pin} {
                        set cur_clk [my get_net_value $net_name]
                        set pclk "0"
                        if {[dict exists $clk_prev "$inst/$in_pin"]} {
                            set pclk [dict get $clk_prev "$inst/$in_pin"]
                        }
                        dict set clk_prev "$inst/$in_pin" $cur_clk

                        # Check for rising edge: 0 -> 1
                        if {$pclk eq "0" && $cur_clk eq "1"} {
                            # Sample D input
                            set d_net [$netlist get_pin_net $inst "D"]
                            set d_val [my get_net_value $d_net]
                            dict set reg_states $inst $d_val

                            # Schedule Q output update after clock-to-q delay
                            set q_net [$netlist get_pin_net $inst "Q"]
                            if {$q_net ne ""} {
                                set ev_time [expr {$current_time + $default_gate_delay}]
                                $queue cancel_pending_for $q_net
                                $queue schedule $ev_time $q_net $d_val
                            }
                        }
                    }
                } else {
                    # Combinational cell: gather all input pin values
                    set pin_vals [dict create]
                    set ipins [$netlist get_instance_pins $inst]
                    dict for {pname pnet} $ipins {
                        dict set pin_vals $pname [my get_net_value $pnet]
                    }

                    set out_val [my _eval_cell_function $cell_type $pin_vals]
                    
                    # Find output pin and driving net
                    set out_net ""
                    if {$cinfo ne ""} {
                        dict for {pname pinfo} [dict get $cinfo pins] {
                            if {[dict get $pinfo direction] eq "output"} {
                                set out_net [$netlist get_pin_net $inst $pname]
                                break
                            }
                        }
                    }
                    if {$out_net eq ""} {
                        set out_net [$netlist get_pin_net $inst "Y"]
                    }

                    if {$out_net ne ""} {
                        set ev_time [expr {$current_time + $default_gate_delay}]
                        # Inertial delay: cancel sub-delay pending glitches
                        $queue cancel_pending_for $out_net
                        $queue schedule $ev_time $out_net $out_val
                    }
                }
            }
        }
    }
}
