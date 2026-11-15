// Runtime settings of the deployed app.
//
// ansible/deploy.sh writes config.local.json (gitignored) from the platform stack's
// app_config output before zipping the app. An environment variable overrides each
// value, and every value has a default, so the app also starts without the file.
// A new setting is a new key in app_config (infra/envs/prd/platform/outputs.tf) and
// a new line below.
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

function readGenerated() {
  try {
    return JSON.parse(readFileSync(new URL("./config.local.json", import.meta.url), "utf8"));
  } catch (error) {
    if (error.code === "ENOENT") return {};
    throw error;
  }
}

const generated = readGenerated();

export default {
  // Base URI of the ARCA service
  arcaUri: process.env.ARCA_URI ?? generated.arcaUri ?? "",
  // How long a DNI validation waits for ARCA before answering 502. ARCA's
  // slowest observed answer was 502 ms (issue #14).
  arcaTimeoutMs: Number(process.env.ARCA_TIMEOUT_MS ?? generated.arcaTimeoutMs ?? 2000),
  // Connection URL of the PostgreSQL store. Without one, pg falls back to
  // localhost:5432, as it did in tp1's Docker Compose.
  databaseUrl: process.env.DATABASE_URL ?? generated.databaseUrl ?? "",
  // How many connections each process opens to Postgres, at most. A request
  // that finds them all busy waits in the process for one. 10 is pg's own
  // default, which every run before this setting used.
  dbPoolMax: Number(process.env.DB_POOL_MAX ?? generated.dbPoolMax ?? 10),
  // Where metrics.js sends its metrics: the Datadog agent's DogStatsD, which
  // Ansible installs on every VMSS instance and which listens on loopback
  // only. tp1 defaulted to "graphite", its Compose service, which does not
  // resolve here: every metric was dropped without an error.
  metricsHost: process.env.METRICS_HOST ?? generated.metricsHost ?? "127.0.0.1",
  metricsPort: Number(process.env.METRICS_PORT ?? generated.metricsPort ?? 8125),
  // H-38: the process terminates TLS. The load balancer forwards 443 to
  // httpsPort and 80 to redirectPort, which only answers 308 to HTTPS.
  httpsPort: Number(process.env.HTTPS_PORT ?? generated.httpsPort ?? 3443),
  redirectPort: Number(process.env.REDIRECT_PORT ?? generated.redirectPort ?? 3080),
  // The self-signed pair from `mise run app:certs`. ansible/vmss_deploy.yml
  // copies it next to the app, outside the zip, so it never enters git.
  tlsCertPath:
    process.env.TLS_CERT_PATH ?? fileURLToPath(new URL("./tls/server.crt", import.meta.url)),
  tlsKeyPath:
    process.env.TLS_KEY_PATH ?? fileURLToPath(new URL("./tls/server.key", import.meta.url)),
};
