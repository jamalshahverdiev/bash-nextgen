#!/usr/bin/env bash

usage() {
    echo "ERROR: Argument mismatch."
    echo "Usage: $0 -i RDS_INSTANCE -k BACKUP_KEY -g SECURITY_GROUP -u 'username@hostname:/dest_folder_name dest_port' [ -u 'username@hostname:/dest_folder_name dest_port' ... ] [ -t INSTANCE_CLASS]"
    echo " -i/--instance        RDS_INSTANCE                        RDS Instance to backup"
    echo " -k/--keyofbackup     BACKUP_KEY                          Public key to encrypt symmetcis key"
    echo " -g/--groupofsecurity SECURITY_GROUP                      AWS Security Group for restored RDS instance"
    echo " -u/--uploaddests     DEST_Username_Hostname_FLDR_PORT    DST Server user,IP,folder,port where will be uploaded backups"
    echo " -t/--typeofinstance  INSTANCE_CLASS                      RDS Instance type for restored DB. Default: ${INSTANCE_CLASS}"
    exit 64
}

get_arguments_with_parameters(){
    while getopts_long ':i:k:g:u:t: instance: keyofbackup: groupofsecurity: uploaddests: typeofinstance:' OPTKEY; do
        case ${OPTKEY} in
            'i'|'instance')         RDS_INSTANCE="${OPTARG}" ;;
            'k'|'keyofbackup')      BACKUP_KEY="${OPTARG}" ;;
            'g'|'groupofsecurity')  SECURITY_GROUP="${OPTARG}" ;;
            'u'|'uploaddests')      UPLOAD_DESTINATIONS+=("$OPTARG") ;;
            't'|'typeofinstance')   INSTANCE_CLASS="${OPTARG}" ;;
            '?')            echo "INVALID OPTION -- ${OPTARG}"; usage >&2 ; exit 1 ;;
            ':')            echo "MISSING ARGUMENT for option -- ${OPTARG}"; usage >&2 ; exit 1 ;;
            *)              echo "Misconfigured OPTSPEC or uncaught option -- ${OPTKEY}"; usage >&2 ; exit 1 ;;
        esac
    done
}

upload_backups_to_remote_servers(){
    md5sum ${UPLOAD_FILE} > ${UPLOAD_FILE}.md5
    for BACKUP_DESTINATION in "${UPLOAD_DESTINATIONS[@]}"
    do
        DEST=(${BACKUP_DESTINATION})
        log "Upload $UPLOAD_FILE with checksum ${UPLOAD_FILE}.md5 to ${DEST[0]} port ${DEST[1]}"
        scp -Bpq -P ${DEST[1]} -o "StrictHostKeyChecking no" ${UPLOAD_FILE} ${UPLOAD_FILE}.md5 ${DEST[0]} &
    done
    wait
}

delete_db_instance_and_sql_files(){
    log "Delete database ${BACKUP_RDS_INSTANCE} and files: $(ls ${RDS_INSTANCE}*.sql*)"
    aws rds delete-db-instance --db-instance-identifier ${BACKUP_RDS_INSTANCE} --skip-final-snapshot
    for shred_file in *.sql*; do
        if [ -f ${shred_file} ]; then shred -fu -n1 *.sql*; fi
    done
    rm -f ${SQLDUMPERROR}
}

get_rds_last_snapshot_name_to_genereate_password_file(){
    if [ -z "${SNAPSHOT_IDENTIFIER}" ]; then
        log "ERROR: No automated snapshots found for $RDS_INSTANCE , exiting."
        exit 64
    else
        TAR_FILE="$(echo ${SNAPSHOT_IDENTIFIER} | cut -d: -f2).tar"
        UPLOAD_FILE=${TAR_FILE}
        # generate password file, cut rds: from snapshot identifier
        PASSWORD_FILE="${SNAPSHOT_IDENTIFIER:4}.passfile"
        openssl rand -out ${PASSWORD_FILE} -base64 48
        # encrypt password file with public key
        openssl rsautl -encrypt -inkey ${BACKUP_KEY} -pubin -in ${PASSWORD_FILE} -out ${PASSWORD_FILE}.enc
    fi
}

archive_all_schemas_md5sum_encryptfile(){
    log "Pack all schemas.sql.bz2.gpg, shemas.sql.bz2.md5 and ${PASSWORD_FILE}.enc to ${TAR_FILE}"
    tar cvf ${TAR_FILE} ${RDS_INSTANCE}*.sql.bz2.gpg ${RDS_INSTANCE}*.sql.bz2.md5 ${PASSWORD_FILE}.enc ${db_check_result_file_name} *__procedure.sql.bz2*
}

