#!/usr/bin/env bash
resource_groups=$(az group list --query '[].name' -o tsv)
all_ip_objects_in_json=$(az network public-ip list)
public_ip_names=$(echo ${all_ip_objects_in_json} | jq -r '.[].name')
public_ip_ids=$(echo ${all_ip_objects_in_json} | jq -r '.[].id')
declare -A az_object_types_array
