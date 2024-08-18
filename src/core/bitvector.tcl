# Tempo Core Bitvector and Multi-Valued Logic Framework
# Supports 4-state logic (0, 1, X, Z) and Roth 5-state D-calculus (0, 1, X, D, D_BAR)
# Namespace: ::tempo::logic and ::tempo::bv

namespace eval ::tempo::logic {
    # 4-State standard truth tables for single bit primitives
    # States: 0, 1, X (unknown), Z (high impedance)
    # According to IEEE 1364 Verilog specification

    variable not_table
    dict set not_table "0" "1"
    dict set not_table "1" "0"
    dict set not_table "x" "x"
    dict set not_table "z" "x"

    variable buf_table
    dict set buf_table "0" "0"
    dict set buf_table "1" "1"
    dict set buf_table "x" "x"
    dict set buf_table "z" "x"

    variable and_table
    dict set and_table "0" "0" "0"
    dict set and_table "0" "1" "0"
    dict set and_table "0" "x" "0"
    dict set and_table "0" "z" "0"
    dict set and_table "1" "0" "0"
    dict set and_table "1" "1" "1"
    dict set and_table "1" "x" "x"
    dict set and_table "1" "z" "x"
    dict set and_table "x" "0" "0"
    dict set and_table "x" "1" "x"
    dict set and_table "x" "x" "x"
    dict set and_table "x" "z" "x"
    dict set and_table "z" "0" "0"
    dict set and_table "z" "1" "x"
    dict set and_table "z" "x" "x"
    dict set and_table "z" "z" "x"

    variable or_table
    dict set or_table "0" "0" "0"
    dict set or_table "0" "1" "1"
    dict set or_table "0" "x" "x"
    dict set or_table "0" "z" "x"
    dict set or_table "1" "0" "1"
    dict set or_table "1" "1" "1"
    dict set or_table "1" "x" "1"
    dict set or_table "1" "z" "1"
    dict set or_table "x" "0" "x"
    dict set or_table "x" "1" "1"
    dict set or_table "x" "x" "x"
    dict set or_table "x" "z" "x"
    dict set or_table "z" "0" "x"
    dict set or_table "z" "1" "1"
    dict set or_table "z" "x" "x"
    dict set or_table "z" "z" "x"

    variable xor_table
    dict set xor_table "0" "0" "0"
    dict set xor_table "0" "1" "1"
    dict set xor_table "0" "x" "x"
    dict set xor_table "0" "z" "x"
    dict set xor_table "1" "0" "1"
    dict set xor_table "1" "1" "0"
    dict set xor_table "1" "x" "x"
    dict set bit "1" "z" "x"
    dict set xor_table "1" "z" "x"
    dict set xor_table "x" "0" "x"
    dict set xor_table "x" "1" "x"
    dict set xor_table "x" "x" "x"
    dict set xor_table "x" "z" "x"
    dict set xor_table "z" "0" "x"
    dict set xor_table "z" "1" "x"
    dict set xor_table "z" "x" "x"
    dict set xor_table "z" "z" "x"

    # Evaluator procs for single-bit 4-state operations
    proc gate_not {a} {
        variable not_table
        set norm [string tolower $a]
        if {![dict exists $not_table $norm]} { return "x" }
        return [dict get $not_table $norm]
    }

    proc gate_buf {a} {
        variable buf_table
        set norm [string tolower $a]
        if {![dict exists $buf_table $norm]} { return "x" }
        return [dict get $buf_table $norm]
    }

    proc gate_and {a b} {
        variable and_table
        set na [string tolower $a]
        set nb [string tolower $b]
        if {![dict exists $and_table $na $nb]} { return "x" }
        return [dict get $and_table $na $nb]
    }

    proc gate_nand {a b} {
        return [gate_not [gate_and $a $b]]
    }

    proc gate_or {a b} {
        variable or_table
        set na [string tolower $a]
        set nb [string tolower $b]
        if {![dict exists $or_table $na $nb]} { return "x" }
        return [dict get $or_table $na $nb]
    }

    proc gate_nor {a b} {
        return [gate_not [gate_or $a $b]]
    }

    proc gate_xor {a b} {
        variable xor_table
        set na [string tolower $a]
        set nb [string tolower $b]
        if {![dict exists $xor_table $na $nb]} { return "x" }
        return [dict get $xor_table $na $nb]
    }

    proc gate_xnor {a b} {
        return [gate_not [gate_xor $a $b]]
    }

    proc gate_mux2 {sel d0 d1} {
        set nsel [string tolower $sel]
        switch -exact -- $nsel {
            "0" { return [gate_buf $d0] }
            "1" { return [gate_buf $d1] }
            default {
                set v0 [gate_buf $d0]
                set v1 [gate_buf $d1]
                if {$v0 eq $v1 && ($v0 eq "0" || $v0 eq "1")} {
                    return $v0
                }
                return "x"
            }
        }
    }

