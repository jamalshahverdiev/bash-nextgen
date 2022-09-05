#!/usr/bin/env bash

. ./libs/functions.sh
. ./libs/global-variables.sh

get_vpn_gateway_ips_from_all_rgs "${resource_groups}"
get_vms_public_ips_from_all_rgs "${resource_groups}"
get_lbs_public_ips_from_all_rgs "${resource_groups}"
get_app_gateway_ips_from_all_rgs "${resource_groups}"
get_az_firewall_ips_from_all_rgs "${resource_groups}"