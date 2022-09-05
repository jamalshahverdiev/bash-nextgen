#!/usr/bin/env bash

check_stack_docker_parameters(){
    function_name_to_call=$1
    if [[ -z $STACK_NAME || -z $DOCKER_IMAGE_NAME || -z $DOCKER_IMAGE_TAG ]]; then
        echo "ERROR: STACK_NAME or DOCKER_IMAGE_NAME or DOCKER_IMAGE_TAG undefined"
        ${function_name_to_call}
    fi
}

install_awscli() {
  curl -s -o /tmp/awscli-bundle.zip "https://s3.amazonaws.com/aws-cli/awscli-bundle.zip"
  unzip /tmp/awscli-bundle.zip -d /tmp
  sudo rm -rf /opt/awscli /usr/local/bin/aws
  sudo python3 /tmp/awscli-bundle/install -i /opt/awscli -b /usr/local/bin/aws
  rm -rf /tmp/awscli-bundle*
}

check_needed_packages(){
    for package in jq unzip ; do which ${package} || sudo apt-get install ${package} -y; done
    which aws || install_awscli
}

check_variable_is_empty() {
    input_variable_to_search=$1
    error_message_to_print=$2
    if [ -z $input_variable_to_search ]; then
        echo "ERROR: ${error_message_to_print} ${STACK_NAME} not found"
        exit 65
    fi
}

get_stackid_stackarn_layerid_appid_stagtagalb(){
    # Get stack ID
    STACK_ID=$(aws opsworks describe-stacks | jq -r --arg STACK_NAME "$STACK_NAME" '.Stacks[]|select(.Name==$STACK_NAME)|.StackId')
    check_variable_is_empty ${STACK_ID} 'Stack' 

    # Get stack ARN
    STACK_ARN=$(aws opsworks describe-stacks --stack-ids ${STACK_ID} | jq -r '.Stacks[].Arn')
    check_variable_is_empty ${STACK_ARN} 'StackARN'

    # Get Layer ID
    LAYER_ID=$(aws opsworks describe-layers --stack-id $STACK_ID | jq -r '.Layers[0].LayerId')
    check_variable_is_empty ${LAYER_ID} 'Layer'

    # Get AppID
    APP_ID=$(aws opsworks describe-apps --stack-id $STACK_ID | jq -r '.Apps[0].AppId')
    check_variable_is_empty ${APP_ID} 'App'

    # Get Target Group ARN of ALB
    ALB_TG_ARN=$(aws opsworks list-tags  --resource-arn "${STACK_ARN}" | jq -r '.Tags.ALB_TARGET_GROUP_ARN')
#    check_variable_is_empty ${ALB_TG_ARN} 'ALB_TG_ARN'

    # Get ARN of ALB
    ALB_ARN=$(aws opsworks list-tags  --resource-arn "${STACK_ARN}" | jq -r '.Tags.ALB_ARN')
#    check_variable_is_empty ${ALB_ARN} 'ALB_ARN'
}

get_application_environment_variables(){
    # Get Apps Environment Variables
    APP_ENVIRONMENT_JSON=$(aws opsworks describe-apps --stack-id $STACK_ID | jq -r '.Apps[].Environment')
    for k in $(echo $APP_ENVIRONMENT_JSON | jq -r '. | keys | .[]')
    do
        key=$(echo $APP_ENVIRONMENT_JSON | jq -r ".[$k].Key")
        value=$(echo $APP_ENVIRONMENT_JSON | jq -r ".[$k].Value")
        if [[ "$key" != "IMAGE_NAME" && "$key" != "IMAGE_TAG" ]]; then APP_ENVIRONMENT_VARS+=("Key=$key,Value=\"$value\""); fi
    done
    echo "${APP_ENVIRONMENT_VARS[*]}"
}

get_all_healty_instances_tg_in_alb() {
    # Maybe we should verify all running instances online in ALB TG?
    running_instance_id_id_tg_alb=$(aws elbv2 describe-target-health --target-group-arn ${ALB_TG_ARN} --region "eu-west-1" | jq -r '.TargetHealthDescriptions[].Target.Id')
    for instance_id in ${running_instance_id_id_tg_alb}; do
        state_of_target_instance=$(aws elbv2 describe-target-health --target-group-arn ${ALB_TG_ARN} --region "eu-west-1" \
                                    --targets Id=${instance_id} | jq -r '.TargetHealthDescriptions[].TargetHealth.State')
        if [[ "${state_of_target_instance}" -eq 'healthy' ]]; then ONLINE_ALB_TG_INSTANCES+=(${instance_id}); fi
    done
    echo "ONLINE_ALB_INSTANCES=${ONLINE_ALB_TG_INSTANCES[*]}"
}

