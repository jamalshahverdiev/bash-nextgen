import ovh, requests, json
from requests import post, put
from os import remove
from time import sleep
from resources.ovh_variables import (
        shodan_api_url, 
        shodan_api_key, 
        notifier_ids, 
        trigger_rule_names,
        headers,
        project_name
    )
# from logging import basicConfig
# basicConfig(level=logging.DEBUG)
def create_alert_return_id(shodan_api_url, shodan_api_key, json_data_object, headers):
    url = "{0}?key={1}".format(shodan_api_url, shodan_api_key)
    response_of_alert_in_create = post(url, data=json_data_object, headers=headers)
    id_created_alert = json.loads(response_of_alert_in_create.content)["id"]
    return id_created_alert

def update_trigger_notifier(shodan_api_url, shodan_api_key, id_of_alert, notifier_ids, trigger_rule_names, headers):
    notify_url = "{0}/{1}/notifier/{2}?key={3}".format(shodan_api_url, id_of_alert, notifier_ids, shodan_api_key)
    trigger_url = "{0}/{1}/trigger/{2}?key={3}".format(shodan_api_url, id_of_alert, trigger_rule_names, shodan_api_key)
    put(trigger_url, headers=headers)
    put(notify_url, headers=headers)
    sleep(1)  

def prepare_template(host_name, ip_address, template_name):
    with open(template_name, "rt") as file_in:
        with open(host_name + '.json', "w") as file_out:
            for line in file_in:
                file_out.write(
                    line.replace('replace_alert_name', 'ovh_{0}_{1}'.format(project_name, host_name)).replace('ip_list_to_replace', '"{0}"'.format(ip_address))
                )

def create_alert_in_shodan(host_name):
    with open(host_name + '.json') as json_file_to_post:
        id_of_alert = create_alert_return_id(shodan_api_url, shodan_api_key, json_file_to_post.read(), headers)
        update_trigger_notifier(shodan_api_url, shodan_api_key, id_of_alert, notifier_ids, trigger_rule_names, headers)
    sleep(1)

def execute_shodan(service_names, client, template_name):
    for service_name in service_names:
        service_json_content = json.dumps(client.get("/dedicated/server/{0}".format(service_name)))
        service_json_object = json.loads(service_json_content)
        host_name = service_json_object["reverse"].split('.')[0].replace('-', '_')
        ip_address = service_json_object["ip"]
        prepare_template(host_name, ip_address, template_name)
        create_alert_in_shodan(host_name)
        print("Alert | ", 'ovh_{0}'.format(host_name), " | PublicIPs | ", '"{0}"'.format(ip_address))
        remove(host_name + '.json')