#===============================================================================
# oc_proc-1.0.tm
#
# proc with precondition.
#
# Copyright Sam O'Connor 2014
# Licenced for use under the same terms as Tcl 8.6. See:
# http://core.tcl.tk/tcl/artifact/537ba3f664b958496ab51849e23d7f564342014b
# http://github.com/tcltk/tcl/raw/core_8_6_1/license.terms
#===============================================================================


package provide oc_proc 1.0
package require oclib::oc_base


rename proc tcl_proc

tcl_proc proc {name arguments body args} {
    # usage: proc name args body
    #    or: proc name args comment ?option arg...? do body
    #
    # options:
    #     require precondition_code
    #     example test_case_code
    #     alias   alias_list

    assign $args require do example alias

    # Generate body for "do body" procs...
    if {[llength $args] != 0} {

        # Validate args...
        for k in [dict keys $args] {
            assert {$k in {do require example alias}}
        }

        set precondition [split [string trim $require] \n]
        set precondition [join [lmap l $precondition {get "assert $l"}] \n]

        set body $precondition$do
    }

    # Create proc...
    uplevel [list tcl_proc $name $arguments $body]

    # Create alias...
    foreach alias $alias {
        interp alias {} $alias {} $name
    }

    # Run "example" tests...
    foreach example [lmap e [split $example \n] {string trim $e}] {
        if {$example != {}} {
            assert $example
        }
    }
}



#===============================================================================
# End of file.
#===============================================================================

