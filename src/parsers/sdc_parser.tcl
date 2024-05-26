# Tempo Synopsys Design Constraints (SDC) Command Interpreter
# Evaluates standard SDC 2.1 constraint scripts in an isolated execution context
# Namespace: ::tempo::sdc::parser

namespace eval ::tempo::sdc::parser {
    variable cur_constraints ""
    variable cur_netlist ""

    # Evaluates an SDC script string or file against target Constraints and Netlist
    proc evaluate {sdc_content constraints {netlist ""}} {
        variable cur_constraints
        variable cur_netlist

        set cur_constraints $constraints
        set cur_netlist $netlist

        set interp [interp create -safe]

        # Expose SDC command procedures in the safe interpreter
        _install_sdc_commands $interp

        set status [catch {$interp eval $sdc_content} result]
        interp delete $interp

        if {$status != 0} {
            return -code error "Error evaluating SDC constraints: $result"
        }
        return $constraints
    }

    proc evaluate_file {filepath constraints {netlist ""}} {
        if {![file exists $filepath]} {
            return -code error "SDC file does not exist: $filepath"
        }
        set fp [open $filepath r]
        set content [read $fp]
        close $fp
        return [evaluate $content $constraints $netlist]
    }

    # Install SDC commands inside target interpreter
    proc _install_sdc_commands {interp} {
        # Helper to query ports from netlist
        $interp alias get_ports ::tempo::sdc::parser::_cmd_get_ports
        $interp alias get_pins ::tempo::sdc::parser::_cmd_get_pins
        $interp alias get_clocks ::tempo::sdc::parser::_cmd_get_clocks
        $interp alias all_inputs ::tempo::sdc::parser::_cmd_all_inputs
        $interp alias all_outputs ::tempo::sdc::parser::_cmd_all_outputs
        $interp alias all_clocks ::tempo::sdc::parser::_cmd_all_clocks

        # Core constraint commands
        $interp alias create_clock ::tempo::sdc::parser::_cmd_create_clock
        $interp alias set_clock_uncertainty ::tempo::sdc::parser::_cmd_set_clock_uncertainty
        $interp alias set_clock_latency ::tempo::sdc::parser::_cmd_set_clock_latency
        $interp alias set_input_delay ::tempo::sdc::parser::_cmd_set_input_delay
        $interp alias set_output_delay ::tempo::sdc::parser::_cmd_set_output_delay
        $interp alias set_load ::tempo::sdc::parser::_cmd_set_load
        $interp alias set_input_transition ::tempo::sdc::parser::_cmd_set_input_transition
        $interp alias set_driving_cell ::tempo::sdc::parser::_cmd_set_driving_cell
        $interp alias set_false_path ::tempo::sdc::parser::_cmd_set_false_path
        $interp alias set_multicycle_path ::tempo::sdc::parser::_cmd_set_multicycle_path
    }

    # SDC Collection commands
    proc _cmd_get_ports {args} {
        variable cur_netlist
        set pattern [lindex $args 0]
        if {$cur_netlist ne "" && [info object isa typeof $cur_netlist ::tempo::netlist::Netlist]} {
            set all [$cur_netlist get_ports]
            set matched [list]
            foreach p $all {
                if {[string match $pattern $p]} {
                    lappend matched $p
                }
            }
            return $matched
        }
        return [list $pattern]
    }

    proc _cmd_get_pins {args} {
        set pattern [lindex $args 0]
        return [list $pattern]
    }

    proc _cmd_get_clocks {args} {
        variable cur_constraints
        set pattern [lindex $args 0]
        set clks [$cur_constraints get_clocks]
        set matched [list]
        foreach clk $clks {
            if {[string match $pattern $clk]} {
                lappend matched $clk
            }
        }
        if {[llength $matched] == 0} {
            return [list $pattern]
        }
        return $matched
    }

    proc _cmd_all_inputs {} {
        variable cur_netlist
        if {$cur_netlist ne "" && [info object isa typeof $cur_netlist ::tempo::netlist::Netlist]} {
            return [$cur_netlist get_ports "INPUT"]
        }
        return [list]
    }

    proc _cmd_all_outputs {} {
        variable cur_netlist
        if {$cur_netlist ne "" && [info object isa typeof $cur_netlist ::tempo::netlist::Netlist]} {
            return [$cur_netlist get_ports "OUTPUT"]
        }
        return [list]
    }

