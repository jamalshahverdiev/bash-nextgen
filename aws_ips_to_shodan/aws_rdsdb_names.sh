#!/usr/bin/env bash

if [[ $# -lt 1 ]]
then
    echo "Usage: ./$(basename $0) environment_name(prod/staging) project_name"
    exit 89
fi

. ./libs/functions.sh
. ./libs/small_variables.sh
error_outputs_of_script
aws_db_json_object=$(aws rds describe-db-instances | jq '.DBInstances[]')
aws_db_names=$(echo ${aws_db_json_object} | jq -r '.DBInstanceIdentifier')
env_name=$1
project_name=$2
check_prj_name_not_empty "${project_name}"

for aws_db_name in $aws_db_names
do
    db_name=$(echo ${aws_db_name} | sed 's/-/_/g')
    alert_name="${project_name}_${env_name}_rds_${db_name}"
    db_dns_endpoint=$(echo ${aws_db_json_object} | jq -r 'select(.DBInstanceIdentifier=="'${aws_db_name}'")|.Endpoint.Address')
    echo '*************************************************************************************************************'
    echo "DB_Name: ${db_name}"
    echo "DB_DNS_Name: ${db_dns_endpoint}"
    ips=$(get_ips_by_name "${db_dns_endpoint}")
    listed_ips=$(prepare_ip_struct "${ips}")
    execute_shodan_api
done

