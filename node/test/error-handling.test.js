import assert from "node:assert/strict";
import { after, before, describe, test } from "node:test";

import { createApp } from "../http.js";
import { UnknownCurrencyError } from "../errors.js";

// An exchange service that does whatever the test scripts. The HTTP surface is
// the real one: the point is what the middleware does with what a route throws.
function fakeExchange(overrides = {}) {
  return {
    getAccounts: () => [],
    setAccountBalance: () => {},
    getRates: () => ({}),
    setRate: () => {},
    getLog: () => [],
    exchange: async () => ({ ok: true }),
    ...overrides,
  };
}

const validExchange = {
  baseCurrency: "ARS",
  counterCurrency: "USD",
  baseAccountId: 101,
  counterAccountId: 102,
  baseAmount: 1000,
};

let server;
let url;
let exchange;
let routes;

// A 5xx is logged with its stack; keep the test output clean.
const consoleError = console.error;
before(async () => {
  console.error = () => {};
  exchange = fakeExchange();
  // The service is rebuilt per test through this indirection, so each test can
  // script the exchange and the same server keeps answering afterwards.
  const app = createApp(
    new Proxy(
      {},
      { get: (_, name) => (...args) => exchange[name](...args) },
    ),
  );
  server = app.listen(0);
  await new Promise((resolve) => server.once("listening", resolve));
  url = `http://127.0.0.1:${server.address().port}`;
  routes = app;
});
after(() => {
  console.error = consoleError;
  server.close();
});

async function call(method, path, body, { raw = false } = {}) {
  const res = await fetch(`${url}${path}`, {
    method,
    headers: body === undefined ? {} : { "content-type": "application/json" },
    body: body === undefined ? undefined : raw ? body : JSON.stringify(body),
  });
  return { status: res.status, json: await res.json() };
}

describe("H-01: the routes and the middleware, in process", () => {
  test("every route goes through asyncHandler", () => {
    const layers = routes._router.stack.filter((layer) => layer.route);

    assert.ok(layers.length >= 6, "the router lost its routes");
    for (const layer of layers) {
      for (const { handle } of layer.route.stack) {
        assert.equal(
          handle.asyncHandled,
          true,
          `${Object.keys(layer.route.methods)} ${layer.route.path} skips asyncHandler`,
        );
      }
    }
  });

  test("errorHandler is the last middleware, after notFoundHandler", () => {
    const names = routes._router.stack.map((layer) => layer.name);

    assert.deepEqual(names.slice(-2), ["notFoundHandler", "errorHandler"]);
  });

  test("a synchronous throw in a route answers 500 and the server stays up", async () => {
    exchange = fakeExchange({
      getRates: () => {
        throw new TypeError("cannot read properties of null");
      },
    });

    const failed = await call("GET", "/rates");
    exchange = fakeExchange();
    const after = await call("GET", "/rates");

    assert.equal(failed.status, 500);
    assert.deepEqual(failed.json, {
      error: "Internal server error",
      code: "INTERNAL_ERROR",
    });
    assert.equal(after.status, 200);
  });

  test("a rejected promise answers 500 instead of ending the process", async () => {
    exchange = fakeExchange({
      exchange: async () => {
        throw new TypeError("cannot read properties of undefined");
      },
    });

    const failed = await call("POST", "/exchange", validExchange);
    exchange = fakeExchange();
    const after = await call("GET", "/accounts");

    assert.equal(failed.status, 500);
    assert.equal(failed.json.code, "INTERNAL_ERROR");
    assert.equal(after.status, 200);
  });

  test("an error of the domain answers its own status and code", async () => {
    exchange = fakeExchange({
      exchange: async () => {
        throw new UnknownCurrencyError("XXX");
      },
    });

    const res = await call("POST", "/exchange", validExchange);

    assert.equal(res.status, 422);
    assert.equal(res.json.code, "UNKNOWN_CURRENCY");
    assert.deepEqual(res.json.details, { currency: "XXX" });
  });

  test("missing fields and a non-positive amount answer 400", async () => {
    exchange = fakeExchange();

    const missing = await call("POST", "/exchange", { baseCurrency: "ARS" });
    const negative = await call("POST", "/exchange", {
      ...validExchange,
      baseAmount: -5,
    });

    assert.equal(missing.status, 400);
    assert.equal(missing.json.code, "VALIDATION_ERROR");
    assert.equal(negative.status, 400);
    assert.equal(negative.json.error, "baseAmount must be a positive number");
  });

  test("a body that is not JSON answers 400, and a large one 413", async () => {
    const broken = await call("POST", "/exchange", "{not json", { raw: true });
    const large = await call("POST", "/exchange", {
      ...validExchange,
      padding: "x".repeat(200 * 1024),
    });

    assert.equal(broken.status, 400);
    assert.equal(broken.json.code, "INVALID_JSON");
    assert.equal(large.status, 413);
    assert.equal(large.json.code, "PAYLOAD_TOO_LARGE");
  });

  test("a route nobody serves answers a JSON 404", async () => {
    const res = await call("GET", "/nope");

    assert.equal(res.status, 404);
    assert.equal(res.json.code, "NOT_FOUND");
  });
});
