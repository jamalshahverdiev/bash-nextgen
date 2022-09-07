#!/usr/bin/env bash

# Get all metric names inside of AWS/ApplicationELB namespace
# aws cloudwatch list-metrics --namespace AWS/ApplicationELB | jq -r '.Metrics[].MetricName' | grep -i target | sort -n | uniq -c

prepare_dimensions(){
    namespace_input=$1
    namespace_dimensions_value=$2
    if [[ ${namespace_input} == 'NATGateway' ]]; then
        dimensions_command=" --dimensions Name=NatGatewayId,Value=${namespace_dimensions_value} "
    elif [[ ${namespace_input} == 'SQS' ]]; then
        dimensions_command=" --dimensions Name=QueueName,Value=${namespace_dimensions_value} "
    elif [[ ${namespace_input} == 'ElastiCache' ]]; then
        dimensions_command=" --dimensions Name=CacheClusterId,Value=${namespace_dimensions_value} "
    elif [[ ${namespace_input} == 'RDS' ]]; then
        dimensions_command=" --dimensions Name=DBInstanceIdentifier,Value=${namespace_dimensions_value} "
    elif [[ ${namespace_input} == 'OpsWorks' ]]; then
        dimensions_command=" --dimensions Name=StackId,Value=${namespace_dimensions_value} "
    elif [[ ${namespace_input} == 'ELB' || ${namespace_input} == 'ApplicationELB' ]]; then
        dimensions_command=" --dimensions Name=LoadBalancerName,Value=${namespace_dimensions_value} "
    elif [[ ${namespace_input} == 'ES' && ! -z ${CLIENT_ID} ]]; then
        dimensions_command=" --dimensions Name=DomainName,Value=${namespace_dimensions_value} Name=ClientId,Value=${CLIENT_ID} "
    elif [[ ${namespace_input} == 'EC2' ]]; then
        dimensions_command=" --dimensions Name=InstanceId,Value=${namespace_dimensions_value} "
    fi
}

prepare_unit_command(){
    unit_input=$1
    if [ -z ${unit_input} ]; then 
        unit_command=''
    else 
        unit_command=" --unit ${unit_input} "
    fi
}

prepare_tread_missing_data_command(){
    treat_missing_data=$1
    if [ -z ${treat_missing_data} ]; then
        thread_missing_data_command=''
    else
        thread_missing_data_command=" --treat-missing-data $treat_missing_data "
    fi 
}

validate_tread_unit_arguments(){
    if [ ! -z ${treat_missing_data_input} ]; then
        if [[ ${treat_missing_data_input} == 'notBreaching' || ${treat_missing_data_input} == 'breaching' || ${treat_missing_data_input} == 'ignore' || ${treat_missing_data_input} == 'missing' ]]; then
            prepare_tread_missing_data_command ${treat_missing_data_input}
        fi
    fi
    if [ ! -z ${unit_input} ]; then
        if [[ ${unit_input} == 'Bytes' || ${unit_input} == 'Seconds' || ${unit_input} == 'Count' || ${unit_input} == 'Percent' ]]; then
            prepare_unit_command ${unit_input}
        fi
    fi
}

prepare_alarm_full_command(){
    name_and_description="${namespace_input}_${object_name_input_to_create}_${metric_name_input}"
    prepare_dimensions ${namespace_input} ${object_name_input_to_create}
    validate_tread_unit_arguments
    full_alarm_command=$(echo --alarm-name ${name_and_description} \
                --alarm-description ${name_and_description} \
                --namespace "AWS/${namespace_input}" $dimensions_command \
                --statistic "${statistic_input}" \
                --metric-name "${metric_name_input}" \
                --comparison-operator "${comparison_operator_input}" ${unit_command} \
                --threshold ${threshold_input} \
                --period ${period_input} \
                --datapoints-to-alarm ${datapoints_to_alarm_input} \
                --evaluation-periods ${evaluation_periods_input} ${thread_missing_data_command} \
                --alarm-actions "${sns_arn_to_alarm}" \
                --ok-actions "${sns_arn_to_alarm}" \
                --actions-enabled)
}

create_alarm_by_object() {
    object_name_input_to_create=${1}
    namespace_input=${2}
    statistic_input=${3}
    metric_name_input=${4}
    comparison_operator_input=${5}
    threshold_input=${6}
    period_input=${7}
    datapoints_to_alarm_input=${8}
    evaluation_periods_input=${9}
    sns_arn_to_alarm=${10}
    treat_missing_data_input=${11}
    unit_input=${12}
    prepare_alarm_full_command 
    aws cloudwatch put-metric-alarm ${full_alarm_command}
}

clean_alarms_from_aws() {
    namespace=$1
    aws_object_name=$2
    if [ $CLEAN_ALARMS == 'true' ]; then
        selected_alarms_object=$(echo $get_alarm_objects | jq -r 'select(.Namespace=="AWS/'${namespace}'")')
        selected_alarm_names=$(echo $selected_alarms_object | jq -r '.AlarmName')
        
        for selected_alarm_name in ${selected_alarm_names}; do 
            if [[ $selected_alarm_name =~ "${aws_object_name}" ]]; then
                aws cloudwatch delete-alarms --alarm-names "${selected_alarm_name}" && echo "Deleted alarm name: ${selected_alarm_name}" 
            fi            
        done   
    fi
}

usage() {
    echo "ERROR: Argument mismatch."
    echo "Usage: $0 -a ARN_OF_NORMAL_ALARM_ACTION_SNS_TOPIC -u ARN_OF_URGENT_ALARM_ACTION_SNS_TOPIC"
    echo "   -a ARN_OF_NORMAL_ALARM_ACTION_SNS_TOPIC"
    echo "   -u ARN_OF_URGENT_ALARM_ACTION_SNS_TOPIC"
    echo "   -k [true/false] Keep existing alarms"
    echo "   -p AWS_PROFILE_NAME (DEFAULT=staging)"
    exit 64
}

get_arguments_with_parameters(){
    while getopts_long ':a:u:k:p: arnofnormal: arnofurgent: keepalarms: awsprofile:' OPTKEY; do
    case ${OPTKEY} in
        'a'|'arnofnormal')        ALARM_ACTION="${OPTARG}" ;;
        'u'|'arnofurgent')        URGENT_ALARM_ACTION="${OPTARG}" ;;
        'k'|'keepalarms')         CLEAN_ALARMS=${OPTARG} ;;
        'p'|'awsprofile')         AWS_PROFILE="${OPTARG}" ;;
        '?')            echo "INVALID OPTION -- ${OPTARG}"; usage >&2 ; exit 1 ;;
        ':')            echo "MISSING ARGUMENT for option -- ${OPTARG}"; usage >&2 ; exit 1 ;;
        *)              echo "Misconfigured OPTSPEC or uncaught option -- ${OPTKEY}"; usage >&2 ; exit 1 ;;
    esac
    done
}

print_variables(){
    echo "ALARM_ACTION=$1"
    echo "URGENT_ALARM_ACTION=$2"
    echo "CLEAN_ALARMS=$3"
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

