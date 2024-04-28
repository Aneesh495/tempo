# Tempo Liberty (.lib) Lexer
# Tokenizes Liberty standard cell library files into structured token streams
# Namespace: ::tempo::liberty::lexer

namespace eval ::tempo::liberty::lexer {

    # Token types:
    # IDENT, STRING, NUMBER, LBRACE, RBRACE, LPAREN, RPAREN, COLON, SEMICOLON, COMMA

    proc tokenize {text} {
        set len [string length $text]
        set pos 0
        set line 1
        set tokens [list]

        while {$pos < $len} {
            set ch [string index $text $pos]

            # Whitespace and newlines
            if {$ch eq "\n"} {
                incr line
                incr pos
                continue
            }
            if {[string is space $ch]} {
                incr pos
                continue
            }

            # Backslash line continuation
            if {$ch eq "\\"} {
                incr pos
                if {$pos < $len && [string index $text $pos] eq "\r"} { incr pos }
                if {$pos < $len && [string index $text $pos] eq "\n"} {
                    incr line
                    incr pos
                }
                continue
            }

            # Block comments /* ... */
            if {$ch eq "/" && [string index $text [expr {$pos + 1}]] eq "*"} {
                incr pos 2
                while {$pos < $len} {
                    if {[string index $text $pos] eq "\n"} { incr line }
                    if {[string index $text $pos] eq "*" && [string index $text [expr {$pos + 1}]] eq "/"} {
                        incr pos 2
                        break
                    }
                    incr pos
                }
                continue
            }

            # Line comments //
            if {$ch eq "/" && [string index $text [expr {$pos + 1}]] eq "/"} {
                incr pos 2
                while {$pos < $len && [string index $text $pos] ne "\n"} {
                    incr pos
                }
                continue
            }

            # Delimiters
            set ascii_code [scan $ch %c]
            if {$ascii_code == 123} {
                lappend tokens [list LBRACE [format %c 123] $line]
                incr pos
                continue
            }
            if {$ascii_code == 125} {
                lappend tokens [list RBRACE [format %c 125] $line]
                incr pos
                continue
            }
            if {$ch eq "("} {
                lappend tokens [list LPAREN "(" $line]
                incr pos
                continue
            }
            if {$ch eq ")"} {
                lappend tokens [list RPAREN ")" $line]
                incr pos
                continue
            }
            if {$ch eq ":"} {
                lappend tokens [list COLON ":" $line]
                incr pos
                continue
            }
            if {$ch eq ";"} {
                lappend tokens [list SEMICOLON ";" $line]
                incr pos
                continue
            }
            if {$ch eq ","} {
                lappend tokens [list COMMA "," $line]
                incr pos
                continue
            }

            # Quoted string
            if {$ch eq "\""} {
                incr pos
                set str_val ""
                set str_line $line
                while {$pos < $len} {
                    set sc [string index $text $pos]
                    if {$sc eq "\\"} {
                        incr pos
                        if {$pos < $len} {
                            set esc_c [string index $text $pos]
                            if {$esc_c eq "\n"} {
                                incr line
                            } else {
                                append str_val $esc_c
                            }
                            incr pos
                        }
                        continue
                    }
                    if {$sc eq "\""} {
                        incr pos
                        break
                    }
                    if {$sc eq "\n"} { incr line }
                    append str_val $sc
                    incr pos
                }
                lappend tokens [list STRING $str_val $str_line]
                continue
            }

            # Number (including exponential, e.g., 1.2e-3, -0.05, 100)
            if {[regexp {^[+-]?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?} [string range $text $pos end] num_match]} {
                set peek_next [string index $text [expr {$pos + [string length $num_match]}]]
                # Ensure it's not part of an identifier like 1_in or 2D
                if {![regexp {[a-zA-Z_]} $peek_next]} {
                    lappend tokens [list NUMBER $num_match $line]
                    incr pos [string length $num_match]
                    continue
                }
            }

            # Identifier or boolean or keyword
            if {[regexp {^[a-zA-Z_!~^&|][a-zA-Z0-9_!~^&|]*|^[0-9]+[a-zA-Z_][a-zA-Z0-9_]*} [string range $text $pos end] ident_match]} {
                lappend tokens [list IDENT $ident_match $line]
                incr pos [string length $ident_match]
                continue
            }

            # Operator or standalone char
            lappend tokens [list CHAR $ch $line]
            incr pos
        }

        return $tokens
    }
}