clear_old_data_files() {
  log "Clear files older than 5 days with mask"
  find ./ -type f \( -name "*.md5" -or -name "*.enc" -or -name "*.tar" -or -name "*.bz2.gpg" \) -mtime +5 -delete
}

create_rds_instance_from_snapshot_and_modify(){
    log "Create RDS instance ${BACKUP_RDS_INSTANCE} from snapshot $SNAPSHOT_IDENTIFIER"
    aws rds restore-db-instance-from-db-snapshot --db-instance-identifier ${BACKUP_RDS_INSTANCE} \
        --db-snapshot-identifier ${SNAPSHOT_IDENTIFIER} --db-instance-class ${INSTANCE_CLASS} \
        --db-parameter-group-name ${RDS_PARAM_GROUP} --no-multi-az --tags Key=workload-type,Value=backup \
        || exit 69
    wait_rds_available ${BACKUP_RDS_INSTANCE}
    log "Disable backup, assign security group and change root password to ${DB_PASSWORD} "
    aws rds modify-db-instance --db-instance-identifier ${BACKUP_RDS_INSTANCE} --apply-immediately \
        --backup-retention-period 0 --vpc-security-group-ids ${SECURITY_GROUP} --master-user-password ${DB_PASSWORD} --db-parameter-group-name ${RDS_PARAM_GROUP}
    wait_rds_available ${BACKUP_RDS_INSTANCE}
}

is_backup_key_exists(){
    if ! [[ -r "${BACKUP_KEY}" ]]; then
        log "ERROR: ${BACKUP_KEY} is missing."
        exit 65
    fi
}

check_mysqldump_error_log_files_emty_or_not(){
    for LOGFILE in *.err.log
    do
        if [ -s ${LOGFILE} ]
        then
            log "ERROR: after mysqldump we got errorlog : $LOGFILE"
            cat ${LOGFILE}
            exit 67
        else
            rm -f ${LOGFILE}
        fi
    done
}

encrypt_bz2_files(){
    for SCHEMA_NAME_BZIP in *.bz2; do
        gpg2 --compress-algo none --cipher-algo AES256 --symmetric --batch --passphrase-file ${PASSWORD_FILE} --output ${SCHEMA_NAME_BZIP}.gpg ${SCHEMA_NAME_BZIP}
        if [ -f ${SCHEMA_NAME_BZIP} ]; then shred -fu -n1 ${SCHEMA_NAME_BZIP}; fi
    done
}

wait_for_snapshot_to_become_available(){
    log "Waiting for snapshot ${SNAPSHOT_IDENTIFIER} of ${RDS_INSTANCE} to become available: "
    while [ "$SNAPSHOT_STATUS" != "available" ]; do
        sleep 20
        SNAPSHOT_STATUS=$(aws rds describe-db-snapshots --db-snapshot-identifier ${SNAPSHOT_IDENTIFIER} | jq -r '.DBSnapshots[].Status')
        echo -n "${SNAPSHOT_STATUS} ... "
    done
    echo ""
}

check_rds_instance_listener(){
    BACKUP_RDS_INSTANCE=$1
    DB_INSTANCE_ADDRESS=$(aws rds describe-db-instances --db-instance-identifier ${BACKUP_RDS_INSTANCE} | jq -r ".DBInstances[].Endpoint.Address")
    DB_INSTANCE_PORT='3306'
    timed_out='5'
    time_after_5_minutes=$(date -d '+ 5 minutes' '+%H%M')
    state_of_listener=$(timeout ${timed_out} bash -c "cat < /dev/null > /dev/tcp/${DB_INSTANCE_ADDRESS}/${DB_INSTANCE_PORT}"; echo $?)
    while [[ ${state_of_listener} -ne 0 ]]; do
        if [[ $(date '+%H%M') -eq ${time_after_5_minutes} ]]; then 
            log "Was waiting for: ${time_after_5_minutes}" && exit 71
        else
            log "Cannot connect to the ${DB_INSTANCE_ADDRESS} and port ${DB_INSTANCE_PORT}. Waiting !!!"
            state_of_listener=$(timeout ${timed_out} bash -c "cat < /dev/null > /dev/tcp/${DB_INSTANCE_ADDRESS}/${DB_INSTANCE_PORT}"; echo $?)
        fi
    done
    log "Connected to ${DB_INSTANCE_ADDRESS} host and port ${DB_INSTANCE_PORT}. Hooray!"
}

