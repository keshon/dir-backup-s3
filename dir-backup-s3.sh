#!/bin/sh

# Hello stranger!

#--------------------------------

# Exec examples with passing params:
# Minimal:
# $ bash dir-backup-s3.sh --m sync --s s://path-to-bucket/dir-example/
#
# Complete:
# $ bash dir-backup-s3.sh \
#     --mode archive \
#     --webhookurl https://path-to-webhook.example \
#     --range 1_week_ago \
#     --s3url s://path-to-bucket/dir-example/ \
#     --name MySuperServer \
#     --dirs dirs.txt \

#--------------------------------

# Variables
## Script related
backupMode="" # 'sync' or 'archive'. Use sync to direct copy to S3 (good for heavy content), archive - make archives first then upload to S3.
webhookURL="" # 'https://webhook.example'. Path to webhook URL. Useful for external integrations.
pastRange="1 week ago" # '2 days ago','1 week ago' and so on. How many backups are going to be made.

## S3 related
pathS3="" # 's3://BucketName/ChildDirectory/'. Must have trail '/'. Path to your bucket, can be nested.

## Server related
serverName=$(hostname) # 'someServer'. Name of the server to backup. Hostname is used by default.
tempDir="/tmp/s3backups" # directory to store archives before uploading to S3. Valid if backup mode is set to 'archive'. Set 700 permission.

# Array of directories to backup - read them from dirs.txt file (each path per line)
dirFile="dirs.txt"
IFS=$'\n' read -d '' -r -a backupDirsList < ./"$dirFile"

#--------------------------------

# Functions
## Show help
function _help() 
{
cat <<EOF
$*
Usage: bash dir-backup-to-s3.sh <[options]>
Options:
    --h   --help          Show this message.
    --m   --mode          Can be: 'sync' or 'archive'. Sync is direct copy to S3. Archive - make archives first then upload to S3.
    --w   --webhookurl    Path to webhook URL. Useful for external integrations.
    --r   --range         Use format like: '2_days_ago','1_week_ago' etc. How many backups are going to be made. Underscore as space.
    --s   --s3url         Path to S3. Starts with 's3://' and ends with trailing '/'.
    --n   --name          Name of the server. Hostname is used by default.
    --d   --dirs          Path to file with directories list to backup (each path per line).
    --a   --about         About the author.

EOF
exit 1
}

## POST message to webhook
_post() {
    local step="$1"
    local title="$2"
    local message="$3"
    local backupMode="$4"
    local webhookURL="$5"
    local pastRange="$6"
    local pathS3="$7"
    local serverName="$8"
    local report="$9"
    
    curl -X POST $webhookURL\
            -H "Content-Type: application/json"\
            -d '{"step": "'$step'", "title": "'$title'", "message": "'$message'", "backup_mode":"'$backupMode'", "webhook_url": "'$webhookURL'", "past_range": "'$pastRange'", "path_s3": "'$pathS3'", "server_name":"'$serverName'", "report": "'$report'"}'
}

## Echo message to CLI
_log() {
    local title="$1"
    local message="$2"

    printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' | tr ' ' -
    echo $title
    echo -e $message
    printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' | tr ' ' -
}

## Check if dir is writable
isDirWritable() {
    local path="$1"
    if [ -w "$path" ]
    then
        echo "Found and is writable: ${path}"
    else
        echo "Can't write to (or not found): ${path}"
        exit
    fi
}

#--------------------------------

# Arguments
## Read
if ! options=$(getopt -u -o mwrsndha: -l mode:,webhookurl:,range:,s3url:,name:,dirs:,help,about -- "$@")
then
    # Something went wrong, getopt will put out an error message for us
    exit 1
fi

set -- $options

while [ $# -gt 0 ]
do
    case $1 in
    # for options with required arguments, an additional shift is required
    -m|--mode) backupMode="$2"; shift ;;
    -w|--webhookurl) webhookURL="$2"; shift ;;
    -r|--range) pastRange="$2"; shift ;;
    -s|--s3url) pathS3="$2"; shift ;;
    -n|--name) serverName="$2"; shift ;;
    -d|--dirs) dirFile="$2"; shift ;;
    -h|--help) _help ;;
    -a|--about) echo -e "\nInnokentiy Sokolov • keshon@zoho.com • https://github.com/keshon • https://keshon.ru \n2021\n"; exit 1 ;;
    (--) shift; break;;
    (-*) echo "$0: error - unrecognized option $1" 1>&2; exit 1;;
    (*) break;;
    esac
    shift
done

## Validate
### backupMode
if [ "$backupMode" == "" ]; then 
    echo "ERROR. No mode selected: use 'archive' or 'sync' only."
    exit 1
fi
if [[ ! $backupMode =~ ^(sync|archive)$ ]]; then 
    echo "ERROR. Wrong mode selected ($backupMode): use 'archive' or 'sync' only."
    exit 1
fi

### webhookURL
### TODO: add URL regex validation

### pastRange
pastRange="${pastRange//_/ }"

### pathS3
### TODO: add URL regex validation
if [[ $pathS3 == "" ]]; then
    echo "ERROR. S3 URL is invalid: specify valid URL started with 's://..'"
    exit 1 
fi

