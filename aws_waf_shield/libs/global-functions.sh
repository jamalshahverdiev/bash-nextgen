#!/usr/bin/env bash

# Prepare Json file
prepare_json_file(){
    if [ $# -lt 2 ]; then echo "Usage: ./$(basename $0) src_json_file_path dst_json_file_path"; exit 14; fi
    src_file=$1
    dst_file=$2
    cp ${src_file} ${dst_file}
}

# Get All labels by AWS managed RuleName
get_aws_managed_rule_labels(){
    aws_managed_rule_group_name=$1
    aws_managed_rule_group_object=$(aws wafv2 describe-managed-rule-group --region=${region_name} --scope=REGIONAL --vendor-name AWS --name ${aws_managed_rule_group_name} | jq -r '.AvailableLabels')
    if [[ ${aws_managed_rule_group_object} != 'null' ]]; then echo ${aws_managed_rule_group_object} | jq -r '.[].Name'; fi
}

get_all_labels_of_aws_managed_rule_groups(){
    aws_managed_rule_group_names=$(aws wafv2 list-available-managed-rule-groups --region=${region_name} --scope=REGIONAL | jq -r '.ManagedRuleGroups[].Name')
    all_labels_from_rule_group_rules=()
    for aws_managed_rule_group_name in ${aws_managed_rule_group_names}; do
        all_labels_from_rule_group_rules+=($(get_aws_managed_rule_labels ${aws_managed_rule_group_name}))
    done
    for value in "${all_labels_from_rule_group_rules[@]}"; do echo $value; done
}

create_ip_sets(){
    for ip_sets_name in "${!ip_sets[@]}"; do 
        existing_ip_sets=$(aws wafv2 list-ip-sets --scope=REGIONAL --region=${region_name} | jq -r '.IPSets[].Name')
        if [[ ! ${existing_ip_sets} =~ "${ip_sets_name}" ]]; then
            aws wafv2 create-ip-set --name ${ip_sets_name} \
                                    --description "${ip_sets_name} Public IP address list" \
                                    --scope=REGIONAL \
                                    --region=${region_name} \
                                    --addresses ${ip_sets[$ip_sets_name]} \
                                    --ip-address-version IPV4 2>&1 > /dev/null
        fi
    done
}

create_regex_pattern_sets(){
    # Create Regex Pattern set
    existing_regex_pattern_set_names=$(aws wafv2 list-regex-pattern-sets --scope=REGIONAL --region=${region_name} | jq -r '.RegexPatternSets[].Name')
    for regex_pattern_set_name in "${!regex_pattern_sets[@]}"; do 
        if [[ ! ${existing_regex_pattern_set_names} =~ "${regex_pattern_set_name}" ]]; then
            aws wafv2 create-regex-pattern-set \
                        --name ${regex_pattern_set_name} \
                        --region=${region_name} \
                        --scope=REGIONAL \
                        --description "${regex_pattern_set_name} regex list for matchs." \
                        --regular-expression-list "${regex_pattern_sets[$regex_pattern_set_name]}" 2>&1 > /dev/null  
            sleep 0.5      
        fi
    done
    regex_pattern_set_obj=$(aws wafv2 list-regex-pattern-sets --scope=REGIONAL --region=${region_name} | jq '.RegexPatternSets[]')
}

prepare_rule_group_json(){
    prepare_json_file $1 $2
    existing_ip_sets_object=$(aws wafv2 list-ip-sets --scope=REGIONAL --region=${region_name} | jq '.IPSets[]')
    existing_ip_sets_names=$(echo ${existing_ip_sets_object} | jq -r '.Name')
    existing_regex_pattern_set_names=$(echo ${regex_pattern_set_obj} | jq -r .Name)
    for ip_sets_name in "${!ip_sets[@]}"; do
        if [[ ${existing_ip_sets_names} =~ "${ip_sets_name}" ]]; then
            arn_of_ip_set=$(echo ${existing_ip_sets_object} | jq -r 'select(.Name=="'${ip_sets_name}'")|.ARN')
            sed -i "s|replace_${ip_sets_name}_string|${arn_of_ip_set}|g" ${dst_file}
        fi
    done
    
    for regex_pattern_set_name in "${!regex_pattern_sets[@]}"; do
        if [[ ${existing_regex_pattern_set_names} =~ "${regex_pattern_set_name}" ]]; then
            arn_of_regex_pattern_set=$(echo ${regex_pattern_set_obj} | jq -r 'select(.Name=="'$regex_pattern_set_name'")|.ARN')
            sed -i "s|replace_${regex_pattern_set_name}_string|${arn_of_regex_pattern_set}|g" ${dst_file}
        fi
    done
}

create_rule_groups_json_files(){
    for rule_groups_with_value_key in "${!rule_groups_with_values[@]}"; do
        prepare_rule_group_json ${templates_directory}/${!rule_groups_with_values[${rule_groups_with_value_key}]} ${rule_groups_with_value_key}.json
    done
}

get_rule_group_id_token_by_name(){
    rule_group_name=$1
    list_rule_groups_object=$(aws wafv2 list-rule-groups --scope=REGIONAL --region=${region_name} | jq '.RuleGroups[]')
    # list_rule_group_names=$(echo $list_rule_groups_object | jq -r '.Name')
    id_of_rule_group=$(echo $list_rule_groups_object | jq -r 'select(.Name=="'$rule_group_name'")|.Id')
    lock_token=$(echo $list_rule_groups_object | jq -r 'select(.Name=="'$rule_group_name'")|.LockToken')
}

update_rule_groups(){
    name_of_the_rule_group=$1
    get_rule_group_id_token_by_name ${name_of_the_rule_group}
    aws wafv2 update-rule-group --scope=REGIONAL \
                                --region=${region_name} \
                                --name ${name_of_the_rule_group} \
                                --visibility-config ${visibility_config} \
                                --rules file://waf-rule.json \
                                --id ${id_of_rule_group} \
                                --lock-token ${lock_token} 2>&1 > /dev/null
}

delete_web_acl_by_name(){
    web_acl_names_input=$1
    for web_acl_name in ${web_acl_names_input}; do 
        web_acls_object=$(aws wafv2 list-web-acls --region=${region_name} --scope=REGIONAL | jq '.WebACLs[]')
        id_of_web_acl=$(echo ${web_acls_object} | jq -r 'select(.Name=="'${web_acl_name}'")|.Id')
        lock_token_of_web_acl=$(echo ${web_acls_object} | jq -r 'select(.Name=="'${web_acl_name}'")|.LockToken')
        aws wafv2 delete-web-acl --name ${web_acl_name} --region=${region_name} --scope=REGIONAL --id ${id_of_web_acl} --lock-token ${lock_token_of_web_acl}
    done
}

delete_rule_group_by_name(){
    rule_group_name_input=$1
    rule_groups_object=$(aws wafv2 list-rule-groups --region=${region_name} --scope=REGIONAL | jq '.RuleGroups[]')
    id_of_rule_group=$(echo ${rule_groups_object} | jq -r 'select(.Name=="'${rule_group_name_input}'")|.Id')
    lock_token_of_rule_group=$(echo ${rule_groups_object} | jq -r 'select(.Name=="'${rule_group_name_input}'")|.LockToken')
    aws wafv2 delete-rule-group --name ${rule_group_name_input} --region=${region_name} --scope=REGIONAL --id ${id_of_rule_group} --lock-token ${lock_token_of_rule_group}
}

delete_ip_set_by_name(){
    ip_set_name_input=$1
    ip_sets_full_object=$(aws wafv2 list-ip-sets --scope=REGIONAL --region=${region_name} | jq '.IPSets[]')
    id_of_ip_set=$(echo ${ip_sets_full_object} | jq -r 'select(.Name=="'${ip_set_name_input}'")|.Id')
    lock_token_of_ip_set=$(echo ${ip_sets_full_object} | jq -r 'select(.Name=="'${ip_set_name_input}'")|.LockToken')
    aws wafv2 delete-ip-set --region=${region_name} --scope=REGIONAL --name $ip_set_name_input --id ${id_of_ip_set} --lock-token ${lock_token_of_ip_set}
}

delete_regex_pattern_sets(){
    regex_pattern_set_name_input=$1
    regex_pattern_set_object=$(aws wafv2 list-regex-pattern-sets --scope=REGIONAL --region=${region_name} | jq '.RegexPatternSets[]')
    id_of_regex_pattern_set=$(echo ${regex_pattern_set_object} | jq -r 'select(.Name=="'${regex_pattern_set_name_input}'")|.Id')
    lock_token_of_regex_pattern_set=$(echo ${regex_pattern_set_object} | jq -r 'select(.Name=="'${regex_pattern_set_name_input}'")|.LockToken')
    aws wafv2 delete-regex-pattern-set --scope=REGIONAL \
                                    --region=${region_name} \
                                    --name ${regex_pattern_set_name_input} \
                                    --id ${id_of_regex_pattern_set} \
                                    --lock-token ${lock_token_of_regex_pattern_set}
}

clean_template_files(){
    rm -rf *.json
}