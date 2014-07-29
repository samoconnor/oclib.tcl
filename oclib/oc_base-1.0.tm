#===============================================================================
# oc_base-1.0.tm
#
# Shorthand conveniance functions: get, exists, for and assign.
#
# Copyright Sam O'Connor 2014
# Licenced for use under the same terms as Tcl 8.6. See:
# http://core.tcl.tk/tcl/artifact/537ba3f664b958496ab51849e23d7f564342014b
# http://github.com/tcltk/tcl/raw/core_8_6_1/license.terms
#===============================================================================


package provide oc_base 1.0
package require oclib::oc_assert


if [info exists ::oc::options::overload_set] {

    rename set tcl_set

    proc set {args} {
        # usage: set var_name value
        #    or: set dict_name key... value

        if {[llength $args] <= 2} {
            uplevel [list tcl_set {*}$args]
        } else {
            uplevel [list dict set {*}$args]
        }
    }
}


proc get {args} { 
    # usage: get dict key...
    #   get: get value

    if {[llength $args] == 1} {
        lfirst $args
    } else {
        try {
            dict get {*}$args
        } trap {TCL LOOKUP DICT} {} {}
    }
}


proc exists {args} {
    # usage: exists var_name
    #    or: exists dict key...

    if {[llength $args] == 1} {
        uplevel [list info exists {*}$args] 
    } else {
        uplevel [list dict exists {*}$args] 
    }
}
interp alias {} ∃ {} exists


rename for tcl_for

proc for {args} {
    # usage: for {set i 0} {$i < $limit} {incr i} { ... }
    #    or: for {n v} in $dict { ... }
    #    or: for x in $list { ... }

    try {
        if {[lindex $args 1] eq "in"} {
            uplevel [list foreach {*}[lreplace $args 1 1]]
        } else {
            uplevel [list tcl_for {*}$args]
        }
    } on return {result options} {
        dict incr options -level
        return {*}$options $result
    }
}
    

proc assign {dict args} {
    # usage: assign $dict key...

    for v in $args {
        uplevel [list set $v [get $dict $v]]
    }
}


proc capture {args} {
    # usage: capture var...

    for var in $args {
        upvar $var v
        dset result $var $v
    }
    return $result
}



#===============================================================================
# End of file.
#===============================================================================
