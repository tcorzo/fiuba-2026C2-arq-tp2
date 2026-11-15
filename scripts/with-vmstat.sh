#!/bin/bash
# Runs a command, usually the load test, while vmstat records the load
# generator's CPU into <file>. If the generator saturates, the test measures the
# generator and not the service. Same command as the 1-node run's
# generador-vmstat.txt (ebf1f58): vmstat -t 5, in local time.
#
# Prints the run's UTC window at the end, for capture-run-evidence.sh.
#
# Usage: scripts/with-vmstat.sh <file> <command...>
#   scripts/with-vmstat.sh evidencia/scaled/generador-vmstat.txt \
#     mise run perf:run baseline results/scaled/baseline-ramp ramp
set -uo pipefail

if [ $# -lt 2 ]; then
  echo "usage: $0 <file> <command...>" >&2
  exit 2
fi

FILE=$1
shift
if [ -e "$FILE" ]; then
  echo "$FILE exists. Evidence is never overwritten." >&2
  exit 1
fi
mkdir -p "$(dirname "$FILE")"

START=$(date -u +%FT%TZ)
vmstat -t 5 >"$FILE" &
VMSTAT=$!
"$@"
STATUS=$?
kill "$VMSTAT"
END=$(date -u +%FT%TZ)

echo "Run window (UTC): $START $END" >&2
exit "$STATUS"
