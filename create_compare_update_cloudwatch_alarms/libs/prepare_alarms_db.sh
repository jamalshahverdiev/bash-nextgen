#!/usr/bin/env bash

if [ $# -lt 1 ]
then
    echo Usage: ./$(basename $0) csv_file_name_to_save
    exit 63
fi

csv_file_name=$1
if [[ $(echo $csv_file_name | awk -F '.' '{ print $2 }') != 'csv' ]]
then
    echo "Extension is not defined to the CSV file. Script itself ovverride this as $csv_file_name.csv"
    csv_file_name="$csv_file_name.csv"
    rm -f $csv_file_name
fi

#### Load prepare_alarm_csv_file, generate_csv_fields functions to script
. ./libs/functions.sh
. ./libs/global_variables.sh

prepare_alarm_csv_file AlarmName \
        AlarmDescription \
        Namespace \
        Dimensions \
        Statistic \
        MetricName \
        ComparisonOperator \
        Threshold \
        Period \
        DatapointsToAlarm \
        EvaluationPeriods \
        TreatMissingData \
        Unit \
        ActionsEnabled \
        AlarmActions \
        OKActions 

for alarm_name in $all_alarm_names
do
    generate_csv_fields $alarm_name
    prepare_alarm_csv_file $alarm_name \
            $alarm_description \
            $namespace \
            $dimensions \
            $statistic \
            $metric_name \
            $comparison_operator \
            $threshold \
            $period \
            $datapoints_to_alarm \
            $evaluation_periods \
            $treat_missing_data \
            $unit \
            $actions_enabled \
            $alarm_actions \
            $ok_actions 
done