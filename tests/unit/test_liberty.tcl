# Unit Tests for Liberty (.lib) Lexer, Parser, and Semantic Model

set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ".." ".."]]

source [file join $root_dir "tests" "framework.tcl"]
source [file join $root_dir "src" "core" "types.tcl"]
source [file join $root_dir "src" "parsers" "liberty_lexer.tcl"]
source [file join $root_dir "src" "parsers" "liberty_parser.tcl"]
source [file join $root_dir "src" "parsers" "liberty_model.tcl"]

::tempo::test::suite "Liberty Lexer and Parser"

set sample_lib {
/* Realistic Standard Cell Library */
library (demo_lib) {
  time_unit : "1ns";
  voltage_unit : "1V";

  lu_table_template(lut_3x3) {
    variable_1 : input_net_transition;
    variable_2 : total_output_net_capacitance;
    index_1 ("0.01, 0.05, 0.2");
    index_2 ("0.001, 0.01, 0.1");
  }

  cell (INV_X1) {
    area : 1.5;
    pin (A) {
      direction : input;
      capacitance : 0.002;
    }
    pin (Y) {
      direction : output;
      function : "!A";
      timing () {
        related_pin : "A";
        timing_sense : negative_unate;
        timing_type : combinational;
        cell_rise(lut_3x3) {
          values ("0.025, 0.045, 0.150", \
                  "0.035, 0.065, 0.190", \
                  "0.060, 0.110, 0.320");
        }
        rise_transition(lut_3x3) {
          values ("0.015, 0.030, 0.090", \
                  "0.020, 0.040, 0.110", \
                  "0.035, 0.070, 0.180");
        }
        cell_fall(lut_3x3) {
          values ("0.020, 0.040, 0.140", \
                  "0.030, 0.055, 0.170", \
                  "0.050, 0.095, 0.290");
        }
      }
    }
  }

  cell (DFF_X1) {
    area : 6.0;
    ff ("IQ", "IQN") {
      next_state : "D";
      clocked_on : "CK";
    }
    pin (CK) {
      direction : input;
      clock : true;
      capacitance : 0.004;
    }
    pin (D) {
      direction : input;
      capacitance : 0.003;
      timing () {
        related_pin : "CK";
        timing_type : setup_rising;
        rise_constraint(lut_3x3) {
          values ("0.050, 0.052, 0.060", \
                  "0.055, 0.058, 0.068", \
                  "0.070, 0.075, 0.090");
        }
      }
    }
    pin (Q) {
      direction : output;
      function : "IQ";
      timing () {
        related_pin : "CK";
        timing_type : rising_edge;
        cell_rise(lut_3x3) {
          values ("0.080, 0.110, 0.220", \
                  "0.095, 0.130, 0.250", \
                  "0.130, 0.180, 0.350");
        }
      }
    }
  }
}
}

::tempo::test::test "Tokenize and parse Liberty snippet" {
    set tokens [::tempo::liberty::lexer::tokenize $sample_lib]
    ::tempo::test::assert_true [expr {[llength $tokens] > 50}] "Should tokenize into many tokens"

    set ast [::tempo::liberty::parser::parse $tokens]
    ::tempo::test::assert_true [expr {[llength [dict get $ast _groups]] >= 1}] "AST should contain library group"

    set lib [::tempo::liberty::Library new]
    $lib load_ast $ast
    ::tempo::test::assert_equal [$lib get_name] "demo_lib"
    ::tempo::test::assert_equal [llength [$lib get_cells]] 2 "Library should have 2 cells: INV_X1 and DFF_X1"
    ::tempo::test::assert_true [$lib has_cell "INV_X1"]
    ::tempo::test::assert_true [$lib has_cell "DFF_X1"]

    set c_inv [$lib get_cell "INV_X1"]
    ::tempo::test::assert_almost_equal [dict get $c_inv area] 1.5
    ::tempo::test::assert_equal [dict get $c_inv is_sequential] 0

    set c_dff [$lib get_cell "DFF_X1"]
    ::tempo::test::assert_almost_equal [dict get $c_dff area] 6.0
    ::tempo::test::assert_equal [dict get $c_dff is_sequential] 1

    # Check pin capacitance
    set p_a [dict get [dict get $c_inv pins] "A"]
    ::tempo::test::assert_almost_equal [dict get $p_a capacitance] 0.002

    # Check 2D delay interpolation for INV_X1:
    # At in_trans = 0.01, out_cap = 0.001 (corner index1[0], index2[0]), cell_rise = 0.025
    set d_corner [$lib lookup_delay "INV_X1" "Y" "A" 0.01 0.001 "cell_rise"]
    ::tempo::test::assert_almost_equal $d_corner 0.025 1e-6

    # At midpoint in_trans = 0.03 (between 0.01 and 0.05), out_cap = 0.0055 (between 0.001 and 0.01)
    # The value should be smoothly interpolated between the 4 surrounding points
    set d_mid [$lib lookup_delay "INV_X1" "Y" "A" 0.03 0.0055 "cell_rise"]
    ::tempo::test::assert_true [expr {$d_mid > 0.025 && $d_mid < 0.070}] "Interpolated delay must be bounded"

    # Check output slew lookup
    set slew_val [$lib lookup_slew "INV_X1" "Y" "A" 0.01 0.001 "rise_transition"]
    ::tempo::test::assert_almost_equal $slew_val 0.015 1e-6

    # Check setup constraint lookup on DFF_X1
    # At in_trans = 0.01, clk_trans = 0.001, rise_constraint corner is 0.050 ns
    set setup_d [$lib lookup_delay "DFF_X1" "D" "CK" 0.01 0.001 "rise_constraint"]
    ::tempo::test::assert_almost_equal $setup_d 0.050 1e-6 "Setup constraint corner lookup"

    # Check out-of-bounds extrapolation handling
    # Load 0.2 is greater than max index2 (0.1), should smoothly extrapolate without crashing
    set d_extrap [$lib lookup_delay "INV_X1" "Y" "A" 0.01 0.2 "cell_rise"]
    ::tempo::test::assert_true [expr {$d_extrap > 0.150}] "Extrapolated delay should exceed boundary point"

    $lib destroy
}

set code [::tempo::test::report]
exit $code
