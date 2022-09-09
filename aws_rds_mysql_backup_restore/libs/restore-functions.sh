#!/usr/bin/env bash

usage() {
	echo "ERROR: Argument mismatch."
	echo "Usage: $0"
	echo "$0 [ -b backup-file ] -i instance-name -g security-group [ -o rds-option-group ] [ -p rds-params-group ]"
	echo "   [ -t rds-instance-type ] [ -s storage-type ] [ -d disk-size-gb ] "
    echo "  -k RESTORE_PRIVATE_KEY      Private Key file to decrypt symmetric key"
    echo "  -l BACKUP_DESTINATION       Remote server like as user_name@remote_ip_address:/path/of/backups/"
	echo "  -b backup-tar-filename      Name of encrypted backup tar file in remote to restore. Current: ${BACKUP_FILE}"
    echo "  -x schemas-to-restore       Schema names to restore"
	echo "  -i RDS_INSTANCE             RDS Instance to create"
	echo "  -g SECURITY_GROUP_ID        AWS Security Group for restored RDS instance Default: ${SECURITY_GROUP_ID}"
	echo "  -o RDS_OPT_GROUP            RDS Option Group for restored RDS instance. Default: ${RDS_OPT_GROUP}"
	echo "  -p RDS_PARAM_GROUP          RDS Parameters Group for restored RDS instance. Default: ${RDS_PARAM_GROUP}"
	echo "  -t RDS_INSTANCE_CLASS       RDS Instance type. Default: ${RDS_INSTANCE_CLASS}"
	echo "  -s STORAGE_TYPE             RDS Storage type: standard|gp2|io1  Default: ${STORAGE_TYPE}"
	echo "  -d ALLOCATED_STORAGE_GB     Disk Size in GB. Default: ${ALLOCATED_STORAGE_GB}"
	echo "  -n CHECK_MD5                Skip MD5 sum of files (true/false)"
	exit 64
}

get_arguments_with_parameters(){
    while getopts_long ':k:l:b:x:i:g:o:p:t:s:d:n: kprestore: bkpdst: bkpfile: schmeastorestore: rdsinstance: secgrpid: rdsoptgrp: rdsparamgrp: rdsinstclass: strgtype: allocstrggb: checkmd5:' OPTKEY; do
    case ${OPTKEY} in
        'k'|'kprestore')          RESTORE_PRIVATE_KEY="${OPTARG}" ;;
        'l'|'bkpdst')             BACKUP_DESTINATION="${OPTARG}" ;;
        'b'|'bkpfile')            BACKUP_FILE="${OPTARG}" ;;
        'x'|'schmeastorestore')   SCHEMAS_TO_RESTORE+=("${OPTARG}") ;;
        'i'|'rdsinstance')        RDS_INSTANCE="${OPTARG}" ;;
        'g'|'secgrpid')           SECURITY_GROUP_ID="${OPTARG}" ;;
        'o'|'rdsoptgrp')          RDS_OPT_GROUP="${OPTARG}" ;;
        'p'|'rdsparamgrp')        RDS_PARAM_GROUP="${OPTARG}" ;;
        't'|'rdsinstclass')       RDS_INSTANCE_CLASS="${OPTARG}" ;;
        's'|'strgtype')           STORAGE_TYPE="${OPTARG}" ;;
        'd'|'allocstrggb')        ALLOCATED_STORAGE_GB="${OPTARG}" ;;
        'n'|'checkmd5')           CHECK_MD5="${OPTARG}" ;;
        '?')            echo "INVALID OPTION -- ${OPTARG}"; usage >&2 ; exit 1 ;;
        ':')            echo "MISSING ARGUMENT for option -- ${OPTARG}"; usage >&2 ; exit 1 ;;
        *)              echo "Misconfigured OPTSPEC or uncaught option -- ${OPTKEY}"; usage >&2 ; exit 1 ;;
    esac
    done
}

get_backups_from_remote_ssh_servers(){
    if ! [[ -r ${BACKUP_FILE} && -r ${BACKUP_FILE}.md5 ]]
    then
	    log "Downloading ${BACKUP_FILE} from ${BACKUP_DESTINATION}"
        scp -P ${BACKUP_DESTINATION_PORT} -Bpq -o "StrictHostKeyChecking no" ${BACKUP_DESTINATION}\{${BACKUP_FILE},${BACKUP_FILE}.md5\} ./
    fi
}

check_md5sum_state(){
    if ${CHECK_MD5}
    then
        log "Verifying MD5 of ${BACKUP_FILE}"
        if ! md5sum -c ${BACKUP_FILE}.md5
        then
            log "ERROR: MD5 mismatch in ${BACKUP_FILE}.md5"
            exit 64
        fi
    fi
}

