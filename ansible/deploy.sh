#!/bin/bash
OLD_DIR="$(pwd)"
DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd $DIR

if [ ! -r ../key.pem ]; then
  echo "Missing key.pem at the repository root: the private key of the Azure SSH key ssh_key (chmod 400)." >&2
  exit 1
fi

# The app's runtime settings (ARCA's URI, ...) come from the platform stack's
# app_config output. node/config.local.json is gitignored and goes into the zip.
APP_CONFIG=$(../infra/output.sh platform app_config -json) || exit 1
echo "$APP_CONFIG" > ../node/config.local.json

../node/zip.sh
ansible-playbook -i vmss_hosts --private-key ../key.pem -u azureuser vmss_deploy.yml

cd $OLD_DIR
