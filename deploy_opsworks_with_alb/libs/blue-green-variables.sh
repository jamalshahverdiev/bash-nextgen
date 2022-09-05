#!/usr/bin/env bash

INSTANCE_TYPE="t3.medium"
INSTANCE_COUNT=2
SUBNET_IDS=()
declare -a GREENINSTANCE_IDS
# With trailing slash
WAIT_TIME="3m"