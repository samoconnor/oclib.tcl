#!/usr/bin/tclsh8.6

package require oclib::oclib

set v "hello"

✅  equal [length $v] 5

🚫  empty $v

⊢ [: 7 is integer]
✓ [: 7 is integer]

❌  [: 7 is space]


test equal 5        [: "hello" | bytelength]
test equal 5        [. "hello" bytelength]
test equal 5        [bytelength "hello"]
test equal 5        [string bytelength "hello"]
test equal 0        [: "hello" compare "hello"]
test equal 0        [. "hello" compare "hello"]
test equal 0        [compare "hello" "hello"]
test equal 0        [string compare "hello" "hello"]
test equal 1        [: 2 compare 1]
test equal -1       [: 1 compare 2]
test equal 0        [: "yes" equal "no"]
test                [: "same" equal "same"]

test equal 5        [: "hello" length]
test equal 0        [: "hello" is integer]
test                [. 7 is integer]
test                [is integer 7]
test                [string is integer 7]
test                [: 7 is integer]

test equal 2        [: "hello" first l]
test equal 2        [. "hello" first l]
test equal 2        [first l "hello"]
test equal 2        [string first l "hello"]
test equal 3        [: "hello" last l]
test equal "l"      [: "hello" index 3]
test equal "Hello"  [: "hello" map {h H}]
test equal "Hello"  [: "hello" map {h H}]
test                [: "hello" match h*]
test equal "el"     [: "hello" range 1 2]
test equal "hehehe" [: he repeat 3]
test equal "hehehe" [repeat he 3]
test equal "hejjo"  [: "hello" replace 2 3 jj]
test equal "hejjo"  [: "hello" | replace 2 3 jj]
test equal "olleh"  [: "hello" reverse]
test equal "olleh"  [. "hello" reverse]
test equal "hello"  [: "HELLO" tolower]
test equal "HELLO"  [: "hello" toupper]
test equal "Hello"  [: "hello" totitle]
test equal "hello"  [: " hello " trim]
test equal "hello"  [. " hello " trim]
test equal "hello"  [trim " hello "]
test equal "hello"  [string trim " hello "]
test equal " hello" [: " hello " trimright]
test equal "hello " [: " hello " trimleft]


test equal [get "Hello World!"]      [dict get "Hello World!"]
test equal [get {1 a 2 b 3 c}]       [dict get {1 a 2 b 3 c}]
test equal [get {1 a 2 b 3 c} 2]     [dict get {1 a 2 b 3 c} 2]
test equal [dget {1 a 2 b 3 c} 2]    [dict get {1 a 2 b 3 c} 2]
test equal [: {1 a 2 b 3 c} get 2]   [dict get {1 a 2 b 3 c} 2]
test equal [: {1 a 2 b 3 c} | get 2] [dict get {1 a 2 b 3 c} 2]

set ::env(FOO) BAR ; test equal [exec bash -c "echo \$FOO"] "BAR"

set a foo     ; test equal $a "foo"
dset b Foo bar ; test equal $b {Foo bar}
dset b x y z   ; test equal $b {Foo bar x {y z}}

: b dset k v ; test equal $b {Foo bar x {y z} k v}
: b dunset k ; test equal $b {Foo bar x {y z}}

. b dset k v ; test equal $b {Foo bar x {y z} k v}
. b dunset k ; test equal $b {Foo bar x {y z}}


test equal [get foo]       "foo"
test equal [get {foo bar}] {foo bar}
test equal [get $b]        [dict get $b]
test equal [get $b Foo]    [dict get $b Foo]
test equal [get $b x y]    [dict get $b x y]

test equal [get $b]        [: $b get]
test equal [get $b Foo]    [: $b get Foo]
test equal [get $b x y]    [: $b get x y]

test equal [. $b get]     [: $b get]
test equal [. $b get Foo] [: $b get Foo]
test equal [. $b get x y] [: $b get x y]

test equal [keys $b] {Foo x}
test equal [values $b] {bar {y z}}

