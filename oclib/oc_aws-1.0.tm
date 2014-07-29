#===============================================================================
# oc_aws-1.0.tm
#
# OC_AWS: OC Technology Amazon AWS utilities for Tcl.
#
# See oc_aws_test.tcl for usage examples.
#
# Copyright Sam O'Connor 2012
# Licenced for use under the same terms as Tcl 8.6. See:
# http://core.tcl.tk/tcl/artifact/537ba3f664b958496ab51849e23d7f564342014b
# http://github.com/tcltk/tcl/raw/core_8_6_1/license.terms
#===============================================================================


package require Tcl 8.6
package require tdom
package require tcllibc
package require md5
package require sha1
package require sha256
package require uri
package require tls
package require http 2.8.7
package require json

package require oclib::oc_base 1.0
package require oclib::oc_string 1.0
package require oclib::oc_object 1.0
package require oclib::oc_dict 1.0
package require oclib::oc_list 1.0
package require oclib::oc_retry 1.0

package provide oc_aws 1.0


#proc http::Log {args} {
#    puts "http: $args"
#}


proc load_aws_credentials {{file {}}} {
    # Load credentials from "file".
    # Format:
    # AWSAccessKeyId=XXXXXXXXXXXX
    # AWSSecretKey=XXXXXXXXXXXX
    # AWSToken=XXXXXXXXXXXX (optional STS token)

    if {$file != {}} {
        for line in [: [file get $file] | trim | lines] {
            if {[regexp {^([^=]*)=(.*)$} $line - name value]} {
                dset result $name $value
            }
        }
        return $result
    }

    # Try to load from file specified by env var...
    if {[exists ::env(OC_AWS_CREDENTIALS)]
    &&  [file exists $::env(OC_AWS_CREDENTIALS)]} {
        return [load_aws_credentials $::env(OC_AWS_CREDENTIALS)]
    }

    # Try to load from env vars...
    for var in {AWSAccessKeyId AWSSecretKey AWSToken AWSUserArn} {
        if {[exists ::env($var)]} {
            dset result $var $::env($var)
        }
    }
    if {[exists result]} {
        return $result
    }

    # Try to load from HTTP cookie...
    if {[exists ::env(HTTP_COOKIE)]} {
        set result [: $::env(HTTP_COOKIE) | parse qstring | get oc_aws_auth]
        if {[not_empty $result]} {
            return [parse base64 $result]
        }
    }

    # Try to load from local EC2 instance metadata...
    get_aws_ec2_instance_credentials {} -force-refresh

    return {}
}



#-------------------------------------------------------------------------------
# AWS Resource & Region Name Utilities.
#-------------------------------------------------------------------------------


proc aws_account_number {aws} {

    if {![exists $aws AWSUserArn]} {
        set aws [get_aws_ec2_instance_credentials $aws]
    }

    regexp {^arn:aws:[^:]*:[^:]*:([^:]*):[^:]*$} \
           [get $aws AWSUserArn] \
           - account
    return $account
}


proc aws_region_id {region} {

    Look up AWS region id for 2-letter region code.

} do {

    switch $region {
        *       {return *}
        us      {return us-east-1}
        eu      {return eu-west-1}
        au      {return ap-southeast-2}
        as      {return ap-southeast-2}
        default {return us-east-1}
    }
}


proc aws_path_region {path} {

    Return 2-letter region prefix for "path".
    Defaults to "us".

} example {

    [aws_path_region "au-foobar"] eq "au"
    [aws_path_region "au"]        eq "au"
    [aws_path_region "foobar"]    eq "us"
    [aws_path_region "*"]         eq "*"

} do {

    if {$path eq "*"} {
        return $path
    }

    if {[length $path] == 2} {
        return $path
    }
    for region in {au eu as us} {
        if {[equal -length 3 $region- $path]} {
            return $region
        }
    }
    return $region
}


proc aws_bucket_region {bucket} {

     Return 2-letter region from for "bucket".

} example {

    [aws_bucket_region foo.bar.au.bucket1] eq "au"
    [aws_bucket_region foo.bar.us.bucket1] eq "us"

} do {

    set region {}
    regexp {([aeus]{2})[.][^.]*$} $bucket - region
    return $region
}


proc aws_endpoint {service {path {}}} {

    if {$service in {iam sts}} {
        set protocol https
    } else {
        set protocol http
    }

    if {$path eq {}} {
        return $protocol://$service.amazonaws.com/
    }

    set region_id [aws_region_id [aws_path_region $path]]

    if {"$service.$region_id" eq "sdb.us-east-1"} {
        return $protocol://sdb.amazonaws.com/
    }

    return $protocol://$service.$region_id.amazonaws.com/
}


proc aws_s3_endpoint {bucket} {

    set region [aws_region_id [aws_bucket_region $bucket]]

    if {$region eq "us-east-1"} {
        set host s3
    } else {
        set host s3-$region
    }

    if {$bucket ne {}} {
        append bucket .
    }

    return http://$bucket$host.amazonaws.com/
}


proc aws_arn {aws service resource {region {}} {account {}}} {
    if {$service in {iam s3}} {
        assert empty $region
    } else {
        if {$region eq {}} {
            set region [aws_path_region $resource]
        }
        if {$region ne "*"} {
            set region [aws_region_id $region]
        }
    }
    if {$service ne "s3" && $account eq {}} {
        set account [aws_account_number $aws]
    }
    return arn:aws:$service:$region:$account:$resource
}



#-------------------------------------------------------------------------------
# S3 Utilities. See http://aws.amazon.com/documentation/s3/
#-------------------------------------------------------------------------------


proc aws_s3_arn {bucket {path {}}} {
    # S3 ARN for "path" in "bucket".

    if {$path eq {}} {
        aws_arn {} s3 $bucket
    } else {
        aws_arn {} s3 $bucket/$path
    }
}


proc aws_s3_bucket_list {aws} {
    # List of S3 buckets.

    set xml [aws_rest $aws GET]
    set buckets [get [aws_xml_dict $xml] ListAllMyBucketsResult Buckets]
    lmap {tag bucket} $buckets {get $bucket Name}
}


proc create_aws_s3_bucket {aws bucket} {
    # Create S3 "bucket".

    puts "Creating Bucket \"$bucket\"..."

    set region [aws_bucket_region $bucket]

    try {

        if {$region != "us"} {

            switch $region {
                eu {set region EU}
                au {set region ap-southeast-2}
            }

            aws_rest $aws PUT $bucket Content [subst {
                <CreateBucketConfiguration
                                xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
                  <LocationConstraint>$region</LocationConstraint>
                </CreateBucketConfiguration >
            }] Content-Type text/plain

        } else {

            aws_rest $aws PUT $bucket
        }

    } trap BucketAlreadyOwnedByYou {} {}
}


proc delete_aws_s3_bucket {aws bucket} {
    # Delete S3 "bucket" (which must be empty).

    aws_rest $aws DELETE $bucket
}


proc aws_s3_key_dicts {aws bucket {delimiter {}} {prefix {}} {marker {}}} {
    # List of dicts for keys in S3 "bucket". e.g.:
    # {Key file1 LastModified 2012-03-09T09:49:30.000Z Size 19} ...

    set qs {}
    if {$delimiter != {}} {
        lappend qs delimiter $delimiter
    }
    if {$prefix != {}} {
        lappend qs prefix $prefix
    }
    if {$marker != {}} {
        lappend qs marker $marker
    }

    set xml [aws_rest $aws GET $bucket query $qs]
    set dict [aws_xml_dict $xml]
    set result {}
    set is_truncated 0

    foreach {tag value} [get $dict ListBucketResult] {
        if {$tag eq "IsTruncated" && $value eq "true"} {
            set is_truncated 1
        }
        if {$tag eq "Contents"} {
            lappend result $value
        }
        if {$tag eq "CommonPrefixes"} {
            foreach {{} prefix} $value {
                lappend result [list Key $prefix]
            }
        }
    }
    if {$is_truncated} {
        set marker [get [lindex $result end] Key]
        set more [aws_s3_key_dicts $aws $bucket $delimiter $prefix $marker]
        set result [concat $result $more]
    }
    return $result
}


proc aws_s3_key_list {aws bucket {delimiter {}}} {
    # List of keys in S3 "bucket".

    set result {}
    foreach dict [aws_s3_key_dicts $aws $bucket $delimiter] {
        lappend result [get $dict Key]
    }
    return $result
}


proc aws_s3_folder_list {aws bucket delimiter {prefix {}}} {
    # List of subkeys under "prefix" in S3 "bucket".

    set result {}
    set l [length $prefix]
    foreach dict [aws_s3_key_dicts $aws $bucket $delimiter $prefix] {
        set name [: $dict | get Key | range $l end]
        if {$name != {}} {
            lappend result $name
        }
    }
    return $result
}


