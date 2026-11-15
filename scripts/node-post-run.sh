#!/bin/sh
# Runs on each VMSS instance after a load test; capture-run-evidence.sh copies it
# to each instance with Ansible's script module, so it is POSIX sh. Did the app restart, and did
# the kernel drop connections before the app saw them?
date -u
echo '$ pm2 jlist (name, restarts, uptime start, status)'
pm2 jlist | node -e '
let s = "";
process.stdin.on("data", (d) => (s += d)).on("end", () => {
  for (const p of JSON.parse(s)) {
    const start = new Date(p.pm2_env.pm_uptime).toISOString().replace(/\.\d+Z$/, "Z");
    console.log([p.name, p.pm2_env.restart_time, start, p.pm2_env.status].join("\t"));
  }
});'
echo '$ nstat -az TcpExtListenOverflows TcpExtListenDrops TcpExtTCPReqQFullDrop TcpExtSyncookiesSent'
nstat -az TcpExtListenOverflows TcpExtListenDrops TcpExtTCPReqQFullDrop TcpExtSyncookiesSent
echo '$ sysctl net.core.somaxconn net.ipv4.tcp_max_syn_backlog'
sysctl net.core.somaxconn net.ipv4.tcp_max_syn_backlog
