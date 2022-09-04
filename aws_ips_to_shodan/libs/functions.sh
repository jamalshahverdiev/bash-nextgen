#!/usr/bin/env bash
# Exit code '89' means: Count of the arguments is not right
# Exit code '109' means: Cannot find string inside of the Array
# Exit cod '64' means: input argument of parameter empty or parameter not defined correctly

error_outputs_of_script(){
    set -o errexit
    set -o pipefail
    #set -o nounset
}

prepare_ip_struct(){
    if [[ $# -lt 1 ]]; then
        echo "Usage: ./$(basename $0) ips_object"
        exit 89
    fi
    local ips=("$1")
    declare -a ip_array
    for ip in $ips
    do
        ip_array+=('"'${ip}'",')
    done
    listed_ips=$(echo ${ip_array[@]} | sed 's/,$//') && ip_array=()
    echo $listed_ips
}

update_trigger_and_notifier(){
    if [[ $# -lt 5 ]]; then
        echo "Usage: ./$(basename $0) shodan_api_url id_of_alert_in_create trigger_rule_names notifier_ids shodan_api_key"
        exit 89
    fi
    shodan_api_url=$1
    id_of_alert_in_create=$2
    trigger_rule_names=$3
    notifier_ids=$4
    shodan_api_key=$5
    curl -s -X PUT "$shodan_api_url/$id_of_alert_in_create/trigger/$trigger_rule_names?key=$shodan_api_key" \
	"$shodan_api_url/$id_of_alert_in_create/notifier/$notifier_ids?key=$shodan_api_key"
    echo
}

prepare_shodan_post_json(){
    if [[ $# -lt 4 ]]; then
        echo "Usage: ./$(basename $0) input_json_file_name output_json_file_name alert_name_to_create ip_list_object"
        exit 89
    fi
    local alert_name_to_create=("$3")
    local ip_list_object=("$4")
    input_json_file_name="$1"
    output_json_file_name="$2"
    cp $input_json_file_name $output_json_file_name
    sed -i "s/replace_alert_name/${alert_name_to_create}/g;s/ip_list_to_replace/$ip_list_object/g" $output_json_file_name
}

update_existing_alert(){
    if [[ $# -lt 4 ]]; then
        echo "Usage: ./$(basename $0) shodan_api_url shodan_api_key alert_name alert_json_file_name"
        exit 89
    fi   
    shodan_api_url=$1
    shodan_api_key=$2
    local alert_name=("$3")
    alert_json_file_name=$4
    id_of_alert=$(curl -s -X GET "$shodan_api_url/info?key=$shodan_api_key" | jq -r '.[]|select(.name=="'$alert_name'").id')
    curl -s -X POST "$shodan_api_url/$id_of_alert?key=$shodan_api_key" -H 'Content-Type: application/json' -d @${alert_json_file_name}
    echo
    echo "Updated alert | ${alert_name} | with ID | ${id_of_alert}"
}

create_new_alert(){
    if [[ $# -lt 7 ]]; then
        echo "Usage: ./$(basename $0) shodan_api_url shodan_api_key trigger_rule_names notifier_ids alert_name alert_names_object alert_json_file_name"
        exit 89
    fi

    shodan_api_url=$1
    shodan_api_key=$2
    trigger_rule_names=$3
    notifier_ids=$4
    local alert_name=("$5")
    local alert_names_object=("$6")
    alert_json_file_name=$7

    if printf '%s\n' "${alert_names_object[@]}" | grep -q -P "^$alert_name$"; then
        echo "Alert | $alert_name | already exists. Going to update Shodan."
        update_existing_alert "${shodan_api_url}" "${shodan_api_key}" "${alert_name}" "${alert_json_file_name}"
    else
        id_of_alert_in_create=$(curl -s -X POST "$shodan_api_url?key=$shodan_api_key" -H 'Content-Type: application/json' -d @${alert_json_file_name} | jq -r .id)
        echo "Creating new alert with name | $alert_name | and ID | $id_of_alert_in_create"
        update_trigger_and_notifier $shodan_api_url $id_of_alert_in_create $trigger_rule_names $notifier_ids $shodan_api_key    
    fi
    
    sleep 2
    rm ${alert_json_file_name}
}

check_alert_exists(){
    if [[ $# -lt 2 ]]; then
        echo "Usage: ./$(basename $0) alert_name alert_names_object"
        exit 89
    fi  
    local alert_name=("$1")
    local alert_names_object=("$2")
    if printf '%s\n' "${alert_names_object[@]}" | grep -q -P "^$alert_name$"; then
        echo "The alert name | $alert_name | already exists. Please use update function to update existing alert."
        exit 109
    fi
}

get_ips_by_name() {
    if [[ $# -lt 1 ]]; then
        echo "Usage: ./$(basename $0) dns_name"
        exit 89
    fi
    ns_server='8.8.8.8'
    dns_name=$1
    public_ips=$(dig A $dns_name +short @${ns_server} | egrep -v 'amazonaws')
    echo $public_ips
}

delete_shodan_alert(){
    if [[ $# -lt 3 ]]; then
        echo "Usage: ./$(basename $0) shodan_api_url shodan_api_key alert_name"
        exit 89
    fi
    shodan_api_url=$1 
    shodan_api_key=$2 
    alert_name=$3
    id_of_alert=$(curl -s -X GET "$shodan_api_url/info?key=$shodan_api_key" | jq -r '.[]|select(.name=="'$alert_name'").id')
    curl -X DELETE "$shodan_api_url/$id_of_alert?key=$shodan_api_key"
    sleep 2
}

check_prj_name_not_empty(){
    project_name=$1
    if [[ -z $project_name  ]]; then
        echo '*************************** Project name argument is empty I set myself to: onoff ***************************'
        project_name='onoff'
    fi
}

execute_shodan_api(){
    if [[ ! -z ${listed_ips} ]]; then
        prepare_shodan_post_json "${input_json_file_name}" "${output_json_file_name}" "${alert_name}" "${listed_ips}"
        create_new_alert "${shodan_api_url}" "${shodan_api_key}" "${trigger_rule_names}" "${notifier_ids}" "${alert_name}" "${alert_names}" "${output_json_file_name}"
        echo "Alert | ${alert_name} | PublicIPs | ${listed_ips}"
    fi 
}

post_lbs_to_shodan(){
    lb_names=$1
    lbs_object=$2
    lb_type=$3
    for lb_name in ${lb_names}; do
        scheme_type=$(echo ${lbs_object} | jq -r 'select(.LoadBalancerName=="'${lb_name}'")|.Scheme')
        if [[ "${scheme_type}" != *"internal"* ]]; then             
            echo '*************************************************************************************************************'
            dns_name_of_lb=$(echo ${lbs_object} | jq -r 'select(.LoadBalancerName=="'${lb_name}'")|.DNSName')
            lb_name=$(echo $lb_name | sed 's/-/_/g')
            echo -e "LBname | $lb_name\t\t\t | scheme type | $scheme_type"
            echo DNSname: ${dns_name_of_lb}
            ips=$(get_ips_by_name $dns_name_of_lb)
            alert_name="${project_name}_${env_name}_${lb_type}_${lb_name}"
            listed_ips=$(prepare_ip_struct "${ips}")
            execute_shodan_api
        fi
    done
}

getopts_long() {
    : "${1:?Missing required parameter -- long optspec}"
    : "${2:?Missing required parameter -- variable name}"

    local optspec_short="${1%% *}-:"
    local optspec_long="${1#* }"
    local optvar="${2}"

    shift 2

    if [[ "${#}" == 0 ]]; then
        local args=()
        while [[ ${#BASH_ARGV[@]} -gt ${#args[@]} ]]; do
            local index=$(( ${#BASH_ARGV[@]} - ${#args[@]} - 1 ))
            args[${#args[@]}]="${BASH_ARGV[${index}]}"
        done
        set -- "${args[@]}"
    fi

    builtin getopts "${optspec_short}" "${optvar}" "${@}" || return 1
    [[ "${!optvar}" == '-' ]] || return 0

    printf -v "${optvar}" "%s" "${OPTARG%%=*}"

    if [[ "${optspec_long}" =~ (^|[[:space:]])${!optvar}:([[:space:]]|$) ]]; then
        OPTARG="${OPTARG#${!optvar}}"
        OPTARG="${OPTARG#=}"

        # Missing argument
        if [[ -z "${OPTARG}" ]]; then
            OPTARG="${!OPTIND}" && OPTIND=$(( OPTIND + 1 ))
            [[ -z "${OPTARG}" ]] || return 0

            if [[ "${optspec_short:0:1}" == ':' ]]; then
                OPTARG="${!optvar}" && printf -v "${optvar}" ':'
            else
                [[ "${OPTERR}" == 0 ]] || \
                    echo "${0}: option requires an argument -- ${!optvar}" >&2
                unset OPTARG && printf -v "${optvar}" '?'
            fi
        fi
    elif [[ "${optspec_long}" =~ (^|[[:space:]])${!optvar}([[:space:]]|$) ]]; then
        unset OPTARG
    else
        # Invalid option
        if [[ "${optspec_short:0:1}" == ':' ]]; then
            OPTARG="${!optvar}"
        else
            [[ "${OPTERR}" == 0 ]] || echo "${0}: illegal option -- ${!optvar}" >&2
            unset OPTARG
        fi
        printf -v "${optvar}" '?'
    fi
}

usage () {
  echo "Usage: "
  echo "  $0 [-e/--env/] environment_name(prod/staging)"
  exit 64
}