proc aws_s3_get {aws bucket path args} {
    # Data for S3 "path".

    aws_rest $aws GET $bucket path $path {*}$args
}


proc aws_s3_version_list {aws bucket path} {
    # Version List for S3 "path".

    set is_truncated 1
    set versions {}
    set marker {}

    while {$is_truncated} {
        set xml [aws_rest $aws GET $bucket query versions=&prefix=$path$marker]

        foreach {n v} [: $xml | aws_xml_dict | get ListVersionsResult] {
            if {$n eq "IsTruncated" && $v eq "false"} {
                set is_truncated 0
            }
            if {$n eq "Version"} {
                lappend versions $v
                set marker &key-marker=[get $v Key]
            }
        }
    }

    return $versions
}


proc aws_s3_get_meta {aws bucket path} {
    # Metadata for S3 "path".

    aws_s3_get $aws $bucket $path Range bytes=0-0
}


proc aws_s3_get_version {aws bucket path version} {
    # Data for S3 "path".

    aws_rest $aws GET $bucket path $path query versionId=$version
}


proc aws_s3_creation_date {aws bucket path} {
    set creation_date {}
    foreach version [aws_s3_version_list $aws $bucket $path] {
        set version_date [get $version LastModified]
        regsub {[.]000Z} $version_date {} version_date
        if {$creation_date eq {}
        ||  [clock scan $creation_date -gmt 1]
          > [clock scan $version_date -gmt 1]} {
            set creation_date $version_date
        }
    }
    return $creation_date
}


proc purge_aws_s3_versions {aws bucket {path {}} {pattern {}}} {
    # Delete all except the latest version.

    foreach v [aws_s3_version_list $aws $bucket $path] {
        dict with v {
            if {$pattern eq {} || [regexp $pattern $Key]} {
                if {$IsLatest eq "false"} {
                    puts "Purge: $Key $LastModified"
                    aws_s3_delete $aws $bucket $Key $VersionId
                }
            }
        }
        unset {*}[keys $v]
    }
}


proc aws_s3_exists {aws bucket path} {
    # Does S3 "path" exist?

    try {

        aws_s3_get $aws $bucket $path Range bytes=0-0
        return 1

    } trap NoSuchKey {} {
    } trap AccessDenied {} {}

    return 0
}


proc aws_s3_put {aws bucket path data {type {}}} {
    # Upload "data" for "path" in s3.

    if {$type eq {}} {
        foreach {ext type} {
            .pdf  application/pdf
            .csv  text/csv
            .txt  text/plain
            .log  text/plain
            .dat  application/octet-stream
            .gz   application/octet-stream
            .bz2  application/octet-stream
        } {
            if {[file extension $path] eq $ext} {
                break
            }
        }
    }

    aws_rest $aws PUT $bucket path $path Content $data Content-Type $type
}


proc aws_s3_delete {aws bucket path {version {}}} {
    # Remove data for "path" from S3.

    if {$version != {}} {
        set version versionId=$version
    }

    aws_rest $aws DELETE $bucket path $path query $version
}


proc aws_s3_copy {aws from_bucket from_path to_bucket to_path} {
    # Copy S3 "from_path" to "to_path".

    aws_rest $aws PUT $to_bucket path $to_path \
                  x-amz-copy-source /$from_bucket/$from_path
}


proc sign_aws_s3_url {aws bucket path seconds} {
    aws_attempt sign_aws_s3_url_attempt $aws $bucket $path $seconds
}


proc sign_aws_s3_url_attempt {aws bucket path seconds} {
    # Signed URL that grants access to "path" for "seconds".

    dset query AWSAccessKeyId [get $aws AWSAccessKeyId]
    dset query x-amz-security-token [get $aws AWSToken]
    dset query Expires [expr {[clock seconds] + $seconds}]
    dset query response-content-disposition attachment

    set digest "GET\n\n\n[get $query Expires]\n"
    append digest "x-amz-security-token:[get $query x-amz-security-token]\n"
    append digest "/$bucket/$path?response-content-disposition=attachment"
    dset query Signature [sign_aws_string $aws sha1 $digest]

    return [aws_s3_endpoint $bucket]$path?[qstring $query]
}


proc aws_s3_put_dict {aws bucket path dict} {
    aws_s3_put $aws $bucket $path [dict rfc_2822 $dict]
}


proc aws_s3_get_dict {aws bucket path} {

    try {

        parse rfc_2822 [aws_s3_get $aws $bucket $path]

    } trap NoSuchKey {} {
    } trap AccessDenied {} {}
}


#-------------------------------------------------------------------------------
# SQS Utilities. See http://aws.amazon.com/documentation/sqs/
#-------------------------------------------------------------------------------


proc aws_sqs_arn {aws {name {}}} {
    if {$name eq {}} {
        set name [get $aws QueueName]
    }
    aws_arn $aws sqs $name
}


#proc aws_sqs_arn {queue} {
#    # Look up queue's ARN.
#
#    set res [aws_sqs $queue GetQueueAttributes AttributeName.1 QueueArn]
#    get $res Attribute Value
#}


proc aws_sqs {queue action args} {
    # Send request to "queue".

    require not_empty $queue

    dset args Version 2012-11-05

    set response [aws_request $queue sqs \
                              name   [get $queue QueueName] \
                              path   [get $queue QueuePath] \
                              Action $action \
                              {*}$args]

    foreach tag [list ${action}Result ResponseMetadata] {
        if {[exists $response $tag]} {
            return [get $response $tag]
        }
    }
    error [list $action $args $response]
}


proc aws_sqs_queue {aws name} {
    # Look up existing queue.

#    return [dict replace $aws QueueName $name \
#                              QueuePath [aws_account_number $aws]/$name]

    try {

        dset aws QueueName $name
        dset aws QueuePath {}
        set res [aws_sqs $aws GetQueueUrl QueueName $name]
        dset aws QueuePath [: $res | get QueueUrl | uri::split | get path]
        return $aws

    } trap AWS.SimpleQueueService.NonExistentQueue {} {}
}


proc create_aws_sqs_queue {aws name args} {
    # Create new queue with "name".
    # args: VisibilityTimeout, MessageRetentionPeriod, DelaySeconds etc

    puts "Creating SQS Queue \"$name\"..."

    set attributes {}
    set i 1
    foreach {n v} $args {
        dset attributes Attribute.$i.Name $n
        dset attributes Attribute.$i.Value $v
        incr i
    }

    dset aws QueuePath {}
    dset aws QueueName $name

    retry count 4 {

        set res [aws_sqs $aws CreateQueue QueueName $name {*}$attributes]

    } trap QueueAlreadyExists {} {

        delete_aws_sqs_queue [aws_sqs_queue $aws $name]

    } trap AWS.SimpleQueueService.QueueDeletedRecently {} {

        puts "Waiting 1 minute to re-create SQS Queue \"$name\"..."
        after 60000
    }

    dset aws QueuePath [: $res | get QueueUrl | uri::split | get path]

    # Allow SNS topics from this AWS account to post to this queue...
    set sqs_arn [aws_sqs_arn $aws $name]
    set sns_arn [aws_sns_arn_prefix $aws $name]*
    aws_sqs $aws SetQueueAttributes \
        Attribute.Name Policy \
        Attribute.Value [subst -nocommands {{
          "Version": "2008-10-17",
          "Id": "$sqs_arn-policy",
          "Statement": [
            {
              "Sid": "1",
              "Effect": "Allow",
              "Principal": {
                "AWS": "*"
              },
              "Action": "SQS:SendMessage",
              "Resource": "$sqs_arn",
              "Condition": {
                "ArnEquals": {
                  "aws:SourceArn": "$sns_arn"
                }
              }
            }
          ]
        }}]

    return $aws
}


proc delete_aws_sqs_queue {queue} {
    # Remove "queue".

    try {

        puts "Deleting SQS Queue \"[get $queue QueueName]\"..."
        return [aws_sqs $queue DeleteQueue]

    } trap AWS.SimpleQueueService.NonExistentQueue {} {}
}


proc aws_sqs_send {queue message} {
    # Send "message" to "queue".

    set res [aws_sqs $queue SendMessage \
                            MessageBody $message \
                            MD5OfMessageBody [md5 $message base64]]
    get $res MessageId
}


proc aws_sqs_send_batch {queue args} {
    # Send "messages" to "queue".

    set i 1
    foreach message $args {
        lappend batch SendMessageBatchRequestEntry.$i.Id $i
        lappend batch SendMessageBatchRequestEntry.$i.MessageBody $message
        incr i
    }
    aws_sqs $queue SendMessageBatch {*}$batch
}


