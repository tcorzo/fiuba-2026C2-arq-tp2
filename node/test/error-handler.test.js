import assert from "node:assert/strict";
import { describe, test } from "node:test";

import {
  asyncHandler,
  errorHandler,
  notFoundHandler,
} from "../error-handler.js";
import {
  ExchangeFailedError,
  NotFoundError,
  UnknownCurrencyError,
  ValidationError,
} from "../errors.js";

// Just enough of a response to see what the handler answered.
function fakeResponse({ headersSent = false } = {}) {
  const res = {
    headersSent,
    statusCode: null,
    body: null,
    status(code) {
      res.statusCode = code;
      return res;
    },
    json(body) {
      res.body = body;
      return res;
    },
  };
  return res;
}

const req = { method: "POST", originalUrl: "/exchange" };

function handle(err) {
  const res = fakeResponse();
  errorHandler(err, req, res, () => assert.fail("next must not be called"));
  return res;
}

// A 5xx is logged with its stack; keep the test output clean.
function silenced(fn) {
  const original = console.error;
  console.error = () => {};
  try {
    return fn();
  } finally {
    console.error = original;
  }
}

describe("H-01: errorHandler answers what each error deserves", () => {
  test("an AppError answers its own status, code and details", () => {
    const res = handle(new UnknownCurrencyError("XXX"));

    assert.equal(res.statusCode, 422);
    assert.equal(res.body.code, "UNKNOWN_CURRENCY");
    assert.deepEqual(res.body.details, { currency: "XXX" });
  });

  test("a ValidationError answers 400", () => {
    const res = handle(new ValidationError("baseAmount must be a positive number"));

    assert.equal(res.statusCode, 400);
    assert.equal(res.body.code, "VALIDATION_ERROR");
    assert.equal(res.body.error, "baseAmount must be a positive number");
  });

  test("body-parser failures are the client's fault", () => {
    const parse = handle(Object.assign(new Error("bad"), { type: "entity.parse.failed" }));
    const large = handle(Object.assign(new Error("big"), { type: "entity.too.large" }));

    assert.deepEqual([parse.statusCode, parse.body.code], [400, "INVALID_JSON"]);
    assert.deepEqual([large.statusCode, large.body.code], [413, "PAYLOAD_TOO_LARGE"]);
  });

  test("any other 4xx keeps its status with a generic message", () => {
    const res = handle(Object.assign(new Error("internal detail"), { status: 415 }));

    assert.equal(res.statusCode, 415);
    assert.equal(res.body.code, "BAD_REQUEST");
    assert.equal(res.body.error, "Bad request");
  });

  test("a fault of ours answers 500 and tells the client nothing", () => {
    const res = silenced(() => handle(new TypeError("cannot read properties")));

    assert.equal(res.statusCode, 500);
    assert.equal(res.body.code, "INTERNAL_ERROR");
    assert.equal(res.body.error, "Internal server error");
    assert.ok(!JSON.stringify(res.body).includes("cannot read"));
  });

  test("an exchange failure with an unmapped cause stays a 500", () => {
    const res = silenced(() =>
      handle(new ExchangeFailedError({ ok: false, failure: "new_cause", obs: "x" })),
    );

    assert.equal(res.statusCode, 500);
    assert.equal(res.body.code, "EXCHANGE_FAILED");
  });

  test("a response already on the wire is left to Express", () => {
    const res = fakeResponse({ headersSent: true });
    let forwarded = null;

    errorHandler(new Error("late"), req, res, (err) => (forwarded = err));

    assert.equal(forwarded.message, "late");
    assert.equal(res.statusCode, null);
  });
});

describe("H-01: a rejected promise reaches the handler, not the process", () => {
  test("asyncHandler forwards a rejection to next", async () => {
    const boom = new Error("boom");
    let forwarded = null;

    asyncHandler(async () => {
      throw boom;
    })({}, {}, (err) => (forwarded = err));
    await new Promise((resolve) => setImmediate(resolve));

    assert.equal(forwarded, boom);
  });

  test("notFoundHandler raises a NotFoundError", () => {
    let forwarded = null;

    notFoundHandler({}, {}, (err) => (forwarded = err));

    assert.ok(forwarded instanceof NotFoundError);
  });
});
