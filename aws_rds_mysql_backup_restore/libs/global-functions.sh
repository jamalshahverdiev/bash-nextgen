#!/usr/bin/env bash

log() {
	echo "$(date --iso-8601=seconds) $*"
}

check_needed_packages(){
    for package in zip unzip openssl aws jq mysql-client gpg2 ; do
        which ${package} || sudo apt-get install ${package} -y
    done
}

wait_rds_available() {
    RDS_INSTANCE_NAME=$1
    log "Waiting for instance ${RDS_INSTANCE_NAME} to become available: "
    DBINSTANCE_STATUS=""
    while [ "$DBINSTANCE_STATUS" != "available" ]; do
      sleep 20
      DBINSTANCE_STATUS=$(aws rds describe-db-instances --db-instance-identifier ${RDS_INSTANCE_NAME} | jq -r '.DBInstances[].DBInstanceStatus')
      echo -n "${DBINSTANCE_STATUS} ... "
    done
    sleep 20
    log "RDS instance ${RDS_INSTANCE_NAME} ready"
}

cleanup_sensitive_data() {
    log "Clean-up sensitive data"
    for clean_file in ${PASSWORD_FILE} ${BACKUP_RDS_INSTANCE}.cnf; do
        if [ -f ${clean_file} ]; then shred -fu -n1 ${clean_file}; fi 
    done 
}

setup_mysql_cnf() {
BACKUP_RDS_INSTANCE=$1
DB_PASSWORD=$2
DB_INSTANCE_ADDRESS=$(aws rds describe-db-instances --db-instance-identifier ${BACKUP_RDS_INSTANCE} | jq -r ".DBInstances[].Endpoint.Address")
cat << EOF > ${BACKUP_RDS_INSTANCE}.cnf
[client]
user = root
password = ${DB_PASSWORD}
host = ${DB_INSTANCE_ADDRESS}
max_allowed_packet=1G
EOF
}

mysqldump_error_log_is_empty(){
    PATH_TO_SQL_ERROR_FILE=$1
    if [ -s ${PATH_TO_SQL_ERROR_FILE} ]; then
        log "ERROR during mysqldump: $(cat ${PATH_TO_SQL_ERROR_FILE}) "
        log "NOTE: Investigate carefully"
        log "NOTE: remove backup files manually after investigation"
        exit 66
    fi
}

