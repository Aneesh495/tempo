# Tempo Structural Verilog Parser
# Parses Verilog-2005 netlists into ::tempo::netlist::Netlist objects
# Namespace: ::tempo::verilog::parser

namespace eval ::tempo::verilog::parser {

    proc parse {tokens {lib_lookup ""}} {
        set idx 0
        set len [llength $tokens]

        # Scan for module declaration
        while {$idx < $len && [lindex [lindex $tokens $idx] 0] ne "KW_MODULE"} {
            incr idx
        }
        if {$idx >= $len} {
            return -code error "No module declaration found in Verilog source"
        }

        incr idx ;# consume KW_MODULE
        if {$idx >= $len || [lindex [lindex $tokens $idx] 0] ne "IDENT"} {
            return -code error "Expected module name identifier"
        }
        set mod_name [lindex [lindex $tokens $idx] 1]
        incr idx

        set netlist [::tempo::netlist::Netlist new $mod_name]

        # Optional port list in header: module name ( ... );
        if {$idx < $len && [lindex [lindex $tokens $idx] 0] eq "LPAREN"} {
            incr idx
            while {$idx < $len && [lindex [lindex $tokens $idx] 0] ne "RPAREN"} {
                # Could be ANSI C-style port declarations (input a, output b) or just port names
                set tok_type [lindex [lindex $tokens $idx] 0]
                if {$tok_type in {KW_INPUT KW_OUTPUT KW_INOUT}} {
                    _parse_port_decl tokens idx len $netlist
                } else {
                    incr idx ;# skip port name or comma
                }
            }
            if {$idx < $len && [lindex [lindex $tokens $idx] 0] eq "RPAREN"} {
                incr idx
            }
        }

        # Expect semicolon after module header
        if {$idx < $len && [lindex [lindex $tokens $idx] 0] eq "SEMICOLON"} {
            incr idx
        }

        # Parse module body
        while {$idx < $len} {
            set tok [lindex $tokens $idx]
            set ttype [lindex $tok 0]
            set tval [lindex $tok 1]
            set tline [lindex $tok 2]

            if {$ttype eq "KW_ENDMODULE"} {
                incr idx
                break
            }

            switch -exact -- $ttype {
                "KW_INPUT" - "KW_OUTPUT" - "KW_INOUT" {
                    _parse_port_decl tokens idx len $netlist
                }
                "KW_WIRE" - "KW_REG" {
                    _parse_wire_decl tokens idx len $netlist
                }
                "KW_ASSIGN" {
                    _parse_assign tokens idx len $netlist
                }
                "KW_PRIM" {
                    _parse_primitive tokens idx len $netlist
                }
                "IDENT" {
                    _parse_cell_instance tokens idx len $netlist $lib_lookup
                }
                "SEMICOLON" {
                    incr idx
                }
                default {
                    incr idx
                }
            }
        }

        return $netlist
    }

    # Parse port declarations (e.g., input [7:0] data, clk;)
    proc _parse_port_decl {tokens_var idx_var len netlist} {
        upvar 1 $tokens_var tokens
        upvar 1 $idx_var idx

        set dir_tok [lindex $tokens $idx]
        set dir [string range [lindex $dir_tok 0] 3 end] ;# INPUT, OUTPUT, INOUT
        incr idx

        # Check for bit range: [msb:lsb]
        set range [_parse_range tokens idx $len]
        set msb [lindex $range 0]
        set lsb [lindex $range 1]
        set width [lindex $range 2]

        while {$idx < $len} {
            set tok [lindex $tokens $idx]
            if {[lindex $tok 0] eq "IDENT"} {
                set pname [lindex $tok 1]
                incr idx

                if {$width == 1} {
                    $netlist add_port $pname $dir 1 0 0
                } else {
                    $netlist add_port $pname $dir $width $msb $lsb
                    # Expand scalar nets for each bit in the bus
                    set step [expr {$msb >= $lsb ? -1 : 1}]
                    for {set b $msb} {1} {incr b $step} {
                        $netlist add_net "${pname}\[$b\]"
                        if {$b == $lsb} { break }
                    }
                }
            }
            if {$idx < $len && [lindex [lindex $tokens $idx] 0] eq "COMMA"} {
                incr idx
                # If next token is input/output/inout, break out to let outer loop parse it
                if {$idx < $len && [lindex [lindex $tokens $idx] 0] in {KW_INPUT KW_OUTPUT KW_INOUT}} {
                    break
                }
                continue
            }
            if {$idx < $len && [lindex [lindex $tokens $idx] 0] in {SEMICOLON RPAREN}} {
                if {[lindex [lindex $tokens $idx] 0] eq "SEMICOLON"} { incr idx }
                break
            }
        }
    }

