#!/bin/bash
# Writes ansible/vmss_hosts: the VMSS instances' private IPs, reached through the jumpbox.
# Works from any directory.
DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEY="$(dirname "$DIR")/key.pem"

if [ ! -r "$KEY" ]; then
  echo "Missing $KEY: the private key of the Azure SSH key ssh_key goes at the repository root (chmod 400)." >&2
  exit 1
fi

# Get the Jumpbox DNS name, the resource group and the scale set from the stacks' outputs
JUMPBOX_DNS=$("$DIR/../infra/output.sh" foundation jumpbox_fqdn) || exit 1
RESOURCE_GROUP=$("$DIR/../infra/output.sh" foundation resource_group_name) || exit 1
VMSS_NAME=$("$DIR/../infra/output.sh" platform vmss_name) || exit 1

# Setup how Ansible is going to use the Jumpbox to communicate with the VMSS instances.
# LogLevel=ERROR instead of -q: a failure on the jumpbox hop is printed, not hidden.
echo "[vmss:vars]" > "$DIR/vmss_hosts"
echo "ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ProxyCommand=\"ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -i $KEY -W %h:%p azureuser@$JUMPBOX_DNS\"'" >> "$DIR/vmss_hosts"

# List all instances, obtain their private IP and add those to the inventory
echo "[vmss]" >> "$DIR/vmss_hosts"
az vmss nic list --resource-group "$RESOURCE_GROUP" --vmss-name "$VMSS_NAME" --query [].ipConfigurations[].privateIPAddress -o tsv | tr "\t" "\n" >> "$DIR/vmss_hosts"
