#!/usr/bin/env bash

if [ $# -lt 1 ]; then
    echo "Usage: ./$(basename $0) environment_name(staging/prod) project_name"
    exit 89
fi 

. ./libs/small_variables.sh
. ./libs/functions.sh
error_outputs_of_script
shodan_env_name=$1
project_name=$2
check_prj_name_not_empty "${project_name}"
constructed=$(echo ${project_name}_${shodan_env_name})
search_pattern="${constructed}_elb_|${constructed}_alb_|${constructed}_eip_|${constructed}_rds_"
shodan_alert_names=$(echo $all_alerts_json | jq -r .name | egrep ${search_pattern})

if [[ ! -z ${shodan_alert_names} ]]; then
    for alert_name in $shodan_alert_names
    do
        echo "DeletedAlert: ${alert_name}"
        delete_shodan_alert "${shodan_api_url}" "${shodan_api_key}" "${alert_name}"
        echo
    done
else
    echo "Not found any alerts matched to the search criteria!!!"
fi
