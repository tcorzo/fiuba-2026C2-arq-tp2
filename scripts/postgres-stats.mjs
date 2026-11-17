#!/usr/bin/env node
// Prints Postgres's cumulative statistics for the app's database: transactions,
// row writes per table (HOT updates among them) and WAL writes and fsyncs.
// with-vmstat.sh takes it right before and right after a load test; the
// difference between the two is what the test cost Postgres. Divided into the
// CPU that Azure Monitor recorded, it gives the CPU per transaction that the
// scaled case could not measure.
//
// Postgres collects these counters always (track_counts is on by default), so
// reading them changes nothing the server does per request. pg_stat_statements
// would give the time per statement, but this server has
// pg_stat_statements.track = none: turning it on would add a cost that the
// earlier runs did not have.
//
// It runs on one VMSS instance, from the app's directory: Ansible's script
// module copies it there and runs it with node. It reaches the database the way
// the app does, through config.js and the app's own pg. It never prints the
// connection URL, which holds the password.
import { createRequire } from "node:module";
import path from "node:path";
import { pathToFileURL } from "node:url";

const appDir = process.cwd();
const pg = createRequire(path.join(appDir, "package.json"))("pg");
const { default: config } = await import(
  pathToFileURL(path.join(appDir, "config.js")).href
);

// One section per query: the query, then its rows as tab-separated values with
// a header, as psql -A -F $'\t' would print them.
const QUERIES = [
  "SELECT now() AS ts, version()",
  `SELECT datname, numbackends, xact_commit, xact_rollback, deadlocks, conflicts,
          blks_read, blks_hit, tup_returned, tup_fetched,
          tup_inserted, tup_updated, tup_deleted
     FROM pg_stat_database WHERE datname = current_database()`,
  `SELECT relname, seq_scan, idx_scan, n_tup_ins, n_tup_upd, n_tup_hot_upd,
          n_tup_newpage_upd, n_live_tup, n_dead_tup,
          vacuum_count, autovacuum_count, autoanalyze_count
     FROM pg_stat_user_tables ORDER BY relname`,
  "SELECT * FROM pg_stat_wal",
  `SELECT backend_type, context, writes, write_bytes, fsyncs
     FROM pg_stat_io WHERE object = 'wal' ORDER BY backend_type, context`,
];

const client = new pg.Client({ connectionString: config.databaseUrl });
await client.connect();
try {
  for (const query of QUERIES) {
    const { fields, rows } = await client.query(query);
    console.log(`$ ${query.replace(/\s+/g, " ")}`);
    console.log(fields.map((field) => field.name).join("\t"));
    for (const row of rows) {
      console.log(fields.map((field) => format(row[field.name])).join("\t"));
    }
  }
} finally {
  await client.end();
}

function format(value) {
  if (value === null) return "";
  if (value instanceof Date) return value.toISOString();
  return String(value);
}
