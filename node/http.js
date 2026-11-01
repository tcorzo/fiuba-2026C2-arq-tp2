import express from "express";

import {
  countHttpStatus,
  gaugeResponseBytes,
  msSince,
  recordHttpDuration,
} from "./metrics.js";
import {
  asyncHandler,
  errorHandler,
  notFoundHandler,
} from "./error-handler.js";
import {
  ExchangeFailedError,
  NotFoundError,
  ValidationError,
} from "./errors.js";
import { assertNonNegativeNumber, assertPositiveNumber } from "./validation.js";

// An allow-list instead of req.route.path: that path carries a ":", which is
// the statsd name/value separator, and a label derived from the URL itself
// would let any caller create new series. Express sets req.route only after
// routing, so a 404 has none.
const ROUTE_BY_METHOD_AND_PATH = new Map([
  ["GET /accounts", "accounts_get"],
  ["PUT /accounts/:id/balance", "accounts_balance_put"],
  ["GET /rates", "rates_get"],
  ["PUT /rates", "rates_put"],
  ["GET /log", "log_get"],
  ["POST /exchange", "exchange_post"],
  ["GET /exchanges", "exchanges_get"],
  ["GET /exchanges/:id", "exchanges_id_get"],
]);

function routeLabel(req) {
  const key = `${req.method} ${req.route?.path}`;
  return ROUTE_BY_METHOD_AND_PATH.get(key) ?? "unmatched";
}

// H-35: the log is read one page at a time. `limit` defaults to PAGE_SIZE and
// is capped at MAX_PAGE_SIZE; `after` is the `next` of the previous page, and
// the adapter that issued it is the one that checks it.
const PAGE_SIZE = 100;
const MAX_PAGE_SIZE = 1000;

function pageCursor({ after, limit }) {
  if (after !== undefined && typeof after !== "string") {
    throw new ValidationError("after must appear once");
  }
  if (limit === undefined) {
    return { after, limit: PAGE_SIZE };
  }
  const size = Number(limit);
  if (
    typeof limit !== "string" ||
    !/^\d+$/.test(limit) ||
    size < 1 ||
    size > MAX_PAGE_SIZE
  ) {
    throw new ValidationError(
      `limit must be an integer from 1 to ${MAX_PAGE_SIZE}`,
    );
  }
  return { after, limit: size };
}

// The HTTP surface over an exchange service built by createExchange().
export function createApp(exchange) {
  const app = express();

  // Before express.json() so the timer covers body parsing, which the client
  // waits for too. `finish` fires when the last byte is handed to the socket.
  app.use((req, res, next) => {
    const startedAt = process.hrtime.bigint();

    res.on("finish", () => {
      const route = routeLabel(req);
      recordHttpDuration(route, msSince(startedAt));
      countHttpStatus(route, res.statusCode);

      // H-35: GET /log returns the whole log, so this grows over a run.
      const bytes = Number(res.getHeader("content-length") ?? 0);
      if (bytes > 0) {
        gaugeResponseBytes(route, bytes);
      }
    });

    next();
  });

  app.use(express.json());

  // ACCOUNT endpoints

  app.get(
    "/accounts",
    asyncHandler(async (req, res) => {
      res.json(await exchange.getAccounts());
    }),
  );

  app.put(
    "/accounts/:id/balance",
    asyncHandler(async (req, res) => {
      const accountId = req.params.id;
      const { balance } = req.body;

      if (!accountId) {
        throw new ValidationError();
      }
      // H-31, H-44: a number, and zero is a balance like any other.
      assertNonNegativeNumber("balance", balance);

      await exchange.setAccountBalance(accountId, balance);

      res.json(await exchange.getAccounts());
    }),
  );

  // RATE endpoints

  app.get(
    "/rates",
    asyncHandler(async (req, res) => {
      res.json(await exchange.getRates());
    }),
  );

  app.put(
    "/rates",
    asyncHandler(async (req, res) => {
      const { baseCurrency, counterCurrency, rate } = req.body;

      if (!baseCurrency || !counterCurrency) {
        throw new ValidationError();
      }
      // H-31: the reciprocal is derived as 1 / rate on every read, so a zero
      // rate would read back as Infinity and a negative one inverts exchanges.
      assertPositiveNumber("rate", rate);

      const newRateRequest = { ...req.body };
      await exchange.setRate(newRateRequest);

      res.json(await exchange.getRates());
    }),
  );

  // LOG endpoint

  app.get(
    "/log",
    asyncHandler(async (req, res) => {
      res.json(await exchange.getLog(pageCursor(req.query)));
    }),
  );

  // CLIENT view of the log (H-15): one operation, or the operations of one
  // account. The whole log stays behind the admin listener; nginx only
  // publishes these. The collection is never returned whole, even if nginx
  // let it through.

  app.get(
    "/exchanges",
    asyncHandler(async (req, res) => {
      const { accountId } = req.query;

      if (typeof accountId !== "string" || accountId === "") {
        throw new ValidationError("accountId is required");
      }

      res.json(
        await exchange.getExchangesByAccount(accountId, pageCursor(req.query)),
      );
    }),
  );

  app.get(
    "/exchanges/:id",
    asyncHandler(async (req, res) => {
      const entry = await exchange.findExchangeById(req.params.id);

      if (entry == null) {
        throw new NotFoundError("Exchange not found");
      }

      res.json(entry);
    }),
  );

  // EXCHANGE endpoint

  app.post(
    "/exchange",
    asyncHandler(async (req, res) => {
      const {
        baseCurrency,
        counterCurrency,
        baseAccountId,
        counterAccountId,
        baseAmount,
      } = req.body;

      if (
        !baseCurrency ||
        !counterCurrency ||
        !baseAccountId ||
        !counterAccountId
      ) {
        throw new ValidationError();
      }

      // H-07: a negative amount inverts both transfers and slips past the funds
      // check, so only a positive finite number reaches the domain.
      assertPositiveNumber("baseAmount", baseAmount);

      const exchangeRequest = { ...req.body };
      const exchangeResult = await exchange.exchange(exchangeRequest);

      if (!exchangeResult.ok) {
        throw new ExchangeFailedError(exchangeResult);
      }

      res.status(200).json(exchangeResult);
    }),
  );

  // Last, and in this order: whatever no route answered is a 404, and every
  // error thrown above ends up in errorHandler. See ERRORES.md.
  app.use(notFoundHandler);
  app.use(errorHandler);

  return app;
}