get_alb_name_and_tg_arn(){
    ALB_NAME=$(aws elbv2 describe-load-balancers | jq -r '.LoadBalancers[]|select(.LoadBalancerArn=="'${ALB_ARN}'")|.LoadBalancerName')
    if [ -z ${ALB_NAME} ]; then 
        echo "Script cannot find ALB_NAME by entered ALB_ARN: ${ALB_ARN}"
        exit 155
    else
        ALB_TG_ARN=$(aws elbv2 describe-target-groups --load-balancer-arn ${ALB_ARN} | jq -r '.TargetGroups[]|select(.LoadBalancerArns[]=="'${ALB_ARN}'")|.TargetGroupArn')
        if [ -z ${ALB_TG_ARN} ]; then
            echo "Cannot find right target group for the alb: ${ALB_NAME}"
            exit 156
        else
            echo "ALB_NAME: ${ALB_NAME} | ALB_TG_ARN: ${ALB_TG_ARN} | STACK_NAME: ${STACK_NAME}"
            echo "Will deploy to all instances on ALB $ALB_NAME"
        fi
    fi
}

check_container_registry_and_tag() {
    CONAINER_REGISTRY_PATH=$1
    CONTAINER_TAG=$2
    REGISTRY_ID=$3
    ECR_REPO_NAME=$(echo ${CONAINER_REGISTRY_PATH} | awk -F '/' 'BEGIN { OFS="/" } { print $2,$3}')
    container_repositories_object=$(aws ecr describe-repositories --registry-id ${REGISTRY_ID} --repository-names ${ECR_REPO_NAME})
    get_registry_uri=$(echo ${container_repositories_object} | jq . | grep "${CONAINER_REGISTRY_PATH}" | awk '{ print $2 }' | tr -d '",')
    get_registry_name=$(echo ${container_repositories_object} | jq -r '.repositories[]|select(.repositoryUri=="'${get_registry_uri}'")|.repositoryName')
    if [[ ! -z ${get_registry_uri} ]]; then
        get_tag_from_registry=$(aws ecr describe-images \
            --registry-id ${REGISTRY_ID} \
            --repository-name ${get_registry_name} | \
            jq -r '.[][]|select(.imageTags[]?=="'${CONTAINER_TAG}'")|.imageTags[]')
        if [[ ! -z ${get_tag_from_registry} ]]; then
            echo "Container registry: ${get_registry_name} | Tag: ${get_tag_from_registry} exists!"
        else
            echo "Container registry or TAG not exists!"
            exit 92
        fi        
    fi
}

getopts_long() {
    : "${1:?Missing required parameter -- long optspec}"
    : "${2:?Missing required parameter -- variable name}"

    local optspec_short="${1%% *}-:"
    local optspec_long="${1#* }"
    local optvar="${2}"

    shift 2

    if [[ "${#}" == 0 ]]; then
        local args=()
        while [[ ${#BASH_ARGV[@]} -gt ${#args[@]} ]]; do
            local index=$(( ${#BASH_ARGV[@]} - ${#args[@]} - 1 ))
            args[${#args[@]}]="${BASH_ARGV[${index}]}"
        done
        set -- "${args[@]}"
    fi

    builtin getopts "${optspec_short}" "${optvar}" "${@}" || return 1
    [[ "${!optvar}" == '-' ]] || return 0

    printf -v "${optvar}" "%s" "${OPTARG%%=*}"

    if [[ "${optspec_long}" =~ (^|[[:space:]])${!optvar}:([[:space:]]|$) ]]; then
        OPTARG="${OPTARG#${!optvar}}"
        OPTARG="${OPTARG#=}"

        # Missing argument
        if [[ -z "${OPTARG}" ]]; then
            OPTARG="${!OPTIND}" && OPTIND=$(( OPTIND + 1 ))
            [[ -z "${OPTARG}" ]] || return 0

            if [[ "${optspec_short:0:1}" == ':' ]]; then
                OPTARG="${!optvar}" && printf -v "${optvar}" ':'
            else
                [[ "${OPTERR}" == 0 ]] || \
                    echo "${0}: option requires an argument -- ${!optvar}" >&2
                unset OPTARG && printf -v "${optvar}" '?'
            fi
        fi
    elif [[ "${optspec_long}" =~ (^|[[:space:]])${!optvar}([[:space:]]|$) ]]; then
        unset OPTARG
    else
        # Invalid option
        if [[ "${optspec_short:0:1}" == ':' ]]; then
            OPTARG="${!optvar}"
        else
            [[ "${OPTERR}" == 0 ]] || echo "${0}: illegal option -- ${!optvar}" >&2
            unset OPTARG
        fi
        printf -v "${optvar}" '?'
    fi
}

