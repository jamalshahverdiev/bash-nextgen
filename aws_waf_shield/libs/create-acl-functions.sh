#!/usr/bin/env bash

create_web_acl(){
    web_acl_names_input=$1
    for web_acl_name in ${web_acl_names_input}; do 
        aws wafv2 create-web-acl --cli-input-json file://${web_acl_name}.json --region=${region_name} 2>&1 > /dev/null 
    done 
}

create_new_rule_group_and_prepare_web_acl_json(){
    # Create new rule group
    src_dir_web_acl_json=$1
    web_acl_names_input=$2
    for rule_group_name in ${rule_group_names}; do 
        json_file_name=${rule_group_name}.json
        existing_rule_group_names=$(aws wafv2 list-rule-groups --scope=REGIONAL --region=${region_name} | jq -r '.RuleGroups[].Name')
        if [[ ! ${existing_rule_group_names} =~ "${rule_group_name}" ]]; then
            aws wafv2 create-rule-group --scope=REGIONAL \
                                            --region=${region_name} \
                                            --name ${rule_group_name} \
                                            --description ${rule_group_name} \
                                            --visibility-config ${visibility_config} \
                                            --rules file://${json_file_name} \
                                            --capacity 200 2>&1 > /dev/null
            arn_of_rule_group=$(aws wafv2 list-rule-groups --region=${region_name} --scope=REGIONAL | jq -r '.RuleGroups[]|select(.Name=="'${rule_group_name}'")|.ARN') 
            IFS=' '
            for web_acl_name in ${web_acl_names_input}; do
                if [[ ! -f ${web_acl_name}.json ]]; then cp ${src_dir_web_acl_json}/${web_acl_name}.json ${web_acl_name}.json; fi
                if [[ ! -z ${arn_of_rule_group} ]]; then sed -i "s|replace_${rule_group_name}_string|${arn_of_rule_group}|g" ${web_acl_name}.json; fi
            done
            unset IFS
        fi
    done
}