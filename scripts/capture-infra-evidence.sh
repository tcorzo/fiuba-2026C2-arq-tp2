#!/bin/bash
# Captures the infra evidence of the deployed configuration into evidencia/<case>/,
# as CLAUDE.md asks for every measured case: terraform state list and output of
# each stack, the VMSS and its instances, the load balancer, Postgres, the ARCA
# container, and the runtime of every instance.
#
# The file names, commands and columns are those of evidencia/1-node/measured/
# (a3c51fe), so every case can be compared file by file with the 1-node one.
#
# Each file is the command's output as written, with two exceptions decided
# here and not afterwards: vmss_subnet_id is left out of the foundation outputs
# (it carries the subscription id), and nodo-runtime.txt is Ansible's output,
# which heads each instance with its private IP.
#
# Usage: scripts/capture-infra-evidence.sh <case> [dest-dir]
#   scripts/capture-infra-evidence.sh escalado   # writes evidencia/escalado/
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "usage: $0 <case> [dest-dir]" >&2
  exit 2
fi

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST=${2:-$ROOT/evidencia/$1}
OUTPUT="$ROOT/infra/output.sh"

if [ -e "$DEST" ] && [ -n "$(ls -A "$DEST")" ]; then
  echo "$DEST is not empty. Evidence is never overwritten: pick another case name." >&2
  exit 1
fi
mkdir -p "$DEST"

RG=$("$OUTPUT" foundation resource_group_name)
VMSS=$("$OUTPUT" platform vmss_name)
LB=$(az network lb list -g "$RG" --query "[0].name" -o tsv)
PG=$(az postgres flexible-server list -g "$RG" --query "[0].name" -o tsv)
ARCA=$(az container list -g "$RG" --query "[0].name" -o tsv)

for stack in foundation platform; do
  terraform -chdir="$ROOT/infra/envs/prd/$stack" state list \
    >"$DEST/terraform-state-list-$stack.txt"
  terraform -chdir="$ROOT/infra/envs/prd/$stack" output -no-color |
    grep -v '^vmss_subnet_id = ' >"$DEST/terraform-output-$stack.txt"
done

az vmss list-instances -g "$RG" -n "$VMSS" -o table --query \
  "[].{Name:name, InstanceId:instanceId, Sku:sku.name, Location:location, State:provisioningState, LatestModel:latestModelApplied}" \
  >"$DEST/az-vmss-list-instances.txt"
az vmss show -g "$RG" -n "$VMSS" -o table --query \
  "{Name:name, Sku:sku.name, Capacity:sku.capacity, Location:location, UpgradeMode:upgradePolicy.mode}" \
  >"$DEST/az-vmss-show.txt"
az network lb rule list -g "$RG" --lb-name "$LB" -o table --query \
  "[].{Name:name, Protocol:protocol, FrontendPort:frontendPort, BackendPort:backendPort, IdleTimeoutMinutes:idleTimeoutInMinutes, Distribution:loadDistribution}" \
  >"$DEST/az-lb-rule.txt"
az network lb probe list -g "$RG" --lb-name "$LB" -o table --query \
  "[].{Name:name, Protocol:protocol, Port:port, IntervalSeconds:intervalInSeconds, Threshold:probeThreshold}" \
  >"$DEST/az-lb-probe.txt"
az postgres flexible-server show -g "$RG" -n "$PG" -o table --query \
  "{Version:version, Sku:sku.name, Tier:sku.tier, StorageGb:storage.storageSizeGb, PublicAccess:network.publicNetworkAccess, Location:location}" \
  >"$DEST/az-postgres-show.txt"
az postgres flexible-server parameter show -g "$RG" -s "$PG" -n max_connections -o table \
  --query "{Name:name, Value:value}" >"$DEST/az-postgres-max-connections.txt"
# Without it, the wait-event metrics of evidence:run come back empty.
az postgres flexible-server parameter show -g "$RG" -s "$PG" -n metrics.collector_database_activity \
  -o table --query "{Name:name, Value:value, Source:source}" \
  >"$DEST/az-postgres-collector-database-activity.txt"
az container show -g "$RG" -n "$ARCA" -o table --query \
  "{Image:containers[0].image, Cpu:containers[0].resources.requests.cpu, MemoryGb:containers[0].resources.requests.memoryInGb, IpType:ipAddress.type, Port:ipAddress.ports[0].port, RestartPolicy:restartPolicy, Location:location}" \
  >"$DEST/az-arca-container-show.txt"

# Every instance the VMSS has now, not the ones a stale inventory remembers.
"$ROOT/ansible/update_vmss_inventory.sh"
ansible vmss -i "$ROOT/ansible/vmss_hosts" --private-key "$ROOT/key.pem" -u azureuser \
  -m shell -a 'nproc; free -m; node -v; pm2 -v' \
  >"$DEST/nodo-runtime.txt"

# A public repo: stop before anything that names the subscription or a secret
# reaches a commit. Reading every file is still required.
if grep -rEil 'subscriptions/|password|postgres(ql)?://|api[_-]?key' "$DEST"; then
  echo "The files above may hold a secret or the subscription id. Read them before committing." >&2
  exit 1
fi
empty=$(find "$DEST" -type f -empty)
if [ -n "$empty" ]; then
  echo "Empty evidence files: $empty" >&2
  exit 1
fi
ls -1 "$DEST"
