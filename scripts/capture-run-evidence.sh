#!/bin/bash
# Captures the evidence of a load test after it ends, into <dest-dir>: the
# Azure Monitor metrics of Postgres, the load balancer and ARCA over the test's
# time range, and a snapshot of every instance. Datadog has no agent on the PaaS
# components, so these files are the evidence for naming a bottleneck there.
# Run it right after the test, while the infra still exists: the metrics go away
# with the resources.
#
# The first five files have the names, metrics and shape of the 1-node run's
# (ebf1f58), so every case can be compared file by file with it:
#   postgres-cpu-percent.json, postgres-active-connections.json,
#   postgres-sessions-by-wait-event-type.json, lb-metrics.json, nodo-post-ramp.txt
# The rest extend that set:
#   postgres-cpu-credits-remaining.json  B1ms is burstable: credits that run out slow it down
#   lb-dip-availability-by-backend.json  the probe's view of each instance
#   arca-metrics.json                    ARCA's CPU and memory, which the assignment names
#
# The JSON is what az prints, projected to leave out the resource ids, which
# carry the subscription id. One point per minute (PT1M, Postgres's finest
# grain). The wait-event metrics need the server parameter
# metrics.collector_database_activity on (az-postgres-collector-database-activity.txt).
#
# Usage: scripts/capture-run-evidence.sh <dest-dir> <start> <end>
#   start and end in UTC ISO 8601. Take the run window that with-vmstat.sh
#   prints and add a margin: 2 minutes before, 3 after, as the 1-node run did.
#   scripts/capture-run-evidence.sh evidencia/scaled 2026-11-15T13:58:00Z 2026-11-15T14:12:00Z
set -euo pipefail

if [ $# -ne 3 ]; then
  echo "usage: $0 <dest-dir> <start> <end>" >&2
  exit 2
fi

DEST=$1
START=$2
END=$3
ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RG=$("$ROOT/infra/output.sh" foundation resource_group_name)
PG=$(az postgres flexible-server list -g "$RG" --query "[0].id" -o tsv)
LB=$(az network lb list -g "$RG" --query "[0].id" -o tsv)
ARCA=$(az container list -g "$RG" --query "[0].id" -o tsv)
PROJECTION="{interval:interval, timespan:timespan, value:value[].{name:name.value, unit:unit, timeseries:timeseries}}"

mkdir -p "$DEST"

# Azure Monitor publishes a minute a few minutes after it ends. Captured too
# early, the window's last points come back partial or missing: the 1-node
# capture shows it for its last minutes, which a later query filled in.
READY=$(($(date -d "$END" +%s) + 300))
NOW=$(date +%s)
if [ "$NOW" -lt "$READY" ]; then
  echo "Waiting $((READY - NOW)) s for Azure Monitor to publish the window's last minutes." >&2
  sleep $((READY - NOW))
fi

refuse_existing() {
  if [ -e "$DEST/$1" ]; then
    echo "$DEST/$1 exists. Evidence is never overwritten." >&2
    exit 1
  fi
}

# Prints the names of the metrics in a capture that came back with no series.
empty_metrics() {
  python3 -c 'import json, sys
print(" ".join(m["name"] for m in json.load(open(sys.argv[1]))["value"] if not m["timeseries"]))' "$1"
}

EMPTY=()

# $1 resource id, $2 output file, rest: extra az arguments.
# Azure Monitor sometimes answers the same query with no series at all (seen on
# 2026-11-14: the same load balancer query, run several times in a row, came back
# full or empty at random). Each capture is retried until every metric has
# series, up to 5 times. A metric still empty after that is reported at the end.
metrics() {
  local resource=$1 file=$2 attempt missing
  shift 2
  refuse_existing "$file"
  for attempt in 1 2 3 4 5; do
    az monitor metrics list --resource "$resource" \
      --start-time "$START" --end-time "$END" --interval PT1M \
      --query "$PROJECTION" -o json "$@" >"$DEST/$file"
    missing=$(empty_metrics "$DEST/$file")
    [ -z "$missing" ] && return 0
    [ "$attempt" -lt 5 ] && sleep 5
  done
  EMPTY+=("$file: $missing")
}

metrics "$PG" postgres-cpu-percent.json --metrics cpu_percent --aggregation Average Maximum
metrics "$PG" postgres-active-connections.json --metrics active_connections --aggregation Average Maximum
metrics "$PG" postgres-sessions-by-wait-event-type.json --metrics sessions_by_wait_event_type \
  --aggregation Average Maximum --filter "WaitEventType eq '*'"
metrics "$LB" lb-metrics.json --aggregation Average Maximum Total \
  --metrics VipAvailability DipAvailability SYNCount PacketCount ByteCount

metrics "$PG" postgres-cpu-credits-remaining.json --metrics cpu_credits_remaining \
  --aggregation Average Maximum
metrics "$LB" lb-dip-availability-by-backend.json --metrics DipAvailability \
  --aggregation Average Maximum --filter "BackendIPAddress eq '*'"
metrics "$ARCA" arca-metrics.json --metrics CpuUsage MemoryUsage --aggregation Average Maximum

# The same commands as the 1-node nodo-post-ramp.txt, on every instance. Ansible
# heads each instance's output with its private IP.
refuse_existing nodo-post-ramp.txt
"$ROOT/ansible/update_vmss_inventory.sh"
ansible vmss -i "$ROOT/ansible/vmss_hosts" --private-key "$ROOT/key.pem" -u azureuser \
  -m script -a "$ROOT/scripts/node-post-run.sh" >"$DEST/nodo-post-ramp.txt"

if grep -l 'subscriptions/' "$DEST"/*.json; then
  echo "The files above carry the subscription id. Fix the projection before committing." >&2
  exit 1
fi
ls -1 "$DEST"
if [ ${#EMPTY[@]} -gt 0 ]; then
  printf 'No series after 5 attempts, %s\n' "${EMPTY[@]}" >&2
  echo "Expected only for the wait events with metrics.collector_database_activity off. Otherwise delete those files and run again." >&2
  exit 1
fi
