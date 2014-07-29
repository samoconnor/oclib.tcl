#===============================================================================
# oc_file-1.0.tm
#
# File read/write shorthand.
#
# Copyright Sam O'Connor 2014
# Licenced for use under the same terms as Tcl 8.6. See:
# http://core.tcl.tk/tcl/artifact/537ba3f664b958496ab51849e23d7f564342014b
# http://github.com/tcltk/tcl/raw/core_8_6_1/license.terms
#===============================================================================


package provide oc_file 1.0
package require oclib::oc_proc


interp alias {} 💾  {} file
interp alias {} is_file {} file isfile


proc file_get {file} {

    Read entire content of "file".

} require {

    is_file $file

} do {

    set f [open $file {RDONLY BINARY}]
    set result [read $f]
    close $f
    return $result
}



proc file_lines {file} {

    Read lines from "file".

} do {

    lines [file_get $file]
}



proc file_csv {file} {

    Read Comma Separated Values from "file"
   
} do {

    parse csv [file_get $file]
}



proc file_set {file string} {

    Write "string" to "file".

} do {

    set f [open $file {WRONLY CREAT TRUNC BINARY}]
    puts -nonewline $f $string
    close $f
}



package require oclib::oc_ensemble

foreach cmd {
    get
    set
    lines
    csv
} { 
    extend_proc file $cmd file_$cmd
}

import_ensemble file f

package require oclib::oc_string
package require oclib::oc_dict



#===============================================================================
# End of file.
#===============================================================================

