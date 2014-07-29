#===============================================================================
# oc_object-1.0.tm
#
# "object" as first argument of calls.
#
# Copyright Sam O'Connor 2014
# Licenced for use under the same terms as Tcl 8.6. See:
# http://core.tcl.tk/tcl/artifact/537ba3f664b958496ab51849e23d7f564342014b
# http://github.com/tcltk/tcl/raw/core_8_6_1/license.terms
#===============================================================================


package provide oc_object 1.0
package require oclib::oc_string
package require oclib::oc_proc


# Where is the "object" in the argument list of common procs?
namespace eval ::oc::object {
    set position {
        {string compare} end-1
        {string equal}   end-1
        {string first}   2
        {string is}      end
        {string last}    2
        {string map}     end
        {string match}   end
        {string subst}   end
                compare  end-1
                equal    end-1
                first    1
                is       end
                last     1
                map      end
                match    end
                subst    end
        {dict for}       end-1
        {dict map}       end-1
        {dict update}    end-1
        {dict with}      end-1
        {binary decode}  end
        {binary encode}  end
                decode   end
                encode   end
    }
}


proc object_position {command {subcommand {}}} {

    For "command" and optional "subcommand",
    Determine the argument-list index of the "object" of the command.

} example {

    [object_position string first]   eq 2
    [object_position string map]     eq "end"
    [object_position string compare] eq "end-1"
    [object_position lindex]         eq 0
    [object_position llength]        eq 0

} do {

    set key $command
    set i 0
    if {[namespace ensemble exists $command]} {
        set key [list $command $subcommand]
        set i 1
    }
    if {[dict exists $::oc::object::position $key]} {
        set i [dict get $::oc::object::position $key]
    }
    return $i
}


proc object_call {object command args} {

    Call "command" on "object" (with optional "args"). 

} example {

    [object_call "Hello!" string trim !] eq [string trim "Hello!" !]
    [object_call "Foo" equal -nocase "foo"] eq [equal -nocase "Foo" "foo"]

} do {

    set i [object_position $command [lindex $args 0]]
    uplevel [list $command {*}[linsert $args $i $object]]

} alias {
    .
}



# Force loading of the "clock" ensemble used in the example below...
clock seconds


proc object_pipeline {object args} {

    Object Pipeline.

    "args" is a "|" delimited pipeline of commands.
    "object" is passed as the 1st argument of the 1st command.
    The result of the 1st command is passed to the 2nd command, etc...

} example {

    [join [lrange [split [tolower "A-B-C"] -] 1 end] -] eq "b-c"
    [: "A-B-C" | tolower | split - | lrange 1 end | join -] eq "b-c"

    [: 0 | clock format -gmt yes | clock scan] == 0
    [: "Hello" tolower] eq "hello"

} do {

    if {[llength $args] == 1} {
        lassign $args args
    }

    foreach cmd [lrm_empty [lsplit $args |]] {
        set object [uplevel [list object_call $object {*}$cmd]]
    }
    return $object

} alias {
    :
    with
}



#===============================================================================
# End of file.
#===============================================================================
