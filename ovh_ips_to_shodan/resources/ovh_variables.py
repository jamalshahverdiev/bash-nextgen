import ovh
from os import environ

shodan_api_key = environ.get('SHODAN_API_KEY')
shodan_api_url = 'https://api.shodan.io/shodan/alert'
notifier_ids = 'default,6MWsSAAMqsr3QQiv'
trigger_rule_names = 'malware,open_database,iot,internet_scanner,industrial_control_system,new_service,ssl_expired,vulnerable,uncommon,uncommon_plus'
client = ovh.Client(
    endpoint = 'ovh-eu',
    application_key = environ.get('OVH_APPLICATION_KEY'),
    application_secret = environ.get('OVH_APPLICATION_SECRET'),
    consumer_key = environ.get('OVH_CONSUMER_KEY')
)
headers = {'Content-type': 'application/json'}
template_name = "alert_template.json"
project_name = 'project'
service_names = client.get('/dedicated/server')