proc aws_sqs_receive {queue args} {
    # Recieve one message from "queue".

    get [aws_sqs $queue ReceiveMessage MaxNumberOfMessages 1 {*}$args] Message
}


proc aws_sqs_delete {queue message} {
    # Delete one message from "queue".

    aws_sqs $queue DeleteMessage ReceiptHandle [get $message ReceiptHandle]
}


proc aws_sqs_flush {queue} {
    # Delete all messages from "queue".

    while {[set message [aws_sqs_receive $queue]] ne {}} {
        aws_sqs_delete $queue $message
    }
}


proc aws_sqs_attributes {queue} {

    try {

        set response [aws_sqs $queue GetQueueAttributes AttributeName.1 All]

        foreach {tag attribute} $response {
            assign $attribute Name Value 
            dset result $Name $Value
        }
        return $result

    } trap AWS.SimpleQueueService.NonExistentQueue {} {}
}


proc aws_sqs_count {queue} {
    
    : [aws_sqs_attributes $queue] get ApproximateNumberOfMessages
}


proc aws_sqs_busy_count {queue} {
    
    : [aws_sqs_attributes $queue] get ApproximateNumberOfMessagesNotVisible
}


proc poll_aws_sqs_queue {sqs callback complete_topic error_topic timeout log} {
    # Run "callback" for every key in "sqs".
    # When callback returns, post key to "completion_topic" (or "error_topic")
    # Stop polling if there is no queue activity for "timeout" seconds.
    # Pass status messages to "log".
    # 
    # If "callback" returns without error (or with -errorcode EX_DATAERR)
    # the key is removed from the queue.
    #
    # Queued messages have the following format:
    #     key\r\n
    #     header field: value\r\n
    #     header field: value\r\n
    #     \r\n
    #     body...

    set t [clock seconds]

    while {[clock seconds] < $t + $timeout} {

        $log "Polling [get $sqs QueueName]..."

        if {[not_empty [set job [aws_sqs_receive $sqs WaitTimeSeconds 20]]]} {

            set t [clock seconds]

            run_aws_sqs_job $sqs $job $callback $complete_topic $error_topic $log
        }
    }
}


proc run_aws_sqs_job {sqs job callback complete_topic error_topic log} {

    try {

        set job_info {}

        # Attempt to parse JSON job info form Body of "job"...
        if {[catch {set job_info [: $job | get Body | parse json]}]} {

            dset job_info Message [get $job Body]
        }

        # Extract RFC_2822 formated Message from job info...
        set message [: $job_info | get Message | parse rfc_2822]

        # Filter out unwanted SNS info...
        set job_info [filter $job_info key Timestamp TopicArn]

        # Merge message info into job info...
        set job_info [merge $job_info $message]

        # Extract "topic" and "short_topic" from ARN...
        dset job_info topic [: [get $job_info TopicArn] | split : | lindex end]
        dset job_info short_topic [: \
            $job_info | get topic | split - | lrange end-1 end | join -]

        # Derive region from queue name...
        dset job_info region [aws_path_region [get $sqs QueueName]]

        # Pass temporary credentials in ::env()...
        foreach var {AWSAccessKeyId AWSSecretKey AWSToken AWSUserArn} {
            if {[exists $job_info $var]} {
                set ::env($var) [get $job_info $var]
                dunset job_info $var
            }
        }

        $log "    Key: [get $job_info key] ..."

        # Run the callback...
        set result [eval [list $callback $job_info]]
        set result_info [parse rfc_2822 $result]

        # Send result to completion topic...
        if {$complete_topic ne {}} {
            try {
                aws_sns_publish [aws_sns_topic $sqs $complete_topic] \
                                $result \
                                "$complete_topic: [get $result_info key]"
            } trap NotFound {} {
            }
        }

        aws_sqs_delete $sqs $job

        $log "    $result"
        $log "    Done."

    } on error {message info} {

        $log "    ERROR: [get $info -errorcode]"
        $log "    $message"
        $log "    $job_info"

        dset job_info body $message
        dset job_info error [get $info -errorcode]

        aws_sns_publish [aws_sns_topic $sqs $error_topic] \
                        [rfc_2822 $job_info] \
                        "$error_topic: [get $job_info key]"

        if {[get $info -errorcode] eq "EX_DATAERR"} {
            $log "    Got EX_DATAERR, deleting job from queue!"
            aws_sqs_delete $sqs $job
        }

    } finally {

        unset -nocomplain ::env(AWSAccessKeyId) \
                          ::env(AWSSecretKey) \
                          ::env(AWSToken) \
                          ::env(AWSUserArn)
    }
}



#-------------------------------------------------------------------------------
# EC2 Utilities. See http://aws.amazon.com/documentation/ec2/
#-------------------------------------------------------------------------------


proc aws_ec2 {ec2 action args} {
    # Send "request" to EC2.

    dset args Version 2014-02-01

    set response [aws_request $ec2   ec2 \
                              name   [get $ec2 name] \
                              Action $action \
                              {*}$args]

    if {$action eq "DescribeTags"} {
        set result {}
        foreach {item dict} [get $response tagSet] {
            lappend result $dict
        }
        return $result
    }

    return $response
}


proc aws_ec2_tags {ec2} {
    # Tags for "instance".

    set response [aws_ec2 $ec2 DescribeTags \
                               Filter.1.Name resource-id \
                               Filter.1.Value.1 [get $ec2 id]]
    foreach tag $response {
        dset result [get $tag key] [get $tag value]
    }
    return $result
}


proc aws_ec2_instances {aws region} {
    # Dictionary of instance ids keyed on instance name.

    set ec2 $aws
    dset ec2 name $region

    set result {}
    foreach item [aws_ec2 $ec2 DescribeTags] {
        dict with item {
            if {"$resourceType.$key" eq "instance.Name"} {
                lappend result $value \
                               [merge $ec2 [list name $value id $resourceId]]
            }
        }
    }
    return $result
}


proc aws_ec2_instance {aws name} {
    # EC2 instance matching "name".

    : [aws_ec2_instances $aws $name] get $name
}


proc aws_ec2_ip_for_name {aws name} {
    # IP Address of instance with Name tag matching "name".

    : $aws | aws_ec2_instance $name | describe_aws_ec2 | get ipAddress
}


proc create_aws_ec2_tag {ec2 tag_key tag_value} {
    # Apply "tag_key" and "tag_value" to "instance".

    retry count 3 {

        aws_ec2 $ec2 CreateTags \
                     ResourceId.1 [get $ec2 id] \
                     Tag.1.Key $tag_key \
                     Tag.1.Value $tag_value

    } trap InvalidInstanceID.NotFound {} {
        after [expr {$count * $count * 1000}]
    }
}


proc delete_aws_ec2_tag {ec2 tag_key} {
    # Remove "tag_key" from "instance".

    aws_ec2 $ec2 DeleteTags ResourceId.1 [get $ec2 id] Tag.1.Key $tag_key
}


proc encode_aws_ec2_user_data {name_type_content_list} {

    package require mime

    set parts {}
    foreach {name type content} $name_type_content_list {
        lappend parts [mime::initialize \
                            -canonical $type \
                            -encoding binary \
                            -string $content \
                            -header [list Content-Disposition \
                                          "attachment; filename=$name"]]
    }

    set user_data [mime::buildmessage \
                  [mime::initialize -canonical multipart/mixed -parts $parts]]

    base64 $user_data
}


proc find_aws_ec2_image {ec2 description {filter {}}} {

    set response [aws_ec2 $ec2 DescribeImages \
                               Filter.1.Name description \
                               Filter.1.Value.1 $description]

    foreach {image info} [get $response imagesSet] {
        dset result [get $info imageId] $info
    }

    if {$filter != {}} {
        set filtered [dict create]
        foreach {id info} $result {
            set keep 1
            foreach {n v} $filter {
                if {![exists $info $n]
                ||  ![regexp $v [get $info $n]]} {
                    set keep 0
                }
            }
            if {$keep} {
                dset filtered $id $info
            }
        }
        set result $filtered
    }
    return $result
}


