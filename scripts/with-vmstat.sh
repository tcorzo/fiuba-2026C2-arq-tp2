#!/bin/bash
# Runs a command, usually the load test, while vmstat records the load
# generator's CPU into <file>. If the generator saturates, the test measures the
# generator and not the service. Same command as the 1-node run's
# generador-vmstat.txt (ebf1f58): vmstat -t 5, in local time.
#
# It also takes the kernel's TCP counters right before and right after the
# command, on the generator and on every VMSS instance, into two files next to
# <file> (generador-vmstat becomes generador-tcp-counters and
# nodo-tcp-counters). The 1-node runs needed them to tell the generator's limits
# from the service's: requests that time out without the node opening a
# connection never reached it (4a679f3, 353902f). Same counters as those runs.
#
# Prints the run's UTC window at the end, for capture-run-evidence.sh.
#
# Usage: scripts/with-vmstat.sh <file> <command...>
#   <file>'s name must contain generador-vmstat.
#   scripts/with-vmstat.sh evidencia/scaled/generador-vmstat.txt \
#     mise run perf:run baseline results/scaled/baseline-ramp ramp
set -uo pipefail

if [ $# -lt 2 ]; then
  echo "usage: $0 <file> <command...>" >&2
  exit 2
fi

FILE=$1
shift
DIR=$(dirname "$FILE")
BASE=$(basename "$FILE")
case "$BASE" in
  *generador-vmstat*) ;;
  *)
    echo "$BASE must contain generador-vmstat: the counter files are named after it." >&2
    exit 2
    ;;
esac
GEN_TCP="$DIR/${BASE/generador-vmstat/generador-tcp-counters}"
NODE_TCP="$DIR/${BASE/generador-vmstat/nodo-tcp-counters}"
for f in "$FILE" "$GEN_TCP" "$NODE_TCP"; do
  if [ -e "$f" ]; then
    echo "$f exists. Evidence is never overwritten." >&2
    exit 1
  fi
done
mkdir -p "$DIR"

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
gen_counters() {
  date -u
  echo '$ nstat -az TcpActiveOpens TcpAttemptFails TcpExtTCPSynRetrans'
  nstat -az TcpActiveOpens TcpAttemptFails TcpExtTCPSynRetrans
}
# Ansible heads each instance's output with its private IP.
node_counters() {
  ansible vmss -i "$ROOT/ansible/vmss_hosts" --private-key "$ROOT/key.pem" -u azureuser \
    -m shell -a 'date -u; echo "$ nstat -az TcpPassiveOpens TcpExtTCPSynRetrans TcpExtListenOverflows TcpExtListenDrops TcpExtTCPReqQFullDrop TcpExtSyncookiesSent"; nstat -az TcpPassiveOpens TcpExtTCPSynRetrans TcpExtListenOverflows TcpExtListenDrops TcpExtTCPReqQFullDrop TcpExtSyncookiesSent'
}

# Every instance the VMSS has now, not the ones a stale inventory remembers.
"$ROOT/ansible/update_vmss_inventory.sh" >/dev/null || exit 1
{ echo "== before"; node_counters; } >"$NODE_TCP" || exit 1
{ echo "== before"; gen_counters; } >"$GEN_TCP"

START=$(date -u +%FT%TZ)
vmstat -t 5 >"$FILE" &
VMSTAT=$!
"$@"
STATUS=$?
kill "$VMSTAT"
END=$(date -u +%FT%TZ)

{ echo "== after"; gen_counters; } >>"$GEN_TCP"
{ echo "== after"; node_counters; } >>"$NODE_TCP"

echo "Run window (UTC): $START $END" >&2
exit "$STATUS"
