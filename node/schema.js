// The Postgres schema. A .js file so that node/zip (`zip src.zip *.js *.json`) ships it.
// Money is numeric: exact decimals, computed in SQL. No CHECK (balance >= 0):
// refusing a negative balance is H-07's tactic, not this one.
export const SCHEMA = `
CREATE TABLE IF NOT EXISTS accounts (
  id       integer PRIMARY KEY,
  currency text    NOT NULL UNIQUE,
  balance  numeric NOT NULL
);

CREATE TABLE IF NOT EXISTS rates (
  base_currency    text    NOT NULL,
  counter_currency text    NOT NULL,
  rate             numeric NOT NULL,
  PRIMARY KEY (base_currency, counter_currency)
);

-- One row per exchange, in the order they were logged. request keeps the body
-- as the client sent it: ids and amounts are not coerced.
CREATE TABLE IF NOT EXISTS exchanges (
  seq            bigserial   PRIMARY KEY,
  id             text        NOT NULL UNIQUE,
  ts             timestamptz NOT NULL,
  ok             boolean     NOT NULL,
  request        jsonb       NOT NULL,
  exchange_rate  numeric,
  counter_amount numeric     NOT NULL,
  obs            text,
  failure        text
);

-- H-35: GET /exchanges?accountId= reads one page of an account's entries. An
-- index per side, ordered by seq, lets the query stop at the page's end.
CREATE INDEX IF NOT EXISTS exchanges_base_account
  ON exchanges ((request->>'baseAccountId'), seq);
CREATE INDEX IF NOT EXISTS exchanges_counter_account
  ON exchanges ((request->>'counterAccountId'), seq);
`;