proc create_aws_ec2 {aws name args} {
    # Create a new instance with "name".
    # args: ImageId, KeyName, UserData, InstanceType etc
    #       IamInstanceProfile.Name

    set ec2 $aws
    dset ec2 name $name

    # Delete old instance...
    set old [aws_ec2_instance $ec2 $name]
    if {$old != {}} {
        puts "Deleting old \"$name\" [get $old id]..."
        delete_aws_ec2_tag $old Name
        aws_ec2_instance_do $old Terminate
    }

    # Lookup ImageID...
    if {![exists $args ImageId]} {

        assign $args ImageDescription ImageVersion
        set image [find_aws_ec2_image $ec2 $ImageDescription \
                                           [list name $ImageVersion]]
        set image [lindex $image 0]
        puts "Found \"$ImageDescription $ImageVersion\": $image"
        dset args ImageId $image
        dunset args ImageDescription
        dunset args ImageVersion
    }

    # Set up InstanceProfile Policy...
    if {[exists $args Policy]} {
        create_aws_iam_role $aws $name-role
        put_aws_iam_role_policy $aws $name-role \
                                     $name-policy \
                                     [get $args Policy]
        create_aws_iam_instance_profile $aws $name-role
        add_role_to_aws_iam_instance_profile $aws $name-role $name-role
        dset args IamInstanceProfile.Name $name-role
        dunset args Policy
        after 10000
    }

    # MIME/Base64 Encode UserData...
    if {[exists $args UserData]} {
        dset args UserData [encode_aws_ec2_user_data [get $args UserData]]
    }

    # Set default instance count to 1...
    foreach count {MinCount MaxCount} {
        if {![exists $args $count]} {
            dset args $count 1
        }
    }

    if {[exists $args ElasticIP]} {
        set elastic_ip [get $args ElasticIP]
        dunset args ElasticIP
    }

    # Create the instance...
    dict with args {puts "Creating $InstanceType, $ImageId, \"$name\"..."}
    set response [aws_ec2 $ec2 RunInstances {*}$args]
    dset ec2 id [get $response instancesSet item instanceId]

    create_aws_ec2_tag $ec2 Name $name

    wait_for_aws_ec2 $ec2

    if {[exists elastic_ip]} {
        aws_ec2_associate_address $ec2 $elastic_ip
    }

    return $ec2
}


proc aws_ec2_associate_address {ec2 elastic_ip} {

    puts "Assigning Elastic IP: $elastic_ip"
    retry count 3 {

        aws_ec2 $ec2 AssociateAddress InstanceId [get $ec2 id] \
                                      PublicIp $elastic_ip

    } trap InvalidInstanceID {} {
        after [expr {$count * $count * 1000}]
    }
}


proc aws_ec2_state {ec2} {

    : $ec2 | describe_aws_ec2 | get instanceState name
}


proc aws_ec2_is_running {ec2} {

    expr {[aws_ec2_state $ec2] eq "running"}
}


proc aws_ec2_is_stopped {ec2} {

    expr {[aws_ec2_state $ec2] eq "stopped"}
}


proc wait_for_aws_ec2 {ec2} {

    puts -nonewline "Waiting for instance [get $ec2 id] to boot..."
    while {1} {
        set ec2_info [describe_aws_ec2 $ec2]
        set state [get $ec2_info instanceState name]
        if {$state ne "pending"} {
            set ip [get $ec2_info ipAddress]
            puts " $state $ip"
            puts "ssh -i ~/.ec2/ssh-ec2-gkc.pem ec2-user@$ip"
            break
        }
        puts -nonewline "."
        flush stdout
        after 1000
    }
}


proc describe_aws_ec2 {ec2} {
    # Info about "instance".

    set response [aws_ec2 $ec2 DescribeInstances \
                               Filter.1.Name instance-id \
                               Filter.1.Value.1 [get $ec2 id]]
    get $response reservationSet item instancesSet item
}


proc aws_ec2_instance_do {ec2 verb} {
    # Do "verb" to "$ec2".
    # verb: Stop, Start, Reboot, Terminate

    aws_ec2 $ec2 ${verb}Instances InstanceId.1 [get $ec2 id]
}


proc aws_ec2_stop      {ec2} {aws_ec2_instance_do $ec2 Stop     }
proc aws_ec2_start     {ec2} {aws_ec2_instance_do $ec2 Start    }
proc aws_ec2_reboot    {ec2} {aws_ec2_instance_do $ec2 Reboot   }
proc aws_ec2_terminate {ec2} {aws_ec2_instance_do $ec2 Terminate}


proc aws_ec2_address {ec2} {
    # DNS address of "ec2".

    set response [aws_ec2 $ec2 DescribeInstances \
                                 Filter.1.Name instance-id \
                                 Filter.1.Value.1 [get $ec2 id]]
    get $response reservationSet item instancesSet item dnsName
}


proc aws_ec2_console {ec2} {
    # Console output for "ec2".

    set response [aws_ec2 $ec2 GetConsoleOutput InstanceId.1 [get $ec2 id]]

    : $response | get output | parse base64
}


proc aws_ec2_scp {ip files target {key {}}} {
    # scp to EC2 box at "ip".

    if {$key eq {}} {
        set key $::env(HOME)/.ssh/ssh-ec2.pem
    }
    exec scp -r -C -o StrictHostKeyChecking=no \
                   -i $key \
                      {*}$files ec2-user@$ip:$target >&@ stdout
}


proc aws_ec2_ssh {ip cmd {key {}}} {
    # Execute "args" on EC2 box at "ip" using ssh.

    if {$key eq {}} {
        set key $::env(HOME)/.ssh/ssh-ec2.pem
    }
    puts "$ip: $cmd:"
    exec ssh -o StrictHostKeyChecking=no \
             -i $key \
             ec2-user@$ip $cmd >&@ stdout
}


proc aws_ec2_metadata {key} {
    # Lookup EC2 meta-data "key".
    # Must be called from and EC2 instance.
    # http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/AESDG-chapter-instancedata.html

    : http://169.254.169.254/latest/meta-data/$key | aws_http_attempt | get body
}


proc get_aws_ec2_instance_credentials {aws {option {}}} {

    if {$option != "-force-refresh"
    && [info exists ::oc_aws_ec2_instance_credentials]} {
        return [merge $aws $::oc_aws_ec2_instance_credentials]
    }

    set info [: [aws_ec2_metadata iam/info] | parse json]
    set name [aws_ec2_metadata iam/security-credentials/]
    set creds [: [aws_ec2_metadata iam/security-credentials/$name] | parse json]

    set ::oc_aws_ec2_instance_credentials \
        [dict create AWSAccessKeyId [get $creds AccessKeyId] \
                     AWSSecretKey   [get $creds SecretAccessKey] \
                     AWSToken       [get $creds Token] \
                     AWSUserArn     [get $info InstanceProfileArn]]
    return [merge $aws $::oc_aws_ec2_instance_credentials]
}


#-------------------------------------------------------------------------------
# SES Utilities. See http://aws.amazon.com/documentation/ses/
#-------------------------------------------------------------------------------


proc aws_ses {aws query_dict} {
    aws_attempt aws_ses_attempt $aws $query_dict
}


proc aws_ses_attempt {aws query} {
    # Send "query" to SES...

    set date [aws_http_date_now]
    set auth [list  "AWS3-HTTPS AWSAccessKeyId=[get $aws AWSAccessKeyId]" \
                    "Algorithm=HmacSHA256" \
                    "Signature=[sign_aws_string $aws sha2 $date]"]
    dset headers Date $date
    dset headers X-Amzn-Authorization [join $auth ,]

    dset query AWSAccessKeyId [get $aws AWSAccessKeyId]

    if {[exists $aws AWSToken]} {
        dset query SecurityToken [get $aws AWSToken]
    }

    set result [aws_http_attempt https://email.us-east-1.amazonaws.com/ \
                                 -method POST \
                                 -query [qstring $query] \
                                 -headers $headers \
                                 -timeout [expr {60 * 1000}]]
    set data [get $result body]

    # Find [Action]Response tag...
    set tag [get $query Action]Response
    : $data | aws_xml_dict | get $tag
}


proc aws_ses_send {aws from to subject body} {
    # Send email.

    aws_ses $aws [subst {
        Action SendEmail
        Source $from
        Destination.ToAddresses.member.1 $to
        Message.Subject.Data $subject
        Message.Body.Text.Data $body
    }]
}


proc aws_ses_send_raw {aws from to raw_message} {
    # Send raw email.

    aws_ses $aws [subst {
        Action SendRawEmail
        Source $from
        Destination.ToAddresses.member.1 $to
        RawMessage.Data [base64 $raw_message]
    }]
}


proc aws_ses_send_attachment {aws from to subject message type name attachment} {
    # Send message with attachment.

    set message_type text/plain

    if {[regexp {DOCTYPE HTML PUBLIC} $message]} {
        set message_type text/html
    }

    package require mime
    set m [mime::initialize \
        -canonical multipart/mixed \
        -header [list To $to] \
        -header [list From $from] \
        -header [list Subject $subject] \
        -parts  [list \
            [mime::initialize -canonical $message_type -string $message] \
            [mime::initialize -canonical $type -string $attachment \
                              -header [list Content-Disposition \
                                            "attachment; filename=$name"]] \
        ]]

    aws_ses $aws [subst {
        Action SendRawEmail
        Source $from
        Destination.ToAddresses.member.1 $to
        RawMessage.Data [: $m | mime::buildmessage | base64 ]
    }]
}