### backupDirsList
if test -f "$dirFile"; then
    IFS=$'\n' read -d '' -r -a backupDirsList < ./"$dirFile"
else
    echo "ERROR. Specified file ($dirFile) was not found."
    exit 1 
fi


#--------------------------------

echo ""
echo "Starting.."

# Inform
message="backupMode: $backupMode\nwebhookURL: $webhookURL\npastRange: $pastRange\npathS3: $pathS3\nserverName: $serverName\n"
if [[ $webhookURL != "" ]]; then
    _post "$step" "$title" "$message" "$backupMode" "$webhookURL" "$pastRange" "$pathS3" "$serverName" "$report"
else
    _log "$title" "$message"
    echo "Dirs list:"
    printf '%s\n' "${backupDirsList[@]}"
fi

# Set dates
## Only store 0 days of backups on the server.
## Changed to 0 days to not fill the server with unneccessary backups
expiry[0]=`date --date="today" +%y-%m-%d`

## Only store 1 week worth of backups on S3 
expiry[1]=`date --date="$pastRange" +%y-%m-%d`

## Using ExpiryDayOfMonth to skip first day of the month when deleting so monthly backups are kept on s3
expiryDayOfMonth=`date --date="$pastRange" +%d`

## Todays date.
todayDate=`date --date="today" +%y-%m-%d`

## Finally, setup the today specific variables.
tempCurrentDir=$tempDir/$todayDate

if [[ $backupMode == "archive" ]]; then
    # Archive dirs
    ## Check we can write to the backups directory
    isDirWritable $tempDir

    ## Make the backup directory (Also make it writable)
    echo ""
    echo "Making Directory: $tempCurrentDir"
    mkdir $tempCurrentDir
    chmod 0777 $tempCurrentDir

    ## GZip the directories and put them into the backups folder
    echo ""
    for i in "${backupDirsList[@]}"
    do
        filename=""`echo $i | tr '/' '_'`".tar.gz"
        echo "Backing up $i to $tempCurrentDir/$filename"
        tar -czpPf $tempCurrentDir/$filename $i
    done

    ## Alert that backup complete, starting sync
    title="$serverName Backup complete, starting sync $todayDate"
    message="Backup script has finished and starting sync to S3 now."

    if [[ $webhookURL != "" ]]; then
        _post "$step" "$title" "$message" "$backupMode" "$webhookURL" "$pastRange" "$pathS3" "$serverName" "$report"
    else
        _log "$title" "$message"
    fi


    # Send to S3 (put)
    echo ""
    echo "Syncing $todayDate to $pathS3$todayDate/"
    s3cmd put --recursive $tempCurrentDir $pathS3
    if [ $? -ne 0 ]; then
        subject="s3cmd put failed on $serverName"
        message="s3cmd put of $tempCurrentDir failed. You should check things out immediately."
        if [[ $webhookURL != "" ]]; then
            _post "$step" "$title" "$message" "$backupMode" "$webhookURL" "$pastRange" "$pathS3" "$serverName" "$report"
        else
            _log "$title" "$message"
        fi
    fi
    
    # Cleanup
    echo "Removing local expired backup: $tempDir/${expiry[0]}"
    rm -R $tempDir/"${expiry[0]}"

    if [ -w "$tempCurrentDir" ]; then
        echo 'Making '$tempCurrentDir' permissions 0755'
        chmod 0755 $tempCurrentDir
    fi    
fi
if [[ $backupMode == "sync" ]]; then
    # Send to S3 (sync)
    echo ""
    echo "Syncing $todayDate to $pathS3$todayDate/"
    for i in "${backupDirsList[@]}"; do
        s3cmd sync $i $pathS3$todayDate/
        if [ $? -ne 0 ]; then
            subject="s3cmd sync failed on $serverName"
            message="s3cmd sync of $tempCurrentDir failed. You should check things out immediately."
            if [[ $webhookURL != "" ]]; then
                _post "$step" "$title" "$message" "$backupMode" "$webhookURL" "$pastRange" "$pathS3" "$serverName" "$report"
            else
                _log "$title" "$message"
            fi
        fi
    done
fi


# Cleanup S3
echo ""
if [ "$expiryDayOfMonth" != "01" ]; then
    echo "Removing remote expired backup: $pathS3${expiry[1]}/"
    s3cmd del $pathS3${expiry[1]}/ --recursive
else
    echo "No need to remove backup on the 1st"
fi

subject="$serverName sync to S3 Complete - $todayDate"
message="$todayDate sync has now completed."
if [[ $webhookURL != "" ]]; then
    _post "$step" "$title" "$message" "$backupMode" "$webhookURL" "$pastRange" "$pathS3" "$serverName" "$report"
else
    _log "$title" "$message"
fi


# Report
exec 1>'/tmp/s3report.txt'
s3cmd ls $pathS3$todayDate/
exec 1>&-
exec 2>&-

subject="S3 sync report of $serverName: $todayDate"
message="Detail report is located at $tempDir/s3report.txt"
if [[ $webhookURL != "" ]]; then
    report=$(s3cmd du -H $pathS3$todayDate)
    _post "$step" "$title" "$message" "$backupMode" "$webhookURL" "$pastRange" "$pathS3" "$serverName" "$report"
else
    _log "$title" "$message"
fi

echo "Finished."
echo ""

# Bye friend!
