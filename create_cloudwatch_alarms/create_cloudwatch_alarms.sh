#!/usr/bin/env bash
. ./libs/global-functions.sh
. ./libs/alarm_functions.sh

if [ $# -lt 1 ]; then usage; fi

. ./libs/global-variables.sh

get_arguments_with_parameters
print_variables ${ALARM_ACTION} ${URGENT_ALARM_ACTION} ${CLEAN_ALARMS}

create_all_alarms