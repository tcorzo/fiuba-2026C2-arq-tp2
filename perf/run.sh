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
export TARGET=http://$LB_FQDN
export DEBUG=plugin:publish-metrics:datadog-statsd
# $3, optional, is the Artillery environment (e.g. baseline.yaml's ramp).
npm run artillery -- run ${3:+-e "$3"} "$1.yaml" --output "$2.json"
