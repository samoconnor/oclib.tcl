#===============================================================================
# oc_retry-1.0.tm
#
# Retry loop.
#
# Copyright Sam O'Connor 2014
# Licenced for use under the same terms as Tcl 8.6. See:
# http://core.tcl.tk/tcl/artifact/537ba3f664b958496ab51849e23d7f564342014b
# http://github.com/tcltk/tcl/raw/core_8_6_1/license.terms
#===============================================================================


package provide oc_retry 1.0
package require oclib::oc_proc

# FIXME. A simpler way? ...
# 
#interp alias {} retry {} continue
#
#rename try tcl_try
#proc try {args} {
#
#    while {1} {
#        uplevel tcl_try $args
#        break
#    }
#}


proc retry {count_var count body args} {

    Retry "body" up to "count" times for exceptions caught by "args".
    "args" is a list of trap handlers: trap pattern variableList script...
    The retry count is made visible through "count_var".

} require {

    is wordchar $count_var
    is integer $count
    {[lfirst $args] in {trap on finally}}

} do {

    upvar $count_var i

    if {[lindex $args end-1] eq "finally"} {
        set traps [lrange $args 0 end-2]
        set finally [lrange $args end-1 end]
    } else {
        set traps $args
        set finally {}
    }

    for {set i 1} {$i <= $count} {incr i} {

        # Try to execute "body". On success break from loop...
        uplevel [list try $body {*}$traps on ok {} break {*}$finally]

        # On the last attempt, suppress the trap handlers...
        if {$i + 1 == $count} {
            set traps {}
        }
    }
}



#===============================================================================
# End of file.
#===============================================================================

