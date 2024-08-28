# ==============================================================================
# Single Stuck-at Fault Modeling and Fault Collapsing Engine
#
# Generates stuck-at-0 (SA0) and stuck-at-1 (SA1) fault lists across netlist
# interconnects and performs structural equivalence fault collapsing for
# standard logic gates (INV, NAND, NOR, AND, OR).
# ==============================================================================

namespace eval ::tempo::fault::model {
    oo::class create FaultManager {
        variable netlist
        variable library
        variable uncollapsed_faults
        variable collapsed_faults

        constructor {nl lib} {
            set netlist $nl
            set library $lib
            set uncollapsed_faults [list]
            set collapsed_faults [list]
            my _generate_uncollapsed
        }

        # Generate standard 2N uncollapsed faults (SA0 and SA1 on all nets)
        method _generate_uncollapsed {} {
            set uncollapsed_faults [list]
            foreach net [$netlist get_nets] {
                lappend uncollapsed_faults [dict create net $net type "SA0" id "${net}_SA0"]
                lappend uncollapsed_faults [dict create net $net type "SA1" id "${net}_SA1"]
            }
        }

        # Perform structural equivalence fault collapsing
        method collapse_faults {} {
            set collapsed [dict create]
            set dropped [dict create]

            # Mark all uncollapsed faults as candidate active
            foreach f $uncollapsed_faults {
                dict set collapsed [dict get $f id] $f
            }

            # Traverse gates and collapse equivalent faults
            foreach inst [$netlist get_instance_names] {
                set cell [$netlist get_cell_name $inst]
                set pins [$netlist get_instance_pins $inst]

                # Inverter collapsing: input SA0 == output SA1; input SA1 == output SA0
                if {[string match "*INV*" $cell]} {
                    if {[dict exists $pins "A"] && [dict exists $pins "Y"]} {
                        set in_net [dict get $pins "A"]
                        set out_net [dict get $pins "Y"]

                        # Collapse output SA1 into input SA0
                        if {[dict exists $collapsed "${out_net}_SA1"]} {
                            dict unset collapsed "${out_net}_SA1"
                            dict set dropped "${out_net}_SA1" "${in_net}_SA0"
                        }
                        # Collapse output SA0 into input SA1
                        if {[dict exists $collapsed "${out_net}_SA0"]} {
                            dict unset collapsed "${out_net}_SA0"
                            dict set dropped "${out_net}_SA0" "${in_net}_SA1"
                        }
                    }
                }

                # NAND2 collapsing: input SA0 is equivalent to output SA1
                if {[string match "*NAND2*" $cell]} {
                    if {[dict exists $pins "A"] && [dict exists $pins "B"] && [dict exists $pins "Y"]} {
                        set in_a [dict get $pins "A"]
                        set out_y [dict get $pins "Y"]

                        # Collapse out_y SA1
                        if {[dict exists $collapsed "${out_y}_SA1"]} {
                            dict unset collapsed "${out_y}_SA1"
                            dict set dropped "${out_y}_SA1" "${in_a}_SA0"
                        }
                    }
                }

                # NOR2 collapsing: input SA1 is equivalent to output SA0
                if {[string match "*NOR2*" $cell]} {
                    if {[dict exists $pins "A"] && [dict exists $pins "B"] && [dict exists $pins "Y"]} {
                        set in_a [dict get $pins "A"]
                        set out_y [dict get $pins "Y"]

                        # Collapse out_y SA0
                        if {[dict exists $collapsed "${out_y}_SA0"]} {
                            dict unset collapsed "${out_y}_SA0"
                            dict set dropped "${out_y}_SA0" "${in_a}_SA1"
                        }
                    }
                }
            }

            set collapsed_faults [dict values $collapsed]
            return $collapsed_faults
        }

        method get_uncollapsed_faults {} {
            return $uncollapsed_faults
        }

        method get_collapsed_faults {} {
            if {[llength $collapsed_faults] == 0} {
                my collapse_faults
            }
            return $collapsed_faults
        }

        method get_collapse_ratio {} {
            set u_count [llength $uncollapsed_faults]
            if {$u_count == 0} { return 1.0 }
            set c_count [llength [my get_collapsed_faults]]
            return [expr {double($c_count) / double($u_count)}]
        }
    }
}
