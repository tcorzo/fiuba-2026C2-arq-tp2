import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import path from "node:path";
import { describe, test } from "node:test";
import { fileURLToPath } from "node:url";

const appDir = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");

// config.js reads the environment once, when it is imported, so each case
// imports it in a process of its own.
function configWith(env) {
  const result = spawnSync(
    process.execPath,
    [
      "--input-type=module",
      "-e",
      'const { default: c } = await import("./config.js"); console.log(JSON.stringify(c));',
    ],
    { cwd: appDir, env: { PATH: process.env.PATH, ...env }, encoding: "utf8" },
  );
  assert.equal(result.status, 0, result.stderr);
  return JSON.parse(result.stdout);
}

describe("config", () => {
  test("DATABASE_URL overrides the deployed databaseUrl", () => {
    const url = "postgres://exchange:exchange@db:5432/exchange";
    assert.equal(configWith({ DATABASE_URL: url }).databaseUrl, url);
  });

  test("ARCA_URI overrides the deployed arcaUri", () => {
    const uri = "http://arca.test:8080";
    assert.equal(configWith({ ARCA_URI: uri }).arcaUri, uri);
  });

  test("the ARCA timeout defaults to 2000 ms", () => {
    assert.equal(configWith({}).arcaTimeoutMs, 2000);
  });

  test("ARCA_TIMEOUT_MS overrides the deployed arcaTimeoutMs", () => {
    assert.equal(configWith({ ARCA_TIMEOUT_MS: "750" }).arcaTimeoutMs, 750);
  });

  test("TLS listens on 3443 and the redirect on 3080 by default", () => {
    const config = configWith({});
    assert.equal(config.httpsPort, 3443);
    assert.equal(config.redirectPort, 3080);
  });

  test("HTTPS_PORT and REDIRECT_PORT override the deployed ports", () => {
    const config = configWith({ HTTPS_PORT: "8443", REDIRECT_PORT: "8080" });
    assert.equal(config.httpsPort, 8443);
    assert.equal(config.redirectPort, 8080);
  });

  test("the certificate pair lives in tls/ next to the app by default", () => {
    const config = configWith({});
    assert.equal(config.tlsCertPath, path.join(appDir, "tls", "server.crt"));
    assert.equal(config.tlsKeyPath, path.join(appDir, "tls", "server.key"));
  });

  test("TLS_CERT_PATH and TLS_KEY_PATH override the pair's paths", () => {
    const config = configWith({ TLS_CERT_PATH: "/c.crt", TLS_KEY_PATH: "/c.key" });
    assert.equal(config.tlsCertPath, "/c.crt");
    assert.equal(config.tlsKeyPath, "/c.key");
  });

  test("metrics go to the local Datadog agent by default", () => {
    const config = configWith({});
    assert.equal(config.metricsHost, "127.0.0.1");
    assert.equal(config.metricsPort, 8125);
  });
});
