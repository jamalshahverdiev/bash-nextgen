#!/usr/bin/env bash

if [[ $# -lt 1 ]]
then
    echo "Usage: ./$(basename $0) environment_name(prod/staging) project_name"
    exit 89
fi

. ./libs/functions.sh
. ./libs/small_variables.sh

elbs_json_object=$(aws elb describe-load-balancers | jq '.LoadBalancerDescriptions|.[]')
albs_json_object=$(aws elbv2 describe-load-balancers | jq '.LoadBalancers[]')
get_alb_names=$(echo ${albs_json_object} | jq -r '.LoadBalancerName')
get_elb_names=$(echo ${elbs_json_object} | jq -r '.LoadBalancerName')

error_outputs_of_script

env_name=$1
project_name=$2

check_prj_name_not_empty "${project_name}"

post_lbs_to_shodan "${get_alb_names}" "${albs_json_object}" 'alb'
post_lbs_to_shodan "${get_elb_names}" "${elbs_json_object}" 'elb'

