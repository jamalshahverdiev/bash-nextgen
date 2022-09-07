#!/usr/bin/env bash

# https://docs.aws.amazon.com/cli/latest/reference/cloudwatch/put-metric-alarm.html
# https://docs.aws.amazon.com/cli/latest/reference/cloudwatch/delete-alarms.html
# https://github.com/swoodford/aws/blob/master/cloudwatch-create-alarms.sh
# Setup:
# export AWS_PROFILE=staging
# export AWS_PROFILE=albums-stage
# export AWS_DEFAULT_REGION=eu-west-1
# aws configure --profile $AWS_PROFILE
AWS_PROFILE=staging
# aws configure list --profile $AWS_PROFILE || exit 64
get_alarm_objects=$(aws cloudwatch describe-alarms | jq '.MetricAlarms|.[]')
all_alarm_names=$(echo $get_alarm_objects | jq -r '.AlarmName')

# ALARM_ACTION="arn:aws:sns:eu-west-1:843482687672:Pagerduty_Devops"
# URGENT_ALARM_ACTION="arn:aws:sns:eu-west-1:843482687672:Pagerduty_Devops_Urgent"
ALARM_ACTION="arn:aws:sns:eu-west-1:394579837878:stage-aws-services-alarms"
URGENT_ALARM_ACTION="arn:aws:sns:eu-west-1:394579837878:stage-aws-services-alarms"
CLEAN_ALARMS=false