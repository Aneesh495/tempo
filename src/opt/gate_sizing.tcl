# ==============================================================================
# Gate Sizing Engine for Timing and Area Optimization
#
# Analyzes critical and non-critical logic gates to perform drive strength
# sizing. Up-sizes cells on timing-critical paths to reduce propagation delay
# and transition degradation. Down-sizes non-critical cells to recover silicon
# area and dynamic/leakage power dissipation.
# ==============================================================================

namespace eval ::tempo::opt::sizing {
    oo::class create GateSizer {
        variable netlist
        variable library
        variable constraints
        variable timing_graph
        variable cell_families

        constructor {nl lib c tg} {
            set netlist $nl
            set library $lib
            set constraints $c
            set timing_graph $tg
            set cell_families [dict create]
            my _build_cell_families
        }

        # Build map of functional families based on pin counts and logic functions
        method _build_cell_families {} {
            foreach cname [$library get_cell_names] {
                set cinfo [$library get_cell $cname]
                if {[dict get $cinfo is_sequential]} { continue }

                # Group by prefix (e.g., INV, NAND2, NOR2, AND2, OR2, BUF)
                if {[regexp {^([A-Za-z0-9]+)_X(\d+)$} $cname match prefix drive]} {
                    dict lappend cell_families $prefix [dict create name $cname drive [expr {$drive + 0}]]
                }
            }

            # Sort each family by drive strength ascending
            dict for {fam members} $cell_families {
                set sorted [lsort -integer -index 1 [lmap m $members {list [dict get $m name] [dict get $m drive]}]]
                set clean_members [list]
                foreach item $sorted {
                    lappend clean_members [dict create name [lindex $item 0] drive [lindex $item 1]]
                }
                dict set cell_families $fam $clean_members
            }
        }

        # Find family name for a given cell
        method get_cell_family {cell_name} {
            if {[regexp {^([A-Za-z0-9]+)_X\d+$} $cell_name match prefix]} {
                return $prefix
            }
            return ""
        }

        # Find higher drive strength cell in the same family
        method get_upsize_candidate {current_cell} {
            set fam [my get_cell_family $current_cell]
            if {$fam eq "" || ![dict exists $cell_families $fam]} { return "" }

            set members [dict get $cell_families $fam]
            set found 0
            foreach m $members {
                if {$found} {
                    return [dict get $m name]
                }
                if {[dict get $m name] eq $current_cell} {
                    set found 1
                }
            }
            return ""
        }

        # Find lower drive strength cell in the same family
        method get_downsize_candidate {current_cell} {
            set fam [my get_cell_family $current_cell]
            if {$fam eq "" || ![dict exists $cell_families $fam]} { return "" }

            set members [dict get $cell_families $fam]
            set prev ""
            foreach m $members {
                if {[dict get $m name] eq $current_cell} {
                    return $prev
                }
                set prev [dict get $m name]
            }
            return ""
        }

        # Optimize critical paths by selectively up-sizing high-delay gates
        method optimize_setup_timing {critical_instances} {
            set changes [list]

            foreach inst $critical_instances {
                set cur_cell [$netlist get_cell_name $inst]
                set target_cell [my get_upsize_candidate $cur_cell]

                if {$target_cell ne ""} {
                    # Apply up-sizing move in netlist
                    $netlist set_cell_name $inst $target_cell
                    lappend changes [dict create instance $inst from $cur_cell to $target_cell action "upsize"]
                }
            }

            return $changes
        }

        # Recover area on non-critical positive slack paths
        method recover_area {non_critical_instances} {
            set changes [list]

            foreach inst $non_critical_instances {
                set cur_cell [$netlist get_cell_name $inst]
                set target_cell [my get_downsize_candidate $cur_cell]

                if {$target_cell ne ""} {
                    $netlist set_cell_name $inst $target_cell
                    lappend changes [dict create instance $inst from $cur_cell to $target_cell action "downsize"]
                }
            }

            return $changes
        }
    }
}
