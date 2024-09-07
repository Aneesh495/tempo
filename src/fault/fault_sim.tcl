# ==============================================================================
# Parallel Fault Simulation and Test Coverage Calculation Engine
#
# Simulates test pattern suites against target single stuck-at fault lists,
# performs fault dropping on detection, and calculates manufacturing test coverage.
# ==============================================================================

namespace eval ::tempo::fault::sim {
    oo::class create FaultSimulator {
        variable netlist
        variable library
        variable detected_faults
        variable undetected_faults
        variable fault_detection_map   ;# dict: fault_id -> vector_index

        constructor {nl lib} {
            set netlist $nl
            set library $lib
            set detected_faults [dict create]
            set undetected_faults [dict create]
            set fault_detection_map [dict create]
        }

        # Simulate good (fault-free) circuit under input vector
        method _eval_good {input_vector} {
            set sim [::tempo::sim::Simulator new $netlist $library 10]
            $sim reset

            dict for {p val} $input_vector {
                $sim schedule_input 0 $p $val
            }
            $sim run 200

            set po_vals [dict create]
            foreach po [$netlist get_ports "OUTPUT"] {
                dict set po_vals $po [$sim get_net_value $po]
            }

            $sim destroy
            return $po_vals
        }

        # Simulate circuit with injected single stuck-at fault
        method _eval_faulty {input_vector fault} {
            set f_net  [dict get $fault net]
            set f_type [dict get $fault type]
            set stuck_val [expr {$f_type eq "SA0" ? "0" : "1"}]

            set sim [::tempo::sim::Simulator new $netlist $library 10]
            $sim reset

            # Clamp the faulty net permanently
            $sim clamp_net $f_net $stuck_val

            # Schedule standard inputs
            dict for {p val} $input_vector {
                if {$p ne $f_net} {
                    $sim schedule_input 0 $p $val
                }
            }

            $sim run 200

            set po_vals [dict create]
            foreach po [$netlist get_ports "OUTPUT"] {
                dict set po_vals $po [$sim get_net_value $po]
            }

            $sim destroy
            return $po_vals
        }

        # Run fault simulation for a list of test vectors
        # vectors: list of dicts: [list [dict create in1 0 in2 1] ...]
        method run_fault_simulation {vectors target_faults} {
            set detected_faults [dict create]
            set undetected_faults [dict create]
            set fault_detection_map [dict create]

            foreach f $target_faults {
                dict set undetected_faults [dict get $f id] $f
            }

            set vec_idx 0
            foreach vec $vectors {
                set golden_po [my _eval_good $vec]

                set active_ids [dict keys $undetected_faults]
                foreach fid $active_ids {
                    set f [dict get $undetected_faults $fid]
                    set faulty_po [my _eval_faulty $vec $f]

                    # Check if any primary output differs
                    set detected 0
                    dict for {po g_val} $golden_po {
                        if {[dict exists $faulty_po $po]} {
                            set f_val [dict get $faulty_po $po]
                            if {$f_val in {0 1} && $g_val in {0 1} && $f_val ne $g_val} {
                                set detected 1
                                break
                            }
                        }
                    }

                    if {$detected} {
                        # Fault dropping: move from undetected to detected
                        dict set detected_faults $fid $f
                        dict unset undetected_faults $fid
                        dict set fault_detection_map $fid $vec_idx
                    }
                }

                incr vec_idx
                # Early stop if all faults detected
                if {[dict size $undetected_faults] == 0} {
                    break
                }
            }

            set total [llength $target_faults]
            set det_count [dict size $detected_faults]
            set cov [expr {$total > 0 ? (double($det_count) / double($total)) * 100.0 : 100.0}]

            return [dict create \
                total_faults $total \
                detected_faults $det_count \
                undetected_faults [dict size $undetected_faults] \
                coverage_percent $cov \
                test_vector_count [llength $vectors]]
        }

        # Format comprehensive ATPG Fault Coverage ASCII report
        method format_coverage_report {summary} {
            set lines [list]
            lappend lines "================================================================================"
            lappend lines "TEMPO MANUFACTURING ATPG & FAULT COVERAGE REPORT"
            lappend lines "================================================================================"
            lappend lines [format "%-35s: %15d" "Total Targeted Faults" [dict get $summary total_faults]]
            lappend lines [format "%-35s: %15d" "Detected Faults" [dict get $summary detected_faults]]
            lappend lines [format "%-35s: %15d" "Undetected / Redundant Faults" [dict get $summary undetected_faults]]
            lappend lines [format "%-35s: %15d" "Test Vector Count" [dict get $summary test_vector_count]]
            lappend lines "--------------------------------------------------------------------------------"
            lappend lines [format "%-35s: %14.2f %%" "TEST FAULT COVERAGE" [dict get $summary coverage_percent]]
            lappend lines "================================================================================"
            return [join $lines "\n"]
        }
    }
}
