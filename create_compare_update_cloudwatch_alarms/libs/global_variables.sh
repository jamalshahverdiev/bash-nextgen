#!/usr/bin/env bash

get_alarm_objects=$(aws cloudwatch describe-alarms | jq '.MetricAlarms|.[]')
all_alarm_names=$(echo $get_alarm_objects | jq -r '.AlarmName')