getopts_long() {
    : "${1:?Missing required parameter -- long optspec}"
    : "${2:?Missing required parameter -- variable name}"

    local optspec_short="${1%% *}-:"
    local optspec_long="${1#* }"
    local optvar="${2}"

    shift 2

    if [[ "${#}" == 0 ]]; then
        local args=()
        while [[ ${#BASH_ARGV[@]} -gt ${#args[@]} ]]; do
            local index=$(( ${#BASH_ARGV[@]} - ${#args[@]} - 1 ))
            args[${#args[@]}]="${BASH_ARGV[${index}]}"
        done
        set -- "${args[@]}"
    fi

    builtin getopts "${optspec_short}" "${optvar}" "${@}" || return 1
    [[ "${!optvar}" == '-' ]] || return 0

    printf -v "${optvar}" "%s" "${OPTARG%%=*}"

    if [[ "${optspec_long}" =~ (^|[[:space:]])${!optvar}:([[:space:]]|$) ]]; then
        OPTARG="${OPTARG#${!optvar}}"
        OPTARG="${OPTARG#=}"

        # Missing argument
        if [[ -z "${OPTARG}" ]]; then
            OPTARG="${!OPTIND}" && OPTIND=$(( OPTIND + 1 ))
            [[ -z "${OPTARG}" ]] || return 0

            if [[ "${optspec_short:0:1}" == ':' ]]; then
                OPTARG="${!optvar}" && printf -v "${optvar}" ':'
            else
                [[ "${OPTERR}" == 0 ]] || \
                    echo "${0}: option requires an argument -- ${!optvar}" >&2
                unset OPTARG && printf -v "${optvar}" '?'
            fi
        fi
    elif [[ "${optspec_long}" =~ (^|[[:space:]])${!optvar}([[:space:]]|$) ]]; then
        unset OPTARG
    else
        # Invalid option
        if [[ "${optspec_short:0:1}" == ':' ]]; then
            OPTARG="${!optvar}"
        else
            [[ "${OPTERR}" == 0 ]] || echo "${0}: illegal option -- ${!optvar}" >&2
            unset OPTARG
        fi
        printf -v "${optvar}" '?'
    fi
}

generate_rsa_keys_to_crypt_decrypt(){
    key_name=$1
    # Private key
    openssl genpkey -algorithm RSA -out ${key_name}.key -pkeyopt rsa_keygen_bits:2048
    # Public key
    openssl rsa -pubout -in ${key_name}.key -out ${key_name}.pem
}

get_shemas_users_views_stproc_counters(){
    mysql_config_file=$1
    input_file_name=$2
    count_of_users=$(mysql --defaults-extra-file=${mysql_config_file}.cnf -NBe 'select user from mysql.user;' | wc -l)
    count_of_schemas=$(mysql --defaults-extra-file=${mysql_config_file}.cnf -NBe 'show schemas;' | egrep -v "innodb|mysql|information_schema|performance_schema|sys|tmp" | wc -w)
    count_of_stored_procedures=$(mysql --defaults-extra-file=${mysql_config_file}.cnf -NBe 'SHOW PROCEDURE STATUS;' | egrep -v "^sys|^mysql" | wc -l)
    count_of_views=$(mysql --defaults-extra-file=${mysql_config_file}.cnf -NBe "SELECT TABLE_SCHEMA, TABLE_NAME FROM information_schema.tables WHERE TABLE_TYPE LIKE 'VIEW';"  | egrep -v '^sys' | wc -l)
    echo '==============================================================================' 
    echo "count_of_all_schemas: ${count_of_schemas}" | tee -a ${input_file_name} 
    echo "count_of_all_views: ${count_of_views}" | tee -a ${input_file_name}
    echo "count_of_all_stored_procedures: ${count_of_stored_procedures}" | tee -a ${input_file_name}
    echo "count_of_all_users: ${count_of_users}" | tee -a ${input_file_name}
}

collect_schemas_with_tables(){
    mysql_config_file=$1
    all_schema_names=$(mysql --defaults-extra-file=${mysql_config_file}.cnf -NBe 'show schemas;' | egrep -v "innodb|mysql|information_schema|performance_schema|sys|tmp")

    while read -r schema; do
        all_tables=$(mysql --defaults-extra-file=${mysql_config_file}.cnf -NBe "use ${schema}; show tables;")
        while read -r table_name; do
            if [[ ! -v schema_names[${schema}] ]]; then
                schema_names+=([${schema}]=${schema_names[${schema}]='"'${table_name}'"'})
            else
                schema_names+=([${schema}]=$(echo ${schema_names[${schema}]}, '"'${table_name}'"'))
            fi
        done <<< "${all_tables}"
    done <<< "${all_schema_names}"
}

get_smpp_dynamic_table_names(){
    smpp_schema=$1
    smpp_tables=$(mysql --defaults-extra-file=${mysql_config_file}.cnf -NBe "use ${smpp_schema}; show tables;" | egrep "${smpp_schema^^}_INC|${smpp_schema^^}_OUT")
    while read -r smpp_table_name; do
        if [[ ! -v srch_table_cnt_in_schms[${smpp_schema}] ]]; then
            srch_table_cnt_in_schms+=([${smpp_schema}]=${srch_table_cnt_in_schms[${smpp_schema}]=${smpp_table_name}})
        else
            srch_table_cnt_in_schms+=([${smpp_schema}]=$(echo ${srch_table_cnt_in_schms[${smpp_schema}]} ${smpp_table_name}))
        fi
    done <<< "${smpp_tables}"
}

get_schema_tables_with_rows() {
    schema_names=$1
    mysql_config_file=$2
    statistics_input_file_name=$3
    get_smpp_dynamic_table_names 'smpp'
    for schema_name in "${!schema_names[@]}"; do
        for schema_in_array in "${!srch_table_cnt_in_schms[@]}"; do
            if [[ ${schema_name} == ${schema_in_array} ]]; then
                IFS=' '
                for table_value in ${srch_table_cnt_in_schms[${schema_in_array}]}; do
                    raws_in_table=$(mysql --defaults-extra-file=${mysql_config_file}.cnf -NBe "use ${schema_name}; select count(*) from ${table_value};")
                    echo "Schema: ${schema_name} | Table: ${table_value} | RAWs: ${raws_in_table}" | tee -a ${statistics_input_file_name}
                done
                unset IFS
            fi
        done
        echo "Schema: ${schema_name} | Tables: $(echo ${schema_names[${schema_name}]} | wc -w)" | tee -a ${statistics_input_file_name}
        echo '==============================================================================' | tee -a ${statistics_input_file_name}
    done
}

compare_src_dst_files_statistics(){
    src_file=$1
    dst_file=$2
    echo
    echo "============ Compare result of 'Backup' and 'Restore' statistic counters ============" 
    sort ${src_file} ${dst_file} | uniq -u
    echo '====================================================================================='
}