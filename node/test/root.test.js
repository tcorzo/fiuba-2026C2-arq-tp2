import assert from "node:assert/strict";
import { after, before, describe, test } from "node:test";

import { createApp } from "../http.js";
import { memoryService } from "./helpers.js";

// GET / is the TP's baseline-latency target: it has to answer without
// touching the store or the transfer service.
describe("GET /", () => {
  let server;
  let baseUrl;
  let storeTouched = false;

  before(async () => {
    const exchange = memoryService(
      { accounts: [], rates: {}, log: [] },
      async () => true,
    );
    // Any call into the exchange service means the route reached the store.
    const guarded = new Proxy(exchange, {
      get(target, prop, receiver) {
        storeTouched = true;
        return Reflect.get(target, prop, receiver);
      },
    });

    server = createApp(guarded).listen(0);
    await new Promise((resolve) => server.once("listening", resolve));
    baseUrl = `http://127.0.0.1:${server.address().port}`;
  });

  after(() => server.close());

  test("answers 200 without touching the exchange service", async () => {
    storeTouched = false;
    const response = await fetch(`${baseUrl}/`);

    assert.equal(response.status, 200);
    assert.equal(await response.text(), "Server is up.");
    assert.equal(storeTouched, false);
  });
});
