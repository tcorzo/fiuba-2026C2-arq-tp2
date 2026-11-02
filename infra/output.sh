#!/bin/bash
# Prints one output of a prd stack, read from its HCP Terraform workspace. The value
# is always the one in the latest applied state, so nothing goes stale on disk, and
# any member logged in with `terraform login` can read it without applying.
#
# Usage: infra/output.sh <stack> <output> [-raw|-json]   (default -raw)
#   infra/output.sh platform lb_fqdn
#   infra/output.sh platform app_config -json
set -euo pipefail

if [ $# -lt 2 ]; then
  echo "usage: $0 <stack> <output> [-raw|-json]" >&2
  exit 2
fi

stack=$1
name=$2
format=${3:--raw}
dir="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)/envs/prd/$stack"

# A stack that was never initialized against HCP Terraform (or only with
# -backend=false, as infra:validate does) can't read its outputs yet.
if [ ! -f "$dir/.terraform/terraform.tfstate" ]; then
  terraform -chdir="$dir" init -input=false >&2
fi

terraform -chdir="$dir" output "$format" "$name"
