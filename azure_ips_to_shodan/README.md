# Usage.
### Prerequisites:
You have the following tools installed on your computer:

- [Git](https://git-scm.com/downloads "Git downloads page") 
- [az cli](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli "Azure CLI install page")
- [JQ](https://stedolan.github.io/jq/download/ "Tool to parse Json data")

## In order to have a working environment please follow the sequence shown below:
- [x] Prepare environment
- [x] Create Shodan Objects
- [x] Delete created objects 

## Prepare environment
- Clone repository and login to Azure as Administrator (`az login`) [to create Azure SP](https://docs.microsoft.com/en-us/cli/azure/create-an-azure-service-principal-azure-cli "Create Azure Service principal") 
- Create Service Principal and store output of the secret inside Azure Key/Valut with `good-templates/azure_kv.sh` script.
- Test service principal with created `ClientSecretID`, `ClientSecret` and `TenantID`

#### Create Service Principal and store in Azure Key/Value
```bash
$ az login
$ ./good-templates/azure_kv.sh
```
#### Check service principal
Define `AZURE_APP_ID`, `AZURE_APP_PASSWORD` and `AZURE_TENANT_ID` variable values from script output `good-templates/azure_kv.sh`:
```bash
$ az login --service-principal --username ${AZURE_APP_ID} --password ${AZURE_APP_PASSWORD} --tenant ${AZURE_TENANT_ID}
```

## Create Shodan Objects
Execute `start.sh` with one of the environments (`prod` or `staging`) to prepate objects in Shodan:
```bash
$ ./start.sh --env staging
```
### Code details
- `good-templates` folder contains useful code files and template functions for the future.
- `libs` folder contains functions and variable files which used inside `most_types_in_one.sh` and `azure_db_names.sh` scripts.
- `start.sh` main file which needs `--env` parameter with argument to create objects. It will calls `most_types_in_one.sh` and `azure_db_names.sh` scripts with argument from `--env` parameter. 
- `most_types_in_one.sh` script creates shodan objects for `vpn`, `loadbalancer`, `application_gateway`, `virtual_machines` and `azure_firewalls` public IP addresses.
- `azure_db_names.sh` script creates shodan objects for `mysql` database public IP addresses.
  
## Delete created objects
If you want to delete created objects in Shodan just execute `delete_created_azure_alerts.sh` script with environment argument. Don't forget change `shodan_api_key` variable value to the right one inside `libs/global-variables.sh` file.
```bash
$ ./delete_created_azure_alerts.sh staging
```