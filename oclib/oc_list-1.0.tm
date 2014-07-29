#===============================================================================
# oc_list.tm
#
# oclib list utilities for Tcl
#
# This file is a subset of oclib/tcl/oclib_list.tcl.
# Licenced to Global Kinetics Corporation Pty Ltd under terms defined in
# 070002_invoice_1_october_2010.pdf.
#
# Copyright Sam O'Connor 2010
# Licenced for use under the same terms as Tcl 8.6. See:
# http://core.tcl.tk/tcl/artifact/537ba3f664b958496ab51849e23d7f564342014b
# http://github.com/tcltk/tcl/raw/core_8_6_1/license.terms
#===============================================================================


package provide oc_list 1.0

package require Tcl 8.6


proc foreach_window {vars list code} {
    # Evaluate "code" with "vars" taking values from sliding window over "list".
    # e.g.
    # foreach_window {a b c} {1 2 3 4 5 6 7} {puts "window: $a $b $c"}
    # window: 1 2 3
    # window: 2 3 4
    # window: 3 4 5
    # window: 4 5 6
    # window: 5 6 7

    set count [llength $list]
    set width [llength $vars]
    
    for {set i 0} {$i < $count - $width + 1} {incr i} {
        set win [lrange $list $i [expr {$i + $width - 1}]]
        uplevel foreach [list $vars] [list $win] [list $code]
    }
}


proc foreach_windowl {l width list code} {
    # Evaluate "code" with "l" taking values from "width"-item sliding window
    # over "list".
    # e.g.
    # foreach_lwindow l 3 {1 2 3 4 5 6 7} {puts "window: $l"}
    # window: 1 2 3
    # window: 2 3 4
    # window: 3 4 5
    # window: 4 5 6
    # window: 5 6 7

    set count [llength $list]
    
    for {set i 0} {$i < $count - $width + 1} {incr i} {
        set win [lrange $list $i [expr {$i + $width - 1}]]
        uplevel set $l [list $win]
        uplevel $code
    }
}


proc foreach_windowl_pad {l width list code} {
    # Evaluate "code" with "l" taking values from "width"-item sliding window
    # over "list".
    # e.g.
    # foreach_lwindow l 3 {1 2 3 4 5 6 7} {puts "window: $l"}
    # window: 1 1 2
    # window: 1 2 3
    # window: 2 3 4
    # window: 3 4 5
    # window: 4 5 6
    # window: 5 6 7
    # window: 6 7 7

    set count [llength $list]

    for {set i 0} {$i < $count} {incr i} {
        set a [expr {$i - $width/2}]
        set b [expr {$i + ($width-1)/2}]

        set win [list]
        while {$a < 0} {
            lappend win [lindex $list 0]
            incr a
        }

        while {$a <= $b && $a < $count} {
            lappend win [lindex $list $a]
            incr a
        }

        while {$a <= $b} {
            lappend win [lindex $list end]
            incr a
        }
        uplevel set $l [list $win]
        uplevel $code
    }
}


proc lconcat {listname list} {
    # lappend contents of "list" to other list named "listname".

    upvar $listname var
    set var [concat $var $list]
}


proc lfilter {data_list boolean_list} {
    # Returns filtered "data_list".
    # Items corresponding to false values in "boolean_list" are replaced by {}.
    # e.g. [lfilter {1 2 3 4 5} {1 1 0 1 0}] == {1 2 {} 4 {}}.

    set result {}
    foreach d $data_list b $boolean_list {
        if {$b != "" && $b} {
            lappend result $d
        } else {
            lappend result {}
        }
    }
    return $result
}


proc lrm_empty {list} {
    # Returns copy of "list" with empty items removed.

    set result [list]

    foreach i $list {
        if {$i != {}} {
            lappend result $i
        }
    }
    return $result
}


proc laverage {list} {
    # Average values of "list" items.
    # e.g. [average {1 2 3 4} == 2.5

    set count [llength $list]

    set sum 0
    foreach v $list {
        if {$v == ""} {
            incr count -1
        } else {
            set sum [expr $sum + $v]
        }
    }
    if {$count == 0} {
        return {}
    } else {
        return [expr $sum / $count]
    }
}



proc lpercentile {list p} {
    # Return the "p"th percentile value from "list".
    # e.g [lpercentile {3 2 5 1 4} 50] == 3
    #     [lpercentile {3 2 5 1 4} 90] == 4.6
    # Equivelant to excel: PERCENTILE($l,$p / 100.0)

    set l [llength $list]
    if {$l == 0} {
        return {}
    }
    set list [lsort -real $list]
    set n [expr {($p * ($l - 1)) / 100.0}]
    set n2 [expr {ceil($n)}]
    set f [expr {$n2 - $n}]
    set n [expr {int($n)}]
    set n2 [expr {int($n2)}]
    if {$f > 0.0} {
        return [expr {[lindex $list $n2] * (1.0 - $f)
                    + [lindex $list $n] * $f}]
    } else {
        return [lindex $list $n]
    }
}


