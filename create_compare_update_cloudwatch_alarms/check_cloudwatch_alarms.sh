#!/usr/bin/env bash

. ./libs/functions.sh

if [ $# -lt 1 ]
then
    usage
fi

while getopts_long ':g:u:c: get: update: check:' OPTKEY; do
    case ${OPTKEY} in
        'g'|'get')      ./libs/prepare_alarms_db.sh $OPTARG ;;
        'u'|'update')   ./libs/update_alarms_from_db.sh $OPTARG ;;
        'c'|'check')    ./libs/compare_alarms_db_with_aws.sh $OPTARG ;;
        '?')            echo "INVALID OPTION -- ${OPTARG}"; usage >&2 ; exit 1 ;;
        ':')            echo "MISSING ARGUMENT for option -- ${OPTARG}"; usage >&2 ; exit 1 ;;
        *)              echo "Misconfigured OPTSPEC or uncaught option -- ${OPTKEY}"; usage >&2 ; exit 1 ;;
    esac
done
