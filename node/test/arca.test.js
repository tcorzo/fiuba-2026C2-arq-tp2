import assert from "node:assert/strict";
import { createServer } from "node:http";
import { after, before, beforeEach, describe, test } from "node:test";

import { createArcaClient } from "../arca.js";
import { ArcaRejectedError, ArcaUnavailableError } from "../errors.js";
import { createApp } from "../http.js";
import { fakeArca, memoryService } from "./helpers.js";

function seed() {
  return {
    accounts: [
      { id: 1, currency: "ARS", balance: 1_000_000 },
      { id: 2, currency: "USD", balance: 1_000 },
    ],
    rates: { ARS: { USD: 0.001 } },
    log: [],
  };
}

const request = {
  baseCurrency: "ARS",
  counterCurrency: "USD",
  baseAccountId: 101,
  counterAccountId: 102,
  baseAmount: 1000,
  dni: "12345678",
};

// Captures what console.log writes while fn runs.
async function logLines(fn) {
  const lines = [];
  const original = console.log;
  console.log = (...args) => lines.push(args.join(" "));
  try {
    return { result: await fn(), lines };
  } catch (error) {
    return { error, lines };
  } finally {
    console.log = original;
  }
}

// ── The HTTP adapter, against a fake ARCA server ────────────────────────────

describe("ARCA adapter", () => {
  let server;
  let uri;
  // What the fake ARCA does with the next request: (req, res, body) => void.
  let answer;
  let received;

  before(async () => {
    server = createServer((req, res) => {
      let raw = "";
      req.on("data", (chunk) => (raw += chunk));
      req.on("end", () => {
        received = { method: req.method, url: req.url, body: raw };
        answer(req, res);
      });
    });
    server.listen(0);
    await new Promise((resolve) => server.once("listening", resolve));
    uri = `http://127.0.0.1:${server.address().port}`;
  });

  after(() => {
    server.closeAllConnections();
    server.close();
  });

  function json(status, body) {
    return (req, res) => {
      res.writeHead(status, { "content-type": "application/json" });
      res.end(typeof body === "string" ? body : JSON.stringify(body));
    };
  }

  const client = () => createArcaClient({ uri, timeoutMs: 200 });

  test("sends POST /validar with { dni } and returns the approval", async () => {
    answer = json(200, { ok: true, codigoAutorizacion: "a1b2" });

    const validation = await client().validate("12345678");

    assert.deepEqual(validation, { ok: true, authorizationCode: "a1b2" });
    assert.equal(received.method, "POST");
    assert.equal(received.url, "/validar");
    assert.deepEqual(JSON.parse(received.body), { dni: "12345678" });
  });

  test("a trailing slash on the base URI still reaches /validar", async () => {
    answer = json(200, { ok: true, codigoAutorizacion: "a1b2" });

    await createArcaClient({ uri: `${uri}/`, timeoutMs: 200 }).validate("12345678");

    assert.equal(received.url, "/validar");
  });

  test("ok: false is a rejection", async () => {
    answer = json(200, { ok: false, codigoAutorizacion: null });

    assert.deepEqual(await client().validate("99999999"), { ok: false });
  });

  test("a 500 with an empty body is ARCA unavailable", async () => {
    answer = (req, res) => {
      res.writeHead(500);
      res.end();
    };

    await assert.rejects(client().validate("12345678"), (error) => {
      assert.ok(error instanceof ArcaUnavailableError);
      assert.equal(error.reason, "status_500");
      return true;
    });
  });

  test("any other non-200 is ARCA unavailable", async () => {
    answer = json(400, { error: "dni" });

    await assert.rejects(client().validate("12345678"), ArcaUnavailableError);
  });

  test("no answer within the timeout is ARCA unavailable", async () => {
    answer = () => {}; // never answers

    const startedAt = Date.now();
    await assert.rejects(client().validate("12345678"), (error) => {
      assert.ok(error instanceof ArcaUnavailableError);
      assert.equal(error.reason, "timeout");
      return true;
    });
    assert.ok(Date.now() - startedAt < 1000, "the timeout did not cut the call");
  });

  for (const [label, body] of [
    ["a body that is not JSON", "<html>"],
    ["a body without ok", { codigoAutorizacion: "a1b2" }],
    ["a string ok", { ok: "true", codigoAutorizacion: "a1b2" }],
    ["an approval without a code", { ok: true, codigoAutorizacion: null }],
  ]) {
    test(`${label} is ARCA unavailable`, async () => {
      answer = json(200, body);

      await assert.rejects(client().validate("12345678"), (error) => {
        assert.ok(error instanceof ArcaUnavailableError);
        assert.equal(error.reason, "malformed_body");
        return true;
      });
    });
  }

  test("an unreachable ARCA is ARCA unavailable", async () => {
    const closed = createServer();
    closed.listen(0);
    await new Promise((resolve) => closed.once("listening", resolve));
    const port = closed.address().port;
    await new Promise((resolve) => closed.close(resolve));

    await assert.rejects(
      createArcaClient({ uri: `http://127.0.0.1:${port}`, timeoutMs: 200 }).validate("12345678"),
      ArcaUnavailableError,
    );
  });
});

// ── The exchange service, with a fake ARCA port ─────────────────────────────

