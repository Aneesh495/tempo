# ==============================================================================
# Static Leakage Power Analysis Engine
#
# Computes static subthreshold and gate tunneling leakage power dissipation
# across standard cell instances using Liberty cell_leakage_power models
# and state-dependent leakage characterization.
# ==============================================================================

namespace eval ::tempo::power::leakage {
    oo::class create LeakageAnalyzer {
        variable netlist
        variable library
        variable default_leakage_per_gate_uW

        constructor {nl lib {default_leak_uW 0.05}} {
            set netlist $nl
            set library $lib
            set default_leakage_per_gate_uW $default_leak_uW
        }

        # Calculate static leakage power for a single instance in microwatts (uW)
        method calculate_instance_leakage {inst_name} {
            set cell_name [$netlist get_cell_name $inst_name]
            if {$cell_name eq ""} { return 0.0 }

            set cinfo [$library get_cell $cell_name]
            if {$cinfo eq ""} {
                return $default_leakage_per_gate_uW
            }

            if {[dict exists $cinfo cell_leakage_power]} {
                return [dict get $cinfo cell_leakage_power]
            }

            # Scale leakage proportionally to cell area if explicit leakage is omitted
            set area 1.0
            if {[dict exists $cinfo area]} {
                set area [dict get $cinfo area]
            }

            return [expr {$default_leakage_per_gate_uW * $area}]
        }

        # Compute total leakage across the entire netlist
        method calculate_total_leakage {} {
            set total 0.0
            set cell_breakdown [dict create]

            foreach inst [$netlist get_instance_names] {
                set leak [my calculate_instance_leakage $inst]
                set total [expr {$total + $leak}]

                set cname [$netlist get_cell_name $inst]
                set cur 0.0
                if {[dict exists $cell_breakdown $cname]} {
                    set cur [dict get $cell_breakdown $cname]
                }
                dict set cell_breakdown $cname [expr {$cur + $leak}]
            }

            return [dict create \
                total_leakage_uW $total \
                total_leakage_mW [expr {$total / 1000.0}] \
                by_cell $cell_breakdown]
        }
    }
}
