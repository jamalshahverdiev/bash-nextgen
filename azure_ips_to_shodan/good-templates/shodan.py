#!/usr/bin/env python3
import json
from library_functions import (
        tenant, 
        client_id, 
        client_secret, 
        subscription_id,
        shodan_api_key,
        shodan_api_url,
        get_shodan_alerts_json,
        get_shodan_alert_names,
        get_all_alerts_public_ips,
        get_azure_public_ips
        )

shodan_alert_ips = get_all_alerts_public_ips(shodan_api_key, shodan_api_url)
print(shodan_alert_ips)
shodan_alert_names = get_shodan_alert_names(shodan_api_key, shodan_api_url)
print(shodan_alert_names)

# for alert_name in shodan_alert_names:
#     print(alert_name)
#if content['name'] == 'project_stage_hot_db':
#    print(content['name'])


azure_public_ips = get_azure_public_ips(tenant, client_id, client_secret, subscription_id)
print(azure_public_ips)