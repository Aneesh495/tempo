# Tempo Boolean Function and Shannon Expansion Engine
# Truth tables, cofactors, Boolean difference, and NPN classification
# Namespace: ::tempo::synth::bool

namespace eval ::tempo::synth::bool {

    # Evaluate boolean expression string with dictionary of variable values
    # Supports operators: !, ~, &, &&, |, ||, ^
    proc eval_expr {expr_str var_bindings} {
        set sanitized $expr_str
        # Replace variable names with $var
        # Sort variable names by descending length so prefix variables don't collide
        set sorted_vars [lsort -decreasing -command {apply {{a b} {expr {[string length $a] - [string length $b]}}}} [dict keys $var_bindings]]

        foreach v $sorted_vars {
            set val [dict get $var_bindings $v]
            # Replace variable with value
            regsub -all "\\m$v\\M" $sanitized $val sanitized
        }

        # Normalize operators to Tcl expr syntax
        set sanitized [string map {"!" "!" "~" "~" "&" "&" "|" "|" "^" "^"} $sanitized]

        set status [catch {expr $sanitized} res]
        if {$status != 0} {
            return -code error "Error evaluating boolean expression '$expr_str': $res"
        }
        return [expr {$res ? 1 : 0}]
    }

    # Generate truth table for a boolean function over variables list
    # Returns 64-bit integer mask or bit string
    proc truth_table {expr_str vars} {
        set num_vars [llength $vars]
        set num_rows [expr {1 << $num_vars}]
        set tt_bits ""

        for {set row 0} {$row < $num_rows} {incr row} {
            set bindings [dict create]
            for {set i 0} {$i < $num_vars} {incr i} {
                set vname [lindex $vars $i]
                set bit_val [expr {($row >> $i) & 1}]
                dict set bindings $vname $bit_val
            }
            set out_bit [eval_expr $expr_str $bindings]
            append tt_bits $out_bit
        }
        return $tt_bits
    }

    # Shannon positive cofactor: f_{x=1}
    proc cofactor_pos {expr_str var_name} {
        set bindings [dict create $var_name 1]
        set sanitized $expr_str
        regsub -all "\\m$var_name\\M" $sanitized "1" sanitized
        return $sanitized
    }

    # Shannon negative cofactor: f_{x=0}
    proc cofactor_neg {expr_str var_name} {
        set bindings [dict create $var_name 0]
        set sanitized $expr_str
        regsub -all "\\m$var_name\\M" $sanitized "0" sanitized
        return $sanitized
    }

    # Boolean difference with respect to variable: df/dx = f_{x=1} ^ f_{x=0}
    # Used in ATPG for fault sensitizing: a fault on x is observable if df/dx == 1
    proc boolean_difference {expr_str var_name test_bindings} {
        set b1 $test_bindings
        dict set b1 $var_name 1
        set b0 $test_bindings
        dict set b0 $var_name 0

        set f1 [eval_expr $expr_str $b1]
        set f0 [eval_expr $expr_str $b0]

        return [expr {$f1 ^ $f0}]
    }

    # Standard cell gate truth table signatures (up to 4 inputs: A, B, C, D)
    # Allows fast O(1) matching of synthesized logic to standard cells
    variable gate_signatures
    dict set gate_signatures "INV"   "10"       ;# A=0 -> 1, A=1 -> 0
    dict set gate_signatures "BUF"   "01"       ;# A=0 -> 0, A=1 -> 1
    dict set gate_signatures "AND2"  "0001"     ;# A, B: 00->0, 10->0, 01->0, 11->1
    dict set gate_signatures "NAND2" "1110"
    dict set gate_signatures "OR2"   "0111"
    dict set gate_signatures "NOR2"  "1000"
    dict set gate_signatures "XOR2"  "0110"
    dict set gate_signatures "XNOR2" "1001"
    dict set gate_signatures "AND3"  "00000001"
    dict set gate_signatures "NAND3" "11111110"
    dict set gate_signatures "OR3"   "01111111"
    dict set gate_signatures "NOR3"  "10000000"
    dict set gate_signatures "AOI21" "11101110" ;# !( (A & B) | C )
    dict set gate_signatures "OAI21" "10001000" ;# !( (A | B) & C )
    dict set gate_signatures "MUX2"  "01001101" ;# (S? B : A)

    proc get_gate_signature {gate_name} {
        variable gate_signatures
        set u [string toupper $gate_name]
        if {[dict exists $gate_signatures $u]} {
            return [dict get $gate_signatures $u]
        }
        return ""
    }

    proc match_signature {tt_bits} {
        variable gate_signatures
        dict for {gate sig} $gate_signatures {
            if {$sig eq $tt_bits} {
                return $gate
            }
        }
        return ""
    }
}
