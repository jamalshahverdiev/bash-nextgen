import os.path, shutil, json, requests, tempfile, adal, os

from requests.models import Response
#from flask import make_response, request, abort
#from functools import wraps

shodan_api_url = 'https://api.shodan.io/shodan/alert/info'
shodan_api_key = os.environ['ShodanAPIKey']
tenant = os.environ['TenantID']
client_id = os.environ['ClientID']
client_secret = os.environ['ClientSecret']
subscription_id = os.environ['SubscriptionID']

def listToString(s):
    str1 = " " 
    return (str1.join(s))

def get_shodan_alerts_json(api_key, api_url):
    shodan_api_key = api_key
    params = {'key': shodan_api_key}
    shodan_api_url = api_url
    response = requests.get(shodan_api_url, params)
    return response.json()

def get_shodan_alert_names(api_key, api_url):
    response = get_shodan_alerts_json(api_key, api_url)
    alert_names = []

    for content in response:
        alert_names.append(content['name'])

    return alert_names

def get_all_alerts_public_ips(api_key, api_url):
    response = get_shodan_alerts_json(api_key, api_url)
    
    public_ips = []
    for content in response:
        public_ips.append(listToString(content['filters']['ip']))

    return public_ips

def get_azure_public_ips(tenant, client_id, client_secret, subscription_id):
    authority_url = 'https://login.microsoftonline.com/' + tenant
    resource = 'https://management.azure.com/'
    context = adal.AuthenticationContext(authority_url)
    token = context.acquire_token_with_client_credentials(resource, client_id, client_secret)
    headers = {'Authorization': 'Bearer ' + token['accessToken'], 'Content-Type': 'application/json'}
    params = {'api-version': '2020-11-01'}
    url = resource + 'subscriptions/' + subscription_id + '/providers/Microsoft.Network/publicIPAddresses'
    r = requests.get(url, headers=headers, params=params)
    public_ips = []
    for content in r.json()['value']:
        public_ips.append(content['properties']['ipAddress'])
    return public_ips

#def getIdByTitle(url, params, title):
#    response = requests.get(url, params)
#    for content in response.json()['data']:
#        if content['title'] == title:
#            return content['id']