test equal [exists ?]      [info exists ?]
test equal [exists b]      [info exists b]
test equal [exists $b Foo] [dict exists $b Foo]
test equal [exists $b bar] [dict exists $b bar]

test equal [∃ ?]      [info exists ?]
test equal [∃ b]      [info exists b]
test equal [∃ $b Foo] [dict exists $b Foo]
test equal [∃ $b bar] [dict exists $b bar]

test equal [exists $b Foo] [: $b exists Foo]
test equal [exists $b bar] [: $b exists bar]

test equal [rfc_2822 $b] "Foo: bar\r\nx: y z\r\n\r\n"
dset b body body
test equal [rfc_2822 $b] "Foo: bar\r\nx: y z\r\n\r\nbody"
test equal [parse rfc_2822 [rfc_2822 $b]] $b

test equal [json $b] \
{{
    "Foo": "bar",
    "x": [
        "y",
        "z"
    ],
    "body": "body"
}
}

test equal [parse json [json $b]] $b

set c {1 a 2 b 3 c}
test equal [csv $c] "1,a\r\n2,b\r\n3,c\r\n"
test equal [parse csv_as_dict [csv $c]] $c

test equal [lines "a\nb"] {a b}
test equal [lines "a\nb\n"] {a b}
test equal [lines "a\nb\n"] [lines "a\r\nb\r\n"]
test equal [lines "a\n\nb\n"] {a {} b}
test equal [lines "a\nb\n\n"] {a b}

test equal [: "a\nb\n\n" lines] {a b}
test equal [: "a\nb\n\n" | lines] {a b}

close [file tempfile f]

file set $f "Hello!\n"

test equal [file get $f] "Hello!\n"

test equal [💾  get $f] "Hello!\n"

file set $f "a\nb\nc\n"
test equal [file lines $f] {a b c}
file set $f "1,a\r\n2,b\r\n3,c\r\n"
test equal [file csv $f] {{1 a} {2 b} {3 c}}
file delete $f

set s World!
test equal [prepend s "Hello "] "Hello World!"

set l {}
for x in {1 2 3 4 5} {lappend l $x}
test equal $l {1 2 3 4 5}
set l {}
for {x y} in {1 2 3 4 5} {lappend l [list $x $y]}
test equal $l {{1 2} {3 4} {5 {}}}

set l {}
for {x y} in {a 1 a 1 a 1} {lappend l [list $x $y]}
test equal $l {{a 1} {a 1} {a 1}}

set l {}
dict for {x y} {a 1 a 1 a 1} {lappend l [list $x $y]}
test equal $l {{a 1}}


#FIXME assign

proc foo {a b} {
    test only
} require {
    is integer $a
    is integer $b
    {$a > $b}
} do {
    return [expr {$a + $b}]
}

test equal [foo 10 5] 15

test equal [errorcode {foo 5 10}] {assert 5 > 10}
test equal [errorcode {foo a b}] {assert is integer a}

set d {a 1 b 2}
test equal [errorcode {dict get $d c}] {TCL LOOKUP DICT c}
test equal [errorcode {dict get $novar c}] {TCL LOOKUP VARNAME novar}
test equal [errorcode {dict get d c}] {TCL VALUE DICTIONARY}

set l {0 1 2 3 4 5}
test equal 3 [. $l lindex 3]
test equal {3 4} [. $l lrange 3 4]
. l lappend 6 7
test equal 7 [. $l lindex 7]
test equal 8 [. $l llength]
. $l lassign a b c
test equal [list $a $b $c] {0 1 2}

set a xxx
append a yyy ; test equal $a xxxyyy
prepend a yyy ; test equal $a yyyxxxyyy

set a xxx
string append a yyy ; test equal $a xxxyyy
string prepend a yyy ; test equal $a yyyxxxyyy

set a xxx
: a append yyy ; test equal $a xxxyyy
: a prepend yyy ; test equal $a yyyxxxyyy

