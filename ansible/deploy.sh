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
HTTPS_PORT=$(node -p 'require("../node/config.local.json").httpsPort') || exit 1

# The app refuses to start without its TLS pair (H-38), and the pair must name
# the LB's current FQDN, which changes when platform recreates the public IP.
LB_FQDN=$(../infra/output.sh platform lb_fqdn) || exit 1
if [ ! -r ../certs/server.crt ] || [ ! -r ../certs/server.key ] ||
  ! openssl x509 -in ../certs/server.crt -noout -checkhost "$LB_FQDN" | grep -q 'does match'; then
  echo "certs/ has no certificate for $LB_FQDN. Run: mise run app:certs" >&2
  exit 1
fi

../node/zip.sh
ansible-playbook -i vmss_hosts --private-key ../key.pem -u azureuser \
  -e app_https_port="$HTTPS_PORT" vmss_deploy.yml

cd $OLD_DIR
