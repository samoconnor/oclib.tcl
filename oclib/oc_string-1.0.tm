#===============================================================================
# oc_string-1.0.tm
#
# String shorthand.
#
# Copyright Sam O'Connor 2014
# Licenced for use under the same terms as Tcl 8.6. See:
# http://core.tcl.tk/tcl/artifact/537ba3f664b958496ab51849e23d7f564342014b
# http://github.com/tcltk/tcl/raw/core_8_6_1/license.terms
#===============================================================================


package provide oc_string 1.0


proc cat {args} {
    join $args ""
}


proc prepend {var_name args} {
    upvar $var_name v
    set v [append {} {*}$args $v]
}


proc is_empty {string} {
    # Is "string" equal to ""?

    # Note: {$data == ""} converts large binary $data to a string!
    expr {[string length $string] == 0}
}
interp alias {} empty {} is_empty


proc not_empty {string} {
    expr {![is_empty $string]}
}


proc is_iso_date {string} {

    regsub {[.][0-9]{3}Z$} $string Z string

    for format in {
        {%Y-%m-%dT%TZ}
        {%Y-%m-%d %T}
    } {
        if {![catch {clock scan $string -format $format}]} {
            return yes
        }
    }
    return no
}


proc lines {string} {
    parse lines $string
}


proc chars {string} {
    split $string {}
}


proc base64 {string} {
    binary encode base64 $string
}


proc hex {string} {
    binary encode hex $string
}


proc gzip {string} {
    zlib gzip $string
}


proc crc32 {string} {
    zlib crc32 $string
}


proc md5 {string {format hex}} {
    : $string | md5::md5 | $format
}


proc subst_nocomplain {args} {

    try {

        uplevel tcl_subst $args

    } trap {TCL LOOKUP VARNAME} {msg info} {
        lassign [dict get $info -errorcode] - - - var
        set args [string map [list \$$var \\\$$var] $args]
        uplevel subst_nocomplain $args
    } on error {msg info} {
        if {[regexp {invalid command name "(.*)"} $msg - cmd]} {
            regsub -all [cat {\[ *} $cmd] $args {\\\0} args
            uplevel subst_nocomplain $args
        } else {
            return -code error -options $info
        }
    }
}


rename subst tcl_subst

proc subst {args} {

    if {[set i [lsearch [lrange $args 0 end-1] -nocomplain]] != -1} {
        uplevel subst_nocomplain [lreplace $args $i $i]
    } else {
        uplevel tcl_subst $args
    }
}


package require oclib::oc_ensemble

foreach cmd {
    append 
    prepend
    base64
    hex
    gzip
    crc32
    md5
    format
    scan
    split
    subst
    lines
    cat
} {
    extend_proc string $cmd $cmd
}

alias ::tcl::string::equal eq

import_ensemble string


package require oclib::oc_list
package require md5



#===============================================================================
# End of file.
#===============================================================================
