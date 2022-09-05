#!/bin/bash
## Author: jamal.shahverdiev@gmail.com
# Script to handle Opsworks stack deployment in blue-green approach
# Pre-requisites: NO EIP configured in Opsworks Stack

# Setup:
# export AWS_ACCESS_KEY_ID=id
# export AWS_SECRET_ACCESS_KEY=key
# Required permissions - EC2, OpsWorks

. ./libs/global-functions.sh
. ./libs/common-variables.sh
. ./libs/blue-green-functions.sh

#set -uxe
if [ $# -lt 1 ]; then blue_green_usage; fi

. ./libs/blue-green-variables.sh

get_arguments_with_parameters
check_stack_docker_parameters 'blue_green_usage'
check_needed_packages
check_container_registry_and_tag "${DOCKER_IMAGE_NAME}" "${DOCKER_IMAGE_TAG}" ${PROD_ACCOUNT_ID}
get_stackid_stackarn_layerid_appid_stagtagalb
get_subnet_ids
get_application_environment_variables
check_if_opsworks_stack_have_eips
remove_stopped_instances
get_blue_and_stack_instances

if [[ ${ALB_ARN} != 'null' ]]; then
    deploy_to_all_instances_with_alb
else
    # Check if Stack has ELB
    ELB_NAME=$(aws opsworks describe-elastic-load-balancers --stack-id $STACK_ID | jq -r '.ElasticLoadBalancers[0].ElasticLoadBalancerName')
    if [ -z $ELB_NAME ]; then
        echo "ERROR: No ELB found for $STACK_NAME, use another script for deploy"
        exit 67
    else
        deploy_to_all_instances_with_elb
    fi
fi
