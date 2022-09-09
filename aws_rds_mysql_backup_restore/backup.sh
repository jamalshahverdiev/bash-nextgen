#!/bin/bash
# Script for off-site backup of RDS database
# mysql dump per schema -> bz2 -> bz2.gpg -> one tar archive for upload
#
# Prerequisites:
# Ubuntu Linux
# aws cli acces setup outsite of script
# Symmetric key is created every run and encrypted with $BACKUP_KEY
# Setup ssh access with key to $UPLOAD_DESTINATIONS
# Verify IAM role has limit for DB deletion: Key=workload-type,Value=backup
# to save production DB
# Example: ./backup.sh -i staging-hot -k ~/.ssh/id_rsa.pub -g sg-1da1cb78 -u 'rds-production@offline-backups.projectapp.net:/storage/rds-production/ 22' -u 'rds-production@10.10.10.10:/storage/rds-production/ 22' -t db.m5.large

. ./libs/global-variables.sh
. ./libs/global-functions.sh
. ./libs/backup-functions.sh

if [ $# -lt 1 ]; then usage; fi

#set -x

# Get needed arguments with parameters
get_arguments_with_parameters

. ./libs/backup-variables.sh

# Verify we have BACKUP_KEY
is_backup_key_exists

# Install pre-requisites in case we're missing something 
check_needed_packages

# Delete all files(.md5,.enc,.tar,.bz2.gpg) older than 5 days with mask
clear_old_data_files

# It's a Trap! Clean all (Password and CNF file for MySQL connection) sensitive data when script send trap EXIT.
trap cleanup_sensitive_data EXIT

# Create password file from last snapshot name
get_rds_last_snapshot_name_to_genereate_password_file

# Wait for snapshot to become available in case it's just creating
wait_for_snapshot_to_become_available

# Create new RDS from last snapshot and modify root password with defined security group
create_rds_instance_from_snapshot_and_modify

# Create MySQL CNF file
setup_mysql_cnf ${BACKUP_RDS_INSTANCE} ${DB_PASSWORD}

# Get backup of all MySQL schemas in paralel
process_mysqldump_in_paralel

## Collect Database needed data (Users, Schemas, Stored_procedures, Views, Tables, Select counts, ) to compare when we will restore
get_shemas_users_views_stproc_counters "${BACKUP_RDS_INSTANCE}" "${db_check_result_file_name}"
collect_schemas_with_tables "${BACKUP_RDS_INSTANCE}"
get_schema_tables_with_rows "${schema_names}" "${BACKUP_RDS_INSTANCE}" "${db_check_result_file_name}"

# Check temporary dump error file is not empty
mysqldump_error_log_is_empty ${SQLDUMPERROR}

# Check all MySQL dump Error log files if is not empy
check_mysqldump_error_log_files_emty_or_not

# Encrypt all files with .bz2 extension with PASSWORD_FILE from `get_rds_last_snapshot_name_to_genereate_password_file` function
encrypt_bz2_files

# Archive into one TAR file, .sql.bz2.gpg, .sql.bz2.md5 files and PASSWORD_FILE from `get_rds_last_snapshot_name_to_genereate_password_file` function
archive_all_schemas_md5sum_encryptfile

# Create checksum of TAR archive and upload to the remote SSH servers with TAR/Checksum file together
upload_backups_to_remote_servers

# Delete new created DRS instance and all files with extension .sql 
delete_db_instance_and_sql_files

log "Finished"
