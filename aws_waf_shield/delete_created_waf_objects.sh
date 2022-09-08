#!/usr/bin/env bash
. ./libs/global-variables.sh
. ./libs/create-acl-variables.sh
. ./libs/global-functions.sh

# Create WEB ACL via CLI 
# aws wafv2 create-web-acl --description "New Web ACL from command line" \
#                             --name ${acl_name} \
#                             --default-action Allow={} \
#                             --scope=REGIONAL \
#                             --region=${region_name} \
#                             --visibility-config SampledRequestsEnabled=true,CloudWatchMetricsEnabled=true,MetricName=${acl_name}

# Delete WEB ACL
delete_web_acl_by_name "${web_acl_output_names}"

# Delete Rule group
IFS=' '; for rule_group_in_waf in $rule_group_names; do delete_rule_group_by_name ${rule_group_in_waf}; done; unset IFS

# Delete IP sets
for ip_sets_name in "${!ip_sets[@]}"; do delete_ip_set_by_name ${ip_sets_name}; done

# Delete RegEx Pattern Sets
for regex_pattern_set_name in "${!regex_pattern_sets[@]}"; do delete_regex_pattern_sets ${regex_pattern_set_name}; done