#-------------------------------------------------------------------------------
# IAM Utilities. See http://aws.amazon.com/documentation/iam/
#-------------------------------------------------------------------------------


proc aws_iam_role_arn {aws role} {

    aws_arn $aws iam role/$role
}


proc aws_iam {aws action args} {
    # Send "action" to IAM.

    dset args Version 2010-05-08
    aws_request $aws iam Action $action {*}$args
}


proc aws_iam_user_info {aws {user_name {}}} {
    # Information about user.

    set options {}
    if {$user_name != {}} {
        set options [list UserName $user_name]
    }
    get [aws_iam $aws GetUser {*}$options] GetUserResult User
}


proc aws_iam_role_info {aws role_name} {
    # Information about role.

    get [aws_iam $aws GetRole RoleName $role_name] GetRoleResult Role
}


proc create_aws_iam_user {aws user_name} {
    # Create "user_name".

    set response [aws_iam $aws CreateUser UserName $user_name]
    set id [get $response CreateUserResult User UserId]

    create_aws_iam_user_credentials $aws $user_name
}


proc delete_aws_iam_user_credentials {aws user_name} {

    for {- key} in [get [aws_iam $aws ListAccessKeys UserName $user_name] \
                    ListAccessKeysResult AccessKeyMetadata] {
        set key [get $key AccessKeyId]
        aws_iam $aws DeleteAccessKey UserName $user_name AccessKeyId $key
    }
}


proc create_aws_iam_user_credentials {aws user_name} {

    set response [aws_iam $aws CreateAccessKey UserName $user_name]
    set key [get $response CreateAccessKeyResult AccessKey AccessKeyId]
    set sec [get $response CreateAccessKeyResult AccessKey SecretAccessKey]
    merge $aws [dict create AWSAccessKeyId $key \
                            AWSSecretKey $sec \
                            AWSUserArn [aws_arn $aws iam user/$user_name]]
}


proc delete_aws_iam_user {aws user_name} {
    # Delete "user_name".

    for {- policy} in [get [aws_iam $aws ListUserPolicies UserName $user_name] \
                    ListUserPoliciesResult PolicyNames] {
        aws_iam $aws DeleteUserPolicy UserName $user_name PolicyName $policy
    }

    delete_aws_iam_user_credentials $aws $user_name

    for {- key} in [get [aws_iam $aws ListMFADevices UserName $user_name] \
                    ListMFADevicesResult MFADevices] {
        set key [get $key SerialNumber]
        aws_iam $aws DeactivateMFADevice UserName $user_name SerialNumber $key
        aws_iam $aws DeleteVirtualMFADevice SerialNumber $key
    }

    aws_iam $aws DeleteUser UserName $user_name
}


proc put_aws_iam_user_policy {aws user_name policy_name policy} {
    # Set "policy" for "user_name".


    aws_iam $aws PutUserPolicy \
                 UserName $user_name \
                 PolicyName $policy_name \
                 PolicyDocument [aws_iam_policy_format $policy]
}


proc aws_iam_policy_format {policy_statement} {

    json [dict create Version 2012-10-17 Statement $policy_statement]
}


proc assume_aws_sts_role {aws duration_s name role {policy {}} {mfa {}}} {

    dset args Version 2011-06-15
    dset args DurationSeconds $duration_s
    dset args RoleArn [aws_iam_role_arn $aws $role]
    dset args RoleSessionName $name


    if {$policy != {}} {
        dset args Policy [aws_iam_policy_format $policy]
    }
    if {$mfa != {}} {
        dset args SerialNumber [lindex $mfa 0]
        dset args TokenCode [lindex $mfa 1]
    }

    set response [aws_request $aws sts Action AssumeRole {*}$args]

    set TokenArn [get $response AssumeRoleResult AssumedRoleUser Arn]
    set creds [get $response AssumeRoleResult Credentials]
    dict with creds {}
    subst {
        AWSAccessKeyId $AccessKeyId
        AWSSecretKey   $SecretAccessKey
        AWSToken       $SessionToken
        AWSUserArn     $TokenArn
        Expiration     $Expiration
    }
}


proc create_aws_iam_instance_profile {aws name {path /}} {
    # Create an Instance Profile for use with and EC2 instance.

    try {

        aws_iam $aws DeleteInstanceProfile InstanceProfileName $name

    } trap NoSuchEntity {} {}

    set response [aws_iam $aws CreateInstanceProfile \
                               InstanceProfileName $name \
                               Path $path]

    get $response CreateInstanceProfileResult InstanceProfile Arn
}


proc add_role_to_aws_iam_instance_profile {aws ip_name role_name} {
    # Add "role_name to "ip_name".

    set response [aws_iam $aws AddRoleToInstanceProfile \
                               InstanceProfileName  $ip_name \
                               RoleName $role_name]
}


proc create_aws_iam_role {aws name {path /} {options {}}} {
    # Create a Role.

    puts "Creating Role \"$name\"..."

    # Allow EC2 to assume this role...
    # Allow this account number to assume this role...
    if {"-require-mfa" in $options} {
        set assume_role_policy [aws_iam_policy_format [tcl_subst {
            Effect Allow
            Action sts:AssumeRole
            Principal {AWS "arn:aws:iam::[aws_account_number $aws]:root"}
            Condition {Null {JSONDict: aws:MultiFactorAuthAge false}}
        }]]
    } else {
        set assume_role_policy [aws_iam_policy_format [tcl_subst {
            Effect Allow
            Action sts:AssumeRole
            Principal {
                Service "ec2.amazonaws.com"
                AWS "arn:aws:iam::[aws_account_number $aws]:root"
            }
        }]]
    }

    # Clean up old role policies...
    try {

        set response [aws_iam $aws ListRolePolicies RoleName $name]
        set policy_names [get $response ListRolePoliciesResult PolicyNames]
        foreach {member policy_name} $policy_names {
            aws_iam $aws DeleteRolePolicy RoleName $name PolicyName $policy_name
        }
    } trap NoSuchEntity {} {}

    # Remove role from instance profiles...
    try {

        set response [aws_iam $aws ListInstanceProfilesForRole RoleName $name]
        set ip_names [get $response ListInstanceProfilesForRoleResult \
                                         InstanceProfiles]
        foreach {member ip} $ip_names {
            aws_iam $aws RemoveRoleFromInstanceProfile \
                         InstanceProfileName [get $ip InstanceProfileName]\
                         RoleName $name
        }
    } trap NoSuchEntity {} {}

    # Delete role...
    try {

        aws_iam $aws DeleteRole RoleName $name

    } trap NoSuchEntity {} {}

    set response [aws_iam $aws CreateRole \
                               AssumeRolePolicyDocument $assume_role_policy \
                               Path $path \
                               RoleName $name]

    get $response CreateRoleResult Role Arn
}


proc put_aws_iam_role_policy {aws role_name policy_name policy} {
    # Attach "policy" as "policy_name" to "role_name".

    set response [aws_iam $aws PutRolePolicy \
                               PolicyDocument [aws_iam_policy_format $policy] \
                               PolicyName $policy_name \
                               RoleName $role_name]
}


proc create_aws_iam_mfa {aws name {path /}} {

    aws_iam $aws DeleteVirtualMFADevice \
                 SerialNumber [aws_arn $aws iam mfa$path$name]

    : [aws_iam $aws CreateVirtualMFADevice \
                    VirtualMFADeviceName $name \
                    Path $path] \
    | get CreateVirtualMFADeviceResult VirtualMFADevice
}


proc enable_aws_iam_mfa {aws mfa_name user_name code1 code2} {

    aws_iam $aws EnableMFADevice \
                 UserName $user_name \
                 SerialNumber [aws_arn $aws iam mfa/$mfa_name] \
                 AuthenticationCode1 $code1 \
                 AuthenticationCode2 $code2
}



#-------------------------------------------------------------------------------
# DynamoDB Utilities. See http://aws.amazon.com/documentation/dynamodb/
#-------------------------------------------------------------------------------

# FIXME UpdateItem, UpdateTable, DeleteTable, DescribeTable, BatchGetItem,
#       BatchWriteItem

proc aws_dynamodb {aws table operation json} {

    set service dynamodb

    set url [aws_endpoint $service $table]

    set headers [subst {
        x-amz-target DynamoDB_20120810.$operation
        Content-Type application/x-amz-json-1.0
    }]

    set headers [aws4_request_headers $aws service $service \
                                           region  [aws_path_region $table] \
                                           method  POST \
                                           headers $headers \
                                           url     $url \
                                           body    $json]

    set result [aws_http_attempt $url -method POST \
                                      -headers $headers \
                                      -query $json \
                                      -timeout [expr {60 * 1000}]]

    assert {[get $result meta x-amz-crc32] eq [crc32 [get $result body]]}

    : $result | get body | parse json
}


