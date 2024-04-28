# Tempo Lightweight Test Framework
# Namespace: ::tempo::test

namespace eval ::tempo::test {
    variable passed 0
    variable failed 0
    variable current_suite "General"
    variable failures [list]

    proc suite {name} {
        variable current_suite
        set current_suite $name
        puts "\n=== Test Suite: $name ==="
    }

    proc test {name script {expected_pass 1}} {
        variable passed
        variable failed
        variable current_suite
        variable failures

        set status [catch {uplevel 1 $script} result]

        if {$status == 0 && $expected_pass} {
            incr passed
            puts "  \[PASS\] $name"
        } elseif {$status != 0 && !$expected_pass} {
            incr passed
            puts "  \[PASS\] $name (expected failure caught: $result)"
        } else {
            incr failed
            puts "  \[FAIL\] $name"
            puts "         Error: $result"
            lappend failures "\[$current_suite\] $name: $result"
        }
    }

    proc assert_equal {actual expected {msg ""}} {
        if {$actual ne $expected} {
            set detail "Expected '$expected', got '$actual'"
            if {$msg ne ""} { set detail "$msg ($detail)" }
            return -code error $detail
        }
    }

    proc assert_true {cond {msg "Expected true condition"}} {
        if {!$cond} {
            return -code error $msg
        }
    }

    proc assert_almost_equal {actual expected {tol 1.0e-5} {msg ""}} {
        set diff [expr {abs($actual - $expected)}]
        if {$diff > $tol} {
            set detail "Expected ~$expected (+/- $tol), got $actual (diff: $diff)"
            if {$msg ne ""} { set detail "$msg ($detail)" }
            return -code error $detail
        }
    }

    proc assert_error {script {err_pattern ""}} {
        set status [catch {uplevel 1 $script} err]
        if {$status == 0} {
            return -code error "Expected error from script, but it succeeded"
        }
        if {$err_pattern ne "" && ![string match *$err_pattern* $err]} {
            return -code error "Error message '$err' did not match pattern '$err_pattern'"
        }
        return 1
    }

    proc report {} {
        variable passed
        variable failed
        variable failures
        set total [expr {$passed + $failed}]
        puts "\n----------------------------------------"
        puts "Test Summary: $total tests run."
        puts "  Passed: $passed"
        puts "  Failed: $failed"
        if {$failed > 0} {
            puts "\nFailure Details:"
            foreach f $failures {
                puts "  * $f"
            }
            puts "----------------------------------------"
            return 1
        }
        puts "All tests passed successfully!"
        puts "----------------------------------------"
        return 0
    }
}
