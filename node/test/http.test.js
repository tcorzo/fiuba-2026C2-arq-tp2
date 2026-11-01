import assert from "node:assert/strict";
import { after, before, describe, test } from "node:test";

import { createApp } from "../http.js";
import { memoryService } from "./helpers.js";

// Three operations: 101 and 102 take part in two of them, 201 and 202 in one.
function seedLog() {
  const entry = (id, baseAccountId, counterAccountId) => ({
    id,
    ts: "2026-09-30T00:00:00.000Z",
    ok: true,
    request: {
      baseCurrency: "USD",
      counterCurrency: "ARS",
      baseAmount: 10,
      baseAccountId,
      counterAccountId,
    },
    exchangeRate: 1000,
    counterAmount: 10000,
    obs: null,
  });

  return [
    entry("op-a", 102, 101),
    entry("op-b", 202, 201),
    entry("op-c", 101, 102),
  ];
}

describe("H-15", () => {
  let server;
  let baseUrl;

  before(async () => {
    const exchange = memoryService(
      { accounts: [], rates: {}, log: seedLog() },
      async () => true,
    );

    server = createApp(exchange).listen(0);
    await new Promise((resolve) => server.once("listening", resolve));
    baseUrl = `http://127.0.0.1:${server.address().port}`;
  });

  after(() => server.close());

  async function get(path) {
    const response = await fetch(baseUrl + path);
    return { status: response.status, body: await response.json() };
  }

  test("an account sees only the operations it took part in", async () => {
    const { status, body } = await get("/exchanges?accountId=101");

    assert.equal(status, 200);
    assert.deepEqual(
      body.items.map((entry) => entry.id),
      ["op-a", "op-c"]
    );
  });

  test("an account with no operations gets an empty list", async () => {
    const { status, body } = await get("/exchanges?accountId=999");

    assert.equal(status, 200);
    assert.deepEqual(body, { items: [], next: null });
  });

  test("without accountId the whole log is never returned", async () => {
    for (const query of ["", "?accountId=", "?accountId=101&accountId=102"]) {
      const { status, body } = await get(`/exchanges${query}`);

      assert.equal(status, 400, `query: "${query}"`);
      assert.deepEqual(body, {
        error: "accountId is required",
        code: "VALIDATION_ERROR",
      });
    }
  });

  test("one operation is returned by its id", async () => {
    const { status, body } = await get("/exchanges/op-b");

    assert.equal(status, 200);
    assert.equal(body.id, "op-b");
    assert.equal(body.request.baseAccountId, 202);
  });

  test("an unknown id answers 404", async () => {
    const { status, body } = await get("/exchanges/does-not-exist");

    assert.equal(status, 404);
    assert.deepEqual(body, {
      error: "Exchange not found",
      code: "NOT_FOUND",
    });
  });
});

describe("H-34", () => {
  let server;
  let baseUrl;
  // The dependency answers what each test scripts; true once the script ends.
  let transferResults = [];

  before(async () => {
    const exchange = memoryService(
      {
        accounts: [
          { id: 1, currency: "ARS", balance: 1_000_000 },
          { id: 2, currency: "USD", balance: 1_000 },
        ],
        rates: { ARS: { USD: 0.001 }, USD: { ARS: 1000 } },
        log: [],
      },
      async () =>
        transferResults.length > 0 ? transferResults.shift() : true,
    );

    server = createApp(exchange).listen(0);
    await new Promise((resolve) => server.once("listening", resolve));
    baseUrl = `http://127.0.0.1:${server.address().port}`;
  });

  after(() => server.close());

  // A 502 is logged with its stack; keep the test output clean.
  async function postExchange(baseAmount, ...transfers) {
    transferResults = transfers;
    const original = console.error;
    console.error = () => {};
    try {
      const response = await fetch(`${baseUrl}/exchange`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          baseCurrency: "ARS",
          counterCurrency: "USD",
          baseAccountId: 101,
          counterAccountId: 102,
          baseAmount,
        }),
      });
      return { status: response.status, body: await response.json() };
    } finally {
      console.error = original;
    }
  }

  test("a successful exchange still answers 200 with the result", async () => {
    const { status, body } = await postExchange(1000);

    assert.equal(status, 200);
    assert.equal(body.ok, true);
    assert.equal(body.failure, null);
  });

  test("insufficient internal funds is a 409, not a 500", async () => {
    const { status, body } = await postExchange(2_000_000_000);

    assert.equal(status, 409);
    assert.equal(body.code, "INSUFFICIENT_INTERNAL_FUNDS");
    assert.equal(body.error, "Not enough funds on counter currency account");
    assert.equal(body.details.failure, "insufficient_internal_funds");
    assert.ok(body.details.id);
  });

  test("a withdrawal the client's account rejects is a 422", async () => {
    const { status, body } = await postExchange(1000, false);

    assert.equal(status, 422);
    assert.equal(body.code, "WITHDRAW_REJECTED");
  });

  test("a deposit the dependency fails is a 502", async () => {
    const { status, body } = await postExchange(1000, true, false, true);

    assert.equal(status, 502);
    assert.equal(body.code, "DEPOSIT_FAILED");
  });
});