proc aws_dynamodb_dict {dict} {

    dict for {n v} $dict {
        dset result $n [list S [list $v]]
    }
    return $result
}

proc aws_dynamodb_parse_item {item} {

    dict for {n v} $item {
        lassign $v type v
        dset result $n $v
    }
    return $result
}


proc aws_dynamodb_parse_items {items} {

    lmap item $items {aws_dynamodb_parse_item $item}
}


proc aws_dynamodb_list_tables {aws region} {

    : [aws_dynamodb $aws $region ListTables {{}}] | get TableNames
}


proc aws_dynamodb_put_item {aws table item} {

    aws_dynamodb $aws $table PutItem [json [list \
                             TableName $table \
                             Item [aws_dynamodb_dict $item]]]
}


proc aws_dynamodb_delete_item {aws table key} {

    aws_dynamodb $aws $table DeleteItem [json [list \
                             TableName $table \
                             Key [aws_dynamodb_dict $key]]]
}


proc aws_dynamodb_get_item {aws table key} {

    set response [aws_dynamodb $aws $table GetItem [json [list \
                                           TableName $table \
                                           Key [aws_dynamodb_dict $key]]]]

    : $response | get Item | aws_dynamodb_parse_item
}


proc aws_dynamodb_scan {aws table} {

    set response [aws_dynamodb $aws $table Scan [json [list TableName $table]]]

    : $response | get Items | aws_dynamodb_parse_items
}


proc aws_dynamodb_list {list} {

    set list [lmap item $list {subst {{"S": [json_string $item]}}}]
    return \[[join $list ,]\]
}


proc aws_dynamodb_key_condition {key operator args} {

    require {$operator in {EQ LE LT GE GT BEGINS_WITH BETWEEN}}

    aws_dynamodb_condition $key $operator {*}$args
}

proc aws_dynamodb_condition {key operator args} {

    require {$operator in {EQ NE LE LT GE GT NOT_NULL NULL
                          CONTAINS NOT_CONTAINS BEGINS_WITH IN BETWEEN}}

    subst {
        [json_string $key]: {
            "ComparisonOperator": [json_string $operator],
            "AttributeValueList": [aws_dynamodb_list $args]
        }
    }
}



proc aws_dynamodb_query {aws table key {filter {}}} {

    e.g.  aws_dynamodb_query $aws au-Thread {
              ForumName EQ "bAmazon DynamoDB"
              Subject BEGINS_WITH "bHow"
          }

} do {

    set key [lmap {a b c} $key {list $a $b $c}]
    set key_conditions [lmap arg $key {aws_dynamodb_key_condition {*}$arg}]

    if {$filter ne {}} {
        set filter [lmap {a b c} $filter {list $a $b $c}]
        set filter [lmap arg $filter {aws_dynamodb_condition {*}$arg}]
        set filter [subst {,"QueryFilter": { [join $filter ,] }}]
    }

    set query [subst {{
        "TableName": [json_string $table],
        "KeyConditions": { [join $key_conditions ,] }
        $filter
    }}]

    puts $query

    set response [aws_dynamodb $aws $table Query $query]

    : $response | get Items | aws_dynamodb_parse_items
}



#-------------------------------------------------------------------------------
# SimpleDB Utilities. See http://aws.amazon.com/documentation/simpledb/
#-------------------------------------------------------------------------------



proc debug_aws_sdb_usage {action response} {

    if {![exists ::aws_sdb_usage_total]} {
        set ::aws_sdb_usage_total 0
    }

    set usage [dget $response ResponseMetadata BoxUsage]
    set cost [expr {$usage * 0.154}]
    set ::aws_sdb_usage_total [expr {$::aws_sdb_usage_total + $cost}]
    set seconds [expr {$usage / (60.0 * 60.0)}]
    puts stderr "SDB $action $usage s, \$$cost (total \$$::aws_sdb_usage_total)"
}


proc aws_sdb {aws action args} {
    # Send "action" to SimpleDB.

    dset args Version 2009-04-15

    if {[exists $args DomainName]} {
        set domain [get $args DomainName]
    } else {
        regexp {from [`]?([^ `]*)} [get $args SelectExpression] \
                ignored   domain
    }
    set result [aws_request $aws sdb name $domain Action $action {*}$args]
    debug_aws_sdb_usage $action $result
    return $result
}


proc aws_sdb_list_domains {aws region} {
    # List domains.

    set response [aws_request $aws    sdb \
                              name    $region \
                              Action  ListDomains \
                              Version 2009-04-15]

    debug_aws_sdb_usage ListDomains $response
    set l {}
    foreach {n v} [get $response ListDomainsResult] {
        if {$n eq "DomainName"} {
            lappend l $v
        }
    }
    return $l
}


proc aws_sdb_create_domain {aws domain} {
    # Create domain named "domain".

    aws_sdb $aws CreateDomain DomainName $domain
}


proc aws_sdb_delete_domain {aws domain} {
    # Delete domain named "domain".

    aws_sdb $aws DeleteDomain DomainName $domain
}


proc aws_sdb_put {aws domain item replace args} {
    # Assign "args" to "item" in "domain".

    set attributes {}
    set i 1
    foreach {name value} $args {
        lappend attributes Attribute.$i.Name $name \
                           Attribute.$i.Value $value \
                           Attribute.$i.Replace $replace

        incr i
    }

    aws_sdb $aws PutAttributes \
                 DomainName $domain \
                 ItemName $item \
                 {*}$attributes
}


proc aws_sdb_batch_put {aws domain replace dict} {
    # Load item, attributes "dict" into "domain".

    set keys [keys $dict]
    for {set n 0} {$n < [llength $keys]} {incr n 25} {
        set attributes {}
        set i 1
        foreach item [lrange $keys $n [expr {$n + 24}]] {
            set info [get $dict $item]

            lappend attributes Item.$i.ItemName $item

            set j 1
            foreach {name value} $info {
                lappend attributes Item.$i.Attribute.$j.Name $name \
                                   Item.$i.Attribute.$j.Value $value \
                                   Item.$i.Attribute.$j.Replace $replace
                incr j
            }
            incr i
        }
        aws_sdb $aws BatchPutAttributes DomainName $domain {*}$attributes
    }
}


proc delete_aws_sdb_item {aws domain item} {
    # Delete "item" from "domain".

    aws_sdb $aws DeleteAttributes \
                 DomainName $domain \
                 ItemName $item
}


proc aws_sdb_get {aws domain item {attribute {}}} {
    # Get attributes for "item" in "domain".

    set args {}
    if {$attribute != ""} {
        lappend args AttributeName $attribute
    }

    set response [aws_sdb $aws GetAttributes \
                               DomainName $domain \
                               ItemName $item \
                               {*}$args]

    set attributes {}
    foreach {tag dict} [get $response GetAttributesResult] {
        if {$tag eq "Attribute"} {
            dset attributes [get $dict Name] [get $dict Value]
        }
    }
    if {$attribute != {}} {
        return [get $attributes $attribute]
    }
    return $attributes
}


proc aws_sdb_select {aws next_token_var query} {
    # Select "query" items.

    set result {}

    set args [dict create SelectExpression $query]
    if {$next_token_var != {}} {
        upvar $next_token_var next_token
        if {$next_token != {}} {
            dset args NextToken $next_token
        }
    }
    set response [aws_sdb $aws Select {*}$args]

    while {1} {
        set response [get $response SelectResult]

        foreach {tag item} $response {
            if {$tag eq "Item"} {
                set attributes {}
                foreach {n v} $item {
                    switch $n {
                        Name      {set item_name $v}
                        Attribute {dict with v {
                                          dict lappend attributes $Name $Value}}
                    }
                }
                dset result $item_name $attributes
            }
        }

        if {![exists $response NextToken]} {
            set next_token {}
            break
        }

        set next_token [get $response NextToken]
        if {$next_token_var != {}} {
            break
        }
        set response [aws_sdb $aws Select SelectExpression $query \
                                          NextToken $next_token]
    }
    return $result
}



#-------------------------------------------------------------------------------
# SNS Utilities. See http://aws.amazon.com/documentation/sns/
#-------------------------------------------------------------------------------


proc aws_sns_arn_prefix {aws path} {

    aws_arn $aws sns {} [aws_path_region $path]
}


proc aws_sns_arn {aws name} {

    aws_arn $aws sns $name
}


proc aws_sns {topic action args} {
    # Send "action" to SNS "topic".

    dset args Version 2010-03-31

    if {[exists $topic TopicArn]} {
        dset args TopicArn [get $topic TopicArn]
    }
    aws_request $topic sns name [get $topic TopicName] Action $action {*}$args
}


