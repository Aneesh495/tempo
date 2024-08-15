# ==============================================================================
# IEEE 1364 Value Change Dump (VCD) Waveform Generator
#
# Generates standardized VCD waveform traces from simulation change history
# for inspection in GTKWave, ModelSim, or automated waveform regression checks.
# ==============================================================================

namespace eval ::tempo::sim::vcd {
    oo::class create VCDWriter {
        variable simulator
        variable netlist
        variable symbol_map

        constructor {sim nl} {
            set simulator $sim
            set netlist $nl
            set symbol_map [dict create]
            my _assign_symbols
        }

        # Assign compact ASCII identifier code to each net and port
        method _assign_symbols {} {
            set all_signals [list]
            foreach p [$netlist get_ports] { lappend all_signals $p }
            foreach n [$netlist get_nets] {
                if {$n ni $all_signals} { lappend all_signals $n }
            }

            set sym_code 33 ;# ASCII 33 is '!'
            foreach sig $all_signals {
                dict set symbol_map $sig [format "%c" $sym_code]
                incr sym_code
                if {$sym_code == 127} { set sym_code 33 } ;# wrap or extend
            }
        }

        # Generate full IEEE 1364 VCD text
        method generate {} {
            set lines [list]
            lappend lines "\$date [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}] \$end"
            lappend lines "\$version TEMPO EDA Digital Logic Simulator \$end"
            lappend lines "\$timescale 1ps \$end"
            lappend lines "\$scope module top \$end"

            dict for {sig sym} $symbol_map {
                lappend lines [format "\$var wire 1 %s %s \$end" $sym $sig]
            }

            lappend lines "\$upscope \$end"
            lappend lines "\$enddefinitions \$end"
            lappend lines "\$dumpvars"

            # Initial dump at time 0
            dict for {sig sym} $symbol_map {
                set val [$simulator get_net_value $sig]
                lappend lines [format "%s%s" $val $sym]
            }
            lappend lines "\$end"

            # Replay history grouped by simulation timestamp
            set history [$simulator get_history]
            set current_t -1

            foreach event $history {
                set t [dict get $event time]
                set net [dict get $event net]
                set new_val [dict get $event new_val]

                if {![dict exists $symbol_map $net]} { continue }
                set sym [dict get $symbol_map $net]

                if {$t != $current_t} {
                    set current_t $t
                    lappend lines "#$t"
                }

                lappend lines [format "%s%s" $new_val $sym]
            }

            return [join $lines "\n"]
        }

        # Write VCD to physical file on disk
        method write_file {filepath} {
            set content [my generate]
            set fp [open $filepath w]
            puts $fp $content
            close $fp
            return $filepath
        }
    }
}
