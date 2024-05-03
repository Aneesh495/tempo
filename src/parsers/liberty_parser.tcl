# Tempo Liberty (.lib) Parser
# Recursive-descent parser translating tokens into structured AST
# Namespace: ::tempo::liberty::parser

namespace eval ::tempo::liberty::parser {

    proc parse {tokens} {
        set idx 0
        set len [llength $tokens]
        return [_parse_statement_list tokens idx $len 0]
    }

    proc _parse_statement_list {tokens_var idx_var len is_root} {
        upvar 1 $tokens_var tokens
        upvar 1 $idx_var idx

        set ast [dict create _groups [list] _attrs [dict create]]

        while {$idx < $len} {
            set tok [lindex $tokens $idx]
            set type [lindex $tok 0]
            set val [lindex $tok 1]
            set line [lindex $tok 2]

            # Reached end of current group block
            if {$type eq "RBRACE"} {
                if {$is_root} {
                    return -code error "Unexpected closing brace '\}' at line $line"
                }
                incr idx
                break
            }

            # Must start with IDENT
            if {$type ne "IDENT"} {
                # Skip stray semicolons
                if {$type eq "SEMICOLON"} {
                    incr idx
                    continue
                }
                return -code error "Expected identifier at line $line, got '$val' ($type)"
            }

            set stmt_name $val
            incr idx

            # Lookahead to determine whether this is an attribute or a group
            if {$idx >= $len} { break }
            set next_tok [lindex $tokens $idx]
            set next_type [lindex $next_tok 0]
            set next_val [lindex $next_tok 1]

            if {$next_type eq "COLON"} {
                # Simple attribute: name : value ;
                incr idx ;# consume colon
                set attr_val [_parse_attribute_value tokens idx $len]
                dict set ast _attrs $stmt_name $attr_val
                # Consume optional semicolon
                if {$idx < $len && [lindex [lindex $tokens $idx] 0] eq "SEMICOLON"} {
                    incr idx
                }
            } elseif {$next_type eq "LPAREN"} {
                # Either:
                # 1) Group: name (args...) { body }
                # 2) Complex attribute: name (args...) ;
                incr idx ;# consume LPAREN
                set args_list [_parse_argument_list tokens idx $len]
                # Next token after RPAREN
                if {$idx < $len} {
                    set post_tok [lindex $tokens $idx]
                    set post_type [lindex $post_tok 0]
                    if {$post_type eq "LBRACE"} {
                        # Group
                        incr idx ;# consume LBRACE
                        set body [_parse_statement_list tokens idx $len 0]
                        set group_node [dict create \
                            _type "group" \
                            _name $stmt_name \
                            _args $args_list \
                            _body $body]
                        dict lappend ast _groups $group_node
                    } elseif {$post_type eq "SEMICOLON"} {
                        # Complex attribute: name (args) ;
                        incr idx ;# consume SEMICOLON
                        dict set ast _attrs $stmt_name $args_list
                    } else {
                        # Complex attribute without trailing semicolon
                        dict set ast _attrs $stmt_name $args_list
                    }
                }
            } elseif {$next_type eq "LBRACE"} {
                # Group without arguments: name { body }
                incr idx ;# consume LBRACE
                set body [_parse_statement_list tokens idx $len 0]
                set group_node [dict create \
                    _type "group" \
                    _name $stmt_name \
                    _args [list] \
                    _body $body]
                dict lappend ast _groups $group_node
            } else {
                # Standalone keyword or attribute
                if {$next_type eq "SEMICOLON"} {
                    incr idx
                }
                dict set ast _attrs $stmt_name 1
            }
        }

        return $ast
    }

    proc _parse_attribute_value {tokens_var idx_var len} {
        upvar 1 $tokens_var tokens
        upvar 1 $idx_var idx

        set val_parts [list]
        while {$idx < $len} {
            set tok [lindex $tokens $idx]
            set type [lindex $tok 0]
            set val [lindex $tok 1]

            if {$type eq "SEMICOLON" || $type eq "RBRACE"} {
                break
            }
            lappend val_parts $val
            incr idx
        }
        if {[llength $val_parts] == 1} {
            return [lindex $val_parts 0]
        }
        return [join $val_parts " "]
    }

    proc _parse_argument_list {tokens_var idx_var len} {
        upvar 1 $tokens_var tokens
        upvar 1 $idx_var idx

        set args_list [list]
        while {$idx < $len} {
            set tok [lindex $tokens $idx]
            set type [lindex $tok 0]
            set val [lindex $tok 1]

            if {$type eq "RPAREN"} {
                incr idx ;# consume RPAREN
                break
            }
            if {$type ne "COMMA"} {
                lappend args_list $val
            }
            incr idx
        }
        return $args_list
    }
}