proc delete_aws_sns_topic {aws name} {
    # Delete topic with "name".

    dset aws TopicName $name

    aws_sns $aws DeleteTopic Name $name TopicArn [aws_sns_arn $aws $name]
}


proc create_aws_sns_topic {aws name} {
    # Create topic with "name".

    dset aws TopicName $name

    set result [aws_sns $aws CreateTopic Name $name]
    dict replace $aws TopicArn [get $result CreateTopicResult TopicArn]
}


proc aws_sns_topic {aws name} {
    # Lookup topic with "name".

    dict replace $aws TopicName $name TopicArn [aws_sns_arn $aws $name]
}


proc aws_sns_subscribe_sqs {sns sqs {option {}}} {
    # Subscribe "sqs" to "topic".

    if {[llength $sqs] == 1} {
        set sqs [aws_sqs_queue $sns $sqs]
    }

    set result [aws_sns $sns Subscribe Endpoint [aws_sqs_arn $sqs] Protocol sqs]
    set sub [get $result SubscribeResult SubscriptionArn]
    if {$option eq "-raw"} {
        aws_sns $sns SetSubscriptionAttributes \
                     SubscriptionArn $sub \
                     AttributeName RawMessageDelivery \
                     AttributeValue true
    }

    return $result
}


proc aws_sns_subscribe_email {sns email} {
    # Subscribe "email" to "topic".

    aws_sns $sns Subscribe Endpoint $email Protocol email
}


proc aws_sns_publish {sns message {subject {}}} {
    # Publish "message" to "sns".

    if {$subject != {}} {
        aws_sns $sns Publish Message $message Subject [range $subject 0 99]
    } else {
        aws_sns $sns Publish Message $message
    }
}



#-------------------------------------------------------------------------------
# Javascript Utilities.
#-------------------------------------------------------------------------------


proc js_function {name parameters body} {

    append ::js_procs "function $name ([join $parameters ,]) {$body}\n\n"
}


js_function aws_sqs_send {queue_name message} {

    sqs.getQueueUrl({QueueName: queue_name},
        function(err, url) {
            if (!err) {
                sqs.sendMessage({MessageBody: message, QueueUrl: url.QueueUrl},
                    function(err, data) {
                        if (err) {
                            window.alert(err.code + ': ' + err.message);
                        } else {
                            console.log(data);
                        }
                    });
            } else {
                console.log(err);
                if (err.code == 'ExpiredToken') {
                    window.alert('The Security Token has expired.'
                               + 'Please re-load the page and try again');
                } else {
                    window.alert(err.code + ': ' + err.message);
                }
            }
        });
}


js_function aws_ec2_start {ec2_name} {

    var params = {
      Filters: [
        {Name: 'resource-type', Values: ['instance']},
        {Name: 'key', Values: ['Name']},
        {Name: 'value', Values: [ec2_name]}
      ]
    };
    ec2.describeTags(params, function(err, data) {

        if (err) console.log(err, err.stack);
        else     console.log(data);

        var params = { InstanceIds: [ data.Tags.ResourceId ] };
        ec2.startInstances(params, function(err, data) {});
    });
}


proc aws_javascript_sdk_init {token region} {

    set result [subst {
        <script src="https://sdk.amazonaws.com/js/aws-sdk-2.0.0-rc10.min.js">
        </script>
        <script type="text/javascript">
            AWS.config.update({
                accessKeyId:     '[get $token AWSAccessKeyId]',
                secretAccessKey: '[get $token AWSSecretKey]',
                sessionToken:    '[get $token AWSToken]',
                region:          '[aws_region_id $region]'
            });

            var sqs = new AWS.SQS();
//            var ec2 = new AWS.EC2();

    }]
    append result $::js_procs
    append result </script>
    return $result
}



#-------------------------------------------------------------------------------
# HTTP Request Utilities.
#-------------------------------------------------------------------------------


http::register https 443 tls::socket


proc aws4_request_headers {aws args} {

    Create AWS Signature Version 4 Authentication Headers.

    http://docs.aws.amazon.com/general/latest/gr/signature-version-4.html

} do {

    # Extract arguments...
    assign $args service region method headers url body
    assign [uri::split $url] host path query

    # Curent date/time strings...
    set now [expr {[exists $args now] ? [get $args now] : [clock seconds]}]
    set date [aws_iso8601_date $now]
    set datetime [aws_iso8601_basic $now]

    # Authentication scope string...
    set scope $date/[aws_region_id $region]/$service/aws4_request

    # Generate signing key based on scope string...
    set signing_key AWS4[get $aws AWSSecretKey]
    for element in [split $scope /] {
        set signing_key [sha2::hmac -bin -key $signing_key $element]
    }

    # Compute hash of body...
    set body_hash [sha2::sha256 -hex $body]
    set body_length [length $body]

    # Set HTTP headers...
    lappend headers x-amz-content-sha256 $body_hash \
                    x-amz-date           $datetime \
                    host                 $host \
                    Content-MD5          [md5 $body base64]
    if {[exists $aws AWSToken]} {
        dset headers x-amz-security-token [get $aws AWSToken]
    }

    # Sort and "tolower" Headers...
    set signed_headers {}
    set canon_headers {}
    for key in [keys $headers] {
        lappend canon_headers [tolower $key]:[trim [get $headers $key]]
        lappend sig_headers [tolower $key]
    }
    set canon_headers [join [lsort $canon_headers] \n]\n
    set sig_headers [join [lsort $sig_headers] {;}]

    # Sort Query String...
    set query [parse qstring $query]
    set canon_query {}
    for key in [lsort [keys $query]] {
        lappend canon_query $key [get $query $key]
    }
    set canon_query [qstring $canon_query]

    # Create canonical request...
    set canonical_form \
        $method\n/$path\n$canon_query\n$canon_headers\n$sig_headers\n$body_hash

    # Create String to Sign...
    set canonical_hash [sha2::sha256 -hex $canonical_form]
    set string AWS4-HMAC-SHA256\n$datetime\n$scope\n$canonical_hash
    set signature [sha2::hmac -hex -key $signing_key $string]

    # Assemble Authorization header...
    set auth [join [list AWS4-HMAC-SHA256 \
                         Credential=[get $aws AWSAccessKeyId]/$scope, \
                         SignedHeaders=$sig_headers, \
                         Signature=$signature]]

    dset headers Authorization $auth

    #puts "Canonical request:\n$canonical_form"
    #puts "String to sign:\n$string"
    #puts "Headers:\n$headers"

    return $headers
}


proc aws2_request_query {aws args} {

    Create AWS Signature Version 2 Authentication query parameters.

    http://docs.aws.amazon.com/general/latest/gr/signature-version-2.html

} do {

    assign $args url query
    assign [uri::split $url] host path

    set common [subst {
        AWSAccessKeyId    [get $aws AWSAccessKeyId]
        Expires           [aws_iso8601 [expr {[clock seconds] + 120}]]
        SignatureVersion  2
        SignatureMethod   HmacSHA256
    }]
    if {[exists $aws AWSToken]} {
        dset common SecurityToken [get $aws AWSToken]
    }
    set query [merge $common $query]

    foreach key [lsort [keys $query]] {
        dset sorted $key [get $query $key]
    }
    set query $sorted

    set digest "POST\n$host\n/$path\n[qstring $query]"
    dset query Signature [sign_aws_string $aws sha2 $digest]

    return $query
}


proc sign_aws_string {aws sha string} {

    Sign "string" using AWSSecretKey.

} do {

    set key [get $aws AWSSecretKey]
    : [::${sha}::hmac $key $string] | parse hex | base64 | trim
}


proc aws_iso8601 {seconds} {

    ISO8601 Zulu (GMT) time string.

} example {

    [aws_iso8601 3723] eq "1970-01-01T01:02:03Z"

} do {

    clock format $seconds -gmt 1 -format "%Y-%m-%dT%H:%M:%SZ"
}


proc aws_iso8601_date {seconds} {

    ISO8601 Zulu (GMT) date string.

} example {

    [aws_iso8601_date 0] eq "19700101"

} do {

    clock format $seconds -gmt 1 -format "%Y%m%d"
}


proc aws_iso8601_basic {seconds} {

    ISO8601 "Basic" Zulu (GMT) time string.

} example {

    [aws_iso8601_basic 3723] eq "19700101T010203Z"

} do  {

    clock format $seconds -gmt 1 -format "%Y%m%dT%H%M%SZ"
}


proc aws_http_date_now {} {

    Current time in HTTP Date format.

} do {

    clock format [clock seconds] -gmt 1 -format "%a, %e %b %Y %H:%M:%S GMT"
}


