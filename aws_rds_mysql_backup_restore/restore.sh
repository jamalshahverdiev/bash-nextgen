#!/bin/bash
# Script for restore of off-site backup to RDS instance
# download tar -> decrypt symmetric key -> decrypt *.sql.bz2.gpg  -> restore to new RDS Instance

# Prerequisites:
# Ubuntu Linux
# Setup ssh access to $BACKUP_DESTINATIONS
# Private key that was used for creating backup

# Example:
# bash -ex restore.sh -k /home/test-backup/db-backup-v2/project-staging-offsitedb.key -l rds-production@10.10.10.10:/storage/rds-staging/ \
#  -b staging-cold-2020-10-02-04-07.tar -x project-admin-staging -x project-statistics-staging -i restored-staging-cold -g sg-0cad8269 -d 25
# set -ex

# Install pre-requisites in case we're missing something
. ./libs/global-variables.sh
. ./libs/global-functions.sh
. ./libs/restore-variables.sh
. ./libs/restore-functions.sh

if [ $# -lt 1 ]; then usage; fi

get_arguments_with_parameters

log "Restoring data from ${BACKUP_FILE} to ${RDS_INSTANCE}"
# Download latest backup file if not present in current directory
get_backups_from_remote_ssh_servers

check_md5sum_state

log "Unpack to ${restore_dir} directory"
set_workdir ${restore_dir}
extract_specific_schemas_if_defined_in_variable

# It's a Trap!
trap cleanup_sensitive_data EXIT

# Decrypt symmetric key
decrypt_symmetric_key

# Decrypt files with symmetric key
decrypt_files_with_symmetric_key_and_check_md5_if_true

# Create AWS RDS instance, but fail if instance exists
create_rds_instance_if_not_exists_and_get_dns_endpoint

# Create MySQL config file and chech databases
create_mysql_cnf_and_check_databases

# Import data from SQL file
fill_database_with_data

# Collect Database needed data (Users, Schemas, Stored_procedures, Views, Tables, Select counts, ) to compare when we will restore
get_shemas_users_views_stproc_counters "${restore_dir}/${RDS_INSTANCE}" "${restore_dir}/${restore_db_check_result_file_name}"
collect_schemas_with_tables "${restore_dir}/${RDS_INSTANCE}"
get_schema_tables_with_rows "${schema_names}" "${restore_dir}/${RDS_INSTANCE}" "${restore_dir}/${restore_db_check_result_file_name}"
compare_src_dst_files_statistics "${restore_dir}/${db_check_result_file_name}" "${restore_dir}/${restore_db_check_result_file_name}"
production_datas_is_valid "${restore_dir}/${RDS_INSTANCE}"

# Check MySQL error log file
mysqldump_error_log_is_empty ${SQL_RESTORE_ERROR}

# Clean all created files .tar, .md5, .cnf, .sql.bz2 and .cnf files
cleanup
