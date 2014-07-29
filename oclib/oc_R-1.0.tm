#===============================================================================
# oc_R.tm
#
# Utilities for R
#
# See http://www.r-project.org
#
# Copyright Sam O'Connor 2014.
# Licenced for use under the same terms as Tcl 8.6. See:
# http://core.tcl.tk/tcl/artifact/537ba3f664b958496ab51849e23d7f564342014b
# http://github.com/tcltk/tcl/raw/core_8_6_1/license.terms
#===============================================================================


package provide oc_R 1.0 


proc R {script} {
    # Execute "R" script. 

    set script "options(warn=-1); $script"
    exec R --vanilla --slave << [uplevel [list subst $script]] 2>@1
}


proc R.c {list} {
    # Convert Tcl List to "R" vector.

    return c([join $list ,])
}


proc R.call {r_function args} {
    # Call "r_function" with "args".
    # Result is a Tcl dictionary.

    R {format ($r_function ([join $args ,]),scientific=FALSE)}
}



#===============================================================================
# End of file
#===============================================================================