set_workdir(){
    restore_dir=$1
    rm -rf ${restore_dir}
    mkdir -p ${restore_dir}
    pushd ${restore_dir}
}

extract_specific_schemas_if_defined_in_variable(){
    if [ ${#SCHEMAS_TO_RESTORE[@]} -eq 0 ]; then
        tar xvf ../${BACKUP_FILE}
    else
        tar -xvf ../${BACKUP_FILE} --wildcards "*.passfile.enc"
        for SCHEMA_NAME in "${SCHEMAS_TO_RESTORE[@]}"
        do
            tar -xvf ../${BACKUP_FILE} --wildcards "*.${SCHEMA_NAME}.sql.bz2.md5" --wildcards "*.${SCHEMA_NAME}.sql.bz2.gpg"
        done
    fi
}

decrypt_symmetric_key(){
    PASSWORD_FILE_ENC=$(find . -name "*.passfile.enc" -exec readlink -f {} \;)
    PASSWORD_FILE=${PASSWORD_FILE_ENC%.*}
    openssl rsautl -decrypt -inkey ${RESTORE_PRIVATE_KEY} -in ${PASSWORD_FILE_ENC} -out ${PASSWORD_FILE}
}

decrypt_files_with_symmetric_key_and_check_md5_if_true(){
    for GPG_FILE in *.sql.bz2.gpg; do gpg2 --batch --passphrase-file ${PASSWORD_FILE} -d -o ${GPG_FILE%.*} ${GPG_FILE} ; done
    if ${CHECK_MD5}; then md5sum -c *.md5 || { log "ERROR: MD5 mismatch" ; exit 71; }; fi
}

create_rds_instance_if_not_exists_and_get_dns_endpoint(){
    aws rds describe-db-instances --db-instance-identifier ${RDS_INSTANCE} 2> /dev/null && { log "ERROR: RDS Instance already exists"; exit 72; }
    log "Creating instance ${RDS_INSTANCE} using instance type ${RDS_INSTANCE_CLASS} and disk size ${ALLOCATED_STORAGE_GB} GB of ${STORAGE_TYPE} volume"
    aws rds create-db-instance --db-instance-identifier ${RDS_INSTANCE} --db-instance-class ${RDS_INSTANCE_CLASS} --engine MySQL --engine-version "8.0"  \
        --vpc-security-group-ids ${SECURITY_GROUP_ID} --option-group ${RDS_OPT_GROUP} --db-parameter-group-name ${RDS_PARAM_GROUP} --master-username root --master-user-password "${DB_PASSWORD}" \
        --storage-encrypted --allocated-storage ${ALLOCATED_STORAGE_GB} --storage-type ${STORAGE_TYPE} --backup-retention-period 0
    wait_rds_available ${RDS_INSTANCE}
    DB_INSTANCE_ADDRESS=$(aws rds describe-db-instances --db-instance-identifier ${RDS_INSTANCE} | jq -r ".DBInstances[].Endpoint.Address")
}

create_mysql_cnf_and_check_databases(){
    DB_INSTANCE_ADDRESS=$(aws rds describe-db-instances --db-instance-identifier ${RDS_INSTANCE} | jq -r ".DBInstances[].Endpoint.Address")
    log "Show schemas in ${DB_INSTANCE_ADDRESS} RDS endpoint"
    rm -f ${SQL_RESTORE_ERROR}
    # Setup mysql credentials file
    setup_mysql_cnf ${RDS_INSTANCE} ${DB_PASSWORD}
    chmod 600 ${RDS_INSTANCE}.cnf
    mysql --defaults-extra-file=${RDS_INSTANCE}.cnf -e 'show databases;' || { log "ERROR: No connection to mysql database ${DB_INSTANCE_ADDRESS}"; exit 73; }
}

cleanup(){
    log "Removing unencrypted data"
    for clean_file in ${BACKUP_FILE} ${BACKUP_FILE}.md5 *.cnf ${restore_dir}/*.sql.bz2 ${restore_dir}/*.cnf
    do
        if [ -f ${clean_file} ]; then
            log "Cleaned ${clean_file} file"
            shred -fu -n1 ${clean_file}
        fi
    done
    if [ -d ${restore_dir} ]; then rm -rf ${restore_dir}; fi
}

restore_mysql_users(){
    for DB_ARCHIVE in *.sql.bz2; do
        set -x
        if [[ "${DB_ARCHIVE}" == *"${CORE_DB_NAME}_user"* ]]; then
            log "Importing users from ${DB_ARCHIVE}"
            user_insert=$(bunzip2 --stdout ${DB_ARCHIVE} | sed "s/rdsrepladmin/withoutrdsrepl/g" | grep -i ^INSERT) && mysql --defaults-extra-file=${RDS_INSTANCE}.cnf ${CORE_DB_NAME} -BNe "${user_insert}" >/dev/null 2>&1
            mysql --defaults-extra-file=${RDS_INSTANCE}.cnf ${CORE_DB_NAME} -BNe "FLUSH PRIVILEGES;"
        fi
        set +x
    done
    wait
}

restore_mysql_user_grants() {
    for DB_ARCHIVE in *.sql.bz2; do
        if [[ "${DB_ARCHIVE}" == *"${CORE_DB_NAME}_grants"* ]]; then
            log "Executing Grants from ${DB_ARCHIVE}"
            bunzip2 ${DB_ARCHIVE} && granted_users="$(echo ${DB_ARCHIVE} | sed 's/.bz2//g')"
            while IFS=; read -r grant_command
            do
                mysql --defaults-extra-file=${RDS_INSTANCE}.cnf ${CORE_DB_NAME} -BNe "${grant_command}" >/dev/null 2>&1
            done < "${granted_users}"
            mysql --defaults-extra-file=${RDS_INSTANCE}.cnf ${CORE_DB_NAME} -BNe "FLUSH PRIVILEGES;"
        fi
    done
    wait
}

restore_mysql_stored_procedures() {
    st_names=$(ls | grep  __procedure.sql.bz2$)
    while read -r st_name; do
        db_name=$(echo ${st_name} | awk -F '__' '{ print $1 }')
        log "Restoring Stored procedures for the DATABASE=${db_name}"
        bunzip2 --stdout ${st_name} | sed 's/DEFINER=[^ ]* / /' | mysql --defaults-extra-file=${RDS_INSTANCE}.cnf ${db_name}
    done <<< "${st_names}"
    wait
}

fill_database_with_data(){
    log "Filling ${DB_INSTANCE_ADDRESS} database with data"
    for DB_ARCHIVE in *.sql.bz2; do
        if [[ ! ${DB_ARCHIVE} =~ "procedure" ]] ; then
            if [[ ! ${DB_ARCHIVE} =~ "mysql" ]] ; then
                log "Processing ${DB_ARCHIVE}"
                bunzip2 --stdout ${DB_ARCHIVE} | sed 's/DEFINER=[^ ]* / /' | mysql --defaults-extra-file=${RDS_INSTANCE}.cnf --force 2>>${SQL_RESTORE_ERROR} &
            fi
        fi
    done
    wait
    restore_mysql_users
    restore_mysql_user_grants
    restore_mysql_stored_procedures
    log "Restored databases:"
    mysql --defaults-extra-file=${RDS_INSTANCE}.cnf -NBe 'show databases;' | grep -v "information_schema\|innodb\|mysql\|performance_schema\|sys"
    popd
}

user_table_data_check() {
    mysql_cnf_file_name=$1
    input_database_name=$2
    for email in ${email_list}; do
        select_email_result=$(mysql --defaults-extra-file=${mysql_cnf_file_name}.cnf -BNe "select EMAIL from ${input_database_name}.USER WHERE EMAIL = '${email}' LIMIT 1;")
        if [[ -n ${select_email_result} ]]; then
            echo "Found email: ${select_email_result} | in database: ${input_database_name}"
        else
            collected_errors+=("Cannot find email: ${select_email_result} | in database: ${input_database_name}")
        fi
    done
    check_number_exists_and_active=$(mysql --defaults-extra-file=${mysql_cnf_file_name}.cnf -BNe "SELECT VIRTUAL_PHONE_NUMBER_ID FROM ${input_database_name}.CATEGORY WHERE VIRTUAL_PHONE_NUMBER_ID = ${phone_number_to_search} AND NUMBER_IS_ACTIVE = true LIMIT 1;")
    if [[ -n ${select_email_result} ]]; then 
        echo "Found Virtual PN: ${check_number_exists_and_active} with active state"
    else
        collected_errors+=("Cannot find Virtual PN: ${check_number_exists_and_active} with active state")
    fi
    count_of_virtual_pn_from_main=$(mysql --defaults-extra-file=${mysql_cnf_file_name}.cnf -BNe "SELECT COUNT(*) FROM ${input_database_name}.VIRTUAL_PHONE_NUMBER LIMIT 1;")
    if [[ ${count_of_virtual_pn_from_main} -gt 200000 ]]; then
        echo "Total amount of the VIRTUAL_PHONE_NUMBER more than 200k"
    else
        collected_errors+=("Total amount of the VIRTUAL_PHONE_NUMBER less than 200k: ${count_of_virtual_pn_from_main}")
    fi
    virtual_phone_number_id_contains=$(mysql --defaults-extra-file=${mysql_cnf_file_name}.cnf -BNe "SELECT ID FROM ${input_database_name}.VIRTUAL_PHONE_NUMBER WHERE ID LIKE '${phone_number_to_search}' LIMIT 1;")
    if [[ -n ${virtual_phone_number_id_contains} ]]; then
        echo "Found Virtual Phone Number in ID field: ${virtual_phone_number_id_contains}"
    else
        collected_errors+=("Cannot find Virtual Phone Number in ID field")
    fi
    total_mount_of_users=$(mysql --defaults-extra-file=${mysql_cnf_file_name}.cnf -BNe "SELECT COUNT(*) FROM ${input_database_name}.USER LIMIT 1;")
    if [[ ${total_mount_of_users} -gt 3000000 ]]; then
        echo "Total amount of the Users more than 3 million"
    else
        collected_errors+=("Total amount of the Users less than 3 million: ${total_mount_of_users}")
    fi
}

messages_table_data_check() {
    mysql_cnf_file_name=$1
    input_database_name=$2
    total_amount_of_messages=$(mysql --defaults-extra-file=${mysql_cnf_file_name}.cnf -BNe "SELECT COUNT(*) FROM ${input_database_name}.MESSAGE;")
    if [[ ${total_amount_of_messages} -gt 20000000 ]]; then
        echo "Total amount of the Messages more than 20 million"
    else
        collected_errors+=("Total amount of the Messages less than 20 million: ${total_amount_of_messages}")
    fi
}

misc_table_data_check() {
    mysql_cnf_file_name=$1
    input_database_name=$2
    total_amount_of_call_log=$(mysql --defaults-extra-file=${mysql_cnf_file_name}.cnf -BNe "SELECT COUNT(*) from ${input_database_name}.CALL_LOG LIMIT 1;")
    if [[ ${total_amount_of_call_log} -gt 10000000 ]]; then
        echo "Total amount of the Call Logs more than 10 million"
    else
        collected_errors+=("Total amount of the Call Logs more than 10 million: ${total_amount_of_call_log}")
    fi
    phone_number_exists_in_call_log=$(mysql --defaults-extra-file=${mysql_cnf_file_name}.cnf -BNe "SELECT SECOND_PARTY_PHONE FROM ${input_database_name}.CALL_LOG WHERE SECOND_PARTY_PHONE = ${phone_number_to_search} LIMIT 1;")
    if [[ -n ${phone_number_exists_in_call_log} ]]; then 
        echo "Found Phone Number ${phone_number_exists_in_call_log} in Call Logs"
    else
        collected_errors+=("Cannot find Phone Number in Call Logs")
    fi
}

smpp_table_data_check() {
    mysql_cnf_file_name=$1
    input_database_name=$2
    smpp_incoming_outgoing_table_names=$(mysql --defaults-extra-file=${mysql_cnf_file_name}.cnf -BNe "use ${input_database_name}; show tables;" | egrep "${input_database_name^^}_INC|${input_database_name^^}_OUT")
    for table_name in ${smpp_incoming_outgoing_table_names}; do
        sms_to_phone_number=$(mysql --defaults-extra-file=${mysql_cnf_file_name}.cnf -BNe "SELECT PHONE_NUMBER FROM ${input_database_name}.${table_name} WHERE PHONE_NUMBER = ${phone_number_to_search} LIMIT 1;")
        if [[ -n ${sms_to_phone_number} ]]; then
            echo "Found Virtual PN: ${sms_to_phone_number} inside of ${table_name} table"
        else
            collected_errors+=("Cannot find Virtual PN: ${sms_to_phone_number} inside of ${table_name} table")
        fi
    done
}

production_datas_is_valid(){
    declare -a collected_errors
    path_to_mysql_config_file=$1
    if grep -q "production" <<< "${BACKUP_FILE}"; then
        user_table_data_check "${path_to_mysql_config_file}" 'main'
        messages_table_data_check "${path_to_mysql_config_file}" 'messages'
        misc_table_data_check "${path_to_mysql_config_file}" 'misc'
        smpp_table_data_check "${path_to_mysql_config_file}" 'smpp'
    fi

    if [ ${#collected_errors[@]} -eq 0 ]; then
        echo ""
    else
        echo "Oops, something went wrong..."
        for i in "${collected_errors[@]}"; do echo ${i}; done
        exit 99
    fi    
}