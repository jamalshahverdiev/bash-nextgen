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
env_name=$1
project_name=$2

check_prj_name_not_empty "${project_name}"
get_all_types_with_values "${public_ip_ids}"

for az_resource_type in "${!az_object_types_array[@]}"
do
    if [[ "${az_resource_type}" == 'virtualNetworkGateways' ]]; then
        call_shodan_api ${project_name} ${env_name} 'vpns'
    elif [[ "${az_resource_type}" == 'loadBalancers' ]]; then
        call_shodan_api ${project_name} ${env_name} 'lbs'
    elif [[ "${az_resource_type}" == 'applicationGateways' ]]; then
        call_shodan_api ${project_name} ${env_name} 'appgws'
    elif [[ "${az_resource_type}" == 'networkInterfaces' ]]; then
        call_shodan_api ${project_name} ${env_name} 'vms'
    elif [[ "${az_resource_type}" == 'azureFirewalls' ]]; then
        call_shodan_api ${project_name} ${env_name} 'firewalls'
    fi
done   
