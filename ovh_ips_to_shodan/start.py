#!/usr/bin/env python3
from resources.ovh_variables import service_names, client, template_name
from resources.ovh_functions import execute_shodan

execute_shodan(service_names, client, template_name)
