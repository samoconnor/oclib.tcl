oclib.tcl
=========

OClib for Tcl. A collection of Tcl utilities.

Copyright Sam O'Connor 2014

Licenced for use under the same terms as Tcl 8.6. See:
http://core.tcl.tk/tcl/artifact/537ba3f664b958496ab51849e23d7f564342014b
http://github.com/tcltk/tcl/raw/core_8_6_1/license.terms


### Assertions

```tcl
set v "hello"

assert {[llength $v] == 5}
assert equal [length $v] 5
✅  equal [length $v] 5
⊢ [: 7 is integer]

forbid {$v eq {}}
forbid empty $v
🚫  is integer $v
🚫  empty $v
```

[oc_assert-1.0.tm](oclib/oc_assert-1.0.tm]

### Object-before-proc calls and object pipelines

```tcl
[with "Hello" tolower] eq "hello"
[: "Hello" tolower] eq "hello"

[join [lrange [split [tolower "A-B-C"] -] 1 end] -] eq "b-c"
[: "A-B-C" | tolower | split - | lrange 1 end | join -] eq "b-c"
```

[oc_object-1.0.tm](oclib/oc_object-1.0.tm]

### for, in loops

```tcl
for i in $l {puts $i}
```

[oc_base-1.0.tm](oclib/oc_base-1.0.tm]

### "exists" for variables and dicts

```tcl
[exists foo      ] eq [info exists foo]
[exists $dict foo] eq [dict exists $dict foo]
```

[oc_base-1.0.tm](oclib/oc_base-1.0.tm]

### -nocomplain option for "subst"

```tcl
set a foo
[subst -nocomplain {$a $b}] eq {foo $b}
```

[oc_string-1.0.tm](oclib/oc_string-1.0.tm]

### Common subcommands promoted to 1st class commands

```tcl
equal        -> string equal
is           -> string is
length       -> string length
range        -> string range
reverse      -> string reverse
tolower      -> string tolower
toupper      -> string toupper
trim         -> string trim
etc...

merge        -> dict merge
filter       -> dict filter
keys         -> dict keys
values       -> dict values
remove       -> dict remove
dset         -> dict set
etc...

copy         -> file copy
delete       -> file delete
dirname      -> file dirname
extension    -> file extension
isdirectory  -> file isdirectory
isfile       -> file isfile
mkdir        -> file mkdir
tempfile     -> file tempfile
etc...
```

[oc_string-1.0.tm](oclib/oc_string-1.0.tm]
[oc_dict-1.0.tm](oclib/oc_dict-1.0.tm]
[oc_file-1.0.tm](oclib/oc_file-1.0.tm]

### New "string" subcommands 

(also imported as 1st class commands)

```tcl
prepend
is_empty
is_iso_date
lines
chars
base64
hex
gzip
crc32
md5
```

[oc_string-1.0.tm](oclib/oc_string-1.0.tm]


### New "dict" subcommands 

(also imported as 1st class commands)

```tcl
[dict rfc_2822  {To A From B body Hi!}] eq "To: A\r\nFrom: B\r\n\r\nHi!"
[dict csv       {1 one 2 two 3 three} ] eq "1,one\r\n2,two\r\n3,three\r\n"
[dict qstring   {a "A B" b ✓ c \[\]}  ] eq "a=A%20B&b=%E2%9C%93&c=%5B%5D"

set d {a 1 b 2 c 3}
dict pop d a
$a == 1
$d == {b 2 c 3}

assign $d b c
$b == 2
$c == 3

```

[oc_dict-1.0.tm](oclib/oc_dict-1.0.tm]


### "parse" command

```tcl
[parse lines        a\nb\n                           ] eq {a b}
[parse base64       MTIzNA==                         ] eq 1234
[parse hex          "20"                             ] eq " "
[parse json         {{"foo":"bar","l":["1","2","3"]}}] eq {foo bar l {1 2 3}}
[parse csv          a,b,c\r\n1,2,3\r\n               ] eq {{a b c} {1 2 3}}
[parse csv_as_dict  1,one\n2,two\n3,three            ] eq {1 one 2 two 3 three}
[parse csv_as_dicts a,b,c\n1,2,3\nx,y,z              ] eq {{a 1 b 2 c 3} {a x b y c z}}
[parse gzip         $gziped                          ]
[parse rfc_2822     "To: A\r\nFrom: B\r\n\r\nHi!"    ] eq {To A From B body Hi!}
[parse utf8         %E2%9C%93]                       ] eq "✓"
[parse qstring      l=a%20b%20c&Tick=%E2%9C%93       ] eq {l {a b c} Tick ✓}
```
[oc_parse-1.0.tm](oclib/oc_parse-1.0.tm]


### New "file" subcommands

(also avaliable as 1st class commands)

```tcl
file set hello.txt "a,b\n1,2\n"

[file get   hello.txt] eq "a,b\n1,2\n"
[file lines hello.txt] eq {{a,b} {1,2}}
[file csv   hello.txt] eq {{a b} {1 2}}
```

[oc_file-1.0.tm](oclib/oc_file-1.0.tm]


### exec for binary data

```tcl
set wav [file get foo.wav]
set flac [bexec {flac --silent - 2>@ stderr} $wav
file set foo.flac $flac
```

[oc_exec-1.0.tm](oclib/oc_exec-1.0.tm]


### "proc" extension with blocks for contracts, examples, comments and aliass...

```tcl
proc file_get {file} {

    Read entire content of "file".

} require {

    is_file $file

} do {

    set f [open $file {RDONLY BINARY}]
    set result [read $f]
    close $f
    return $result

} alias {

    file_read
    file_read_all
}
```

```tcl
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
```

[oc_proc-1.0.tm](oclib/oc_proc-1.0.tm]


### "retry" error handling loops

```tcl
retry count 4 {

    set res [aws_sqs $aws CreateQueue QueueName $name {*}$attributes]

} trap QueueAlreadyExists {} {

    delete_aws_sqs_queue [aws_sqs_queue $aws $name]

} trap AWS.SimpleQueueService.QueueDeletedRecently {} {

    puts "Waiting 1 minute to re-create SQS Queue \"$name\"..."
    after 60000
}
```

[oc_retry-1.0.tm](oclib/oc_retry-1.0.tm]


### Symbolic exit code handling

(As per sysexits.h)

```tcl
try {
    ...
} trap {AWS.SimpleQueueService.QueueDeletedRecently} {
    exit EX_TEMPFAIL "Can't reuse queue name immediately after deletion. Please wait..."
}
```

```tcl
retry count 2 {
    ...
    exec ./create_queue.tcl "foobar"
    ...
} trap {EX_TEMPFAIL} {
    after 60000
}
```

[oc_exec-1.0.tm](oclib/oc_exec-1.0.tm]


### Micelaneous list processing commands

lconcat, lfilter, lrm_empty, laverage, lpercentile, lcount, lfirst, lshuffle, push, lsplit...

[oc_list-1.0.tm](oclib/oc_list-1.0.tm]

See [oclib/oc_test.tcl](oclib/oc_test.tcl) for more examples.

