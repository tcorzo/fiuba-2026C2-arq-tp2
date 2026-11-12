// Runtime settings of the deployed app.
//
// ansible/deploy.sh writes config.local.json (gitignored) from the platform stack's
// app_config output before zipping the app. An environment variable overrides each
// value, and every value has a default, so the app also starts without the file.
// A new setting is a new key in app_config (infra/envs/prd/platform/outputs.tf) and
// a new line below.
import { readFileSync } from "node:fs";

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
};
