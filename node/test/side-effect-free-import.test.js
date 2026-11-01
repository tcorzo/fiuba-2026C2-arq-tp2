import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { readdirSync, readFileSync } from "node:fs";
import path from "node:path";
import { describe, test } from "node:test";
import { fileURLToPath } from "node:url";

const appDir = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const stateDir = path.join(appDir, "state");

// The process entry point: the one module whose job is to have effects.
const ENTRY_POINT = "server.js";

// Longer than any save period in state.js, so a store started by the import
// would rewrite at least one file before the process is killed.
const IMPORT_TIMEOUT_MS = 6000;

function stateDigest() {
  const hash = createHash("sha256");
  for (const file of readdirSync(stateDir).sort()) {
    hash.update(file).update(readFileSync(path.join(stateDir, file)));
  }
  return hash.digest("hex");
}

// Imports the module in a process of its own, as a test file would, and
// reports whether that process ends by itself.
function importAlone(file) {
  return spawnSync(
    process.execPath,
    ["--input-type=module", "-e", `await import("./${file}")`],
    {
      cwd: appDir,
      env: { ...process.env, METRICS_ENABLED: "false" },
      timeout: IMPORT_TIMEOUT_MS,
      encoding: "utf8",
    },
  );
}

const modules = readdirSync(appDir)
  .filter((file) => file.endsWith(".js") && file !== ENTRY_POINT)
  .sort();

describe("H-21", () => {
  for (const file of modules) {
    test(`importing ${file} has no side effects`, () => {
      const before = stateDigest();
      const result = importAlone(file);

      // Every effect is collected before asserting, so one run names them all.
      const effects = [];
      if (result.signal !== null) {
        effects.push(`kept the process alive: killed after ${IMPORT_TIMEOUT_MS} ms`);
      } else if (result.status !== 0) {
        effects.push(`exited ${result.status}: ${result.stderr.trim()}`);
      }
      if (/listening/i.test(result.stdout)) {
        effects.push(`started a server: "${result.stdout.trim()}"`);
      }
      if (stateDigest() !== before) {
        effects.push("rewrote node/state/");
      }

      assert.deepEqual(effects, []);
    });
  }
});
