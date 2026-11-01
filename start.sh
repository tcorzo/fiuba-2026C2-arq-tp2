#!/bin/bash

DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$DIR/infra"

if [ ! -r "$INFRA_DIR/terraform.tfvars" ]; then
  echo "Could not find 'infra/terraform.tfvars'. Create it before running this script (see README)."
  exit 1
fi

if [ ! -d "$INFRA_DIR/.terraform" ]; then
  echo "Could not find 'infra/.terraform/'. Initializing terraform..."
  terraform -chdir="$INFRA_DIR" init
fi

# Sign in to Azure
echo "##### Logging into Azure #####"
az login

# Create infrastructure. This also sets ARCA service's IP in the node app so that they can communicate
# The -auto-approve flag makes it not to ask for plan approval. Use at your own risk!
echo "##### Applying terraform infrastructure #####"
terraform -chdir="$INFRA_DIR" apply -auto-approve

# Setup the node instances
echo "##### Installing software on VMSS #####"
$DIR/ansible/setup.sh

# Finally, we update the node instances code with the src code
echo "##### Deploying node app to VMSS #####"
$DIR/ansible/deploy.sh

echo "##### Finished #####"
