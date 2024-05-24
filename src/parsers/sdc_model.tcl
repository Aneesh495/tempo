# Tempo Synopsys Design Constraints (SDC) Model
# Container for clocks, I/O delays, electrical constraints, and timing exceptions
# Namespace: ::tempo::sdc

namespace eval ::tempo::sdc {

    oo::class create Constraints {
        variable clocks              ;# dict: clk_name -> dict(period, waveform, port, sources)
        variable clock_uncertainties ;# dict: clk_name -> dict(setup: float, hold: float)
        variable clock_latencies     ;# dict: clk_name -> dict(early: float, late: float)
        variable input_delays        ;# dict: port -> list of dict(clock, min_delay, max_delay)
        variable output_delays       ;# dict: port -> list of dict(clock, min_delay, max_delay)
        variable port_loads          ;# dict: port -> cap_in_ff
        variable input_transitions   ;# dict: port -> slew_in_ps
        variable driving_cells       ;# dict: port -> dict(lib_cell: string, pin: string)
        variable false_paths         ;# list of dict(from, to, through)
        variable multicycle_paths    ;# list of dict(multiplier, type, from, to)
        variable max_delays          ;# list of dict(delay, from, to)
        variable min_delays          ;# list of dict(delay, from, to)

        constructor {} {
            my reset
        }

        method reset {} {
            set clocks [dict create]
            set clock_uncertainties [dict create]
            set clock_latencies [dict create]
            set input_delays [dict create]
            set output_delays [dict create]
            set port_loads [dict create]
            set input_transitions [dict create]
            set driving_cells [dict create]
            set false_paths [list]
            set multicycle_paths [list]
            set max_delays [list]
            set min_delays [list]
        }

        # Clock definitions
        method add_clock {name period {waveform {}} {port_pin ""}} {
            if {[llength $waveform] == 0} {
                set waveform [list 0.0 [expr {$period / 2.0}]]
            }
            dict set clocks $name [dict create \
                name $name \
                period $period \
                waveform $waveform \
                port $port_pin]
        }

        method has_clock {name} {
            return [dict exists $clocks $name]
        }

        method get_clocks {} {
            return [dict keys $clocks]
        }

        method get_clock {name} {
            if {[dict exists $clocks $name]} {
                return [dict get $clocks $name]
            }
            return [dict create]
        }

        method get_clock_period {name} {
            if {[dict exists $clocks $name]} {
                return [dict get [dict get $clocks $name] period]
            }
            return 0.0
        }

        # Clock uncertainty (jitter / skew budget)
        method set_clock_uncertainty {clk_name {setup_unc 0.0} {hold_unc 0.0}} {
            dict set clock_uncertainties $clk_name [dict create \
                setup $setup_unc \
                hold $hold_unc]
        }

        method get_clock_uncertainty {clk_name type} {
            if {[dict exists $clock_uncertainties $clk_name]} {
                set uinfo [dict get $clock_uncertainties $clk_name]
                if {[dict exists $uinfo $type]} {
                    return [dict get $uinfo $type]
                }
            }
            return 0.0
        }

        # Clock latency (source / network insertion delay)
        method set_clock_latency {clk_name {early_lat 0.0} {late_lat 0.0}} {
            dict set clock_latencies $clk_name [dict create \
                early $early_lat \
                late $late_lat]
        }

        method get_clock_latency {clk_name type} {
            if {[dict exists $clock_latencies $clk_name]} {
                set linfo [dict get $clock_latencies $clk_name]
                if {[dict exists $linfo $type]} {
                    return [dict get $linfo $type]
                }
            }
            return 0.0
        }

        # Input and output external delays
        method set_input_delay {port delay {clock ""} {delay_type "max"}} {
            set entry [dict create clock $clock delay $delay type $delay_type]
            dict lappend input_delays $port $entry
        }

        method get_input_delays {port} {
            if {[dict exists $input_delays $port]} {
                return [dict get $input_delays $port]
            }
            return [list]
        }

        method get_max_input_delay {port} {
            set max_d 0.0
            foreach entry [my get_input_delays $port] {
                set d [dict get $entry delay]
                if {$d > $max_d} { set max_d $d }
            }
            return $max_d
        }

        method set_output_delay {port delay {clock ""} {delay_type "max"}} {
            set entry [dict create clock $clock delay $delay type $delay_type]
            dict lappend output_delays $port $entry
        }

        method get_output_delays {port} {
            if {[dict exists $output_delays $port]} {
                return [dict get $output_delays $port]
            }
            return [list]
        }

        method get_max_output_delay {port} {
            set max_d 0.0
            foreach entry [my get_output_delays $port] {
                set d [dict get $entry delay]
                if {$d > $max_d} { set max_d $d }
            }
            return $max_d
        }

        # Electrical environment constraints
        method set_load {port cap_ff} {
            dict set port_loads $port $cap_ff
        }

        method get_load {port {default_val 0.0}} {
            if {[dict exists $port_loads $port]} {
                return [dict get $port_loads $port]
            }
            return $default_val
        }

        method set_input_transition {port slew_ps} {
            dict set input_transitions $port $slew_ps
        }

        method get_input_transition {port {default_val 10.0}} {
            if {[dict exists $input_transitions $port]} {
                return [dict get $input_transitions $port]
            }
            return $default_val
        }

        method set_driving_cell {port lib_cell {pin "Y"}} {
            dict set driving_cells $port [dict create lib_cell $lib_cell pin $pin]
        }

        method get_driving_cell {port} {
            if {[dict exists $driving_cells $port]} {
                return [dict get $driving_cells $port]
            }
            return [dict create]
        }

        # Path exceptions
        method add_false_path {{from ""} {to ""} {through ""}} {
            lappend false_paths [dict create from $from to $to through $through]
        }

        method is_false_path {from to} {
            foreach fp $false_paths {
                set m_from [dict get $fp from]
                set m_to [dict get $fp to]
                set from_match [expr {$m_from eq "" || $m_from eq $from || [string match $m_from $from]}]
                set to_match   [expr {$m_to eq ""   || $m_to eq $to   || [string match $m_to $to]}]
                if {$from_match && $to_match && ($m_from ne "" || $m_to ne "")} {
                    return 1
                }
            }
            return 0
        }

        method add_multicycle_path {multiplier {type "setup"} {from ""} {to ""}} {
            lappend multicycle_paths [dict create \
                multiplier $multiplier \
                type $type \
                from $from \
                to $to]
        }

        method get_multicycle_setup {from to} {
            foreach mp $multicycle_paths {
                if {[dict get $mp type] eq "setup"} {
                    set m_from [dict get $mp from]
                    set m_to [dict get $mp to]
                    set from_match [expr {$m_from eq "" || $m_from eq $from || [string match $m_from $from]}]
                    set to_match   [expr {$m_to eq ""   || $m_to eq $to   || [string match $m_to $to]}]
                    if {$from_match && $to_match && ($m_from ne "" || $m_to ne "")} {
                        return [dict get $mp multiplier]
                    }
                }
            }
            return 1 ;# Default single-cycle path
        }
    }
}