check_shcemas_exists(){
    check_rds_instance_listener "${BACKUP_RDS_INSTANCE}"
    DATABASE_LIST=$(mysql --defaults-extra-file=${BACKUP_RDS_INSTANCE}.cnf -NBe 'show schemas' | grep -Ev "^(Database|performance_schema|information_schema|innodb|sys|tmp)$")
    if [[ -z "${DATABASE_LIST}" ]]; then log "ERROR: No schemas found in ${DB_INSTANCE_ADDRESS}" && exit 65; fi
}

get_stored_procedures(){
    for db_name in ${DATABASE_LIST}; do
        if [[ ${db_name} != 'mysql' ]]; then
            stproc_name=$(mysql --defaults-extra-file=${BACKUP_RDS_INSTANCE}.cnf -NBe "SHOW PROCEDURE STATUS WHERE Db = '${db_name}';" | awk '{ print $2 }')
            if [[ -n ${stproc_name} ]]; then
                log "Getting stored procedures of DATABASE=${db_name} from DB_INSTANCE_ADDRESS=${DB_INSTANCE_ADDRESS}"
                FILENAME="${db_name}__procedure"
                mysqldump --defaults-extra-file=${BACKUP_RDS_INSTANCE}.cnf --databases ${db_name} --no-data --no-create-db --no-create-info --routines --triggers --skip-opt --lock-tables \
                --quick --default-character-set=utf8mb4 --set-gtid-purged=OFF --log-error=${FILENAME}.sql.bz2.err.log | \
                    bzip2 > ${FILENAME}.sql.bz2 && md5sum ${FILENAME}.sql.bz2 > ${FILENAME}.sql.bz2.md5 || echo ${db_name} >> ${SQLDUMPERROR} &
            fi
        fi
    done
    wait
}

process_mysqldump_in_paralel(){
    check_shcemas_exists
    log "Dumping DATABASE_LIST=${DATABASE_LIST} from DB_INSTANCE_ADDRESS=${DB_INSTANCE_ADDRESS}"
    while read -r DATABASE; do
        if [[ ${DATABASE} == 'mysql' ]]; then
            FILENAME_USERS=${RDS_INSTANCE}.${DATABASE}_user.sql.bz2
            FILENAME_GRANTS=${RDS_INSTANCE}.${DATABASE}_grants.sql.bz2
            mysqldump --defaults-extra-file=${BACKUP_RDS_INSTANCE}.cnf --databases ${DATABASE} --tables user \
                --single-transaction --quick --default-character-set=utf8mb4 --set-gtid-purged=OFF \
                --where="user NOT LIKE 'mysql%' AND user NOT like 'rdsadmin%' AND user NOT LIKE 'root'" \
                --log-error=${FILENAME_USERS}.err.log | \
                bzip2 > ${FILENAME_USERS} && md5sum ${FILENAME_USERS} > ${FILENAME_USERS}.md5 || \
                echo ${DATABASE} >> ${SQLDUMPERROR} & 
            mysql --defaults-extra-file=${BACKUP_RDS_INSTANCE}.cnf -BNe \
            "SELECT CONCAT('\'',user,'\'@\'',host,'\'') from ${DATABASE}.user where user NOT LIKE 'mysql%' AND user NOT like 'rdsadmin%' AND user NOT LIKE 'root';" | \
            while read user_grants
            do
                echo "SHOW GRANTS FOR ${user_grants};"
            done | mysql --defaults-extra-file=${BACKUP_RDS_INSTANCE}.cnf -BN | sed -e 's/$/;/' | \
                bzip2 > ${FILENAME_GRANTS} && md5sum ${FILENAME_GRANTS} > ${FILENAME_GRANTS}.md5 || echo ${DATABASE} >> ${SQLDUMPERROR} &
        else
            FILENAME=${RDS_INSTANCE}.${DATABASE}.sql.bz2
            mysqldump --defaults-extra-file=${BACKUP_RDS_INSTANCE}.cnf --databases ${DATABASE} --single-transaction --quick --default-character-set=utf8mb4 \
            --set-gtid-purged=OFF --log-error=${FILENAME}.err.log | bzip2 > ${FILENAME} && md5sum ${FILENAME} > ${FILENAME}.md5 || \
            echo ${DATABASE} >> ${SQLDUMPERROR} &
        fi
    done <<< "${DATABASE_LIST}"
    wait
    get_stored_procedures
}