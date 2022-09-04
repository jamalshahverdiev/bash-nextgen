#!/usr/bin/env bash

if [[ $# -lt 1 ]]
then
    echo "Usage: ./$(basename $0) environment_name(prod/staging) project_name"
    exit 89
fi

. ./libs/functions.sh
. ./libs/small_variables.sh
error_outputs_of_script
get_all_elbs_json=$(aws ec2 describe-addresses | jq '.Addresses[]')
assoc_id_names=$(echo $get_all_elbs_json | jq -r '.AssociationId')
service_names='admin smpp mms steward'
declare -a public_iparray smpp_ip_array admin_ip_array mms_ip_array steward_ip_array
env_name=$1
project_name=$2
check_prj_name_not_empty "${project_name}"

for assoc_id in $assoc_id_names
do
    if [ $assoc_id != 'null' ]
    then
        aws_ec2_public_ip=$(echo $get_all_elbs_json | jq -r 'select(.AssociationId=="'$assoc_id'")|.PublicIp') 
        eip_tag_value=$(echo $get_all_elbs_json | jq -r 'select(.AssociationId=="'$assoc_id'")|.Tags[]|select(.Key="Name")|.Value')
        for service_name in $service_names
        do
            if [[ "$eip_tag_value" == *"$service_name"* ]]
            then                
                if [[ $service_name == 'smpp' ]]; then
                    smpp_ip_array+=("${aws_ec2_public_ip}")
                elif [[ $service_name == 'admin' ]]; then
                    admin_ip_array+=("${aws_ec2_public_ip}")
                elif [[ $service_name == 'mms' ]]; then
                    mms_ip_array+=("${aws_ec2_public_ip}")
                elif [[ $service_name == 'steward' ]]; then
                    steward_ip_array+=("${aws_ec2_public_ip}")
                fi
            else
                if [[ ! " ${public_iparray[@]} " =~ " ${aws_ec2_public_ip} " ]]
                then
                    public_iparray+=("${aws_ec2_public_ip}")
                fi
            fi
        done
    fi
done

# DON'T DELETE - let's keep as template
# for obj in "$(echo ${smpp_ip_array[@]})" "$(echo ${admin_ip_array[@]})" "$(echo ${mms_ip_array[@]})" "$(echo ${steward_ip_array[@]})"
# do
#     new_object=$(echo ${obj}) && listed_ips=$(prepare_ip_struct "${new_object}")
#     echo "PublicIPs:" $listed_ips
# done

for service in ${service_names}
do
    alert_name="${project_name}_${env_name}_eip_$service"
    array_name=$service'_ip_array[@]'
    new_object=$(echo ${!array_name}) && listed_ips=$(prepare_ip_struct "${new_object}")
    execute_shodan_api
    echo '*************************************************************************************************************'
done
# echo -e "External services public IP addresses: \n" ${public_iparray[@]}