proc aws_http_pretty {http_dict} {
    # Pretty-print "http_dict" for debug.

    set result "[get $http_dict -method] [get $http_dict url]\n"
    if {[get $http_dict -method] != "PUT"
    && [exists $http_dict -query]} {
        if {[catch {parse json [lindex [get $http_dict -query] 0]}]
        && ![catch {set query [parse qstring [get $http_dict -query]]}]} {
            for {n v} in $query {
                set ignore 0
                foreach pattern {
                    ^Expires ^Attribute.Value ^Version
                    ^PolicyDocument ^UserData ^AssumeRolePolicyDocument
                } {
                    if {[regexp $pattern $n]} {
                        set ignore 1
                    }
                }
                if {!$ignore} {
                    append result "     $n $v\n"
                }
            }
        } else {
            puts [get $http_dict -query]
        }
    }
#    if {[get $http_dict -method] == "POST"
#    && [exists $http_dict -headers]} {
#        puts [rfc_2822 [get $http_dict -headers]]
#    }
    return $result
}


proc aws_http_attempt {url args} {
    # Try a few times to access "url".
    # Called by aws_rest and aws_request.

    foreach attempt {50 500 5000 giveup} {

        try {

            if {[exists ::oc_aws_verbose]} {
                catch {puts stderr "[get [info frame -5] proc]"}
                puts stderr "[aws_http_pretty [dict replace $args url $url]]"
#                if {[exists $args -headers]} {
#                    puts "headers: [get $args -headers]"
#                }
            }

            # Try HTTP request...
            set http [http::geturl $url {*}$args]

            set code [http::ncode $http]
            set status [http::status $http]

            # Temporary redirect...
            if {$code in {301 302 307}} {
                set url [get [http::meta $http] Location]
                return [aws_http_attempt $url {*}$args]
            }

            set result [array get $http]

            # Don't retry on 2xx success, 3xx redirect or 4xx client error...
            if {$status eq "ok"
            &&  ($code >= 200 && $code < 500)} {
                break
            }

            puts "$status: HTTP $code\n[aws_http_pretty $result]"

        } on error {result info} {
            if {$attempt eq "giveup"} {
                return -options $info $result
            } else {
                puts $result
            }
        } finally {
            if {[exists http]} {
                http::cleanup $http
            }
        }

        if {$attempt != "giveup"} {
            puts Waiting...
            after $attempt
        }
    }

    if {$status != "ok" || $code ni {200 206 204}} {
        set code "HTTP $code"
        catch {
            set body_dict [aws_xml_dict [get $result body]]
            foreach key {
                {Error Code}
                {ErrorResponse Error Code}
                {Response Errors Error Code}
            } {
                if {[exists $body_dict {*}$key]} {
                    set code [get $body_dict {*}$key]
                }
            }
        }
        catch {
            : $result {
               | get body |
               | parse json
               | get __type
               | split #
               | lassign domain code
            }
        }
        return -code error \
               -errorcode $code \
               "$code\n[aws_http_pretty $result]\n[get $result body]"
    }

    return $result
}


proc aws_attempt {command aws args} {

    Attempt to execute "command", passing "aws" and "args"...
    (Called by aws_rest, and aws_request)

    If "aws" contains no access key, use the EC2 Instance Profile credentials
    issued by EC2. If the cached copy of the Instance Profile credentials has
    expired get fresh credentials, then try again...

    http://docs.aws.amazon.com/IAM/latest/UserGuide/instance-profiles.html

} do {

    retry count 3 {

        return [$command $aws {*}$args]

    } trap {TCL LOOKUP DICT AWSAccessKeyId} {} {

        set aws [get_aws_ec2_instance_credentials $aws]

    } trap ExpiredToken {message info} {

        if {![exists ::oc_aws_ec2_instance_credentials]} {
            return -options $info $message
        }

        puts "Refreshing EC2 Instance Credentials..."
        set aws [get_aws_ec2_instance_credentials $aws -force-refresh]
    }
}


proc aws_rest {aws verb {bucket {}} args} {

    aws_attempt aws_rest_attempt $aws $verb $bucket {*}$args
}


proc aws_rest_attempt {aws verb bucket args} {

    S3 REST request.

} require {

    not_empty [dict get $aws AWSAccessKeyId]

} do {

    dpop args path
    dpop args query
    dpop args Content

    # Look up endpoint URL...
    set url [aws_s3_endpoint $bucket]$path

    # Append query string to URL...
    if {$query ne {}} {
        append url ?[expr {[llength $query] > 1 ? [qstring $query] : $query}]
    }

    # Prepare AWS Authentication Headers...
    set headers [aws4_request_headers $aws service s3 \
                                           region  [aws_bucket_region $bucket] \
                                           method  $verb \
                                           headers $args \
                                           url     $url \
                                           body    $Content]


    # Make HTTP request...
    set response [aws_http_attempt $url -headers $headers \
                                        -method $verb \
                                        -query $Content \
                                        -timeout [expr {30 * 60 * 1000}]]

    # Extract result...
    if {[get $args Range] eq "bytes=0-0"} {
        return [get $response meta]
    } else {
        return [get $response body]
    }
}


proc aws_request {aws service args} {

    aws_attempt aws_request_attempt $aws $service {*}$args
}


proc aws_request_attempt {aws service args} {

     AWS request for "url".

} require {

    not_empty [dict get $aws AWSAccessKeyId]

} do {

    dpop args name
    dpop args path

    # Look up endpoint URL...
    set url [aws_endpoint $service $name]$path

    set headers {
        Content-Type "application/x-www-form-urlencoded; charset=utf-8"
    }

    # Prepare AWS Authentication headers...
    if {$service eq "sdb"} {
        set args [aws2_request_query $aws url $url query $args]
    } else {
        set headers [aws4_request_headers $aws service $service \
                                               region  [aws_path_region $name] \
                                               method  POST \
                                               headers $headers \
                                               url     $url \
                                               body    [qstring $args]]
    }

    # Send HTTP request...
    set response [aws_http_attempt $url -method POST \
                                        -headers $headers \
                                        -query [qstring $args] \
                                        -timeout [expr {60 * 1000}]]

    if {[get $response body] eq {}} {
        error "$url response empty!"
    }

    # Find [Action]Response tag...
    : $response | get body | aws_xml_dict | get [get $args Action]Response
}


proc aws_xml_dict {xml} {
    # Dict representation of "xml" response.

    proc walk {node} {
        if {[$node nodeType] eq "ELEMENT_NODE"} {
            set children {}
            foreach n [$node childNodes] {
                lappend children {*}[walk $n]
            }
            if {[llength $children] == 1} {
                return [list [$node nodeName] [lindex $children 0]]
            } else {
                return [list [$node nodeName] $children]
            }
        } else {
            return [list [$node nodeValue]]
        }
    }

    walk [[dom parse -simple $xml] documentElement]
}



#===============================================================================
# Ensemble commands
#===============================================================================

package require oclib::oc_ensemble

# Set up "aws" ensemble command...
namespace eval oc::aws {namespace ensemble create}
namespace eval oc {namespace export aws}
for cmd in {arn region_id endpoint} {
    extend_proc oc::aws $cmd aws_$cmd
}
extend_proc oc::aws region_for_path aws_path_region


# Set up service ensemble commands...
for {cmd subcmds} in {
    iam {
        role_arn
        {create_role create_aws_iam_role}
        {put_role_policy put_aws_iam_role_policy}
    }
    sts {
        {assume_role assume_aws_sts_role}
    }
    s3 {
        arn
        bucket_list
        key_dicts
        key_list
        put
        get
        get_meta
        get_dict
        delete
        exists
        copy
        {create_bucket create_aws_s3_bucket}
    }
    ec2 {
        instance_list
        state
        start
        stop
        reboot
        terminate
        is_stopped
        is_running
        {create create_aws_ec2}
        {wait wait_for_aws_ec2}
    }
    sqs {
        arn
        attributes
        send
        receive
        queue
        delete
        flush
        send_batch
        count
        busy_count
        {create create_aws_sqs_queue}
        {delete_queue delete_aws_sqs_queue}
        {poll poll_aws_sqs_queue}
    }
    ses {
        send_attachment
    }
    sns {arn arn_prefix}
    sdb {
        {create aws_sdb_create_domain}
        put
        batch_put
        {delete_item delete_aws_sdb_item}
    }
} {
    namespace eval oc::aws::$cmd {namespace ensemble create}
    namespace eval oc::aws [list namespace export $cmd]
    for sub in $subcmds {
        if {[llength $sub] == 2} {
            lassign $sub sub target
        } else {
            set target aws_${cmd}_$sub
        }
        extend_proc oc::aws::$cmd $sub $target
    }
}



#===============================================================================
# End of file.
#===============================================================================