set a xxx
. a append yyy ; test equal $a xxxyyy
. a prepend yyy ; test equal $a yyyxxxyyy

set a xxx
test equal [binary encode base64 $a] [string base64 $a]
test equal [binary encode base64 $a] [base64 $a]
test equal [binary encode base64 $a] [. $a base64]
test equal [binary encode base64 $a] [: $a | base64]
test equal [base64 {}] {}
test equal [parse base64 {}] {}

test equal 0A [format "%02X" 10]
test equal [string format "%02X" 10] [format "%02X" 10]
test equal [. "%02X" format 10] [format "%02X" 10]

scan "Foo Bar" "%s %s" a b ; test equal $a Foo ; test equal $b Bar
string scan "Foo Bar" "%s %s" a b ; test equal $a Foo ; test equal $b Bar
: "Foo Bar" scan "%s %s" a b ; test equal $a Foo ; test equal $b Bar
. "Foo Bar" scan "%s %s" a b ; test equal $a Foo ; test equal $b Bar


test equal [. {a b c} join -] a-b-c
set l {} ; . l lappend a b c ; test equal $l {a b c}

set a {}
set b {}
. {Foo Bar} lassign a b ; test equal $a Foo ; test equal $b Bar

test equal [lindex {0 1 2 3} 1] 1
test equal [. {0 1 2 3} lindex 1] 1
test equal [. {0 1 2 3} llength] 4
test equal [. {0 1 2 3} lrange 1 2] {1 2}
test equal [. {0 1 2 3} lreplace 1 2 a b] {0 a b 3}
test equal [: {0 1 2 3} | lreplace 1 2 a b] {0 a b 3}
test equal [: {0 1 2 3} | lreplace 1 2 a b | lreverse] {3 b a 0}
test equal [with {0 1 2 3} {lreplace 1 2 a b | lreverse}] {3 b a 0}
test equal [. {0 1 2 3} lreverse] {3 2 1 0}

set a {0 1 2 3 4} ; . a lset 3 x ; test equal $a {0 1 2 x 4}

test equal [string split "1,2,3" ,] [. "1,2,3" split ,]

set x 7
test equal [subst {$x}] 7
test equal [subst {$x}] [string subst {$x}]
test equal [subst -nocommands {$x}] [string subst -nocommands {$x}]
test equal [subst {$x}] [. {$x} subst]
test equal [subst -nocommands {$x}] [. {$x} subst -nocommands]

test equal [zlib gzip Hello] [. Hello gzip]
test equal [parse gzip [. Hello gzip]] Hello

test equal [. [bexec md5 [file get oc_list-1.0.tm]] trim] \
          [string md5 [file get oc_list-1.0.tm]]

test equal [. [bexec md5 [file get oc_list-1.0.tm]] trim] \
           [. [file get oc_list-1.0.tm] md5]

test equal [errorcode {exec bash -c "exit [get $::oc::ex_codes EX_DATAERR]"}] \
           EX_DATAERR



set id [dict create Name "Sam O'Connor" DOB "22 Jan 1977" Tick ✓]
dset id Box "\[-\]"
set qs "Name=Sam%20O%27Connor&DOB=22%20Jan%201977&Tick=%E2%9C%93&Box=%5B-%5D"
test equal [. $id qstring] $qs
test equal [qstring {*}$id] $qs
test equal [qstring $id] $qs
test equal [parse qstring $qs] $id

test equal [: $qs parse qstring] $id

✅  {[chars "Hello!"] eq {H e l l o !}}
✅  {[cat {*}[chars "Hello!"]] eq "Hello!"}

source oc_ostring.tcl
namespace import ::oc::ostring::*

✅  {[ocompare "abc" to "abC" -case no -length 3] == 0}
✅  [oequal "abc" to "abC" -case no -length 3]
🚫  [oequal "abc" to "abC"]
✅  {[ofirst "b" in "abC"] == 1}
✅  {[ofirst "b" in "abCb" -after 2] == 3}
✅  {[ochar_at 3 in "012345"] == 3}

puts pass
