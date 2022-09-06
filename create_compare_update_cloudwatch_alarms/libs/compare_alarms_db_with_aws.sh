#!/usr/bin/env bash

if [ $# -lt 1 ]
then
    echo Usage: ./$(basename $0) csv_file_name_to_compare
    exit 63
fi

current_csv_data_file=$1
if [[ ! -f $current_csv_data_file ]]
then
    echo "File with name {$current_csv_data_file} don't exists." 
    echo "To create local CSV database execute this command: $0 --get $current_csv_data_file"
    exit 76
fi

csv_content_of_aws='template_csv_file.csv'
./libs/prepare_alarms_db.sh $csv_content_of_aws

current_metrics_data=$(cat $current_csv_data_file | grep -v AlarmDescription)

for line in $current_metrics_data
do
    grep $line $csv_content_of_aws > /dev/null
    if [ $? != 0 ]
    then
        alarm_name=$(echo $line | awk -F ';' '{ print $1 }')
        echo "The alarm with name {$alarm_name} different than on AWS Cloudwatch alarms."
    fi
done
