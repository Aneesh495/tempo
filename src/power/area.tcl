# ==============================================================================
# Physical Area and Full Power Roll-up Engine
#
# Computes standard cell silicon area (in square microns), NAND2-equivalent
# gate counts, and formats complete power and area summary reports.
# ==============================================================================

namespace eval ::tempo::power::area {
    oo::class create AreaAnalyzer {
        variable netlist
        variable library
        variable nand2_cell_area

        constructor {nl lib {nand2_area 1.5}} {
            set netlist $nl
            set library $lib
            set nand2_cell_area $nand2_area
        }

        # Calculate standard cell silicon area breakdown
        method calculate_area {} {
            set total_area 0.0
            set comb_area 0.0
            set seq_area 0.0
            set cell_histogram [dict create]

            foreach inst [$netlist get_instance_names] {
                set cname [$netlist get_cell_name $inst]
                set cinfo [$library get_cell $cname]
                set area 1.0
                set is_seq 0

                if {$cinfo ne ""} {
                    if {[dict exists $cinfo area]} {
                        set area [dict get $cinfo area]
                    }
                    if {[dict exists $cinfo is_sequential]} {
                        set is_seq [dict get $cinfo is_sequential]
                    }
                }

                set total_area [expr {$total_area + $area}]
                if {$is_seq} {
                    set seq_area [expr {$seq_area + $area}]
                } else {
                    set comb_area [expr {$comb_area + $area}]
                }

                set count 0
                if {[dict exists $cell_histogram $cname]} {
                    set count [dict get $cell_histogram $cname]
                }
                dict set cell_histogram $cname [expr {$count + 1}]
            }

            set ge [expr {$total_area / $nand2_cell_area}]

            return [dict create \
                total_area_um2 $total_area \
                combinational_area_um2 $comb_area \
                sequential_area_um2 $seq_area \
                nand2_gate_equivalents $ge \
                cell_histogram $cell_histogram]
        }

        # Format comprehensive Power and Area ASCII report
        method format_power_area_report {leak_res dyn_res area_res} {
            set total_leak_uW [dict get $leak_res total_leakage_uW]
            set dyn_switch_uW [dict get $dyn_res switching_power_uW]
            set dyn_int_uW    [dict get $dyn_res internal_power_uW]
            set total_dyn_uW  [dict get $dyn_res total_dynamic_uW]
            set grand_total_uW [expr {$total_leak_uW + $total_dyn_uW}]

            set lines [list]
            lappend lines "================================================================================"
            lappend lines "TEMPO POWER AND PHYSICAL AREA REPORT"
            lappend lines "================================================================================"
            lappend lines [format "%-35s: %15.3f um^2" "Total Standard Cell Area" [dict get $area_res total_area_um2]]
            lappend lines [format "%-35s: %15.3f um^2" "  Combinational Area" [dict get $area_res combinational_area_um2]]
            lappend lines [format "%-35s: %15.3f um^2" "  Sequential Area" [dict get $area_res sequential_area_um2]]
            lappend lines [format "%-35s: %15.1f" "NAND2 Equivalent Gate Count" [dict get $area_res nand2_gate_equivalents]]
            lappend lines "--------------------------------------------------------------------------------"
            lappend lines [format "%-35s: %15.4f uW (%.6f mW)" "Static Leakage Power" $total_leak_uW [expr {$total_leak_uW / 1000.0}]]
            lappend lines [format "%-35s: %15.4f uW (%.6f mW)" "Dynamic Switching Power" $dyn_switch_uW [expr {$dyn_switch_uW / 1000.0}]]
            lappend lines [format "%-35s: %15.4f uW (%.6f mW)" "Internal Cell Power" $dyn_int_uW [expr {$dyn_int_uW / 1000.0}]]
            lappend lines [format "%-35s: %15.4f uW (%.6f mW)" "Total Dynamic Power" $total_dyn_uW [expr {$total_dyn_uW / 1000.0}]]
            lappend lines "--------------------------------------------------------------------------------"
            lappend lines [format "%-35s: %15.4f uW (%.6f mW)" "TOTAL CHIP POWER" $grand_total_uW [expr {$grand_total_uW / 1000.0}]]
            lappend lines "================================================================================"
            return [join $lines "\n"]
        }
    }
}
