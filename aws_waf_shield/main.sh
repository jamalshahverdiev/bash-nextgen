#!/usr/bin/env bash
. ./libs/global-variables.sh
. ./libs/create-acl-variables.sh
. ./libs/global-functions.sh
. ./libs/create-acl-functions.sh

trap clean_template_files EXIT

create_regex_pattern_sets
create_ip_sets
create_rule_groups_json_files
create_new_rule_group_and_prepare_web_acl_json ${templates_directory} "${web_acl_output_names}"
create_web_acl "${web_acl_output_names}"
