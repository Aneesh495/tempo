# Tempo Core Netlist Representation Engine
# Namespace: ::tempo::netlist

namespace eval ::tempo::netlist {

    oo::class create Netlist {
        variable name
        variable ports           ;# dict: port_name -> dict(dir: IN|OUT|INOUT, width: N, msb: M, lsb: L)
        variable nets            ;# dict: net_name -> dict(drivers: list, loads: list, cap: float)
        variable instances       ;# dict: inst_name -> dict(cell: type, pins: dict(pin_name -> net_name))
        variable top_module

        constructor {{mod_name "top"}} {
            set name $mod_name
            set top_module $mod_name
            my reset
        }

        method reset {} {
            set ports [dict create]
            set nets [dict create]
            set instances [dict create]
        }

        method get_name {} {
            return $name
        }

        method set_name {new_name} {
            set name $new_name
            set top_module $new_name
        }

        # Port management
        method add_port {port_name dir {width 1} {msb 0} {lsb 0}} {
            set udir [string toupper $dir]
            if {$udir ni {INPUT OUTPUT INOUT IN OUT}} {
                return -code error "Invalid port direction: $dir"
            }
            if {$udir eq "IN"} { set udir "INPUT" }
            if {$udir eq "OUT"} { set udir "OUTPUT" }

            dict set ports $port_name [dict create \
                dir $udir \
                width $width \
                msb $msb \
                lsb $lsb]

            # Automatically ensure corresponding net exists
            my add_net $port_name
        }

        method has_port {port_name} {
            return [dict exists $ports $port_name]
        }

        method get_ports {{dir_filter ""}} {
            if {$dir_filter eq ""} {
                return [dict keys $ports]
            }
            set ufilter [string toupper $dir_filter]
            if {$ufilter eq "IN"} { set ufilter "INPUT" }
            if {$ufilter eq "OUT"} { set ufilter "OUTPUT" }

            set res [list]
            dict for {pname pinfo} $ports {
                if {[dict get $pinfo dir] eq $ufilter} {
                    lappend res $pname
                }
            }
            return $res
        }

        method get_port_info {port_name} {
            if {[dict exists $ports $port_name]} {
                return [dict get $ports $port_name]
            }
            return [dict create]
        }

        # Net management
        method add_net {net_name {cap 0.0}} {
            if {![dict exists $nets $net_name]} {
                dict set nets $net_name [dict create \
                    drivers [list] \
                    loads [list] \
                    cap $cap]
            }
            return $net_name
        }

        method has_net {net_name} {
            return [dict exists $nets $net_name]
        }

        method get_nets {} {
            return [dict keys $nets]
        }

        method get_net_cap {net_name} {
            if {[dict exists $nets $net_name]} {
                return [dict get [dict get $nets $net_name] cap]
            }
            return 0.0
        }

        method set_net_cap {net_name cap} {
            my add_net $net_name
            dict set nets $net_name cap $cap
        }

        method get_net_drivers {net_name} {
            if {[dict exists $nets $net_name]} {
                return [dict get [dict get $nets $net_name] drivers]
            }
            return [list]
        }

        method get_net_loads {net_name} {
            if {[dict exists $nets $net_name]} {
                return [dict get [dict get $nets $net_name] loads]
            }
            return [list]
        }

        # Instance management
        method add_instance {inst_name cell_type {pin_conns {}}} {
            if {[dict exists $instances $inst_name]} {
                return -code error "Instance '$inst_name' already exists in netlist"
            }
            dict set instances $inst_name [dict create \
                cell $cell_type \
                pins [dict create]]

            dict for {pin net} $pin_conns {
                my connect_pin $inst_name $pin $net
            }
            return $inst_name
        }

        method remove_instance {inst_name} {
            if {![dict exists $instances $inst_name]} {
                return
            }
            # Disconnect all pins first
            set pins [dict get [dict get $instances $inst_name] pins]
            dict for {pin net} $pins {
                my disconnect_pin $inst_name $pin
            }
            dict unset instances $inst_name
        }

        method has_instance {inst_name} {
            return [dict exists $instances $inst_name]
        }

        method get_instances {} {
            return [dict keys $instances]
        }

        method get_instance_cell {inst_name} {
            if {[dict exists $instances $inst_name]} {
                return [dict get [dict get $instances $inst_name] cell]
            }
            return ""
        }

        method set_instance_cell {inst_name new_cell} {
            if {[dict exists $instances $inst_name]} {
                dict set instances $inst_name cell $new_cell
            }
        }

        method get_instance_names {} {
            return [my get_instances]
        }

        method get_cell_name {inst_name} {
            return [my get_instance_cell $inst_name]
        }

        method set_cell_name {inst_name new_cell} {
            my set_instance_cell $inst_name $new_cell
        }

        method get_instance_pins {inst_name} {
            if {[dict exists $instances $inst_name]} {
                return [dict get [dict get $instances $inst_name] pins]
            }
            return [dict create]
        }

        method get_pin_net {inst_name pin_name} {
            if {[dict exists $instances $inst_name]} {
                set pins [dict get [dict get $instances $inst_name] pins]
                if {[dict exists $pins $pin_name]} {
                    return [dict get $pins $pin_name]
                }
            }
            return ""
        }

        method connect_pin {inst_name pin_name net_name {pin_dir "LOAD"}} {
            if {![dict exists $instances $inst_name]} {
                return -code error "Instance '$inst_name' does not exist"
            }
            my add_net $net_name

            dict set instances $inst_name pins $pin_name $net_name

            set pin_ref "$inst_name/$pin_name"
            set udir [string toupper $pin_dir]

            set ninfo [dict get $nets $net_name]
            if {$udir eq "DRIVER" || $udir eq "OUTPUT" || $udir eq "OUT"} {
                set cur_drivers [dict get $ninfo drivers]
                if {$pin_ref ni $cur_drivers} {
                    lappend cur_drivers $pin_ref
                    dict set ninfo drivers $cur_drivers
                    dict set nets $net_name $ninfo
                }
            } else {
                set cur_loads [dict get $ninfo loads]
                if {$pin_ref ni $cur_loads} {
                    lappend cur_loads $pin_ref
                    dict set ninfo loads $cur_loads
                    dict set nets $net_name $ninfo
                }
            }
        }

        method disconnect_pin {inst_name pin_name} {
            if {![dict exists $instances $inst_name]} { return }
            set pins [dict get [dict get $instances $inst_name] pins]
            if {![dict exists $pins $pin_name]} { return }

            set net_name [dict get $pins $pin_name]
            set pin_ref "$inst_name/$pin_name"

            if {[dict exists $nets $net_name]} {
                set cur_drivers [dict get [dict get $nets $net_name] drivers]
                set new_drivers [list]
                foreach d $cur_drivers {
                    if {$d ne $pin_ref} { lappend new_drivers $d }
                }
                dict set nets $net_name drivers $new_drivers

                set cur_loads [dict get [dict get $nets $net_name] loads]
                set new_loads [list]
                foreach l $cur_loads {
                    if {$l ne $pin_ref} { lappend new_loads $l }
                }
                dict set nets $net_name loads $new_loads
            }

            dict unset instances $inst_name pins $pin_name
        }

        # Check netlist sanity: multi-driven nets, floating inputs, undriven nets
        method check_sanity {} {
            set issues [list]

            # Primary input ports act as drivers for their nets
            set primary_inputs [my get_ports "INPUT"]
            set primary_outputs [my get_ports "OUTPUT"]

            dict for {net_name ninfo} $nets {
                set drivers [dict get $ninfo drivers]
                set loads [dict get $ninfo loads]

                set is_pi [expr {$net_name in $primary_inputs}]
                set is_po [expr {$net_name in $primary_outputs}]

                set total_drivers [llength $drivers]
                if {$is_pi} { incr total_drivers }

                set total_loads [llength $loads]
                if {$is_po} { incr total_loads }

                if {$total_drivers == 0} {
                    lappend issues "UNDRIVEN_NET: Net '$net_name' has no drivers"
                } elseif {$total_drivers > 1} {
                    lappend issues "MULTI_DRIVEN_NET: Net '$net_name' has $total_drivers conflicting drivers: \[[join $drivers {, }]\]"
                }

                if {$total_loads == 0} {
                    lappend issues "FLOATING_NET: Net '$net_name' has no loads"
                }
            }

            return $issues
        }

        # Return comprehensive statistical summary
        method get_stats {} {
            set cell_types [dict create]
            dict for {iname iinfo} $instances {
                set c [dict get $iinfo cell]
                set count 0
                if {[dict exists $cell_types $c]} {
                    set count [dict get $cell_types $c]
                }
                dict set cell_types $c [expr {$count + 1}]
            }

            return [dict create \
                name $name \
                num_inputs [llength [my get_ports "INPUT"]] \
                num_outputs [llength [my get_ports "OUTPUT"]] \
                num_ports [dict size $ports] \
                num_nets [dict size $nets] \
                num_instances [dict size $instances] \
                cell_histogram $cell_types]
        }

        # Deep clone of the netlist
        method clone {{new_name ""}} {
            if {$new_name eq ""} {
                set new_name "${name}_clone"
            }
            set copy [::tempo::netlist::Netlist new $new_name]

            # Copy ports
            dict for {pname pinfo} $ports {
                $copy add_port $pname [dict get $pinfo dir] \
                    [dict get $pinfo width] [dict get $pinfo msb] [dict get $pinfo lsb]
            }

            # Copy nets
            dict for {nname ninfo} $nets {
                $copy add_net $nname [dict get $ninfo cap]
            }

            # Copy instances
            dict for {iname iinfo} $instances {
                set cell [dict get $iinfo cell]
                set pins [dict get $iinfo pins]
                $copy add_instance $iname $cell $pins
            }

            return $copy
        }
    }
}
