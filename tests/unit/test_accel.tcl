# Unit Tests for C Acceleration Extension and Pure-Tcl Fallback Equivalence

set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ".." ".."]]

source [file join $root_dir "tests" "framework.tcl"]
source [file join $root_dir "src" "core" "types.tcl"]
source [file join $root_dir "src" "core" "bitvector.tcl"]
source [file join $root_dir "src" "core" "accel.tcl"]

::tempo::test::suite "Native C Acceleration Extension"

::tempo::test::test "Verify C acceleration presence and bilinear interpolation accuracy" {
    set is_accel [::tempo::accel::is_accelerated]
    ::tempo::test::assert_true $is_accel "C acceleration library should be loaded"

    # Compare fast_bilinear_interp with pure-tcl bilinear_interp across test points
    set test_points [list \
        {0.2 0.8 0.0 1.0 0.0 1.0 10.0 20.0 30.0 40.0} \
        {0.5 0.5 0.1 0.9 0.2 0.8 5.5 12.3 8.7 19.4} \
        {0.0 0.0 0.0 1.0 0.0 1.0 15.0 25.0 35.0 45.0} \
        {1.0 1.0 0.0 1.0 0.0 1.0 15.0 25.0 35.0 45.0}]

    foreach pt $test_points {
        set c_res [::tempo::accel::fast_bilinear_interp {*}$pt]
        set tcl_res [::tempo::types::bilinear_interp {*}$pt]
        ::tempo::test::assert_almost_equal $c_res $tcl_res 1e-9
    }
}

::tempo::test::test "Native C Roth 5-state logic evaluation" {
    if {[::tempo::accel::is_accelerated]} {
        ::tempo::test::assert_equal [::tempo::c::roth5_gate "not" "0"] "1"
        ::tempo::test::assert_equal [::tempo::c::roth5_gate "not" "1"] "0"
        ::tempo::test::assert_equal [::tempo::c::roth5_gate "not" "D"] "D_BAR"
        ::tempo::test::assert_equal [::tempo::c::roth5_gate "not" "D_BAR"] "D"

        ::tempo::test::assert_equal [::tempo::c::roth5_gate "and" "1" "D"] "D"
        ::tempo::test::assert_equal [::tempo::c::roth5_gate "and" "0" "D"] "0"
        ::tempo::test::assert_equal [::tempo::c::roth5_gate "and" "D" "D_BAR"] "0"

        ::tempo::test::assert_equal [::tempo::c::roth5_gate "or" "0" "D"] "D"
        ::tempo::test::assert_equal [::tempo::c::roth5_gate "or" "1" "D"] "1"
        ::tempo::test::assert_equal [::tempo::c::roth5_gate "or" "D" "D_BAR"] "1"
    }
}

set code [::tempo::test::report]
exit $code
