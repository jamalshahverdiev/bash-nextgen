#!/usr/bin/env bash

. ./libs/aws-functions.sh

if [ $# -lt 1 ]
then
    usage
fi

while getopts_long ':e: env:' OPTKEY; do
    case ${OPTKEY} in
        'e'|'env')      
            ./most_types_in_one.sh ${OPTARG}
            ./azure_db_names.sh ${OPTARG}
        ;;
        '?')            echo "INVALID OPTION -- ${OPTARG}"; usage >&2 ; exit 1 ;;
        ':')            echo "MISSING ARGUMENT for option -- ${OPTARG}"; usage >&2 ; exit 1 ;;
        *)              echo "Misconfigured OPTSPEC or uncaught option -- ${OPTKEY}"; usage >&2 ; exit 1 ;;
    esac
done
