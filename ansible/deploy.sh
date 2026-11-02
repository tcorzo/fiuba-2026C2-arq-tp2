#!/bin/bash
OLD_DIR="$(pwd)"
DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd $DIR

# The app's runtime settings (ARCA's URI, ...) come from the platform stack's
# app_config output. node/config.local.json is gitignored and goes into the zip.
APP_CONFIG=$(../infra/output.sh platform app_config -json) || exit 1
echo "$APP_CONFIG" > ../node/config.local.json

../node/zip
ansible-playbook -i vmss_hosts --private-key ../key.pem -u azureuser vmss_deploy.yml

cd $OLD_DIR
