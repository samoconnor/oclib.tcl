#===============================================================================
# oc_assert-1.0.tm
#
# Assert Utility.
#
# Copyright Sam O'Connor 2012
# Licenced for use under the same terms as Tcl 8.6. See:
# http://core.tcl.tk/tcl/artifact/537ba3f664b958496ab51849e23d7f564342014b
# http://github.com/tcltk/tcl/raw/core_8_6_1/license.terms
#===============================================================================


package provide oc_assert 1.0


proc assert {args} {
    # usage: assert command args...
    #    or: assert {expression}

    if {[llength $args] == 1} {
        if {[uplevel expr $args]} {
            return
        }
        set args [uplevel subst $args]
    } else {
        if {[uplevel $args]} {
            return
        }
    }

    return -code error \
           -errorcode [list assert {*}$args] \
           "Assertion Failed:\n    $args"
}


proc forbid {args} {
    # usage: forbid command args...
    #    or: forbid {expression}

    if {[llength $args] == 1} {
        if {![uplevel expr $args]} {
            return
        }
        set args [uplevel subst $args]
    } else {
        if {![uplevel $args]} {
            return
        }
    }

    return -code error \
           -errorcode [list assert {*}$args] \
           "Forbidden:\n    $args"
}


foreach {alias cmd} {
    require assert
    check   assert
    test    assert
    ⊢       assert
    ✅       assert
    ✓       assert

    🚫       forbid
    ❌       forbid
    ❎       forbid
    ✗       forbid

    ⏳       after
    🔎       regexp
    💀       throw
    💥       throw
    💣       throw
    💬       puts
} {
    interp alias {} $alias {} $cmd
}



#===============================================================================
# End of file.
#===============================================================================
