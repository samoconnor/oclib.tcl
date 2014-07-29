#===============================================================================
# oc_dict-1.0.tm
#
# dict utilities.
#
# Copyright Sam O'Connor 2014
# Licenced for use under the same terms as Tcl 8.6. See:
# http://core.tcl.tk/tcl/artifact/537ba3f664b958496ab51849e23d7f564342014b
# http://github.com/tcltk/tcl/raw/core_8_6_1/license.terms
#===============================================================================


package provide oc_dict 1.0
package require oclib::oc_proc

package require csv
package require json
package require http



proc rfc_2822 {dict} {

    Format "dict" as an RFC 2882 message.

} example {

    [rfc_2822 {To A From B body Hi!}] eq "To: A\r\nFrom: B\r\n\r\nHi!"

} do {

    for {name value} in $dict {
        if {$name ne "body"} {
            append header "$name: $value\r\n"
        }
    }
    append header \r\n[get $dict body]
}


proc json_string {s} {
    return \"[string map [list \\ \\\\ \" \\\"] $s]\"
}

proc _json  {v} {
    # Recursive JSON formatter...

    if {[llength $v] == 1} {
        return [json_string [lindex $v 0]]
    } elseif {[regexp {^[A-Z]} [lindex $v 0]]} {
        if {[lindex $v 0] eq "JSONDict:"} {
            set v [lrange $v 1 end]
        }
        for {n v} in $v {lappend items "\"$n\": [_json $v]"}
        return \{\n[join $items ,\n]\n\}
    } else {
        for v in $v {lappend items [_json $v]}
        return "\[\n[join $items ,\n]\n\]"
    }
}


proc json {dict} {

    Format "dict" as a JSON string.

    Note: Value lists begining with an upper-case letter are treated as
    nested dictionaries. Other value lists are treated as plain lists.
    To embed a nested dictionary with lower-case keys prepend "JSONDict:"
    to the start of the nested dictionary.

    e.g.
    json {A 1 B 2 L {i j k}}
    {"A": "1", "B": "2", "L": [ "i", "j", "k" ]}

} do {

    # Generate JSON format...
    set lines [_json $dict]

    # Pretty indenting...
    set indent ""
    for l in [lines $lines] {
        if {[regexp {[\}\]]} $l]} {
            set indent [range $indent 0 end-4]
        }
        append result $indent$l\n
        if {[regexp {[\{\[]} $l]} {
            append indent "    "
        }
    }

    return $result
}



proc csv {dict} {

    Format "dict" as "name,value\r\n"...

} example {

    [csv {1 one 2 two 3 three}] eq "1,one\r\n2,two\r\n3,three\r\n"

} do {

    join [lmap {k v} $dict {get [csv::join [list $k $v]]\r\n}] {}
}



proc qstring {args} {

    Format "args" as a HTTP Query String.
    "args" can be a dict, or can be contain a single item containing a dict.

} example {

    [qstring {a "A B" b ✓ c \[\]}] eq "a=A%20B&b=%E2%9C%93&c=%5B%5D"

} do {

    if {[llength $args] == 1} {
        http::formatQuery {*}[lindex $args 0]
    } else {
        http::formatQuery {*}$args
    }
}



proc pop {dict_var key_var {key {}}} {

    Set "key_var" from "$key" in "dict_var".
    Remove "key" from dictionary. 
    "key" defaults to "key_var".

} do {

    if {$key eq {}} {
        set key $key_var
    }
    upvar $dict_var d
    upvar $key_var v
    set v [get $d $key]
    dict unset d $key
    return $v
}


proc dlist {dict args} {

    List of dict values for keys listed in "args".

} do {

    lmap key $args {dict get $dict $key}
}




package require oclib::oc_ensemble

for cmd in {
    assign
    rfc_2822
    json
    csv
    qstring
    pop
} {
    extend_proc dict $cmd $cmd
}

import_ensemble dict d


package require oclib::oc_string
package require oclib::oc_list
package require oclib::oc_file



#===============================================================================
# End of file.
#===============================================================================
