#!/usr/bin/env bash

if [ $# -lt 1 ]; then
    echo "Usage: ./$(basename $0) environment_name(staging/prod) project_name"
    exit 89
fi 

. ./libs/global-variables.sh
. ./libs/azure-functions.sh
. ./libs/aws-functions.sh

#error_outputs_of_script
shodan_env_name=$1
project_name=$2
check_prj_name_not_empty "${project_name}"
constructed=$(echo az_${project_name}_${shodan_env_name})
search_pattern="${constructed}_vpns|${constructed}_vms|${constructed}_appgws|${constructed}_lbs|${constructed}_firewalls|${constructed}_mysql"
filtered_shodan_alert_names=$(echo $all_alerts_json | jq -r .name | egrep ${search_pattern})

if [[ ! -z ${filtered_shodan_alert_names} ]]; then
    for filtered_alert_name in ${filtered_shodan_alert_names}
    do
        echo "DeletedAlert: ${filtered_alert_name}"
        delete_shodan_alert "${shodan_api_url}" "${shodan_api_key}" "${filtered_alert_name}"
        echo
    done
else
    echo "Not found any alerts matched to the search criteria!!!"
fi
