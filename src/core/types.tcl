# Tempo Core Types and Dimensional Units Framework
# Namespace: ::tempo::types and ::tempo::units

namespace eval ::tempo {
    variable version "1.0.0"
    variable log_level 2 ;# 0: error, 1: warn, 2: info, 3: debug
    variable log_colors 1

    proc set_log_level {lvl} {
        variable log_level
        set log_level $lvl
    }

    proc log {level msg} {
        variable log_level
        variable log_colors
        set lvl_num 2
        set prefix "INFO"
        set color_code ""
        set reset_code ""

        switch -exact -- $level {
            "ERROR" {
                set lvl_num 0
                set prefix "ERROR"
                set color_code "\033\[1;31m"
            }
            "WARN" {
                set lvl_num 1
                set prefix "WARN "
                set color_code "\033\[1;33m"
            }
            "INFO" {
                set lvl_num 2
                set prefix "INFO "
                set color_code "\033\[1;34m"
            }
            "DEBUG" {
                set lvl_num 3
                set prefix "DEBUG"
                set color_code "\033\[1;35m"
            }
        }
        if {$log_colors} {
            set reset_code "\033\[0m"
        } else {
            set color_code ""
        }

        if {$lvl_num <= $log_level} {
            puts stderr "${color_code}\[tempo $prefix\]${reset_code} $msg"
        }
    }

    proc err {msg} {
        log "ERROR" $msg
        return -code error $msg
    }

    proc warn {msg} {
        log "WARN" $msg
    }

    proc info {msg} {
        log "INFO" $msg
    }

    proc dbg {msg} {
        log "DEBUG" $msg
    }
}

namespace eval ::tempo::units {
    # Internal canonical representation:
    # Time: picoseconds (ps), where 1 ns = 1000.0 ps
    # Capacitance: femtofarads (fF), where 1 pF = 1000.0 fF
    # Resistance: ohms (ohm), where 1 kohm = 1000.0 ohm
    # Voltage: volts (V)
    # Power: microwatts (uW), where 1 mW = 1000.0 uW
    # Energy: femtojoules (fJ)

    # Conversion multipliers to internal canonical units
    variable time_scale
    dict set time_scale "s"  1.0e12
    dict set time_scale "ms" 1.0e9
    dict set time_scale "us" 1.0e6
    dict set time_scale "ns" 1000.0
    dict set time_scale "ps" 1.0
    dict set time_scale "fs" 0.001

    variable cap_scale
    dict set cap_scale "f"  1.0e15
    dict set cap_scale "mf" 1.0e12
    dict set cap_scale "uf" 1.0e9
    dict set cap_scale "nf" 1.0e6
    dict set cap_scale "pf" 1000.0
    dict set cap_scale "ff" 1.0

    variable res_scale
    dict set res_scale "mohm" 1.0e6
    dict set res_scale "kohm" 1000.0
    dict set res_scale "ohm"  1.0

    variable power_scale
    dict set power_scale "w"  1.0e6
    dict set power_scale "mw" 1000.0
    dict set power_scale "uw" 1.0
    dict set power_scale "nw" 0.001
    dict set power_scale "pw" 1.0e-6

    # Convert given value in specified unit to internal picoseconds
    proc to_ps {val unit} {
        variable time_scale
        set u [string tolower $unit]
        if {![dict exists $time_scale $u]} {
            return -code error "Unknown time unit: $unit"
        }
        return [expr {$val * [dict get $time_scale $u]}]
    }

    # Convert internal picoseconds to target unit
    proc from_ps {ps_val unit} {
        variable time_scale
        set u [string tolower $unit]
        if {![dict exists $time_scale $u]} {
            return -code error "Unknown time unit: $unit"
        }
        return [expr {$ps_val / [dict get $time_scale $u]}]
    }

    # Convert given value in specified unit to internal femtofarads
    proc to_ff {val unit} {
        variable cap_scale
        set u [string tolower $unit]
        if {![dict exists $cap_scale $u]} {
            return -code error "Unknown capacitance unit: $unit"
        }
        return [expr {$val * [dict get $cap_scale $u]}]
    }

    # Convert internal femtofarads to target unit
    proc from_ff {ff_val unit} {
        variable cap_scale
        set u [string tolower $unit]
        if {![dict exists $cap_scale $u]} {
            return -code error "Unknown capacitance unit: $unit"
        }
        return [expr {$ff_val / [dict get $cap_scale $u]}]
    }

