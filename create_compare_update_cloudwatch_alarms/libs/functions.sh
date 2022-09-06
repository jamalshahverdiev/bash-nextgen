#!/usr/bin/env bash

#### generates CSV file as template
prepare_alarm_csv_file() {
    printf '%s\n' "$@" | paste -sd ";" >> $csv_file_name
}

#### Prepare Dimensions fields
prepare_dimensions(){
    dimensions_skeleton=$(echo $get_alarm_objects | jq -r 'select(.AlarmName=="'$alarm_name'")|.Dimensions|.[]' | tr -d '" {}' | sed 's/:/=/g;')
    if [[ -z $dimensions_skeleton ]]
    then
        dimensions='Name=Empty,Value=Empty'
    else
        dimensions=$(echo -n $dimensions_skeleton | sed 's/, /,/g;s/ /__/g')
    fi
}

#### Generate CSV fields
generate_csv_fields() {
    alarm_name=$1
    alarm_description=$(echo $get_alarm_objects | jq -r 'select(.AlarmName=="'$alarm_name'")|.AlarmDescription')
    namespace=$(echo $get_alarm_objects | jq -r 'select(.AlarmName=="'$alarm_name'")|.Namespace')
    prepare_dimensions
    statistic=$(echo $get_alarm_objects | jq -r 'select(.AlarmName=="'$alarm_name'")|.Statistic')
    metric_name=$(echo $get_alarm_objects | jq -r 'select(.AlarmName=="'$alarm_name'")|.MetricName')
    comparison_operator=$(echo $get_alarm_objects | jq -r 'select(.AlarmName=="'$alarm_name'")|.ComparisonOperator')
    threshold=$(echo $get_alarm_objects | jq -r 'select(.AlarmName=="'$alarm_name'")|.Threshold')
    period=$(echo $get_alarm_objects | jq -r 'select(.AlarmName=="'$alarm_name'")|.Period')
    datapoints_to_alarm=$(echo $get_alarm_objects | jq -r 'select(.AlarmName=="'$alarm_name'")|.DatapointsToAlarm')
    evaluation_periods=$(echo $get_alarm_objects | jq -r 'select(.AlarmName=="'$alarm_name'")|.EvaluationPeriods')
    treat_missing_data=$(echo $get_alarm_objects | jq -r 'select(.AlarmName=="'$alarm_name'")|.TreatMissingData')
    unit=$(echo $get_alarm_objects | jq -r 'select(.AlarmName=="'$alarm_name'")|.Unit')
    alarm_actions=$(echo $get_alarm_objects | jq -r 'select(.AlarmName=="'$alarm_name'")|.AlarmActions|.[]')
    ok_actions=$(echo $get_alarm_objects | jq -r 'select(.AlarmName=="'$alarm_name'")|.OKActions|.[]')
    actions_enabled=$(echo $get_alarm_objects | jq -r 'select(.AlarmName=="'$alarm_name'")|.ActionsEnabled')
}

#### Prints usage of the main script
usage () {
  echo "Usage: "
  echo "  $0 [-g/--get/, -u/--update/, -c/--check] csv_file_name"
  echo "   -g/--get    csv_file_name     Saves all alarms to the CSV file"
  echo "   -u/--update csv_file_name     Applies all changes inside of the CSV file to the AWS Cloudwatch alarms"
  echo "   -c/--check  csv_file_name     Compare AWS alarms with CSV file and prints the names of the alarms"
  exit 64
}

#### Prepare actions command from input line
prepare_actions_command() {
    line=$1
    actions_state_boolean=$(echo $line | awk -F ';' '{ print $14 }')
    if [ $actions_state_boolean = 'true' ]
    then
        actions_command='--actions-enabled'
    else
        actions_command='--no-actions-enabled'
    fi
}

##### Function to create '--unit' field
prepare_unit_command(){
    line=$1
    unit=$(echo $line | awk -F ';' '{ print $13 }')
    if [[ $unit = 'null' ]]
    then 
        unit_command=''
    else 
        unit_command=" --unit $unit "
    fi
}

##### Function to create '--treat-missing-data' field
prepare_tread_missing_data_command(){
    line=$1
    treat_missing_data=$(echo $line | awk -F ';' '{ print $12 }')
    if [[ $treat_missing_data = 'null' ]]
    then
        
        thread_missing_data_command=''
    else
        thread_missing_data_command="--treat-missing-data $treat_missing_data"
    fi 
}

#### Generates full command for aws to update cloudwatch alarms
prepare_put_commands(){
    line=$1
    actions_command=$2
    alarm_name=$(echo $line | awk -F ';' '{ print $1 }')
    alarm_description=$(echo $line | awk -F ';' '{ print $2 }')
    namespace=$(echo $line | awk -F ';' '{ print $3 }')
    dimensions=$(echo $line | awk -F ';' '{ print $4 }' | sed 's/__/ /g')
    statistic=$(echo $line | awk -F ';' '{ print $5 }')
    metric_name=$(echo $line | awk -F ';' '{ print $6 }')
    comparison_operator=$(echo $line | awk -F ';' '{ print $7 }')
    threshold=$(echo $line | awk -F ';' '{ print $8 }')
    period=$(echo $line | awk -F ';' '{ print $9 }')
    datapoints_to_alarm=$(echo $line | awk -F ';' '{ print $10 }')
    evaluation_periods=$(echo $line | awk -F ';' '{ print $11 }')
    prepare_tread_missing_data_command $line
    prepare_unit_command $line
    actions_enabled=$actions_command
    alarm_actions=$(echo $line | awk -F ';' '{ print $15 }')
    ok_actions=$(echo $line | awk -F ';' '{ print $16 }')

    full_command=$(echo --alarm-name $alarm_name \
                --alarm-description "$alarm_description" \
                --namespace "$namespace" \
                --dimensions $dimensions \
                --statistic $statistic \
                --metric-name "$metric_name" \
                --comparison-operator "$comparison_operator" \
                --threshold $threshold \
                --period $period \
                --datapoints-to-alarm $datapoints_to_alarm \
                --evaluation-periods $evaluation_periods \
                $thread_missing_data_command \
                $unit_command \
                $actions_enabled \
                --alarm-actions "$alarm_actions" \
                --ok-actions "$ok_actions")
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
