#!/usr/bin/env bash

if [[ $# -lt 1 ]]
then
    echo "Usage: ./$(basename $0) environment_name(prod/staging) project_name"
    exit 89
fi

. ./libs/global-variables.sh
. ./libs/azure-variables.sh
. ./libs/azure-functions.sh
. ./libs/aws-functions.sh

error_outputs_of_script
azure_mysql_json_obj=$(az mysql server list)
azure_db_ids=$(echo ${azure_mysql_json_obj} | jq -r '.[].id')
all_mysql_domain_names=$(echo $azure_mysql_json_obj | jq -r '.[].fullyQualifiedDomainName')
env_name=$1
project_name=$2
declare -a azure_locations
check_prj_name_not_empty "${project_name}"

for azure_id in ${azure_db_ids}
do
    azure_db_dns_endpoint=$(echo ${azure_mysql_json_obj} | jq -r '.[]|select(.id=="'${azure_id}'")|.fullyQualifiedDomainName')
    azure_db_name=$(echo ${azure_mysql_json_obj} | jq -r '.[]|select(.id=="'${azure_id}'")|.name')
    azure_location=$(echo ${azure_mysql_json_obj} | jq -r '.[]|select(.id=="'${azure_id}'")|.location')
    alert_name="az_${project_name}_${env_name}_mysql_${azure_db_name}"
    
    if ! printf '%s\n' "${azure_locations[@]}" | grep -q -P "^$azure_location$"; then
        echo '*******************************************************************************************************************************'
        echo "DnsEndpoint | ${azure_db_dns_endpoint} | already Added to shodan API."
        azure_locations+=("${azure_location}")
        ips=$(get_ips_by_name "${azure_db_dns_endpoint}")
        listed_ips=$(prepare_ip_struct "${ips}")
        execute_shodan_api
    fi
done
