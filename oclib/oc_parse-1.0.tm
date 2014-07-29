#===============================================================================
# oc_parse-1.0.tm
#
# parsing utilities.
#
# Copyright Sam O'Connor 2014
# Licenced for use under the same terms as Tcl 8.6. See:
# http://core.tcl.tk/tcl/artifact/537ba3f664b958496ab51849e23d7f564342014b
# http://github.com/tcltk/tcl/raw/core_8_6_1/license.terms
#===============================================================================


package provide oc_parse 1.0
package require oclib::oc_proc
package require oclib::oc_object
package require oclib::oc_string

package require csv
package require json
package require http


namespace eval parse {}


proc parse::lines {lines_string} {

    Parse "lines string" into list of lines.
    Lines are delimited by "\n" or "\r\n".

} do {

    lmap l [: $lines_string | trimright \r\n | split \n] {trimright $l \r}

} example {

    [parse::lines a\nb          ] eq {a b}
    [parse::lines a\nb\n        ] eq {a b}
    [parse::lines a\n\nb\n      ] eq {a {} b}
    [parse::lines a\nb\n\n      ] eq {a b}
    [parse::lines a\r\nb\r\n\r\n] eq {a b}
}



proc parse::base64 {base64_string} {

    Decode "base64_string" to raw bytes.

} do  {

    binary decode base64 $base64_string

} example {

    [parse::base64 MTIzNA==] eq 1234
}



proc parse::hex {hex_string} {

    Decode "hex_string" to raw bytes.

} do  {

    binary decode hex $hex_string

} example {

    [parse::hex "20"] eq " "
}




proc parse::json {json_string} {

    Parse "json_string" into dictionaries and lists.

} do {

    json::json2dict $json_string

} example {

    [parse::json {{"foo":"bar","l":["1","2","3"]}}] eq {foo bar l {1 2 3}}
}



proc parse::csv {csv_string} {

    Parse "csv_string" containing multiple CSV lines into a list of lists.

} do {

    lmap l [parse::lines $csv_string] {csv::split $l}

} example {

    [parse::csv a,b,c\r\n1,2,3\r\n] eq {{a b c} {1 2 3}}
}



proc parse::csv_as_dict {csv_string} {

    Parse "csv_string" containing name,value pairs info a dictionary.

} do {

    concat {*}[parse::csv $csv_string]

} example {

    [parse::csv_as_dict 1,one\n2,two\n3,three] eq {1 one 2 two 3 three}
}


proc parse::csv_as_dicts {csv_string} {

    Parse "csv_string" containing multiple CSV lines into a list of dictionarys.

} do {

    set result {}
    set lines [parse::csv $csv_string]
    set names [lindex $lines 0]
    for line in [lrange $lines 1 end] {
        set row {}
        foreach n $names i $line {
            dict set row $n $i
        }
        lappend result $row
    }

    return $result

} example {

    [parse::csv_as_dicts a,b,c\n1,2,3\nx,y,z] eq {{a 1 b 2 c 3} {a x b y c z}}
}


proc parse::gzip {gzip_string} {

    Decompress "gzip_string".

    e.g. set data [parse_gzip [file get data.gz]]

} do {

    zlib gunzip $gzip_string

} example {

    [parse::gzip [parse::base64 H4sIAAAAAAAAAzM0MjYBAKPg45sEAAAA]] eq 1234
}



proc parse::rfc_2822 {message} {

    Parse RFC 2822 encoded "message".
    Result is a dictionary containing the message headers and "body".

} example {

    [parse::rfc_2822 "To: A\r\nFrom: B\r\n\r\nHi!"] eq {To A From B body Hi!}

} do {

    if {[set i [first \r\n\r\n $message]] != -1} {
        set header [range $message 0 $i]
        set body [range $message $i+4 end]
    } else {
        set header $message
        set body {}
    }

    set result {}
    foreach line [lines $header] {
        if {[regexp {^([^#:][^:]*):[ ]*([^\r]*)$} $line - name value]} {
            dict set result $name $value
        } elseif {[exists name]
              &&  [regexp {^[ \t]([^\r]*)$} $line - folded_value]} {
            dict append result $name $folded_value
        }
    }

    if {$body != {}} {
        dict set result body $body
    }

    return $result
}



proc parse::utf8 {hex} {

    Parse hex encoded UTF-8.
    Hex bytes may be prefixed by "%"

} example {

    [parse::utf8 E29C93] eq "✓"
    [parse::utf8 %E2%9C%93] eq "✓"

} do {
    set hex [string map {% {}} $hex]
    encoding convertfrom utf-8 [binary decode hex $hex]
}



proc parse::qstring {query_string} {

    Parse HTTP "query_string" into a dictionary.

} example {

    [parse::qstring "l=a%20b%20c&Tick=%E2%9C%93&Box=%5B%5D"] \
                eq {l {a b c} Tick ✓ Box {[]}}
    
} do {

    set result {}
    foreach {key value} [split $query_string &=] {
        foreach v {key value} {

            # See http://wiki.tcl.tk/14144...
            set str [string map {+ { } \\ {\\}} [set $v]]
            regsub -all {(%[0-9A-Fa-f0-9]{2})+} $str {[parse::utf8 \0]} str
            set $v [subst -novar -noback $str]
        }
        dict set result $key $value
    }
    return $result
}



namespace eval parse {

    namespace export lines base64 hex rfc_2822 json csv csv_as_dict qstring gzip
    namespace export csv_as_dicts
    namespace ensemble create
}



#===============================================================================
# End of file.
#===============================================================================
