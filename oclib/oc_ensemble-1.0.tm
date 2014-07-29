#===============================================================================
# oc_ensemble-1.0.tm
#
# Ensemble extension.
#
# Copyright Sam O'Connor 2014
# Licenced for use under the same terms as Tcl 8.6. See:
# http://core.tcl.tk/tcl/artifact/537ba3f664b958496ab51849e23d7f564342014b
# http://github.com/tcltk/tcl/raw/core_8_6_1/license.terms
#===============================================================================


package provide oc_ensemble 1.0
package require oclib::oc_assert


proc extend_proc {proc sub_command command} {
    # Extend ensemble "proc" with "sub_command" implemented by "command".

    set map [namespace ensemble configure $proc -map]
    🚫  dict exists $map $sub_command
    dict set map $sub_command $command
    namespace ensemble configure $proc -map $map
}


proc command_args {args} {

    set msg {}
    try {{*}$args} trap {TCL WRONGARGS} {msg} {}
    lrange [lindex $msg 5] [llength $args] end
}


proc alias {old new} {

    set old_ns [namespace qualifiers $old]
    set old_cmd [namespace tail $old]

    namespace eval $old_ns [list namespace export $old_cmd]

    if {$old_cmd eq $new} {

        namespace import $old

    } else {

        namespace eval ::oc::aliases [subst {
            namespace import $old
            ::rename $old_cmd $new
            namespace export $new
        }]
        namespace import ::oc::aliases::$new

    }
}


proc import_ensemble {command {prefix {}}} {
    # Import "command" subcommands into the current namespace.
    # Resolve name clashes by prepending "prefix" to "subcommand".

    # Inspect each subcommand...
    dict for {cmd imp} [namespace ensemble configure $command -map] {

        set aliases {}

        if {"::$cmd" eq "$imp"} {
            lappend aliases $cmd
        }

        # Import "cmd" with "prefix"...
        if {$prefix ne {} && [info command $prefix$cmd] eq {}} {
            lappend aliases $prefix$cmd
            alias $imp $prefix$cmd
        }

        # If there is no clash with "cmd", import without prefix as well...
        if {[info command $cmd] eq {}} {
            lappend aliases $cmd
            alias $imp $cmd
        }
        if {$aliases ne {}} {
#            puts "[format %-27s [join $aliases " or "]] -> $command $cmd"
        }
    }
}



#===============================================================================
# End of file.
#===============================================================================

