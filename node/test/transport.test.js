import assert from "node:assert/strict";
import http from "node:http";
import { after, before, describe, test } from "node:test";

import { HSTS, redirectToHttps, withHsts } from "../transport.js";

function listen(handler) {
  const server = http.createServer(handler).listen(0);
  return new Promise((resolve) =>
    server.once("listening", () => resolve(server)),
  );
}

// fetch() cannot set Host, so the requests go through node:http.
function request(port, { method = "GET", path = "/", host, body } = {}) {
  return new Promise((resolve, reject) => {
    const headers = host === undefined ? {} : { Host: host };
    const req = http.request(
      { port, method, path, headers, setHost: host !== undefined },
      (res) => {
        res.resume();
        res.on("end", () => resolve(res));
      },
    );
    req.on("error", reject);
    req.end(body);
  });
}

describe("redirectToHttps", () => {
  let server;
  let port;

  before(async () => {
    server = await listen(redirectToHttps);
    port = server.address().port;
  });

  after(() => server.close());

  test("answers 308 to the same path and query over HTTPS", async () => {
    const res = await request(port, {
      path: "/rates?x=1",
      host: "lb.example.test",
    });

    assert.equal(res.statusCode, 308);
    assert.equal(res.headers.location, "https://lb.example.test/rates?x=1");
  });

  test("keeps a POST a POST: 308, not 301 or 302", async () => {
    const res = await request(port, {
      method: "POST",
      path: "/exchange",
      host: "lb.example.test",
      body: '{"dni":"12345678"}',
    });

    assert.equal(res.statusCode, 308);
    assert.equal(res.headers.location, "https://lb.example.test/exchange");
  });

  test("drops the port of the Host header", async () => {
    const res = await request(port, { host: "lb.example.test:80" });

    assert.equal(res.headers.location, "https://lb.example.test/");
  });

  test("answers 400 without a Host header", async () => {
    const res = await request(port);

    assert.equal(res.statusCode, 400);
    assert.equal(res.headers.location, undefined);
  });
});

describe("withHsts", () => {
  let server;
  let port;

  before(async () => {
    server = await listen(
      withHsts((req, res) => {
        res.writeHead(200).end("ok");
      }),
    );
    port = server.address().port;
  });

  after(() => server.close());

  test("adds Strict-Transport-Security to the app's responses", async () => {
    const res = await fetch(`http://127.0.0.1:${port}/`);

    assert.equal(res.status, 200);
    assert.equal(res.headers.get("strict-transport-security"), HSTS);
  });
});
