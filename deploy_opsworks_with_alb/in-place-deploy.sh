#!/bin/bash
## Author: jamal.shahverdiev@gmail.com
## Script to handle in-place deployment

# set -x
. ./libs/global-functions.sh
. ./libs/common-variables.sh
. ./libs/in-place-functions.sh

if [ $# -lt 1 ]; then in_place_usage; fi

# . ./libs/in-place-variables.sh
get_arguments_with_parameters
check_stack_docker_parameters 'in_place_usage'
check_needed_packages
get_stackid_stackarn_layerid_appid_stagtagalb

# Get Apps Environment Variables
get_application_environment_variables

check_container_registry_and_tag "${DOCKER_IMAGE_NAME}" "${DOCKER_IMAGE_TAG}" ${PROD_ACCOUNT_ID}
aws opsworks update-app --app-id $APP_ID --environment Key=IMAGE_NAME,Value=$DOCKER_IMAGE_NAME Key=IMAGE_TAG,Value=$DOCKER_IMAGE_TAG "${APP_ENVIRONMENT_VARS[@]}"

if [[ ${ALB_ARN} != 'null' ]]; then
    deploy_to_all_instances_with_alb
else
    # Check if Stack has ELB
    ELBNAME=$(aws opsworks describe-elastic-load-balancers --stack-id $STACK_ID | jq -r .ElasticLoadBalancers[].ElasticLoadBalancerName)
    if [ -z $ELBNAME ]; then
        deploy_to_all_instances_without_elb
    else
        deploy_to_all_instances_with_elb
    fi
fi