    # Parse wire declarations (e.g., wire [3:0] w;)
    proc _parse_wire_decl {tokens_var idx_var len netlist} {
        upvar 1 $tokens_var tokens
        upvar 1 $idx_var idx
        incr idx ;# consume KW_WIRE or KW_REG

        set range [_parse_range tokens idx $len]
        set msb [lindex $range 0]
        set lsb [lindex $range 1]
        set width [lindex $range 2]

        while {$idx < $len} {
            set tok [lindex $tokens $idx]
            if {[lindex $tok 0] eq "IDENT"} {
                set wname [lindex $tok 1]
                incr idx
                if {$width == 1} {
                    $netlist add_net $wname
                } else {
                    set step [expr {$msb >= $lsb ? -1 : 1}]
                    for {set b $msb} {1} {incr b $step} {
                        $netlist add_net "${wname}\[$b\]"
                        if {$b == $lsb} { break }
                    }
                }
            }
            if {$idx < $len && [lindex [lindex $tokens $idx] 0] eq "COMMA"} {
                incr idx
                continue
            }
            if {$idx < $len && [lindex [lindex $tokens $idx] 0] eq "SEMICOLON"} {
                incr idx
                break
            }
        }
    }

    # Parse [msb:lsb] range
    proc _parse_range {tokens_var idx_var len} {
        upvar 1 $tokens_var tokens
        upvar 1 $idx_var idx

        if {$idx < $len && [lindex [lindex $tokens $idx] 0] eq "LBRACK"} {
            incr idx ;# consume [
            set msb [lindex [lindex $tokens $idx] 1]
            incr idx
            incr idx ;# consume :
            set lsb [lindex [lindex $tokens $idx] 1]
            incr idx
            incr idx ;# consume ]
            set width [expr {abs($msb - $lsb) + 1}]
            return [list $msb $lsb $width]
        }
        return [list 0 0 1]
    }

    # Parse cell instance: CellType InstName (.Pin(Net), ...);
    proc _parse_cell_instance {tokens_var idx_var len netlist lib_lookup} {
        upvar 1 $tokens_var tokens
        upvar 1 $idx_var idx

        set cell_type [lindex [lindex $tokens $idx] 1]
        incr idx

        set inst_name [lindex [lindex $tokens $idx] 1]
        incr idx

        $netlist add_instance $inst_name $cell_type

        # Expect LPAREN
        if {$idx < $len && [lindex [lindex $tokens $idx] 0] eq "LPAREN"} {
            incr idx
        }

        # Parse port connections
        while {$idx < $len && [lindex [lindex $tokens $idx] 0] ne "RPAREN"} {
            set tok [lindex $tokens $idx]
            if {[lindex $tok 0] eq "DOT"} {
                incr idx ;# consume .
                set pin_name [lindex [lindex $tokens $idx] 1]
                incr idx ;# consume pin name
                incr idx ;# consume (
                set net_ref [_parse_net_ref tokens idx $len]
                incr idx ;# consume )

                # Determine pin direction if library is available
                set pin_dir "LOAD"
                if {$lib_lookup ne "" && [$lib_lookup has_cell $cell_type]} {
                    set cinfo [$lib_lookup get_cell $cell_type]
                    set pins [dict get $cinfo pins]
                    if {[dict exists $pins $pin_name]} {
                        set pdir [dict get [dict get $pins $pin_name] direction]
                        if {$pdir eq "output"} {
                            set pin_dir "DRIVER"
                        }
                    }
                } else {
                    # Standard naming convention fallback: Y, Q, Z, OUT are outputs
                    if {$pin_name in {Y Q Z OUT YN QN}} {
                        set pin_dir "DRIVER"
                    }
                }

                $netlist connect_pin $inst_name $pin_name $net_ref $pin_dir
            }
            if {$idx < $len && [lindex [lindex $tokens $idx] 0] eq "COMMA"} {
                incr idx
            }
        }

        if {$idx < $len && [lindex [lindex $tokens $idx] 0] eq "RPAREN"} {
            incr idx
        }
        if {$idx < $len && [lindex [lindex $tokens $idx] 0] eq "SEMICOLON"} {
            incr idx
        }
    }

