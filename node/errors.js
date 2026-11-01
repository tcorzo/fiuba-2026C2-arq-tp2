// The error vocabulary of the service. Anything a request can do wrong on
// purpose is an AppError: it carries the HTTP status and the machine-readable
// code the client receives, so the handler in error-handler.js never has to
// guess from a message. Anything that is not an AppError is a fault of ours and
// answers 500.
//
// To add a new kind of error: subclass AppError here, throw it from the
// handler or the domain code, and stop. See node/ERRORES.md.
export class AppError extends Error {
  constructor(status, code, message, details) {
    super(message);
    this.name = new.target.name;
    this.status = status;
    this.code = code;
    // Optional, JSON-serializable, safe to show the client.
    this.details = details;
  }
}

// The request is not well formed: missing or malformed fields.
export class ValidationError extends AppError {
  constructor(message = "Malformed request", details) {
    super(400, "VALIDATION_ERROR", message, details);
  }
}

// Well formed, but names a currency the service does not hold (H-01).
export class UnknownCurrencyError extends AppError {
  constructor(currency) {
    super(422, "UNKNOWN_CURRENCY", `Unknown currency: ${currency}`, {
      currency,
    });
  }
}

// Both currencies exist, but there is no rate between them (e.g. USD/USD).
export class UnsupportedPairError extends AppError {
  constructor(baseCurrency, counterCurrency) {
    super(
      422,
      "UNSUPPORTED_PAIR",
      `No exchange rate for ${baseCurrency}/${counterCurrency}`,
      { baseCurrency, counterCurrency },
    );
  }
}

export class NotFoundError extends AppError {
  constructor(message = "Not found") {
    super(404, "NOT_FOUND", message);
  }
}

// The exchange ran and was turned down (H-34). An `ok: false` is not always a
// fault of ours: a rejection the business rules decide is a 4xx, so the 5xx
// ratio stays an alert signal and a client that retries on 5xx does not retry
// it. A failed deposit is the transfer dependency's, so it is a 502. A cause
// missing from this map is a fault of ours and stays a 500.
const EXCHANGE_FAILURES = {
  insufficient_internal_funds: [409, "INSUFFICIENT_INTERNAL_FUNDS"],
  withdraw_failed: [422, "WITHDRAW_REJECTED"],
  deposit_failed: [502, "DEPOSIT_FAILED"],
};

export class ExchangeFailedError extends AppError {
  // The whole result goes back as details, as it did before: it carries the
  // operation id the log keeps it under.
  constructor(exchangeResult) {
    const [status, code] = EXCHANGE_FAILURES[exchangeResult.failure] ?? [
      500,
      "EXCHANGE_FAILED",
    ];
    super(status, code, exchangeResult.obs ?? "Exchange failed", exchangeResult);
  }
}
