#===============================================================================
# oc_exec-1.0.tm
#
# Exec Utility.
#
# Copyright Sam O'Connor 2012
# Licenced for use under the same terms as Tcl 8.6. See:
# http://core.tcl.tk/tcl/artifact/537ba3f664b958496ab51849e23d7f564342014b
# http://github.com/tcltk/tcl/raw/core_8_6_1/license.terms
#===============================================================================


package require Tcl 8.6
package provide oc_exec 1.0


proc bexec {command {input {}}} {
    # Execute shell "command", send "input" to stdin, return stdout.
    # Ignores stderr (but "2>@1" can be part of "command").
    # Supports binary intput and output. e.g.:
    #     set flac_data [bexec {flac -} $wav_data]
    
    # Run "command" in background...
    set f [open |$command {RDWR BINARY}]
    fconfigure $f -blocking 0

    # Connect read function to collect "command" output...
    set ::bexec_done.$f 0
    set ::bexec_output.$f {}
    fileevent $f readable [list bexec_read $f]

    # Send "input" to command...
    puts -nonewline $f $input
    unset input
    close $f write

    # Wait for read function to signal "done"...
    vwait ::bexec_done.$f

    # Retrieve output... 
    set result [set ::bexec_output.$f]
    unset ::bexec_output.$f
    unset ::bexec_done.$f

    fconfigure $f -blocking 1
    close $f

    return $result
}


proc bexec_read {f} {
    # Accumulate output in ::bexec_output.$f.

    append ::bexec_output.$f [read $f]    
    if {[eof $f]} {
        fileevent $f readable {}
        set ::bexec_done.$f 1
    }
}



namespace eval ::oc {

    set ex_codes {
        EX_OK           0
        EX_USAGE       64
        EX_DATAERR     65
        EX_NOINPUT     66
        EX_NOUSER      67
        EX_NOHOST      68
        EX_UNAVAILABLE 69
        EX_SOFTWARE    70
        EX_OSERR       71
        EX_OSFILE      72
        EX_CANTCREAT   73
        EX_IOERR       74
        EX_TEMPFAIL    75
        EX_PROTOCOL    76
        EX_NOPERM      77
        EX_CONFIG      78
    } 

    foreach {name code} $ex_codes {
        dict set ex_names $code $name
    }
}


rename exit tcl_exit

proc exit {code {message {}}} {
    
    if {[dict exists $::oc::ex_codes $code]} {
        set code [dict get $::oc::ex_codes $code]
    }
    if {$message ne {}} {
        flush stderr
        puts $message
        flush stdout
    }
    tcl_exit $code
}


rename exec tcl_exec

proc exec {args} {

    try {

        uplevel tcl_exec $args

    } trap CHILDSTATUS {result info} {  

        set status [lindex [dict get $info -errorcode] 2]
        if {[dict exists $::oc::ex_names $status]} {
            dict set info -errorcode [dict get $::oc::ex_names $status]
        }
        return -options $info $result
    }
}



#===============================================================================
# End of file.
#===============================================================================
