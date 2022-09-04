#!/usr/bin/env bash

. ./libs/functions.sh

if [ $# -lt 1 ]
then
    usage
fi

while getopts_long ':e: env:' OPTKEY; do
    case ${OPTKEY} in
        'e'|'env')      
            ./aws_rdsdb_names.sh ${OPTARG}
            ./internet_facing_elbs.sh ${OPTARG}
            ./eip_ec2_names.sh ${OPTARG}
        ;;
        '?')            echo "INVALID OPTION -- ${OPTARG}"; usage >&2 ; exit 1 ;;
        ':')            echo "MISSING ARGUMENT for option -- ${OPTARG}"; usage >&2 ; exit 1 ;;
        *)              echo "Misconfigured OPTSPEC or uncaught option -- ${OPTKEY}"; usage >&2 ; exit 1 ;;
    esac
done