    # Parse primitive gate instance: and u1 (y, a, b);
    proc _parse_primitive {tokens_var idx_var len netlist} {
        upvar 1 $tokens_var tokens
        upvar 1 $idx_var idx

        set prim_type [lindex [lindex $tokens $idx] 1]
        incr idx

        set inst_name [lindex [lindex $tokens $idx] 1]
        incr idx

        $netlist add_instance $inst_name [string toupper $prim_type]

        if {$idx < $len && [lindex [lindex $tokens $idx] 0] eq "LPAREN"} {
            incr idx
        }

        # First port of Verilog primitive is always the output (DRIVER)
        set is_first 1
        set in_counter 0

        while {$idx < $len && [lindex [lindex $tokens $idx] 0] ne "RPAREN"} {
            if {[lindex [lindex $tokens $idx] 0] eq "DOT"} {
                incr idx ;# consume .
                set pin_name [lindex [lindex $tokens $idx] 1]
                incr idx
                incr idx ;# consume (
                set net_ref [_parse_net_ref tokens idx len]
                incr idx ;# consume )
                set pin_dir "LOAD"
                if {$pin_name eq "Y" || $pin_name eq "OUT"} { set pin_dir "DRIVER" }
                $netlist connect_pin $inst_name $pin_name $net_ref $pin_dir
            } else {
                set net_ref [_parse_net_ref tokens idx len]
                if {$is_first} {
                    $netlist connect_pin $inst_name "Y" $net_ref "DRIVER"
                    set is_first 0
                } else {
                    set pnames {A B C D E F}
                    set pname [lindex $pnames $in_counter]
                    if {$pname eq ""} { set pname "IN_$in_counter" }
                    $netlist connect_pin $inst_name $pname $net_ref "LOAD"
                    incr in_counter
                }
            }
            if {$idx < $len && [lindex [lindex $tokens $idx] 0] eq "COMMA"} {
                incr idx
            }
        }

        if {$idx < $len && [lindex [lindex $tokens $idx] 0] eq "RPAREN"} {
            incr idx
        }
        if {$idx < $len && [lindex [lindex $tokens $idx] 0] eq "SEMICOLON"} {
            incr idx
        }
    }

    # Parse continuous assignment: assign y = a & b;
    proc _parse_assign {tokens_var idx_var len netlist} {
        upvar 1 $tokens_var tokens
        upvar 1 $idx_var idx
        incr idx ;# consume KW_ASSIGN

        set lhs [_parse_net_ref tokens idx len]
        incr idx ;# consume =

        set rhs [_parse_net_ref tokens idx len]

        # Consume up to semicolon
        while {$idx < $len && [lindex [lindex $tokens $idx] 0] ne "SEMICOLON"} {
            incr idx
        }
        if {$idx < $len && [lindex [lindex $tokens $idx] 0] eq "SEMICOLON"} {
            incr idx
        }

        # Synthesize buffer instance for continuous assignment
        set inst_name "assign_buf_[string map {\[ _ \] _} $lhs]"
        $netlist add_instance $inst_name "BUF_X1"
        $netlist connect_pin $inst_name "A" $rhs "LOAD"
        $netlist connect_pin $inst_name "Y" $lhs "DRIVER"
    }

    # Helper to parse net name with optional bit slice: e.g. "w" or "data[2]"
    proc _parse_net_ref {tokens_var idx_var len} {
        upvar 1 $tokens_var tokens
        upvar 1 $idx_var idx

        set base_name [lindex [lindex $tokens $idx] 1]
        incr idx

        # Check for bracket slice: [idx]
        if {$idx < $len && [lindex [lindex $tokens $idx] 0] eq "LBRACK"} {
            incr idx ;# consume [
            set bidx [lindex [lindex $tokens $idx] 1]
            incr idx ;# consume number
            incr idx ;# consume ]
            return "${base_name}\[${bidx}\]"
        }
        return $base_name
    }
}
