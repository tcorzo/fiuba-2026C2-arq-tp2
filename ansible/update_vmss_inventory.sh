#!/bin/bash

# Get the Jumpbox DNS name, the resource group and the scale set from the stacks' outputs
JUMPBOX_DNS=$(../infra/output.sh foundation jumpbox_fqdn) || exit 1
RESOURCE_GROUP=$(../infra/output.sh foundation resource_group_name) || exit 1
VMSS_NAME=$(../infra/output.sh platform vmss_name) || exit 1

# Setup how Ansible is going to use the Jumpbox to communicate with the VMSS instances
echo "[vmss:vars]" > ./vmss_hosts
echo "ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ProxyCommand=\"ssh -o StrictHostKeyChecking=no -i ../key.pem -W %h:%p -q azureuser@$JUMPBOX_DNS\"'" >> ./vmss_hosts

# List all instances, obtain their private IP and add those to the inventory
echo "[vmss]" >> ./vmss_hosts
az vmss nic list --resource-group "$RESOURCE_GROUP" --vmss-name "$VMSS_NAME" --query [].ipConfigurations[].privateIPAddress -o tsv | tr "\t" "\n" >> ./vmss_hosts
