# Tempo Static Timing Analysis Multi-Corner PVT Engine
# Supports Slow-Slow, Fast-Fast, and Typical PVT corner timing analysis
# Namespace: ::tempo::sta::corner

namespace eval ::tempo::sta::corner {

    oo::class create CornerManager {
        variable corners ;# dict: corner_name -> dict(process, voltage, temp, delay_scale)
        variable active_corners

        constructor {} {
            my reset
        }

        method reset {} {
            set corners [dict create]
            set active_corners [list]

            # Standard standard cell PVT operating conditions
            my define_corner "typical" "TT" 1.0  25  1.00
            my define_corner "slow"    "SS" 0.9 125  1.35
            my define_corner "fast"    "FF" 1.1 -40  0.75

            set active_corners [list "typical" "slow" "fast"]
        }

        method define_corner {name proc_type volt temp scale} {
            dict set corners $name [dict create \
                name $name \
                process $proc_type \
                voltage $volt \
                temperature $temp \
                scale $scale]
        }

        method get_corner_scale {name} {
            if {[dict exists $corners $name]} {
                return [dict get [dict get $corners $name] scale]
            }
            return 1.0
        }

        method get_corners {} {
            return [dict keys $corners]
        }

        method get_active_corners {} {
            return $active_corners
        }

        method set_active_corners {corner_list} {
            set active_corners $corner_list
        }
    }
}
