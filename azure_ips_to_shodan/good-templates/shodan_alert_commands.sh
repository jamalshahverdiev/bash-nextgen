#!/usr/bin/env bash
# Author: Jamal Shahverdiyev

####### CREATE ALERT
#id_of_alert_in_create=$(curl -s -X POST "$shodan_api_url?key=$shodan_api_key" -H 'Content-Type: application/json' -d @alert_template.json | jq -r .id)
#curl -X POST "$shodan_api_url?key=$shodan_api_key" -H 'Content-Type: application/json' -d @alert_template.json

####### GET ALL alerts
#all_alerts_json=$(curl -s -X GET "$shodan_api_url/info?key=$shodan_api_key" | jq -r '.[]')
#alert_names=$(echo $all_alerts_json | jq -r .name)


####### GET ID by name of alert
#id_of_alert=$(curl -s -X GET "$shodan_api_url/info?key=$shodan_api_key" | jq -r '.[]|select(.name=="'$new_alert_name'").id')

####### DELETE ALERT
#for id in $id_of_alert
#do
#    curl -X DELETE "$shodan_api_url/$id?key=$shodan_api_key"
#done


####### ADD TRIGGER to NEW CREATED SHODAN ALERT
#curl -s -X PUT "$shodan_api_url/$id_of_alert/trigger/$trigger_rule_names?key=$shodan_api_key"
#curl -s -X PUT "$shodan_api_url/$id_of_alert/notifier/$notifier_ids?key=$shodan_api_key"
#curl -s -X POST "$shodan_api_url/$id_of_alert?key=$shodan_api_key" -H 'Content-Type: application/json' -d @alert_template.json
#echo $alert_names