// A service over its own copy of the state, so each test can read back what a
// request left behind.
async function serve() {
  const state = {
    accounts: [
      { id: 1, currency: "ARS", balance: 1_000_000 },
      { id: 2, currency: "USD", balance: 1_000 },
    ],
    rates: { ARS: {}, USD: { ARS: 1000 } },
    log: [],
  };
  const exchange = memoryService(state, async () => true);

  const server = createApp(exchange).listen(0);
  await new Promise((resolve) => server.once("listening", resolve));
  const baseUrl = `http://127.0.0.1:${server.address().port}`;

  async function call(method, path, body) {
    const response = await fetch(baseUrl + path, {
      method,
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    return { status: response.status, body: await response.json() };
  }

  return { call, state, close: () => server.close() };
}

const usdToArs = {
  baseCurrency: "USD",
  counterCurrency: "ARS",
  baseAccountId: 11,
  counterAccountId: 10,
};

describe("H-31", () => {
  for (const [name, balance] of [
    ["text", "no soy un numero"],
    ["numeric text", "60000"],
    ["a negative number", -5],
    ["an object", {}],
    ["a boolean", true],
    ["null", null],
  ]) {
    test(`a balance sent as ${name} is a 400 and the balance is kept`, async () => {
      const { call, state, close } = await serve();
      try {
        const { status, body } = await call("PUT", "/accounts/2/balance", {
          balance,
        });

        assert.equal(status, 400);
        assert.equal(body.code, "VALIDATION_ERROR");
        assert.equal(
          body.error,
          "balance must be a number greater than or equal to 0",
        );
        assert.equal(state.accounts[1].balance, 1_000);
      } finally {
        close();
      }
    });
  }

  for (const [name, rate] of [
    ["text", "abc"],
    ["numeric text", "1000"],
    ["a negative number", -1000],
    ["an object", {}],
  ]) {
    test(`a rate sent as ${name} is a 400 and the rate is kept`, async () => {
      const { call, state, close } = await serve();
      try {
        const { status, body } = await call("PUT", "/rates", {
          baseCurrency: "USD",
          counterCurrency: "ARS",
          rate,
        });

        assert.equal(status, 400);
        assert.equal(body.error, "rate must be a positive number");
        assert.deepEqual(state.rates, { ARS: {}, USD: { ARS: 1000 } });
      } finally {
        close();
      }
    });
  }

  test("an amount sent as numeric text is a 400 and nothing moves", async () => {
    const { call, state, close } = await serve();
    try {
      const { status, body } = await call("POST", "/exchange", {
        ...usdToArs,
        baseAmount: "10",
      });

      assert.equal(status, 400);
      assert.equal(body.error, "baseAmount must be a positive number");
      assert.equal(state.log.length, 0);
    } finally {
      close();
    }
  });

  test("valid numbers are still written", async () => {
    const { call, state, close } = await serve();
    try {
      const balance = await call("PUT", "/accounts/2/balance", {
        balance: 1_500.5,
      });
      const rate = await call("PUT", "/rates", {
        baseCurrency: "USD",
        counterCurrency: "ARS",
        rate: 1200,
      });

      assert.equal(balance.status, 200);
      assert.equal(rate.status, 200);
      assert.equal(state.accounts[1].balance, 1_500.5);
      assert.equal(state.rates.USD.ARS, 1200);
    } finally {
      close();
    }
  });
});

describe("H-44", () => {
  test("a balance of zero is written", async () => {
    const { call, state, close } = await serve();
    try {
      const { status } = await call("PUT", "/accounts/2/balance", {
        balance: 0,
      });

      assert.equal(status, 200);
      assert.equal(state.accounts[1].balance, 0);
    } finally {
      close();
    }
  });

  test("a rate of zero is a 400 that names the rule", async () => {
    const { call, state, close } = await serve();
    try {
      const { status, body } = await call("PUT", "/rates", {
        baseCurrency: "USD",
        counterCurrency: "ARS",
        rate: 0,
      });

      assert.equal(status, 400);
      assert.equal(body.error, "rate must be a positive number");
      assert.equal(state.rates.USD.ARS, 1000);
    } finally {
      close();
    }
  });

  test("an amount of zero is a 400 that names the rule", async () => {
    const { call, state, close } = await serve();
    try {
      const { status, body } = await call("POST", "/exchange", {
        ...usdToArs,
        baseAmount: 0,
      });

      assert.equal(status, 400);
      assert.equal(body.error, "baseAmount must be a positive number");
      assert.equal(state.log.length, 0);
    } finally {
      close();
    }
  });
});

describe("H-35", () => {
  let server;
  let baseUrl;

  // seedLog's three operations, then 147 more between accounts 301 and 302:
  // 150 in all, more than one default page.
  function longLog() {
    const filler = Array.from({ length: 147 }, (_, i) => ({
      ...seedLog()[0],
      id: `op-${i}`,
      request: { ...seedLog()[0].request, baseAccountId: 301, counterAccountId: 302 },
    }));
    return [...seedLog(), ...filler];
  }

  before(async () => {
    const exchange = memoryService(
      { accounts: [], rates: {}, log: longLog() },
      async () => true,
    );

    server = createApp(exchange).listen(0);
    await new Promise((resolve) => server.once("listening", resolve));
    baseUrl = `http://127.0.0.1:${server.address().port}`;
  });

  after(() => server.close());

  async function get(path) {
    const response = await fetch(baseUrl + path);
    return { status: response.status, body: await response.json() };
  }

  test("GET /log answers a page of 100 entries by default, and a cursor to the rest", async () => {
    const { status, body } = await get("/log");

    assert.equal(status, 200);
    assert.equal(body.items.length, 100);
    assert.equal(body.items[0].id, "op-a");
    assert.equal(typeof body.next, "string");
  });

  test("following next reads the log to its end, each entry once", async () => {
    const seen = [];
    let path = "/log?limit=40";
    for (;;) {
      const { status, body } = await get(path);
      assert.equal(status, 200);
      seen.push(...body.items.map((entry) => entry.id));
      if (body.next === null) break;
      path = `/log?limit=40&after=${encodeURIComponent(body.next)}`;
    }

    assert.equal(seen.length, 150);
    assert.equal(new Set(seen).size, 150);
  });

  test("an account's operations come one page at a time", async () => {
    const first = await get("/exchanges?accountId=101&limit=1");
    assert.deepEqual(
      first.body.items.map((entry) => entry.id),
      ["op-a"]
    );

    const last = await get(
      `/exchanges?accountId=101&limit=1&after=${encodeURIComponent(first.body.next)}`
    );
    assert.deepEqual(
      last.body.items.map((entry) => entry.id),
      ["op-c"]
    );
    assert.equal(last.body.next, null);
  });

  test("a limit out of 1 to 1000, or not an integer, answers 400", async () => {
    for (const limit of ["0", "1001", "abc", "1.5", "-1", "10&limit=20"]) {
      for (const route of ["/log", "/exchanges?accountId=101"]) {
        const separator = route.includes("?") ? "&" : "?";
        const { status, body } = await get(`${route}${separator}limit=${limit}`);

        assert.equal(status, 400, `${route} limit=${limit}`);
        assert.equal(body.code, "VALIDATION_ERROR");
      }
    }
  });

  test("a cursor the service did not issue answers 400", async () => {
    for (const route of ["/log", "/exchanges?accountId=101"]) {
      const separator = route.includes("?") ? "&" : "?";
      const { status, body } = await get(`${route}${separator}after=abc`);

      assert.equal(status, 400, route);
      assert.deepEqual(body, {
        error: "after is not a cursor this service issued",
        code: "VALIDATION_ERROR",
      });
    }
  });
});
