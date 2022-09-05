#!/usr/bin/env bash

define_standards(){
    check_argument_count $1
    local resource_groups=("$1")
    declare -a $2
    echo '*************************************************************************************************************'
}

get_az_firewall_ips_from_all_rgs(){
    define_standards $1 'az_fws_public_ips_in_rgs'
    for rg_name in ${resource_groups}
    do
        az_firewalls_names_in_rg=$(az network firewall list --resource-group ${rg_name} --query '[].name' -o tsv)
        if [[ ! -z ${az_firewalls_names_in_rg} ]]; then
            for az_firewalls_name_in_rg in ${az_firewalls_names_in_rg}
            do
                az_fw_public_ip_id_in_rg=$(az network firewall show --resource-group ${rg_name} --name ${az_firewalls_name_in_rg} --query 'ipConfigurations[].publicIpAddress.id' -o tsv)
                if [[ ! -z ${az_fw_public_ip_id_in_rg} ]]; then
                    az_fw_public_ip_in_rg=$(az network public-ip show --ids ${az_fw_public_ip_id_in_rg} --query "ipAddress" -o tsv)
                    echo "RgName -> ${rg_name} | AppGateName -> ${az_firewalls_name_in_rg} | PublicIP -> ${az_fw_public_ip_in_rg}"
                    if [[ ! "${az_fws_public_ips_in_rgs[@]}" =~ "${az_fw_public_ip_in_rg}" ]]; then
                        az_fws_public_ips_in_rgs+=("${az_fw_public_ip_in_rg}")  
                    fi
                fi
            done
        fi
    done
    echo "All Public IPs of Firewalls:" ${az_fws_public_ips_in_rgs[@]} && az_fws_public_ips_in_rgs=()
}

get_app_gateway_ips_from_all_rgs(){
    define_standards $1 'app_gws_public_ips_in_rgs'
    for rg_name in ${resource_groups}
    do
        app_gw_names_in_rg=$(az network application-gateway list --resource-group ${rg_name} --query '[].name' -o tsv)
        if [[ ! -z $app_gw_names_in_rg ]]; then
            for app_gw_name_in_rg in $app_gw_names_in_rg
            do
                app_gw_public_ip_id_in_rg=$(az network application-gateway show --resource-group ${rg_name} --name ${app_gw_name_in_rg} --query 'frontendIpConfigurations[].publicIpAddress[].id' -o tsv)
                if [[ ! -z ${app_gw_public_ip_id_in_rg} ]]; then
                    app_gw_public_ip_in_rg=$(az network public-ip show --ids ${app_gw_public_ip_id_in_rg} --query "ipAddress" -o tsv)
                    echo "RgName -> ${rg_name} | AppGateName -> ${app_gw_name_in_rg} | PublicIP -> ${app_gw_public_ip_in_rg}"
                    if [[ ! "${app_gws_public_ips_in_rgs[@]}" =~ "${app_gw_public_ip_in_rg}" ]]; then
                        app_gws_public_ips_in_rgs+=("${app_gw_public_ip_in_rg}")  
                    fi
                fi
            done
        fi
    done
    echo "All Public IPs of AppGWs:" ${app_gws_public_ips_in_rgs[@]} && app_gws_public_ips_in_rgs=()
}

get_vms_public_ips_from_all_rgs(){
    define_standards $1 'vms_public_ips_in_rgs'
    for rg_name in ${resource_groups}
    do
        vm_names_in_rg=$(az vm list --query '[].name' -o tsv --resource-group $rg_name)
        if [[ ! -z ${vm_names_in_rg} ]]; then
            for vm_name_in_rg in ${vm_names_in_rg}
            do
                vm_public_ips=$(az vm show -d -g ${rg_name} -n ${vm_name_in_rg} --query publicIps -o tsv)
                if [[ ! -z ${vm_public_ips} ]]; then
                    echo "RgName -> ${rg_name} | VmName -> ${vm_name_in_rg} | VmPublicIPs -> $vm_public_ips"
                    if [[ ! "${vms_public_ips_in_rgs[@]}" =~ "${vm_public_ips}" ]]; then
                        vms_public_ips_in_rgs+=("${vm_public_ips}")
                    fi
                fi
            done
        fi
    done
    echo "All Public IPs of VMs:" ${vms_public_ips_in_rgs[@]} && vms_public_ips_in_rgs=()
}

get_lbs_public_ips_from_all_rgs(){
    define_standards $1 'lb_public_ips_in_rgs'
    for rg_name in ${resource_groups}
    do
        lb_names_in_rg=$(az network lb list --query '[].name' -o tsv --resource-group ${rg_name})
        if [[ ! -z $lb_names_in_rg ]]; then
            for lb_name_in_rg in ${lb_names_in_rg}
            do
                lb_public_ip_id_in_rg=$(az network lb show --resource-group ${rg_name} --name ${lb_name_in_rg} | jq -r '.frontendIpConfigurations[].publicIpAddress.id')
                if [[ ! -z ${lb_public_ip_id_in_rg} ]]; then
                    lb_public_ip_in_rg=$(az network public-ip show --ids ${lb_public_ip_id_in_rg} --query "ipAddress" -o tsv)
                    echo "RgName -> ${rg_name} | LbName -> ${lb_name_in_rg} | PublicIP -> ${lb_public_ip_in_rg}"
                    if [[ ! "${lb_public_ips_in_rgs[@]}" =~ "${lb_public_ip_in_rg}" ]]; then
                        lb_public_ips_in_rgs+=("${lb_public_ip_in_rg}")
                    fi
                fi
            done
        fi
    done
    echo "All Public IPs of LBs:" ${lb_public_ips_in_rgs[@]} && lb_public_ips_in_rgs=()
}

get_vpn_gateway_ips_from_all_rgs(){
    define_standards $1 'vnet_gws_public_ips_in_rgs'
    for rg_name in ${resource_groups}
    do
        vnet_gw_names_in_rg=$(az network vnet-gateway list --query '[].name' -o tsv --resource-group ${rg_name})
        if [[ ! -z ${vnet_gw_names_in_rg} ]]; then
            for vnet_gw_name_in_rg in ${vnet_gw_names_in_rg}
            do
                public_ip_id=$(az network vnet-gateway show --name ${vnet_gw_name_in_rg} --resource-group ${rg_name} --query 'ipConfigurations[].publicIpAddress[].id' -o tsv)
                if [[ ! -z ${public_ip_id} ]]; then
                    vnet_gw_public_ip_in_rg=$(az network public-ip show --ids ${public_ip_id} --query "ipAddress" -o tsv)
                    echo "Resource group -> ${rg_name} | PublicIP -> ${vnet_gw_public_ip_in_rg}"
                    if [[ ! "${vnet_gws_public_ips_in_rgs[@]}" =~ "${vnet_gw_public_ip_in_rg}" ]]; then
                        vnet_gws_public_ips_in_rgs+=("${vnet_gw_public_ip_in_rg}")
                    fi
                fi
            done
        fi
    done
    echo "All Public IPs of VPNs:" ${vnet_gws_public_ips_in_rgs[@]} && vnet_gws_public_ips_in_rgs=()
}
