# Tempo Static Timing Analysis (STA) Bipartite Timing Graph Builder
# Constructs pin nodes, cell timing arcs, net wire arcs, and path boundaries
# Namespace: ::tempo::sta::graph

namespace eval ::tempo::sta::graph {

    oo::class create TimingGraph {
        variable netlist        ;# ::tempo::netlist::Netlist
        variable library        ;# ::tempo::liberty::Library
        variable base_graph     ;# ::tempo::graph::Graph
        variable pin_nodes      ;# dict: pin_ref -> node_id
        variable startpoints    ;# list of pin_refs (PIs, Register Q pins)
        variable endpoints      ;# list of pin_refs (POs, Register D pins)
        variable clock_pins     ;# list of pin_refs (Register CK pins)

        constructor {nl lib} {
            set netlist $nl
            set library $lib
            set base_graph [::tempo::graph::Graph new]
            my reset
        }

        method reset {} {
            $base_graph reset
            set pin_nodes [dict create]
            set startpoints [list]
            set endpoints [list]
            set clock_pins [list]
        }

        method get_graph {} { return $base_graph }
        method get_startpoints {} { return $startpoints }
        method get_endpoints {} { return $endpoints }
        method get_clock_pins {} { return $clock_pins }

        # Build full timing graph from netlist and library
        method build {} {
            my reset

            # 1. Create timing nodes for Primary Inputs and Primary Outputs
            foreach pi [$netlist get_ports "INPUT"] {
                set nid "port:$pi"
                $base_graph add_node $nid "PORT_IN" [dict create name $pi dir "INPUT"]
                dict set pin_nodes $pi $nid
                lappend startpoints $pi
            }

            foreach po [$netlist get_ports "OUTPUT"] {
                set nid "port:$po"
                $base_graph add_node $nid "PORT_OUT" [dict create name $po dir "OUTPUT"]
                dict set pin_nodes $po $nid
                lappend endpoints $po
            }

            # 2. Create timing nodes for instance pins
            foreach inst [$netlist get_instances] {
                set cell_type [$netlist get_instance_cell $inst]
                set is_seq 0
                if {[$library has_cell $cell_type]} {
                    set cinfo [$library get_cell $cell_type]
                    set is_seq [dict get $cinfo is_sequential]
                }

                set pin_map [$netlist get_instance_pins $inst]
                dict for {pin net} $pin_map {
                    set pin_ref "$inst/$pin"
                    set nid "pin:$pin_ref"
                    set pdir "LOAD"
                    if {$pin in {Y Q Z OUT YN QN}} { set pdir "DRIVER" }

                    $base_graph add_node $nid "PIN" [dict create \
                        inst $inst \
                        pin $pin \
                        cell $cell_type \
                        pin_ref $pin_ref \
                        dir $pdir \
                        is_sequential $is_seq]
                    dict set pin_nodes $pin_ref $nid

                    # Classify sequential register pins
                    if {$is_seq} {
                        if {$pin eq "CK" || $pin eq "CLK"} {
                            lappend clock_pins $pin_ref
                        } elseif {$pin eq "D"} {
                            lappend endpoints $pin_ref
                        } elseif {$pin eq "Q" || $pin eq "QN"} {
                            lappend startpoints $pin_ref
                        }
                    }
                }

                # 3. Add internal cell timing arcs (input pin -> output pin)
                if {!$is_seq} {
                    # Combinational cell: connect every input pin to output pin Y
                    set out_pin "Y"
                    if {![dict exists $pin_map $out_pin]} {
                        # Find output pin
                        dict for {p n} $pin_map {
                            if {$p in {Y Q Z OUT}} { set out_pin $p; break }
                        }
                    }

                    if {[dict exists $pin_map $out_pin]} {
                        set out_node [dict get $pin_nodes "$inst/$out_pin"]
                        dict for {in_pin net} $pin_map {
                            if {$in_pin ne $out_pin} {
                                set in_node [dict get $pin_nodes "$inst/$in_pin"]
                                $base_graph add_edge $in_node $out_node "CELL_ARC" [dict create \
                                    cell $cell_type \
                                    from_pin $in_pin \
                                    to_pin $out_pin \
                                    inst $inst]
                            }
                        }
                    }
                } else {
                    # Sequential cell: connect CK -> Q (clock-to-Q arc)
                    set ck_pin "CK"
                    set q_pin "Q"
                    if {[dict exists $pin_map $ck_pin] && [dict exists $pin_map $q_pin]} {
                        set ck_node [dict get $pin_nodes "$inst/$ck_pin"]
                        set q_node [dict get $pin_nodes "$inst/$q_pin"]
                        $base_graph add_edge $ck_node $q_node "SEQ_CLK_TO_Q" [dict create \
                            cell $cell_type \
                            from_pin $ck_pin \
                            to_pin $q_pin \
                            inst $inst]
                    }
                }
            }

            # 4. Add net timing arcs (driver pin -> load pins)
            foreach net_name [$netlist get_nets] {
                set drivers [$netlist get_net_drivers $net_name]
                set loads [$netlist get_net_loads $net_name]

                # If net is a primary input, port is driver
                if {[$netlist has_port $net_name] && [dict get [$netlist get_port_info $net_name] dir] eq "INPUT"} {
                    set drv_node [dict get $pin_nodes $net_name]
                    foreach l $loads {
                        if {[dict exists $pin_nodes $l]} {
                            set load_node [dict get $pin_nodes $l]
                            $base_graph add_edge $drv_node $load_node "NET_ARC" [dict create net $net_name]
                        }
                    }
                } else {
                    foreach d $drivers {
                        if {![dict exists $pin_nodes $d]} { continue }
                        set drv_node [dict get $pin_nodes $d]

                        # Connect to primary output if applicable
                        if {[$netlist has_port $net_name] && [dict get [$netlist get_port_info $net_name] dir] eq "OUTPUT"} {
                            set po_node [dict get $pin_nodes $net_name]
                            $base_graph add_edge $drv_node $po_node "NET_ARC" [dict create net $net_name]
                        }

                        # Connect to all load pins
                        foreach l $loads {
                            if {[dict exists $pin_nodes $l]} {
                                set load_node [dict get $pin_nodes $l]
                                $base_graph add_edge $drv_node $load_node "NET_ARC" [dict create net $net_name]
                            }
                        }
                    }
                }
            }
        }

        method get_node_by_pin {pin_ref} {
            if {[dict exists $pin_nodes $pin_ref]} {
                return [dict get $pin_nodes $pin_ref]
            }
            return ""
        }
    }
}
