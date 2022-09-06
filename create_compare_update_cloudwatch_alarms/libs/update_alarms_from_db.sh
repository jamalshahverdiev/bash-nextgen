#!/usr/bin/env bash

if [ $# -lt 1 ]
then
    echo Usage: ./$(basename $0) csv_file_to_update_cloudwatch_metrics_in_aws
    exit 63
fi

#### File will be used as the database of cloudwatch alarms to update in the AWS API
csv_file_name=$1

#### Load prepare_actions_command and prepare_put_commands functions
. ./libs/functions.sh

load_data_from_csv=$(cat $csv_file_name | grep -v AlarmDescription)
for line in $load_data_from_csv
do
    prepare_actions_command $line
    prepare_put_commands $line $actions_command
    aws cloudwatch put-metric-alarm $full_command
done
