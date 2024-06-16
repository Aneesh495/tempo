# Tempo Clock Domain and Clock Tree Analysis Engine
# Computes clock tree insertion delay, clock skew, and uncertainty budgets
# Namespace: ::tempo::sta::clock

namespace eval ::tempo::sta::clock {

    oo::class create ClockTreeAnalyzer {
        variable constraints    ;# ::tempo::sdc::Constraints
        variable timing_graph   ;# ::tempo::sta::graph::TimingGraph
        variable clock_latencies ;# dict: pin_ref -> dict(early: float, late: float)

        constructor {c tg} {
            set constraints $c
            set timing_graph $tg
            my reset
        }

        method reset {} {
            set clock_latencies [dict create]
        }

        # Analyze clock network and propagate clock arrival times to register CK pins
        method analyze {} {
            my reset

            set clk_names [$constraints get_clocks]
            if {[llength $clk_names] == 0} {
                return
            }

            set default_clk [lindex $clk_names 0]
            set cinfo [$constraints get_clock $default_clk]
            set clk_port [dict get $cinfo port]

            set early_src_lat [$constraints get_clock_latency $default_clk "early"]
            set late_src_lat  [$constraints get_clock_latency $default_clk "late"]

            # Set latencies for all register clock pins
            foreach ck_pin [$timing_graph get_clock_pins] {
                # In basic clock tree, latency = source_latency + wire_insertion_delay
                # Insertion delay estimated or propagated
                set net_insertion 15.0 ;# typical clock buffer tree latency
                dict set clock_latencies $ck_pin [dict create \
                    early [expr {$early_src_lat + $net_insertion * 0.9}] \
                    late  [expr {$late_src_lat + $net_insertion * 1.1}]]
            }
        }

        method get_pin_latency {pin_ref type} {
            if {[dict exists $clock_latencies $pin_ref]} {
                return [dict get [dict get $clock_latencies $pin_ref] $type]
            }
            return 0.0
        }

        # Compute clock skew between launch register and capture register
        # skew = capture_latency - launch_latency
        method compute_skew {launch_pin capture_pin {is_setup 1}} {
            if {$is_setup} {
                # Setup check: worst-case skew is min capture latency - max launch latency
                set lat_launch [my get_pin_latency $launch_pin "late"]
                set lat_capture [my get_pin_latency $capture_pin "early"]
            } else {
                # Hold check: worst-case skew is max capture latency - min launch latency
                set lat_launch [my get_pin_latency $launch_pin "early"]
                set lat_capture [my get_pin_latency $capture_pin "late"]
            }
            return [expr {$lat_capture - $lat_launch}]
        }

        # Get uncertainty budget for clock domain
        method get_uncertainty {clk_name {is_setup 1}} {
            if {$clk_name eq ""} {
                set clks [$constraints get_clocks]
                if {[llength $clks] > 0} { set clk_name [lindex $clks 0] }
            }
            set utype [expr {$is_setup ? "setup" : "hold"}]
            return [$constraints get_clock_uncertainty $clk_name $utype]
        }
    }
}
