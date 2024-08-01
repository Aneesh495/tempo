# ==============================================================================
# Dynamic Switching and Internal Power Analysis Engine
#
# Computes dynamic capacitive switching power:
#   P_switch = 0.5 * alpha * C_load * Vdd^2 * frequency
# and cell internal short-circuit power across all nets and clock domains.
# ==============================================================================

namespace eval ::tempo::power::dynamic {
    oo::class create DynamicPowerAnalyzer {
        variable netlist
        variable library
        variable vdd
        variable default_frequency_hz
        variable default_activity_factor
        variable net_activities

        constructor {nl lib {supply_voltage 1.1} {freq_hz 1.0e9} {alpha 0.2}} {
            set netlist $nl
            set library $lib
            set vdd $supply_voltage
            set default_frequency_hz $freq_hz
            set default_activity_factor $alpha
            set net_activities [dict create]
        }

        # Set specific switching activity factor (toggle rate) for a net
        method set_net_activity {net_name alpha} {
            dict set net_activities $net_name $alpha
        }

        # Query switching activity factor for a net
        method get_net_activity {net_name} {
            if {[dict exists $net_activities $net_name]} {
                return [dict get $net_activities $net_name]
            }
            return $default_activity_factor
        }

        # Calculate switching power for a specific net in microwatts (uW)
        method calculate_net_switching_power {net_name} {
            set alpha [my get_net_activity $net_name]

            # Compute total capacitive load on net: pin load + wire load
            set total_cap 0.0
            set loads [$netlist get_net_loads $net_name]
            foreach ld $loads {
                set parts [split $ld "/"]
                set ld_inst [lindex $parts 0]
                set ld_pin  [lindex $parts 1]
                set ld_cell [$netlist get_cell_name $ld_inst]
                set ld_cinfo [$library get_cell $ld_cell]
                if {$ld_cinfo ne ""} {
                    set ld_pins [dict get $ld_cinfo pins]
                    if {[dict exists $ld_pins $ld_pin]} {
                        set total_cap [expr {$total_cap + [dict get $ld_pins $ld_pin capacitance]}]
                    }
                }
            }

            # Wire capacitance in pF
            set wire_cap [$netlist get_net_cap $net_name]
            set total_cap [expr {$total_cap + $wire_cap}]

            # C_load in Farads (assuming capacitance in pF: 1 pF = 1e-12 F)
            set c_farads [expr {$total_cap * 1.0e-12}]

            # P = 0.5 * alpha * C * V^2 * f  (in Watts)
            set p_watts [expr {0.5 * $alpha * $c_farads * ($vdd * $vdd) * $default_frequency_hz}]

            # Convert Watts to microwatts (1 W = 1e6 uW)
            return [expr {$p_watts * 1.0e6}]
        }

        # Calculate internal short-circuit cell power in microwatts (uW)
        method calculate_instance_internal_power {inst_name} {
            set cell_name [$netlist get_cell_name $inst_name]
            set cinfo [$library get_cell $cell_name]
            if {$cinfo eq ""} { return 0.0 }

            # Internal power estimation based on cell footprint and switching rate
            set area 1.0
            if {[dict exists $cinfo area]} {
                set area [dict get $cinfo area]
            }

            # Approximate internal cell energy: ~0.08 uW per unit area per GHz
            set freq_ghz [expr {$default_frequency_hz / 1.0e9}]
            return [expr {0.08 * $area * $freq_ghz * $default_activity_factor}]
        }

        # Compute full dynamic power breakdown across all nets and instances
        method calculate_total_dynamic_power {} {
            set total_switch 0.0
            set total_internal 0.0

            foreach net [$netlist get_nets] {
                set p [my calculate_net_switching_power $net]
                set total_switch [expr {$total_switch + $p}]
            }

            foreach inst [$netlist get_instance_names] {
                set p [my calculate_instance_internal_power $inst]
                set total_internal [expr {$total_internal + $p}]
            }

            set total [expr {$total_switch + $total_internal}]

            return [dict create \
                switching_power_uW $total_switch \
                internal_power_uW $total_internal \
                total_dynamic_uW $total \
                total_dynamic_mW [expr {$total / 1000.0}]]
        }
    }
}