proc l95ci {l} {
    # Return the 95% confidence interval as {low high}
    # 
    # e.g [l95ci {0 11 3 7 13 2 6 10 14 5 8 1 9 4 12}] == {3 11}

    set l [lrm_empty $l]
    set l [lsort -real $l]
    set n [llength $l]
    if {$n == 0} {
        return {}
    }

    set offset [expr {1.96 * sqrt($n) * 0.5}]
    set low_i [expr {round($n/2.0 - $offset - 1)}]
    set high_i [expr {round($n/2.0 + $offset)}]
    if {$low_i < 0} {set low_i 0}
    if {$high_i >= $n} {set high_i [expr {$n - 1}]}

    return [list [lindex $l $low_i] [lindex $l $high_i]]
}


proc lcsv {lists} {
    
    join [lmap l $lists {get [csv::join $l]\r\n}] {}
}


proc lexists {list item} {
    # Does "list" contain "item"?

    expr {[lsearch -exact $list $item] >= 0}
}


proc lcount {list var condition} {
    # How many items in "list" meet "condition"?
    # 
    # e.g. [lcount {1 2 3 4 5 6 7 8 9 10} i {$i < 4}] == 3

    set count 0
    foreach v $list {
        uplevel set $var $v
        if {[uplevel expr $condition]} {
            incr count
        }
    }
    return $count
}

proc dict_lappend {dictvar path key args} {
    # Append "args" to "path", "key" in "dictvar".

    upvar 1 $dictvar var
    if {![dict exists $var {*}$path $key]} {
        dict set var {*}$path $key $args
    } else {
        dict with var {*}$path {
            lappend $key {*}$args
        }
    }
}


proc dict_incr {dictvar path key {n 1}} {
    # Increment "path", "key" in "dictvar" by "n".

    upvar 1 $dictvar var
    dict with var {*}$path {
        incr $key $n
    }
}


proc csv_to_html {csv} {

    set html {}
    set count 0
    foreach line [lines $csv] {
        if {$count % 2} {
            append html <TR>
        } else {
            append html {<TR bgcolor="#FFFFFF">}
        }
        foreach v [csv::split $line] {
            if {$v != {}
            && ![is integer $v]
            &&  [is double $v]} {
                append html <TD>[format %.2f $v]</TD>
            } else {
                if {$count == 0} {
                    append html <TD><B>$v</B></TD>
                } else {
                    append html <TD>$v</TD>
                }
            }
        }
        append html </TR>\n
        incr count
    }
    return $html
}


proc csv_foreach {vars csv body} {

    catch {set csv [zlib gunzip $csv]}

    set lines [lines $csv]
    set columns [csv::split [lfirst $lines]]
    foreach line [lrange $lines 1 end] {
        uplevel 1 [list lassign [csv::split $line] {*}$columns]
        uplevel 1 $body
    }
}


proc indent {n text} {

    set lines [lines $text]
    set result [list [lfirst $lines]]
    foreach line [lrange $lines 1 end] {
        set indent ""
        for {set i 0} {$i < $n} {incr i} {append indent " "}
        lappend result $indent$line
    }
    return [join $result \n]
}


proc isdict {v} { 

    match "value is a dict *" [::tcl::unsupported::representation $v] 
} 


proc fmt_dict {dict {indent {}}} {

    dict for {key value} $dict { 
        if {[isdict $value]} { 
            append result "$indent[list $key]\n$indent\{\n" 
            append result "[fmt_dict $value "    $indent"]\n" 
            append result "$indent\}\n" 
        } else { 
            append result "$indent[list $key] [list $value]\n" 
        }
    }

    return $result 
}


proc scan_iso_date {date} {

#FIXME See http://core.tcl.tk/tcllib/doc/trunk/embedded/www/tcllib/files/modules/clock/iso8601.html
# package require clock::iso8601
# iso8601 parse_date
    set t {}
    regsub {[.][0-9]{3}Z$} $date Z date
    foreach format {
        %Y-%m-%dT%TZ
    } {
        if {![catch {set t [clock scan $date -format $format -gmt true]}]} {
            break
        }
    }
    return $t
}


proc lfirst {list} {
    lindex $list 0
}


proc lshuffle {list order} {

    for i in $order {
        if {[llength $i] == 1} {
            lappend result [lindex $list $i]
        } else {
            lappend result {*}[lrange $list {*}$i]
        }
    }
    return result
}

proc push {list_var item} {
    upvar $list_var l
    set l [linsert $l 0 $item]
}


proc lsplit {list delimiter} {
    
    set delimiter_length [length $delimiter]
    set sublist {}
    foreach l $list {
        if {[length $l] == $delimiter_length &&  $l eq $delimiter} {
            lappend result $sublist
            set sublist {}
        } else {
            lappend sublist $l
        }
    }
    lappend result $sublist
    return $result
}


proc errorcode {script} {
    try {
        uplevel $script
    } on error {msg info} {
        return [get $info -errorcode]
    }
    return {}
}


package require oclib::oc_base
package require oclib::oc_parse


#===============================================================================
# End of file.
#===============================================================================