    # Convert resistance to internal ohms
    proc to_ohms {val unit} {
        variable res_scale
        set u [string tolower $unit]
        if {![dict exists $res_scale $u]} {
            return -code error "Unknown resistance unit: $unit"
        }
        return [expr {$val * [dict get $res_scale $u]}]
    }

    # Convert internal ohms to target unit
    proc from_ohms {ohm_val unit} {
        variable res_scale
        set u [string tolower $unit]
        if {![dict exists $res_scale $u]} {
            return -code error "Unknown resistance unit: $unit"
        }
        return [expr {$ohm_val / [dict get $res_scale $u]}]
    }

    # Parse compound unit strings like "100ps", "2.5ns", "0.05pF", "1kohm"
    proc parse_quantity {str} {
        set trimmed [string trim $str]
        if {[regexp {^([+-]?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)\s*([a-zA-Z]+)?$} $trimmed -> num unit]} {
            if {$unit eq ""} {
                set unit "raw"
            }
            return [list [expr {$num + 0.0}] $unit]
        }
        return -code error "Cannot parse quantity string: '$str'"
    }

    # Format helpers for user reports
    proc format_time_ps {ps {precision 3}} {
        return [format "%.*f ps" $precision $ps]
    }

    proc format_time_ns {ps {precision 4}} {
        set ns [expr {$ps / 1000.0}]
        return [format "%.*f ns" $precision $ns]
    }

    proc format_cap_ff {ff {precision 3}} {
        return [format "%.*f fF" $precision $ff]
    }

    proc format_cap_pf {ff {precision 4}} {
        set pf [expr {$ff / 1000.0}]
        return [format "%.*f pF" $precision $pf]
    }

    proc format_res_ohm {ohms {precision 2}} {
        return [format "%.*f ohm" $precision $ohms]
    }

    proc format_power_uw {uw {precision 3}} {
        return [format "%.*f uW" $precision $uw]
    }

    proc format_slack {ps} {
        set ns [expr {$ps / 1000.0}]
        if {$ps < 0.0} {
            return [format "%.3f ps (%.4f ns) \[VIOLATED\]" $ps $ns]
        } else {
            return [format "%.3f ps (%.4f ns) \[MET\]" $ps $ns]
        }
    }
}

namespace eval ::tempo::types {
    # Type checking and contract enforcement helper procs

    proc assert_numeric {val param_name} {
        if {![string is double -strict $val]} {
            return -code error "Parameter '$param_name' must be numeric; got '$val'"
        }
    }

    proc assert_positive {val param_name} {
        assert_numeric $val $param_name
        if {$val <= 0.0} {
            return -code error "Parameter '$param_name' must be positive; got '$val'"
        }
    }

    proc assert_non_negative {val param_name} {
        assert_numeric $val $param_name
        if {$val < 0.0} {
            return -code error "Parameter '$param_name' must be non-negative; got '$val'"
        }
    }

    proc assert_bool {val param_name} {
        if {![string is boolean -strict $val]} {
            return -code error "Parameter '$param_name' must be boolean; got '$val'"
        }
    }

    proc assert_one_of {val choices param_name} {
        if {[lsearch -exact $choices $val] == -1} {
            return -code error "Parameter '$param_name' must be one of \[[join $choices {, }]\], got '$val'"
        }
    }

    proc clamp {val min_val max_val} {
        if {$val < $min_val} {
            return $min_val
        }
        if {$val > $max_val} {
            return $max_val
        }
        return $val
    }

    proc lerp {a b t} {
        return [expr {$a + $t * ($b - $a)}]
    }

    # Bilinear 2D interpolation over a 2D grid
    # x0 <= x <= x1, y0 <= y <= y1
    # q00 = f(x0, y0), q01 = f(x0, y1), q10 = f(x1, y0), q11 = f(x1, y1)
    proc bilinear_interp {x y x0 x1 y0 y1 q00 q01 q10 q11} {
        if {$x1 == $x0 && $y1 == $y0} {
            return $q00
        }
        if {$x1 == $x0} {
            set ty [expr {($y - $y0) / double($y1 - $y0)}]
            return [lerp $q00 $q01 $ty]
        }
        if {$y1 == $y0} {
            set tx [expr {($x - $x0) / double($x1 - $x0)}]
            return [lerp $q00 $q10 $tx]
        }
        set tx [expr {($x - $x0) / double($x1 - $x0)}]
        set ty [expr {($y - $y0) / double($y1 - $y0)}]

        set r0 [lerp $q00 $q10 $tx]
        set r1 [lerp $q01 $q11 $tx]
        return [lerp $r0 $r1 $ty]
    }
}
