# ==============================================================================
# Buffer and Repeater Insertion Engine
#
# Remediates electrical design rule violations (max transition, max capacitance)
# and optimizes high-fanout nets by inserting repeater buffers or constructing
# balanced buffer trees.
# ==============================================================================

namespace eval ::tempo::opt::buffer {
    oo::class create BufferInserter {
        variable netlist
        variable library
        variable buf_counter

        constructor {nl lib} {
            set netlist $nl
            set library $lib
            set buf_counter 0
        }

        # Query input and output pin names for a buffer cell
        method _get_buf_pins {buf_cell} {
            set cinfo [$library get_cell $buf_cell]
            if {$cinfo eq ""} {
                return [list "A" "Y"]
            }
            set in_pin "A"
            set out_pin "Y"
            set pins [dict get $cinfo pins]
            foreach {pname pinfo} $pins {
                set dir [dict get $pinfo direction]
                if {$dir eq "input"} { set in_pin $pname }
                if {$dir eq "output"} { set out_pin $pname }
            }
            return [list $in_pin $out_pin]
        }

        # Insert a buffer on an entire net, driving all current loads
        method insert_buffer_on_net {net_name {buf_cell "BUF_X2"}} {
            incr buf_counter
            set buf_inst "u_tempo_buf_${buf_counter}"
            set buf_out_net "${net_name}_buf_${buf_counter}"

            lassign [my _get_buf_pins $buf_cell] in_pin out_pin

            # Current loads on the net
            set loads [$netlist get_net_loads $net_name]
            if {[llength $loads] == 0} {
                return ""
            }

            # Add new buffered net
            $netlist add_net $buf_out_net

            # Add buffer instance
            $netlist add_instance $buf_inst $buf_cell

            # Connect buffer input to original net
            $netlist connect_pin $buf_inst $in_pin $net_name "LOAD"

            # Connect buffer output to new net
            $netlist connect_pin $buf_inst $out_pin $buf_out_net "DRIVER"

            # Reconnect all existing loads from original net to new net
            foreach ld $loads {
                set parts [split $ld "/"]
                set ld_inst [lindex $parts 0]
                set ld_pin  [lindex $parts 1]

                $netlist disconnect_pin $ld_inst $ld_pin
                $netlist connect_pin $ld_inst $ld_pin $buf_out_net "LOAD"
            }

            return [dict create \
                instance $buf_inst \
                cell $buf_cell \
                in_net $net_name \
                out_net $buf_out_net \
                loads_moved [llength $loads]]
        }

        # Split high-fanout net into clusters of maximum fanout
        method split_high_fanout_net {net_name max_fanout {buf_cell "BUF_X2"}} {
            set loads [$netlist get_net_loads $net_name]
            set total_loads [llength $loads]
            if {$total_loads <= $max_fanout} {
                return [list]
            }

            lassign [my _get_buf_pins $buf_cell] in_pin out_pin
            set results [list]

            # Partition loads into chunks of size max_fanout
            set chunk_idx 0
            for {set i 0} {$i < $total_loads} {incr i $max_fanout} {
                set chunk [lrange $loads $i [expr {min($i + $max_fanout - 1, $total_loads - 1)}]]
                incr buf_counter
                incr chunk_idx

                set buf_inst "u_tempo_tree_buf_${buf_counter}"
                set branch_net "${net_name}_branch_${chunk_idx}"

                $netlist add_net $branch_net
                $netlist add_instance $buf_inst $buf_cell
                $netlist connect_pin $buf_inst $in_pin $net_name "LOAD"
                $netlist connect_pin $buf_inst $out_pin $branch_net "DRIVER"

                foreach ld $chunk {
                    set parts [split $ld "/"]
                    set ld_inst [lindex $parts 0]
                    set ld_pin  [lindex $parts 1]

                    $netlist disconnect_pin $ld_inst $ld_pin
                    $netlist connect_pin $ld_inst $ld_pin $branch_net "LOAD"
                }

                lappend results [dict create \
                    instance $buf_inst \
                    branch_net $branch_net \
                    loads_count [llength $chunk]]
            }

            return $results
        }
    }
}
