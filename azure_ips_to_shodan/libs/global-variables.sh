shodan_api_key=${SHODAN_API_KEY}
shodan_api_url='https://api.shodan.io/shodan/alert'
trigger_rule_names='malware,open_database,iot,internet_scanner,industrial_control_system,new_service,ssl_expired,vulnerable'
notifier_ids='default,6MWsSAAMqsr3QQiv'
all_alerts_json=$(curl -s -X GET "$shodan_api_url/info?key=$shodan_api_key" | jq -r '.[]')
alert_names=$(echo $all_alerts_json | jq -r .name)
output_json_file_name='output_alert_json_template.json'
input_json_file_name='alert_template.json'