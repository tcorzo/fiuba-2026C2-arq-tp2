#!/bin/bash
OLD_DIR="$(pwd)"
DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd $DIR

# vmss_setup.yml installs the Datadog agent with this key. It never touches disk.
if [ -z "${DATADOG_API_KEY:-}" ]; then
  echo "DATADOG_API_KEY is not set. Export your Datadog API key first." >&2
  exit 1
fi

# The site the key belongs to. No default: a wrong site drops the data silently.
if [ -z "${DATADOG_SITE:-}" ]; then
  echo "DATADOG_SITE is not set. Export your Datadog site first (e.g. us5.datadoghq.com)." >&2
  exit 1
fi

./update_vmss_inventory.sh || exit 1
ansible-playbook -i vmss_hosts --private-key ../key.pem -u azureuser ./vmss_setup.yml

cd $OLD_DIR