    proc _cmd_all_clocks {} {
        variable cur_constraints
        return [$cur_constraints get_clocks]
    }

    # create_clock -name <name> -period <period> [-waveform {r f}] [ports]
    proc _cmd_create_clock {args} {
        variable cur_constraints
        set name ""
        set period 0.0
        set waveform [list]
        set target_port ""

        set idx 0
        set len [llength $args]
        while {$idx < $len} {
            set opt [lindex $args $idx]
            switch -exact -- $opt {
                "-name" {
                    incr idx
                    set name [lindex $args $idx]
                }
                "-period" {
                    incr idx
                    set period [expr {[lindex $args $idx] + 0.0}]
                }
                "-waveform" {
                    incr idx
                    set waveform [lindex $args $idx]
                }
                default {
                    if {![string match "-*" $opt]} {
                        set target_port $opt
                    }
                }
            }
            incr idx
        }

        # If name not given, derive from port
        if {$name eq "" && [llength $target_port] > 0} {
            set name [lindex $target_port 0]
        }

        $cur_constraints add_clock $name $period $waveform $target_port
    }

    # set_clock_uncertainty [-setup <val>] [-hold <val>] <val> [clocks]
    proc _cmd_set_clock_uncertainty {args} {
        variable cur_constraints
        set setup_unc 0.0
        set hold_unc 0.0
        set common_unc 0.0
        set has_explicit 0
        set target_clocks [list]

        set idx 0
        set len [llength $args]
        while {$idx < $len} {
            set opt [lindex $args $idx]
            switch -exact -- $opt {
                "-setup" {
                    incr idx
                    set setup_unc [expr {[lindex $args $idx] + 0.0}]
                    set has_explicit 1
                }
                "-hold" {
                    incr idx
                    set hold_unc [expr {[lindex $args $idx] + 0.0}]
                    set has_explicit 1
                }
                default {
                    if {[string is double -strict $opt]} {
                        set common_unc [expr {$opt + 0.0}]
                    } else {
                        set target_clocks $opt
                    }
                }
            }
            incr idx
        }

        if {!$has_explicit} {
            set setup_unc $common_unc
            set hold_unc $common_unc
        }

        if {[llength $target_clocks] == 0} {
            set target_clocks [$cur_constraints get_clocks]
        }

        foreach clk $target_clocks {
            $cur_constraints set_clock_uncertainty $clk $setup_unc $hold_unc
        }
    }

    # set_clock_latency [-early <val>] [-late <val>] <val> [clocks]
    proc _cmd_set_clock_latency {args} {
        variable cur_constraints
        set early_lat 0.0
        set late_lat 0.0
        set common_lat 0.0
        set has_explicit 0
        set target_clocks [list]

        set idx 0
        set len [llength $args]
        while {$idx < $len} {
            set opt [lindex $args $idx]
            switch -exact -- $opt {
                "-early" {
                    incr idx
                    set early_lat [expr {[lindex $args $idx] + 0.0}]
                    set has_explicit 1
                }
                "-late" {
                    incr idx
                    set late_lat [expr {[lindex $args $idx] + 0.0}]
                    set has_explicit 1
                }
                "-source" {
                    # Optional source flag
                }
                default {
                    if {[string is double -strict $opt]} {
                        set common_lat [expr {$opt + 0.0}]
                    } else {
                        set target_clocks $opt
                    }
                }
            }
            incr idx
        }

        if {!$has_explicit} {
            set early_lat $common_lat
            set late_lat $common_lat
        }

        if {[llength $target_clocks] == 0} {
            set target_clocks [$cur_constraints get_clocks]
        }

        foreach clk $target_clocks {
            $cur_constraints set_clock_latency $clk $early_lat $late_lat
        }
    }

    # set_input_delay -clock <clk> [-max] [-min] <delay> [ports]
    proc _cmd_set_input_delay {args} {
        variable cur_constraints
        set clock ""
        set delay 0.0
        set type "max"
        set ports [list]

        set idx 0
        set len [llength $args]
        while {$idx < $len} {
            set opt [lindex $args $idx]
            switch -exact -- $opt {
                "-clock" {
                    incr idx
                    set clock [lindex $args $idx]
                }
                "-max" { set type "max" }
                "-min" { set type "min" }
                default {
                    if {[string is double -strict $opt]} {
                        set delay [expr {$opt + 0.0}]
                    } else {
                        set ports $opt
                    }
                }
            }
            incr idx
        }

        foreach p $ports {
            $cur_constraints set_input_delay $p $delay $clock $type
        }
    }

