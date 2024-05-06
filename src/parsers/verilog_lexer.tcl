# Tempo Structural Verilog Lexer
# Tokenizes Verilog-2005 structural netlists
# Namespace: ::tempo::verilog::lexer

namespace eval ::tempo::verilog::lexer {

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

            # Sized literals: e.g., 4'b1010, 8'hA5, 1'b0
            if {[regexp {^\d+\s*'\s*[bhdBHD]\s*[0-9a-fA-FxXzZ_]+} [string range $text $pos end] lit_match]} {
                lappend tokens [list LITERAL $lit_match $line]
                incr pos [string length $lit_match]
                continue
            }

            # Numbers: decimal integer
            if {[regexp {^\d+} [string range $text $pos end] num_match]} {
                set peek_char [string index $text [expr {$pos + [string length $num_match]}]]
                if {![regexp {[a-zA-Z_']} $peek_char]} {
                    lappend tokens [list NUMBER $num_match $line]
                    incr pos [string length $num_match]
                    continue
                }
            }

            # Identifier or keyword
            if {[regexp {^[a-zA-Z_][a-zA-Z0-9_$]*} [string range $text $pos end] id_match]} {
                set lower [string tolower $id_match]
                switch -exact -- $lower {
                    "module"     { lappend tokens [list KW_MODULE "module" $line] }
                    "endmodule"  { lappend tokens [list KW_ENDMODULE "endmodule" $line] }
                    "input"      { lappend tokens [list KW_INPUT "input" $line] }
                    "output"     { lappend tokens [list KW_OUTPUT "output" $line] }
                    "inout"      { lappend tokens [list KW_INOUT "inout" $line] }
                    "wire"       { lappend tokens [list KW_WIRE "wire" $line] }
                    "reg"        { lappend tokens [list KW_REG "reg" $line] }
                    "assign"     { lappend tokens [list KW_ASSIGN "assign" $line] }
                    "and" - "nand" - "or" - "nor" - "xor" - "xnor" - "buf" - "not" {
                        lappend tokens [list KW_PRIM $lower $line]
                    }
                    default {
                        lappend tokens [list IDENT $id_match $line]
                    }
                }
                incr pos [string length $id_match]
                continue
            }

            # Delimiters and operators
            set c_code [scan $ch %c]
            if {$c_code == 123} {
                lappend tokens [list LBRACE [format %c 123] $line]
                incr pos
                continue
            }
            if {$c_code == 125} {
                lappend tokens [list RBRACE [format %c 125] $line]
                incr pos
                continue
            }

            switch -exact -- $ch {
                "(" { lappend tokens [list LPAREN "(" $line]; incr pos; continue }
                ")" { lappend tokens [list RPAREN ")" $line]; incr pos; continue }
                "\[" { lappend tokens [list LBRACK "\[" $line]; incr pos; continue }
                "\]" { lappend tokens [list RBRACK "\]" $line]; incr pos; continue }
                "," { lappend tokens [list COMMA "," $line]; incr pos; continue }
                ";" { lappend tokens [list SEMICOLON ";" $line]; incr pos; continue }
                ":" { lappend tokens [list COLON ":" $line]; incr pos; continue }
                "." { lappend tokens [list DOT "." $line]; incr pos; continue }
                "=" { lappend tokens [list EQUALS "=" $line]; incr pos; continue }
                "&" { lappend tokens [list OP_AND "&" $line]; incr pos; continue }
                "|" { lappend tokens [list OP_OR "|" $line]; incr pos; continue }
                "^" { lappend tokens [list OP_XOR "^" $line]; incr pos; continue }
                "~" { lappend tokens [list OP_NOT "~" $line]; incr pos; continue }
                default {
                    lappend tokens [list CHAR $ch $line]
                    incr pos
                }
            }
        }

        return $tokens
    }
}
