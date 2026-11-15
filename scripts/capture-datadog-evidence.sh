#!/bin/bash
# Exports the service's Datadog series over a load test's time range, and the
# dashboard's definition, into <dest-dir>. Section 7 and later cite server-side
# numbers that otherwise live only in Datadog, which outlives nothing we keep.
#
# The queries are those of the final 1-node run (0cdcf5c, 8c42031), one file per
# query, raw `pup metrics query` output with its envelope. Two of them group by
# host instead of naming one, so they cover any instance count:
#   datadog-cpu-<run>.json             user + system CPU of every instance
#                                      (1-node: the same sum on tp2vmss000000)
#   datadog-eventloop-lag-max-<run>.json  unchanged, already by host
# One extends that set:
#   datadog-http-responses-by-host-<run>.json  responses per instance
#
# Usage: scripts/capture-datadog-evidence.sh <dest-dir> <run> <start> <end> <dashboard-file>
#   <run> names the files, e.g. pool-ramp. <dashboard-file> goes next to the
#   Artillery report, as in perf/results/1-node/2026-11-15/dashboard.json.
#   start and end in UTC ISO 8601: the 1-node run used about 15 s before the
#   test and a minute after it.
#   scripts/capture-datadog-evidence.sh evidencia/scaled/2026-11-15 pool-ramp \
#     2026-11-15T16:00:30Z 2026-11-15T16:14:30Z perf/results/scaled/2026-11-15/dashboard.json
set -euo pipefail

if [ $# -ne 5 ]; then
  echo "usage: $0 <dest-dir> <run> <start> <end> <dashboard-file>" >&2
  exit 2
fi

DEST=$1
RUN=$2
FROM=$(date -d "$3" +%s)
TO=$(date -d "$4" +%s)
DASHBOARD_FILE=$5
DASHBOARD_ID=d46-yiz-n26

mkdir -p "$DEST"

# Datadog publishes the last seconds of a window late: the 1-node exports miss
# their last 30 s, which a later query filled in.
READY=$((TO + 120))
NOW=$(date +%s)
if [ "$NOW" -lt "$READY" ]; then
  echo "Waiting $((READY - NOW)) s for Datadog to publish the window's last points." >&2
  sleep $((READY - NOW))
fi

refuse_existing() {
  if [ -e "$DEST/$1" ]; then
    echo "$DEST/$1 exists. Evidence is never overwritten." >&2
    exit 1
  fi
}

# $1 file name without -<run>.json, $2 query.
series() {
  local file="$1-$RUN.json"
  refuse_existing "$file"
  pup metrics query --read-only -o json --from "$FROM" --to "$TO" --query "$2" >"$DEST/$file"
}

series datadog-http-responses 'sum:arvault.http.responses{*} by {route}.as_count()'
series datadog-http-responses-by-host 'sum:arvault.http.responses{*} by {host}.as_count()'
series datadog-http-duration-p50 'p50:arvault.http.duration{*} by {route}'
series datadog-arca-validation-p50 'p50:arvault.arca.validation.duration{*}'
series datadog-exchange-processing-p50 'p50:arvault.exchange.processing.duration{*}'
series datadog-eventloop-lag-max 'max:arvault.runtime.eventloop.lag.max{*} by {host}'
series datadog-cpu 'avg:system.cpu.user{host:tp2vmss*} by {host} + avg:system.cpu.system{host:tp2vmss*} by {host}'

if [ -e "$DASHBOARD_FILE" ]; then
  echo "$DASHBOARD_FILE exists. Evidence is never overwritten." >&2
  exit 1
fi
mkdir -p "$(dirname "$DASHBOARD_FILE")"
pup dashboards get "$DASHBOARD_ID" --read-only --no-envelope -o json >"$DASHBOARD_FILE"

empty=$(find "$DEST" -name "datadog-*-$RUN.json" -size -200c)
if [ -n "$empty" ]; then
  echo "Suspiciously small exports, check them: $empty" >&2
  exit 1
fi
ls -1 "$DEST"/datadog-*-"$RUN".json "$DASHBOARD_FILE"
