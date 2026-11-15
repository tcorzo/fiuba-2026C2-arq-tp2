#!/bin/bash
# The Datadog plugin publishes with this key to this site. Without DATADOG_SITE it
# falls back to US1, which drops the metrics of any other site silently.
for var in DATADOG_API_KEY DATADOG_SITE; do
  if [ -z "${!var:-}" ]; then
    echo "$var is not set. Export it first." >&2
    exit 1
  fi
done

LB_FQDN=$(../infra/output.sh platform lb_fqdn) || exit 1

# Every virtual user opens a new connection, so every request resolves LB_FQDN.
# Artillery's workers are threads of one process and share libuv's 4-thread
# pool, where getaddrinfo runs. Through DNS that capped the generator at ~140
# lookups/s and the 1-node ramp collapsed at 200 rps without a single SYN
# reaching the node. An /etc/hosts entry answers in microseconds, as localhost
# did in tp1. It must exist and match what DNS says now: the IP changes every
# time platform is recreated.
HOSTS_IP=$(getent -s files hosts "$LB_FQDN" | awk '{print $1}')
DNS_IP=$(getent -s dns hosts "$LB_FQDN" | awk '{print $1}')
if [ -z "$HOSTS_IP" ] || [ "$HOSTS_IP" != "$DNS_IP" ]; then
  echo "/etc/hosts must map $LB_FQDN to ${DNS_IP:-its current IP} (has: ${HOSTS_IP:-nothing}). Run:" >&2
  echo "  echo \"$DNS_IP $LB_FQDN\" | sudo tee -a /etc/hosts" >&2
  exit 1
fi
echo "$LB_FQDN -> $HOSTS_IP from /etc/hosts" >&2

export TARGET=http://$LB_FQDN
export DEBUG=plugin:publish-metrics:datadog-statsd
# $3, optional, is the Artillery environment (e.g. baseline.yaml's ramp).
npm run artillery -- run ${3:+-e "$3"} "$1.yaml" --output "$2.json"
