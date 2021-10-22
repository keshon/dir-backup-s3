# Backup selected directories to S3

Script reads file with directories list to backup and copy them to S3 as archives or direct copy (sync). The script is a compilation of different examples and approaches I found in internet which I adapted for my needs.


## Prerequisites
- `s3cmd` is installed and properly configured
- create `s3backups` dir in `/tmp` with 700 permissions
- edit `dirs.txt` with actual paths - each path per line.

## Examples
Minimal example:
```bash
bash dir-backup-s3.sh --m sync --s s://path-to-bucket/dir-example/
```

Complete example:
```bash
$ bash dir-backup-s3.sh \
    --mode archive \
    --webhookurl https://path-to-webhook.example \
    --range 1_week_ago \
    --s3url s://path-to-bucket/dir-example/ \
    --name MySuperServer \
    --dirs dirs.txt \
```

## Arguments
|Short name|Verbose name|Description|
|--|--|--|
|\-\-m|\-\-mode|`sync` or `archive`. Use sync to direct copy to S3 (good for heavy content), archive - make archives first then upload to S3.|
|\-\-w|\-\-webhookurl|Path to webhook URL. Useful for external integrations.|
|\-\-r|\-\-range|Use format like: `2_days_ago`,`1_week_ago` etc. How many backups are going to be made. Underscore as space.|
|\-\-s|\-\-s3url|Path to S3. Starts with `s3://` and ends with trailing `/`.|
|\-\-n|\-\-name|Name of the server. Hostname is used by default.|
|\-\-d|\-\-dirs|Path to file with directories list to backup (each path per line).|
