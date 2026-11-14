import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import dgram from "node:dgram";
import { once } from "node:events";
import path from "node:path";
import { describe, test } from "node:test";
import { fileURLToPath } from "node:url";

const appDir = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");

// metrics.js builds its client when it is imported, from the environment, so
// each case runs it in a process of its own and listens where it sends: a UDP
// socket standing in for the Datadog agent's DogStatsD.
async function datagramsFrom(script) {
  const agent = dgram.createSocket("udp4");
  agent.bind(0, "127.0.0.1");
  await once(agent, "listening");
  const lines = [];
  agent.on("message", (message) => {
    lines.push(...message.toString().split("\n").filter(Boolean));
  });

  const child = spawn(
    process.execPath,
    [
      "--input-type=module",
      "-e",
      `const m = await import("./metrics.js"); ${script}; await new Promise((r) => setTimeout(r, 400));`,
    ],
    {
      cwd: appDir,
      env: {
        PATH: process.env.PATH,
        METRICS_ENABLED: "true",
        METRICS_PORT: String(agent.address().port),
      },
      stdio: "inherit",
    },
  );
  const [code] = await once(child, "exit");
  // Datagrams already received; give the socket a moment for the last flush.
  await new Promise((resolve) => setTimeout(resolve, 50));
  agent.close();
  assert.equal(code, 0);
  return lines;
}

describe("metrics", () => {
  test("reach the agent on 127.0.0.1 with no METRICS_HOST set", async () => {
    const lines = await datagramsFrom('m.recordExchangeDuration(354)');
    assert.deepEqual(lines, ["arvault.exchange.processing.duration:354|d"]);
  });

  test("carry the route and the status as tags, not in the name", async () => {
    const lines = await datagramsFrom(
      'm.recordHttpDuration("exchange_post", 12); m.countHttpStatus("exchange_post", 502)',
    );
    assert.deepEqual(lines, [
      "arvault.http.duration:12|d|#route:exchange_post",
      "arvault.http.responses:1|c|#route:exchange_post,status:502",
    ]);
  });

  test("count each ARCA validation by outcome", async () => {
    const lines = await datagramsFrom(
      'm.recordArcaValidationDuration(371); m.countArcaValidation("approved")',
    );
    assert.deepEqual(lines, [
      "arvault.arca.validation.duration:371|d",
      "arvault.arca.validation.outcomes:1|c|#outcome:approved",
    ]);
  });
});
