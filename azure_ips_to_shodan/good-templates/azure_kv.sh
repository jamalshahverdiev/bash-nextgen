#!/usr/bin/env bash

RESOURCE_GROUP='staging-rg-pip'
REGION='NorthEurope'
# SP_NAME='python-apps-new'
ENV_NAME='staging'
SP_NAME="${ENV_NAME}-sp-shodan"
KV_NAME="${ENV_NAME}-onoff-shodan-kv"
KV_SECRET_NAME="${ENV_NAME}-secret-shodan"
ROLE='Reader'

if [[ -z $(az ad app list | jq -r '.[].displayName' | grep -w "^${SP_NAME}$") ]]
then
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    SP_INFORMATION=$(az ad sp create-for-rbac -n "${SP_NAME}" --role "${ROLE}" --scopes "/subscriptions/${SUBSCRIPTION_ID}" --years 2)
    CLIENT_SECRET=$(echo $SP_INFORMATION | jq -r .password)
    ClientID=$(echo $SP_INFORMATION | jq -r .appId)
    TenantID=$(echo $SP_INFORMATION | jq -r .tenant)
    echo "ClientID -> ${ClientID} | ClientSecret -> ${CLIENT_SECRET} | TenantID -> ${TenantID}"
    echo "ClientSecret -> ${CLIENT_SECRET} | AzKeyName -> ${KV_NAME}" 
    if [[ -z $(az keyvault list | jq -r '.[].name' | grep $KV_NAME ) ]]
    then
        az keyvault create --name "${KV_NAME}" --resource-group "${RESOURCE_GROUP}" --location "${REGION}"
        az keyvault secret set --name "${KV_SECRET_NAME}" --vault-name "${KV_NAME}" --value "${CLIENT_SECRET}"
    fi
else
    echo "SP is already exists: ${SP_NAME}"
fi

# If you want to delete KV use the following command
# az keyvault delete --name ${KV_NAME} && az keyvault purge --name ${KV_NAME}

# If you want to delete SP use the following command:
# appID=$(az ad sp list --all | jq -r '.[]|select(.appDisplayName=="'$SP_NAME'").appId')
# az ad sp delete --id ${appID}