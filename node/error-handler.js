// The one place where an error becomes an HTTP response. Handlers throw (see
// errors.js); they never build an error response themselves.
//
//   app.get("/x", asyncHandler(async (req, res) => { ... throw new ... }));
//   ...
//   app.use(notFoundHandler);
//   app.use(errorHandler);   // must be the last middleware
import { AppError, NotFoundError } from "./errors.js";
import { countHandledError } from "./metrics.js";

// Express 4 does not catch a rejected promise from an async handler: without
// this wrapper the rejection reaches `unhandledRejection` and Node ends the
// process (H-01). Every async route goes through it.
export function asyncHandler(handler) {
  const wrapped = (req, res, next) => {
    Promise.resolve(handler(req, res, next)).catch(next);
  };
  // Lets a test walk the router and prove that no route skipped the wrapper.
  wrapped.asyncHandled = true;
  return wrapped;
}

export function notFoundHandler(req, res, next) {
  next(new NotFoundError());
}

// body-parser (express.json) fails before any route runs and tags its errors
// with a `type`. They are the client's fault, so they get a 4xx of their own.
const BODY_PARSER_ERRORS = {
  "entity.parse.failed": [400, "INVALID_JSON", "Request body is not valid JSON"],
  "entity.too.large": [413, "PAYLOAD_TOO_LARGE", "Request body is too large"],
};

function describe(err) {
  if (err instanceof AppError) {
    return {
      status: err.status,
      code: err.code,
      message: err.message,
      details: err.details,
    };
  }

  const parser = BODY_PARSER_ERRORS[err?.type];
  if (parser) {
    const [status, code, message] = parser;
    return { status, code, message };
  }

  // Any other 4xx raised by Express or a middleware. Its message is not ours
  // to show, so the client gets a generic one.
  const status = err?.status ?? err?.statusCode;
  if (Number.isInteger(status) && status >= 400 && status < 500) {
    return { status, code: "BAD_REQUEST", message: "Bad request" };
  }

  // Not ours to explain: a bug. The client learns nothing about it.
  return {
    status: 500,
    code: "INTERNAL_ERROR",
    message: "Internal server error",
  };
}

// Four arguments: that is how Express recognizes an error middleware.
// eslint-disable-next-line no-unused-vars
export function errorHandler(err, req, res, next) {
  // Half a response is already on the wire: only Express can close it.
  if (res.headersSent) {
    return next(err);
  }

  const { status, code, message, details } = describe(err);

  // Only faults of ours are logged, with the stack. A 4xx is the caller's doing
  // and a caller could fill the log with them; the counter below keeps them
  // visible without that.
  if (status >= 500) {
    console.error(`${req.method} ${req.originalUrl} failed:`, err);
  }
  countHandledError(code);

  res.status(status).json({ error: message, code, details });
}