    # set_output_delay -clock <clk> [-max] [-min] <delay> [ports]
    proc _cmd_set_output_delay {args} {
        variable cur_constraints
        set clock ""
        set delay 0.0
        set type "max"
        set ports [list]

        set idx 0
        set len [llength $args]
        while {$idx < $len} {
            set opt [lindex $args $idx]
            switch -exact -- $opt {
                "-clock" {
                    incr idx
                    set clock [lindex $args $idx]
                }
                "-max" { set type "max" }
                "-min" { set type "min" }
                default {
                    if {[string is double -strict $opt]} {
                        set delay [expr {$opt + 0.0}]
                    } else {
                        set ports $opt
                    }
                }
            }
            incr idx
        }

        foreach p $ports {
            $cur_constraints set_output_delay $p $delay $clock $type
        }
    }

    # set_load <cap> [ports]
    proc _cmd_set_load {args} {
        variable cur_constraints
        set cap 0.0
        set ports [list]

        set idx 0
        set len [llength $args]
        while {$idx < $len} {
            set opt [lindex $args $idx]
            switch -exact -- $opt {
                "-pin_load" - "-wire_load" {
                    # Ignored qualifier
                }
                default {
                    if {[string is double -strict $opt]} {
                        set cap [expr {$opt + 0.0}]
                    } else {
                        set ports $opt
                    }
                }
            }
            incr idx
        }

        foreach p $ports {
            $cur_constraints set_load $p $cap
        }
    }

    # set_input_transition <slew> [ports]
    proc _cmd_set_input_transition {args} {
        variable cur_constraints
        set slew 10.0
        set ports [list]

        foreach opt $args {
            if {[string is double -strict $opt]} {
                set slew [expr {$opt + 0.0}]
            } elseif {![string match "-*" $opt]} {
                set ports $opt
            }
        }

        foreach p $ports {
            $cur_constraints set_input_transition $p $slew
        }
    }

    # set_driving_cell -lib_cell <cell> [-pin <pin>] [ports]
    proc _cmd_set_driving_cell {args} {
        variable cur_constraints
        set lib_cell ""
        set pin "Y"
        set ports [list]

        set idx 0
        set len [llength $args]
        while {$idx < $len} {
            set opt [lindex $args $idx]
            switch -exact -- $opt {
                "-lib_cell" {
                    incr idx
                    set lib_cell [lindex $args $idx]
                }
                "-pin" {
                    incr idx
                    set pin [lindex $args $idx]
                }
                default {
                    if {![string match "-*" $opt]} {
                        set ports $opt
                    }
                }
            }
            incr idx
        }

        foreach p $ports {
            $cur_constraints set_driving_cell $p $lib_cell $pin
        }
    }

    # set_false_path [-from <from>] [-to <to>] [-through <through>]
    proc _cmd_set_false_path {args} {
        variable cur_constraints
        set from ""
        set to ""
        set through ""

        set idx 0
        set len [llength $args]
        while {$idx < $len} {
            set opt [lindex $args $idx]
            switch -exact -- $opt {
                "-from" { incr idx; set from [lindex $args $idx] }
                "-to"   { incr idx; set to   [lindex $args $idx] }
                "-through" { incr idx; set through [lindex $args $idx] }
            }
            incr idx
        }

        $cur_constraints add_false_path $from $to $through
    }

    # set_multicycle_path <multiplier> [-setup | -hold] [-from <from>] [-to <to>]
    proc _cmd_set_multicycle_path {args} {
        variable cur_constraints
        set multiplier 1
        set type "setup"
        set from ""
        set to ""

        set idx 0
        set len [llength $args]
        while {$idx < $len} {
            set opt [lindex $args $idx]
            switch -exact -- $opt {
                "-setup" { set type "setup" }
                "-hold"  { set type "hold" }
                "-from"  { incr idx; set from [lindex $args $idx] }
                "-to"    { incr idx; set to   [lindex $args $idx] }
                default {
                    if {[string is integer -strict $opt]} {
                        set multiplier $opt
                    }
                }
            }
            incr idx
        }

        $cur_constraints add_multicycle_path $multiplier $type $from $to
    }
}
