# ==============================================================================
# PODEM (Path-Oriented Decision Making) ATPG Algorithm
#
# Generates deterministic test vectors for single stuck-at faults using Goel's
# PODEM algorithm. Makes all decision assignments strictly at Primary Inputs (PIs)
# with goal-directed backtracing and Roth 5-state D-calculus propagation.
# ==============================================================================

namespace eval ::tempo::fault::podem {
    oo::class create PodemATPG {
        variable netlist
        variable library
        variable target_fault
        variable pi_assignments     ;# dict: port -> "0"|"1"
        variable max_backtracks

        constructor {nl lib {backtracks 100}} {
            set netlist $nl
            set library $lib
            set max_backtracks $backtracks
            set pi_assignments [dict create]
        }

        # Generate a test vector for a specific single stuck-at fault
        # fault: [dict create net $n type "SA0"|"SA1"]
        method generate_test {fault} {
            set target_fault $fault
            set pi_assignments [dict create]
            set inputs [$netlist get_ports "INPUT"]

            # Initialize all PIs to unassigned (X)
            foreach pi $inputs {
                dict set pi_assignments $pi "X"
            }

            # Run recursive PODEM search
            set success [my _podem_search 0]
            if {$success} {
                # Fill any remaining don't-care (X) inputs with '0'
                set test_vec [dict create]
                foreach pi $inputs {
                    set v [dict get $pi_assignments $pi]
                    if {$v eq "X"} { set v "0" }
                    dict set test_vec $pi $v
                }
                return [dict create status "SUCCESS" fault $fault vector $test_vec]
            }

            return [dict create status "UNTESTABLE" fault $fault vector [dict create]]
        }

        # Recursive PODEM solver
        method _podem_search {depth} {
            if {$depth > $max_backtracks} { return 0 }

            # Evaluate circuit under current PI assignments with Roth 5-state calculus
            set sim_state [my _simulate_5state]

            # Check if fault is detected at any primary output (D or D_BAR reached PO)
            foreach po [$netlist get_ports "OUTPUT"] {
                if {[dict exists $sim_state $po]} {
                    set po_val [dict get $sim_state $po]
                    if {$po_val eq "D" || $po_val eq "D_BAR"} {
                        return 1 ;# Test generated successfully!
                    }
                }
            }

            # Determine objective: activation or propagation
            lassign [my _get_objective $sim_state] obj_node obj_val
            if {$obj_node eq ""} {
                return 0
            }

            # Backtrace from objective node to an unassigned primary input
            lassign [my _backtrace $obj_node $obj_val] chosen_pi pi_val
            if {$chosen_pi eq ""} {
                return 0
            }

            # Branch 1: Try chosen PI value
            dict set pi_assignments $chosen_pi $pi_val
            if {[my _podem_search [expr {$depth + 1}]]} {
                return 1
            }

            # Branch 2: Backtrack and try complement value
            set comp_val [expr {$pi_val eq "1" ? "0" : "1"}]
            dict set pi_assignments $chosen_pi $comp_val
            if {[my _podem_search [expr {$depth + 1}]]} {
                return 1
            }

            # Restore to unassigned
            dict set pi_assignments $chosen_pi "X"
            return 0
        }

        # Determine next objective for PODEM
        method _get_objective {sim_state} {
            set target_net [dict get $target_fault net]
            set f_type     [dict get $target_fault type]

            # Step 1: Fault activation objective
            # If target net is not yet activated (i.e., not D or D_BAR)
            set cur_val "X"
            if {[dict exists $sim_state $target_net]} {
                set cur_val [dict get $sim_state $target_net]
            }

            if {$cur_val ne "D" && $cur_val ne "D_BAR"} {
                # To activate SA0, target value is 1 (producing D)
                # To activate SA1, target value is 0 (producing D_BAR)
                set needed_val [expr {$f_type eq "SA0" ? "1" : "0"}]
                return [list $target_net $needed_val]
            }

            # Step 2: D-frontier propagation objective
            # Find a gate with D or D_BAR on an input and X on the output
            foreach inst [$netlist get_instance_names] {
                set pins [$netlist get_instance_pins $inst]
                set has_d_input 0
                set unassigned_input ""

                dict for {pname pnet} $pins {
                    set pval [expr {[dict exists $sim_state $pnet] ? [dict get $sim_state $pnet] : "X"}]
                    if {$pval eq "D" || $pval eq "D_BAR"} {
                        set has_d_input 1
                    } elseif {$pval eq "X"} {
                        set unassigned_input $pnet
                    }
                }

                if {$has_d_input && $unassigned_input ne ""} {
                    # Non-controlling value for gate
                    set cell [$netlist get_cell_name $inst]
                    set non_ctrl "1" ;# for AND/NAND
                    if {[string match "*OR*" $cell]} { set non_ctrl "0" }
                    return [list $unassigned_input $non_ctrl]
                }
            }

            return [list "" ""]
        }

        # Backtrace from internal node to an unassigned primary input
        method _backtrace {node_name desired_val} {
            set cur_node $node_name
            set cur_val $desired_val

            while {1} {
                if {[$netlist has_port $cur_node] && [dict get [$netlist get_port_info $cur_node] dir] eq "INPUT"} {
                    if {[dict get $pi_assignments $cur_node] eq "X"} {
                        return [list $cur_node $cur_val]
                    }
                }

                # Find driver instance of current net
                set drivers [$netlist get_net_drivers $cur_node]
                if {[llength $drivers] == 0} {
                    # Search primary inputs if net matches port
                    foreach pi [$netlist get_ports "INPUT"] {
                        if {[dict get $pi_assignments $pi] eq "X"} {
                            return [list $pi $cur_val]
                        }
                    }
                    return [list "" ""]
                }

                set drv_pin [lindex $drivers 0]
                set parts [split $drv_pin "/"]
                set inst [lindex $parts 0]
                set cell [$netlist get_cell_name $inst]

                # Invert objective value if inverting gate
                if {[string match "*INV*" $cell] || [string match "*NAND*" $cell] || [string match "*NOR*" $cell]} {
                    set cur_val [expr {$cur_val eq "1" ? "0" : "1"}]
                }

                # Select an unassigned fanin input to trace backwards
                set found_in ""
                dict for {pname pnet} [$netlist get_instance_pins $inst] {
                    if {$pnet ne $cur_node} {
                        set found_in $pnet
                        break
                    }
                }

                if {$found_in eq "" || $found_in eq $cur_node} {
                    break
                }
                set cur_node $found_in
            }

            # Fallback: pick any unassigned primary input
            foreach pi [$netlist get_ports "INPUT"] {
                if {[dict get $pi_assignments $pi] eq "X"} {
                    return [list $pi $cur_val]
                }
            }
            return [list "" ""]
        }

        # Forward 5-state Roth logic evaluation
        method _simulate_5state {} {
            set state [dict create]
            dict for {pi val} $pi_assignments {
                dict set state $pi $val
            }

            set target_net [dict get $target_fault net]
            set f_type     [dict get $target_fault type]

            # Forward topological pass across instances
            foreach inst [$netlist get_instance_names] {
                set cell [$netlist get_cell_name $inst]
                set pins [$netlist get_instance_pins $inst]

                set in_a "X"
                set in_b "X"
                set out_net ""

                dict for {pname pnet} $pins {
                    set pval [expr {[dict exists $state $pnet] ? [dict get $state $pnet] : "X"}]
                    if {$pname eq "A"} { set in_a $pval }
                    if {$pname eq "B"} { set in_b $pval }
                    if {$pname eq "Y" || $pname eq "Q"} { set out_net $pnet }
                }

                # Evaluate gate logic with 5-state rules
                set out_val "X"
                if {[string match "*INV*" $cell]} {
                    set out_val [::tempo::bv::Roth5::not $in_a]
                } elseif {[string match "*NAND2*" $cell]} {
                    set out_val [::tempo::bv::Roth5::nand $in_a $in_b]
                } elseif {[string match "*NOR2*" $cell]} {
                    set out_val [::tempo::bv::Roth5::nor $in_a $in_b]
                } elseif {[string match "*AND2*" $cell]} {
                    set out_val [::tempo::bv::Roth5::and $in_a $in_b]
                } elseif {[string match "*OR2*" $cell]} {
                    set out_val [::tempo::bv::Roth5::or $in_a $in_b]
                } elseif {[string match "*XOR2*" $cell]} {
                    set out_val [::tempo::bv::Roth5::xor $in_a $in_b]
                } else {
                    set out_val $in_a
                }

                # Inject fault at target net:
                if {$out_net eq $target_net} {
                    if {$f_type eq "SA0" && $out_val eq "1"} {
                        set out_val "D" ;# Good=1, Faulty=0
                    } elseif {$f_type eq "SA1" && $out_val eq "0"} {
                        set out_val "D_BAR" ;# Good=0, Faulty=1
                    }
                }

                if {$out_net ne ""} {
                    dict set state $out_net $out_val
                }
            }

            # Check if fault was directly on a primary input
            if {[$netlist has_port $target_net] && [dict get [$netlist get_port_info $target_net] dir] eq "INPUT"} {
                set pi_val [dict get $pi_assignments $target_net]
                if {$f_type eq "SA0" && $pi_val eq "1"} {
                    dict set state $target_net "D"
                } elseif {$f_type eq "SA1" && $pi_val eq "0"} {
                    dict set state $target_net "D_BAR"
                }
            }

            return $state
        }
    }
}