    # Roth 5-State D-calculus (for ATPG):
    # Values: "0", "1", "x", "d" (1/0), "d_bar" (0/1)
    proc d_not {v} {
        set nv [string tolower $v]
        switch -exact -- $nv {
            "0" { return "1" }
            "1" { return "0" }
            "d" { return "d_bar" }
            "d_bar" { return "d" }
            default { return "x" }
        }
    }

    proc d_and {a b} {
        set na [string tolower $a]
        set nb [string tolower $b]
        # Any 0 makes output 0
        if {$na eq "0" || $nb eq "0"} { return "0" }
        if {$na eq "1"} { return $nb }
        if {$nb eq "1"} { return $na }
        if {$na eq $nb} { return $na }
        if {($na eq "d" && $nb eq "d_bar") || ($na eq "d_bar" && $nb eq "d")} {
            return "0"
        }
        return "x"
    }

    proc d_or {a b} {
        set na [string tolower $a]
        set nb [string tolower $b]
        # Any 1 makes output 1
        if {$na eq "1" || $nb eq "1"} { return "1" }
        if {$na eq "0"} { return $nb }
        if {$nb eq "0"} { return $na }
        if {$na eq $nb} { return $na }
        if {($na eq "d" && $nb eq "d_bar") || ($na eq "d_bar" && $nb eq "d")} {
            return "1"
        }
        return "x"
    }

    proc d_xor {a b} {
        set na [string tolower $a]
        set nb [string tolower $b]
        if {$na eq "0"} { return $nb }
        if {$nb eq "0"} { return $na }
        if {$na eq "1"} { return [d_not $nb] }
        if {$nb eq "1"} { return [d_not $na] }
        if {$na eq $nb} { return "0" }
        if {($na eq "d" && $nb eq "d_bar") || ($na eq "d_bar" && $nb eq "d")} {
            return "1"
        }
        return "x"
    }
}

namespace eval ::tempo::bv::Roth5 {
    proc not {a} { return [string toupper [::tempo::logic::d_not $a]] }
    proc and {a b} { return [string toupper [::tempo::logic::d_and $a $b]] }
    proc nand {a b} { return [string toupper [::tempo::logic::d_not [::tempo::logic::d_and $a $b]]] }
    proc or {a b} { return [string toupper [::tempo::logic::d_or $a $b]] }
    proc nor {a b} { return [string toupper [::tempo::logic::d_not [::tempo::logic::d_or $a $b]]] }
    proc xor {a b} { return [string toupper [::tempo::logic::d_xor $a $b]] }
}

namespace eval ::tempo::bv {
    # Arbitrary-width bitvectors represented as uppercase strings of '0', '1', 'X', 'Z'
    # Index 0 is MSB, Index end is LSB, consistent with string index representation

    # Create bitvector of given width initialized with val
    proc create {width {init_val "0"}} {
        set c [string toupper [string index $init_val 0]]
        if {$c ni {0 1 X Z}} { set c "0" }
        return [string repeat $c $width]
    }

    # Width of bitvector
    proc width {bv} {
        return [string length $bv]
    }

    # Normalize bitvector string
    proc normalize {bv} {
        return [string toupper [string map {" " "" "_" ""} $bv]]
    }

    # Get bit at index (0 is MSB)
    proc get_bit {bv index} {
        return [string index $bv $index]
    }

    # Set bit at index
    proc set_bit {bv index val} {
        set nval [string toupper $val]
        return [string replace $bv $index $index $nval]
    }

    # Slice bitvector from msb_idx to lsb_idx
    proc slice {bv start_idx end_idx} {
        return [string range $bv $start_idx $end_idx]
    }

    # Bitwise NOT
    proc bv_not {bv} {
        set res ""
        set len [string length $bv]
        for {set i 0} {$i < $len} {incr i} {
            append res [::tempo::logic::gate_not [string index $bv $i]]
        }
        return [string toupper $res]
    }

    # Bitwise binary operation
    proc apply_binary_op {op_proc bv1 bv2} {
        set len1 [string length $bv1]
        set len2 [string length $bv2]
        if {$len1 != $len2} {
            return -code error "Bitvector length mismatch: $len1 vs $len2"
        }
        set res ""
        for {set i 0} {$i < $len1} {incr i} {
            set b1 [string index $bv1 $i]
            set b2 [string index $bv2 $i]
            append res [$op_proc $b1 $b2]
        }
        return [string toupper $res]
    }

    proc bv_and {bv1 bv2} {
        return [apply_binary_op ::tempo::logic::gate_and $bv1 $bv2]
    }

