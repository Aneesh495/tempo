# Tempo And-Inverter Graph (AIG) Engine
# High-performance structural hashing (hash-consing) and logic simplification
# Namespace: ::tempo::synth::aig

namespace eval ::tempo::synth::aig {

    # Literal encoding convention:
    # Node ID N -> non-inverted literal = 2*N, inverted literal = 2*N + 1
    # Constant 0 has Node ID 0, so Literal 0 = Const 0, Literal 1 = Const 1

    proc node_of {lit} { return [expr {$lit >> 1}] }
    proc is_inv {lit}  { return [expr {$lit & 1}] }
    proc not_lit {lit} { return [expr {$lit ^ 1}] }

    oo::class create Aig {
        variable next_node_id
        variable pi_nodes       ;# dict: pi_name -> lit
        variable po_nodes       ;# dict: po_name -> lit
        variable and_nodes      ;# dict: node_id -> dict(left: lit, right: lit)
        variable strash_table   ;# dict: "left_lit,right_lit" -> node_id
        variable node_names     ;# dict: node_id -> string

        constructor {} {
            my reset
        }

        method reset {} {
            set next_node_id 1 ;# Node 0 is reserved for CONSTANT 0
            set pi_nodes [dict create]
            set po_nodes [dict create]
            set and_nodes [dict create]
            set strash_table [dict create]
            set node_names [dict create]
        }

        method const0 {} { return 0 }
        method const1 {} { return 1 }

        # Add Primary Input (PI)
        method add_pi {name} {
            if {[dict exists $pi_nodes $name]} {
                return [dict get $pi_nodes $name]
            }
            set nid $next_node_id
            incr next_node_id
            set lit [expr {$nid << 1}]

            dict set pi_nodes $name $lit
            dict set node_names $nid "PI_$name"
            return $lit
        }

        method get_pis {} {
            return [dict keys $pi_nodes]
        }

        method get_pi_lit {name} {
            if {[dict exists $pi_nodes $name]} {
                return [dict get $pi_nodes $name]
            }
            return -1
        }

        # Add Primary Output (PO)
        method add_po {name lit} {
            dict set po_nodes $name $lit
        }

        method get_pos {} {
            return [dict keys $po_nodes]
        }

        method get_po_lit {name} {
            if {[dict exists $po_nodes $name]} {
                return [dict get $po_nodes $name]
            }
            return -1
        }

        # Add 2-input AND gate with constant folding and structural hashing
        method add_and {lit_a lit_b} {
            # Constant 0 rules: 0 AND x = 0
            if {$lit_a == 0 || $lit_b == 0} {
                return 0
            }
            # Constant 1 rules: 1 AND x = x
            if {$lit_a == 1} { return $lit_b }
            if {$lit_b == 1} { return $lit_a }

            # Idempotence: x AND x = x
            if {$lit_a == $lit_b} { return $lit_a }

            # Contradiction: x AND (NOT x) = 0
            if {$lit_a == [::tempo::synth::aig::not_lit $lit_b]} {
                return 0
            }

            # Canonical commutative ordering: left <= right
            set left $lit_a
            set right $lit_b
            if {$left > $right} {
                set left $lit_b
                set right $lit_a
            }

            # Structural hashing lookup
            set key "$left,$right"
            if {[dict exists $strash_table $key]} {
                set nid [dict get $strash_table $key]
                return [expr {$nid << 1}]
            }

            # Create new AND node
            set nid $next_node_id
            incr next_node_id

            dict set and_nodes $nid [dict create left $left right $right]
            dict set strash_table $key $nid
            dict set node_names $nid "AND_$nid"

            return [expr {$nid << 1}]
        }

        # Derived Boolean gates using De Morgan's laws
        method add_not {lit} {
            return [::tempo::synth::aig::not_lit $lit]
        }

        method add_or {lit_a lit_b} {
            # a OR b = NOT( (NOT a) AND (NOT b) )
            set not_a [my add_not $lit_a]
            set not_b [my add_not $lit_b]
            return [my add_not [my add_and $not_a $not_b]]
        }

        method add_nand {lit_a lit_b} {
            return [my add_not [my add_and $lit_a $lit_b]]
        }

        method add_nor {lit_a lit_b} {
            return [my add_not [my add_or $lit_a $lit_b]]
        }

        method add_xor {lit_a lit_b} {
            # a XOR b = (a OR b) AND NOT(a AND b)
            set or_ab  [my add_or $lit_a $lit_b]
            set nand_ab [my add_nand $lit_a $lit_b]
            return [my add_and $or_ab $nand_ab]
        }

        method add_xnor {lit_a lit_b} {
            return [my add_not [my add_xor $lit_a $lit_b]]
        }

        method add_mux {lit_sel lit_d0 lit_d1} {
            # sel ? d1 : d0 = (sel AND d1) OR ((NOT sel) AND d0)
            set term1 [my add_and $lit_sel $lit_d1]
            set term0 [my add_and [my add_not $lit_sel] $lit_d0]
            return [my add_or $term1 $term0]
        }

        method num_and_nodes {} {
            return [dict size $and_nodes]
        }

        method get_and_nodes {} {
            return $and_nodes
        }

        method get_and_node {nid} {
            if {[dict exists $and_nodes $nid]} {
                return [dict get $and_nodes $nid]
            }
            return [dict create]
        }

        method num_pis {} {
            return [dict size $pi_nodes]
        }

        method num_pos {} {
            return [dict size $po_nodes]
        }

        # Evaluate AIG on given boolean primary input dictionary
        method simulate {pi_values} {
            set values [dict create]
            dict set values 0 0 ;# Node 0 is CONSTANT 0

            # Bind PIs
            dict for {pname lit} $pi_nodes {
                set nid [::tempo::synth::aig::node_of $lit]
                set v 0
                if {[dict exists $pi_values $pname]} {
                    set v [expr {[dict get $pi_values $pname] ? 1 : 0}]
                }
                dict set values $nid $v
            }

            # Topologically evaluate AND nodes
            dict for {nid ainfo} $and_nodes {
                set l_lit [dict get $ainfo left]
                set r_lit [dict get $ainfo right]

                set l_node [::tempo::synth::aig::node_of $l_lit]
                set r_node [::tempo::synth::aig::node_of $r_lit]

                set l_val [dict get $values $l_node]
                if {[::tempo::synth::aig::is_inv $l_lit]} { set l_val [expr {!$l_val}] }

                set r_val [dict get $values $r_node]
                if {[::tempo::synth::aig::is_inv $r_lit]} { set r_val [expr {!$r_val}] }

                dict set values $nid [expr {$l_val & $r_val}]
            }

            # Gather POs
            set po_results [dict create]
            dict for {pname lit} $po_nodes {
                set nid [::tempo::synth::aig::node_of $lit]
                set v [dict get $values $nid]
                if {[::tempo::synth::aig::is_inv $lit]} { set v [expr {!$v}] }
                dict set po_results $pname $v
            }

            return $po_results
        }
    }
}
