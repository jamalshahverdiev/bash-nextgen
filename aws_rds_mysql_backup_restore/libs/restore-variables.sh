#!/usr/bin/env bash

PASSWORD_FILE=""
# RESTORE_PRIVATE_KEY="/home/vagrant/ProjectApp/project-tools/db-backup-v2/id_rsa"
RESTORE_PRIVATE_KEY="~/.ssh/id_rsa"
RDS_INSTANCE="restored"
DB_PASSWORD="NMGjhdc783ryiufghJTdjksd"
SECURITY_GROUP_ID="sg-a07174c5"
# SECURITY_GROUP_ID="sg-1da1cb78"
RDS_INSTANCE_CLASS="db.m5.large"
CORE_DB_NAME='mysql'
# ALLOCATED_STORAGE_GB="200"
ALLOCATED_STORAGE_GB="1700"
STORAGE_TYPE="gp2"
RDS_OPT_GROUP="backup-mysql8"
RDS_PARAM_GROUP="backup-mysql8"
BACKUP_DESTINATION='rds-production@10.10.10.10:/storage/rds-production/'
# BACKUP_DESTINATION='rds-production@offline-backups.projectapp.net:/storage/rds-production/'
BACKUP_DESTINATION_PORT=22
CHECK_MD5=true
restore_dir='restored'
SCHEMAS_TO_RESTORE=()
SQL_RESTORE_ERROR="/tmp/sql-restore-error-$(date +%F-%H-%M)-flag"
email_list="jamal.shahverdiev@gmail.com support@projectapp.com"
phone_number_to_search='34876248782'