    proc bv_or {bv1 bv2} {
        return [apply_binary_op ::tempo::logic::gate_or $bv1 $bv2]
    }

    proc bv_xor {bv1 bv2} {
        return [apply_binary_op ::tempo::logic::gate_xor $bv1 $bv2]
    }

    # Parse Verilog numeric literal into standard bitvector
    # Examples:
    #   4'b1010  -> 1010
    #   8'hA5    -> 10100101
    #   8'd255   -> 11111111
    #   1'b1     -> 1
    #   32'h0    -> 32 zeros
    #   123      -> 32-bit decimal equivalent
    proc parse_literal {str} {
        set trimmed [string trim $str]
        # Match sized literal: <size>'<base><value>
        if {[regexp -nocase {^(\d+)\s*'\s*([bhdBHD])\s*([0-9a-fA-FxXzZ_]+)$} $trimmed -> size base val]} {
            set clean_val [string map {"_" ""} $val]
            switch -exact -- [string tolower $base] {
                "b" {
                    set bits [string toupper $clean_val]
                    if {[string length $bits] < $size} {
                        # Sign or zero extend
                        set pad_bit "0"
                        if {[string index $bits 0] eq "X" || [string index $bits 0] eq "Z"} {
                            set pad_bit [string index $bits 0]
                        }
                        set pad_len [expr {$size - [string length $bits]}]
                        set bits "[string repeat $pad_bit $pad_len]$bits"
                    } elseif {[string length $bits] > $size} {
                        set bits [string range $bits end-[expr {$size - 1}] end]
                    }
                    return $bits
                }
                "h" {
                    set bits ""
                    for {set i 0} {$i < [string length $clean_val]} {incr i} {
                        set hex_char [string tolower [string index $clean_val $i]]
                        switch -exact -- $hex_char {
                            "0" { append bits "0000" }
                            "1" { append bits "0001" }
                            "2" { append bits "0010" }
                            "3" { append bits "0011" }
                            "4" { append bits "0100" }
                            "5" { append bits "0101" }
                            "6" { append bits "0110" }
                            "7" { append bits "0111" }
                            "8" { append bits "1000" }
                            "9" { append bits "1001" }
                            "a" { append bits "1010" }
                            "b" { append bits "1011" }
                            "c" { append bits "1100" }
                            "d" { append bits "1101" }
                            "e" { append bits "1110" }
                            "f" { append bits "1111" }
                            "x" { append bits "XXXX" }
                            "z" { append bits "ZZZZ" }
                            default { append bits "XXXX" }
                        }
                    }
                    if {[string length $bits] < $size} {
                        set pad_len [expr {$size - [string length $bits]}]
                        set bits "[string repeat {0} $pad_len]$bits"
                    } elseif {[string length $bits] > $size} {
                        set bits [string range $bits end-[expr {$size - 1}] end]
                    }
                    return $bits
                }
                "d" {
                    set int_val [expr {$clean_val + 0}]
                    return [from_uint $int_val $size]
                }
            }
        } elseif {[string is integer -strict $trimmed]} {
            return [from_uint $trimmed 32]
        }
        return -code error "Unrecognized Verilog literal: '$str'"
    }

    # Convert unsigned integer to bitvector of specified width
    proc from_uint {val width} {
        set bits ""
        set cur $val
        for {set i 0} {$i < $width} {incr i} {
            set b [expr {$cur & 1}]
            set bits "$b$bits"
            set cur [expr {$cur >> 1}]
        }
        return $bits
    }

    # Convert bitvector to unsigned integer (returns -1 if X or Z present)
    proc to_uint {bv} {
        if {[regexp {[xXzZ]} $bv]} {
            return -1
        }
        set val 0
        set len [string length $bv]
        for {set i 0} {$i < $len} {incr i} {
            set bit [string index $bv $i]
            set val [expr {($val << 1) | $bit}]
        }
        return $val
    }

    # Convert bitvector to hex string
    proc to_hex {bv} {
        set len [string length $bv]
        set rem [expr {$len % 4}]
        set padded $bv
        if {$rem != 0} {
            set pad_len [expr {4 - $rem}]
            set padded "[string repeat {0} $pad_len]$bv"
        }
        set hex_res ""
        for {set i 0} {$i < [string length $padded]} {incr i 4} {
            set nibble [string range $padded $i [expr {$i + 3}]]
            if {[regexp {[xX]} $nibble]} {
                append hex_res "x"
            } elseif {[regexp {[zZ]} $nibble]} {
                append hex_res "z"
            } else {
                set val 0
                for {set j 0} {$j < 4} {incr j} {
                    set val [expr {($val << 1) | [string index $nibble $j]}]
                }
                append hex_res [format "%x" $val]
            }
        }
        return $hex_res
    }
}
