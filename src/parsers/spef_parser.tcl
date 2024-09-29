# Tempo Standard Parasitic Exchange Format (SPEF) Parser and RC Network Model
# Parses IEEE 1481 SPEF files representing post-route wire parasitics (R, C, coupling C)
# Namespace: ::tempo::spef

namespace eval ::tempo::spef {

    oo::class create SpefNetwork {
        variable design_name
        variable time_unit
        variable cap_unit
        variable res_unit
        variable nets ;# dict: net_name -> dict(total_cap, conn, caps, res)

        constructor {} {
            my reset
        }

        method reset {} {
            set design_name ""
            set time_unit 1.0 ;# ps
            set cap_unit 1.0  ;# fF
            set res_unit 1.0  ;# ohm
            set nets [dict create]
        }

        method get_design_name {} { return $design_name }
        method set_design_name {name} { set design_name $name }

        method add_net {net_name total_cap} {
            dict set nets $net_name [dict create \
                name $net_name \
                total_cap [expr {$total_cap * $cap_unit}] \
                conn [list] \
                caps [dict create] \
                res [list]]
        }

        method has_net {net_name} {
            return [dict exists $nets $net_name]
        }

        method get_net_cap {net_name} {
            if {[dict exists $nets $net_name]} {
                return [dict get [dict get $nets $net_name] total_cap]
            }
            return 0.0
        }

        method add_conn {net_name pin_name dir} {
            if {![my has_net $net_name]} { my add_net $net_name 0.0 }
            set cur [dict get [dict get $nets $net_name] conn]
            lappend cur [dict create pin $pin_name dir $dir]
            dict set nets $net_name conn $cur
        }

        method add_cap {net_name node_name cap_val} {
            if {![my has_net $net_name]} { my add_net $net_name 0.0 }
            dict set nets $net_name caps $node_name [expr {$cap_val * $cap_unit}]
        }

        method add_res {net_name node1 node2 res_val} {
            if {![my has_net $net_name]} { my add_net $net_name 0.0 }
            set cur [dict get [dict get $nets $net_name] res]
            lappend cur [dict create \
                node1 $node1 \
                node2 $node2 \
                res [expr {$res_val * $res_unit}]]
            dict set nets $net_name res $cur
        }

        method get_net_res_segments {net_name} {
            if {[dict exists $nets $net_name]} {
                return [dict get [dict get $nets $net_name] res]
            }
            return [list]
        }

        method get_net_node_caps {net_name} {
            if {[dict exists $nets $net_name]} {
                return [dict get [dict get $nets $net_name] caps]
            }
            return [dict create]
        }

        method all_nets {} {
            return [dict keys $nets]
        }
    }

    # Parse SPEF text content
    proc parse {content} {
        set net_obj [::tempo::spef::SpefNetwork new]
        set lines [split $content "\n"]
        set len [llength $lines]

        set cur_section ""
        set cur_net ""

        for {set i 0} {$i < $len} {incr i} {
            set line [string trim [lindex $lines $i]]
            # Skip empty lines and full line comments
            if {$line eq "" || [string match "//*" $line]} { continue }

            # Handle backslash line continuations
            while {[string index $line end] eq "\\"} {
                set line [string range $line 0 end-1]
                incr i
                if {$i < $len} {
                    append line " " [string trim [lindex $lines $i]]
                }
            }

            set tokens [regexp -all -inline {\S+} $line]
            if {[llength $tokens] == 0} { continue }

            set first [lindex $tokens 0]

            # Header directives
            if {$first eq "*DESIGN"} {
                $net_obj set_design_name [string trim [lindex $tokens 1] "\""]
                continue
            }
            if {$first eq "*D_NET"} {
                set cur_net [lindex $tokens 1]
                set tot_cap 0.0
                if {[llength $tokens] >= 3} {
                    set tot_cap [expr {[lindex $tokens 2] + 0.0}]
                }
                $net_obj add_net $cur_net $tot_cap
                set cur_section "D_NET"
                continue
            }
            if {$first eq "*CONN"} {
                set cur_section "CONN"
                continue
            }
            if {$first eq "*CAP"} {
                set cur_section "CAP"
                continue
            }
            if {$first eq "*RES"} {
                set cur_section "RES"
                continue
            }
            if {$first eq "*END"} {
                set cur_section ""
                set cur_net ""
                continue
            }

            # Section item processing
            switch -exact -- $cur_section {
                "CONN" {
                    if {$first eq "*P" || $first eq "*I"} {
                        set pin [lindex $tokens 1]
                        set dir [lindex $tokens 2]
                        $net_obj add_conn $cur_net $pin $dir
                    }
                }
                "CAP" {
                    # Format: id node cap
                    if {[llength $tokens] >= 3} {
                        set node [lindex $tokens 1]
                        set cap [expr {[lindex $tokens 2] + 0.0}]
                        $net_obj add_cap $cur_net $node $cap
                    }
                }
                "RES" {
                    # Format: id node1 node2 res
                    if {[llength $tokens] >= 4} {
                        set n1 [lindex $tokens 1]
                        set n2 [lindex $tokens 2]
                        set r [expr {[lindex $tokens 3] + 0.0}]
                        $net_obj add_res $cur_net $n1 $n2 $r
                    }
                }
            }
        }

        return $net_obj
    }

    proc parse_file {filepath} {
        if {![file exists $filepath]} {
            return -code error "SPEF file does not exist: $filepath"
        }
        set fp [open $filepath r]
        set content [read $fp]
        close $fp
        return [parse $content]
    }

    proc read_spef_file {filepath} {
        return [parse_file $filepath]
    }
}

namespace eval ::tempo::spef {
    namespace export read_spef_file
}