describe("the exchange validates the DNI before it operates", () => {
  function build(arca) {
    const state = seed();
    const transfers = [];
    const service = memoryService(
      state,
      async (...args) => {
        transfers.push(args);
        return true;
      },
      arca,
    );
    return { service, state, transfers };
  }

  test("approved: the exchange runs and returns the authorization code", async () => {
    const arca = fakeArca({ ok: true, authorizationCode: "a1b2" });
    const { service, state } = build(arca);

    const { result, lines } = await logLines(() => service.exchange({ ...request }));

    assert.equal(result.ok, true);
    assert.equal(result.codigoAutorizacion, "a1b2");
    assert.deepEqual(arca.calls, ["12345678"]);
    assert.equal(state.log.length, 1);
    assert.deepEqual(lines, ["arca.validation approved codigoAutorizacion=a1b2"]);
  });

  for (const [label, answer, ErrorType, line] of [
    ["rejected", { ok: false }, ArcaRejectedError, "arca.validation rejected"],
    [
      "unavailable",
      new ArcaUnavailableError("status_500"),
      ArcaUnavailableError,
      "arca.validation error reason=status_500",
    ],
    [
      "a port that throws anything else",
      new TypeError("fetch failed"),
      ArcaUnavailableError,
      "arca.validation error reason=unexpected",
    ],
  ]) {
    test(`${label}: no transfer, no balance change, no log entry`, async () => {
      const { service, state, transfers } = build(fakeArca(answer));
      const before = structuredClone(state.accounts);

      const { error, lines } = await logLines(() => service.exchange({ ...request }));

      assert.ok(error instanceof ErrorType, `got ${error}`);
      assert.deepEqual(transfers, []);
      assert.deepEqual(state.accounts, before);
      assert.deepEqual(state.log, []);
      assert.deepEqual(lines, [line]);
    });
  }

  test("an approved and a rejected line are told apart with grep", async () => {
    const approved = await logLines(() =>
      build(fakeArca({ ok: true, authorizationCode: "a1b2" })).service.exchange({ ...request }),
    );
    const rejected = await logLines(() =>
      build(fakeArca({ ok: false })).service.exchange({ ...request }),
    );

    assert.match(approved.lines[0], / approved /);
    assert.doesNotMatch(approved.lines[0], / rejected/);
    assert.match(rejected.lines[0], / rejected$/);
    assert.doesNotMatch(rejected.lines[0], / approved /);
  });
});

// ── POST /exchange ──────────────────────────────────────────────────────────

describe("POST /exchange and ARCA", () => {
  let server;
  let baseUrl;
  let arca;
  let state;
  const originalLog = console.log;
  const originalError = console.error;

  // Rebuilt per test through this indirection, as in error-handling.test.js.
  let service;
  beforeEach(() => {
    state = seed();
    service = memoryService(state, async () => true, {
      validate: (dni) => arca.validate(dni),
    });
  });

  before(async () => {
    server = createApp(
      new Proxy({}, { get: (_, name) => (...args) => service[name](...args) }),
    ).listen(0);
    await new Promise((resolve) => server.once("listening", resolve));
    baseUrl = `http://127.0.0.1:${server.address().port}`;
    // The validation lines and the 5xx stacks; keep the test output clean.
    console.log = () => {};
    console.error = () => {};
  });

  after(() => {
    console.log = originalLog;
    console.error = originalError;
    server.close();
  });

  async function post(body) {
    const response = await fetch(`${baseUrl}/exchange`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
    });
    return { status: response.status, body: await response.json() };
  }

  test("approved: 200, and the response carries codigoAutorizacion", async () => {
    arca = fakeArca({ ok: true, authorizationCode: "a1b2" });

    const { status, body } = await post(request);

    assert.equal(status, 200);
    assert.equal(body.ok, true);
    assert.equal(body.codigoAutorizacion, "a1b2");
  });

  test("rejected: 403 ARCA_REJECTED, and nothing changes", async () => {
    arca = fakeArca({ ok: false });

    const { status, body } = await post(request);

    assert.equal(status, 403);
    assert.equal(body.code, "ARCA_REJECTED");
    assert.deepEqual(state.log, []);
    assert.deepEqual(state.accounts, seed().accounts);
  });

  test("unavailable: 502 ARCA_UNAVAILABLE, and nothing changes", async () => {
    arca = fakeArca(new ArcaUnavailableError("timeout"));

    const { status, body } = await post(request);

    assert.equal(status, 502);
    assert.equal(body.code, "ARCA_UNAVAILABLE");
    assert.deepEqual(state.log, []);
    assert.deepEqual(state.accounts, seed().accounts);
  });

  for (const [label, dni] of [
    ["missing", undefined],
    ["a number", 12345678],
    ["999999", "999999"],
    ["100000000", "100000000"],
    ["abc1234", "abc1234"],
    ["a leading zero", "01234567"],
  ]) {
    test(`a dni that is ${label} answers 400 and never calls ARCA`, async () => {
      arca = fakeArca();

      const { status, body } = await post({ ...request, dni });

      assert.equal(status, 400);
      assert.equal(body.code, "VALIDATION_ERROR");
      assert.deepEqual(arca.calls, []);
    });
  }

  test("the bounds 1000000 and 99999999 are valid", async () => {
    arca = fakeArca();

    assert.equal((await post({ ...request, dni: "1000000" })).status, 200);
    assert.equal((await post({ ...request, dni: "99999999" })).status, 200);
    assert.deepEqual(arca.calls, ["1000000", "99999999"]);
  });
});
