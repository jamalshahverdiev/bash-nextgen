#!/usr/bin/env bash

check_argument_count() {
    if [[ $# -lt 1 ]]; then
        echo "Usage: ./$(basename $0) resource_group_names_object"
        exit 89
    fi
}

get_all_types_with_values(){
    if [[ $# -lt 1 ]]; then
        echo "Usage: ./$(basename $0) public_ip_ids"
        exit 89
    fi
    public_ip_ids=$1
    
    for public_ip_id in ${public_ip_ids}
    do
        public_ip_name=$(echo $all_ip_objects_in_json | jq -r '.[]|select(.id=="'$public_ip_id'").name')
        public_ip_address=$(echo $all_ip_objects_in_json | jq -r '.[]|select(.id=="'$public_ip_id'").ipAddress')
        if [[ ${public_ip_address} != 'null' ]]; then
            ip_config_id=$(echo $all_ip_objects_in_json | jq -r '.[]|select(.id=="'$public_ip_id'").ipConfiguration.id')
            if [[ ${ip_config_id} != 'null' ]]; then
                rg_name=$(echo ${ip_config_id} | awk -F'/' '{ print $5 }')
                az_object_type=$(echo ${ip_config_id} | awk -F'/' '{ print $8 }')
                if [[ ! -v az_object_types_array[${az_object_type}] ]]; then
                    az_object_types_array+=([$az_object_type]=${az_object_types_array[$az_object_type]='"'$public_ip_address'"'})
                else
                    az_object_types_array+=([$az_object_type]=$(echo ${az_object_types_array[${az_object_type}]}, '"'${public_ip_address}'"'))
                fi
            fi
        fi
    done
}

error_outputs_of_script(){
    set -o errexit
    set -o pipefail
    #set -o nounset
}

call_shodan_api(){
    project_name=$1
    env_name=$2
    az_obj_type=$3
    echo '*******************************************************************************************************************************'
    alert_name="az_${project_name}_${env_name}_${az_obj_type}"
    listed_ips=${az_object_types_array[$az_resource_type]}
    execute_shodan_api
}