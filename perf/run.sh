#!/bin/bash
LB_FQDN=$(../infra/output.sh platform lb_fqdn) || exit 1
export TARGET=http://$LB_FQDN
export DEBUG=plugin:publish-metrics:datadog-statsd
npm run artillery -- run $1.yaml --output $2.json
