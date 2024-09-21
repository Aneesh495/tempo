# ==============================================================================
# Native C Acceleration Loader and Transparent Pure-Tcl Fallback
#
# Detects and dynamically loads compiled C extension (tempo_accel.dylib / .so)
# for hardware-accelerated NLDM interpolation and ATPG D-calculus.
# If uncompiled, operates 100% seamlessly in pure Tcl mode.
# ==============================================================================

namespace eval ::tempo::accel {
    variable c_accel_loaded 0

    proc init_accel {{dir ""}} {
        variable c_accel_loaded
        if {$c_accel_loaded} { return 1 }

        if {$dir eq ""} {
            set dir [file normalize [file join [file dirname [info script]] ".." "c"]]
        }

        # Check candidate library names (.dylib on macOS, .so on Linux)
        set candidates [list \
            [file join $dir "tempo_accel.dylib"] \
            [file join $dir "tempo_accel.so"] \
            [file join $dir ".." "build" "tempo_accel.dylib"] \
            [file join $dir ".." "build" "tempo_accel.so"]]

        foreach libpath $candidates {
            if {[file exists $libpath]} {
                if {![catch {load $libpath Tempo_accel} err]} {
                    set c_accel_loaded 1
                    return 1
                }
            }
        }

        set c_accel_loaded 0
        return 0
    }

    proc is_accelerated {} {
        variable c_accel_loaded
        return $c_accel_loaded
    }

    # High-performance bilinear interpolation with automatic dispatch
    proc fast_bilinear_interp {x y x0 x1 y0 y1 q00 q01 q10 q11} {
        variable c_accel_loaded
        if {$c_accel_loaded} {
            return [::tempo::c::bilinear_interp $x $y $x0 $x1 $y0 $y1 $q00 $q01 $q10 $q11]
        }
        return [::tempo::types::bilinear_interp $x $y $x0 $x1 $y0 $y1 $q00 $q01 $q10 $q11]
    }
}

# Attempt opportunistic load on source
catch {::tempo::accel::init_accel}
