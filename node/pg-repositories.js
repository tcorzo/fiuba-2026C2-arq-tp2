import pg from "pg";

import { positionAfter } from "./cursor.js";

// numeric comes back from pg as a string, to keep its precision. The service
// and its JSON answers use numbers, so it is parsed on the way out.
pg.types.setTypeParser(pg.types.builtins.NUMERIC, parseFloat);

const ENTRY_COLUMNS =
  "id, ts, ok, request, exchange_rate, counter_amount, obs, failure";

// The same shape the service logged before: { id, ts, ok, request,
// exchangeRate, counterAmount, obs, failure }.
function toEntry(row) {
  return {
    id: row.id,
    ts: row.ts,
    ok: row.ok,
    request: row.request,
    exchangeRate: row.exchange_rate,
    counterAmount: row.counter_amount,
    obs: row.obs,
    failure: row.failure,
  };
}

function toPage(rows, limit) {
  const items = rows.slice(0, limit);
  return {
    items: items.map(toEntry),
    next: rows.length > limit ? String(items.at(-1).seq) : null,
  };
}

// Adapters of the ports in ports.js over Postgres. db is the pool, where each
// call runs on its own and commits, or one client inside atomically(), where
// every call joins that client's transaction. Building them opens nothing.
export function createPgRepositories(db) {
  return {
    accounts: {
      async all() {
        const { rows } = await db.query(
          "SELECT id, currency, balance FROM accounts ORDER BY id",
        );
        return rows;
      },

      async byCurrency(currency) {
        const { rows } = await db.query(
          "SELECT id, currency, balance FROM accounts WHERE currency = $1",
          [currency],
        );
        return rows[0] ?? null;
      },

      // Compared as text, as the memory adapter compares with ==: an id that is
      // not a number is an unknown account (404), not a database error (500).
      async setBalance(accountId, balance) {
        const { rowCount } = await db.query(
          "UPDATE accounts SET balance = $2 WHERE id::text = $1",
          [String(accountId), balance],
        );
        return rowCount === 1;
      },

      // H-06 across processes: the check and the debit are one statement, and
      // Postgres locks the row for it. No lock is held after it returns.
      async reserve(currency, amount) {
        const { rowCount } = await db.query(
          "UPDATE accounts SET balance = balance - $2 WHERE currency = $1 AND balance >= $2",
          [currency, amount],
        );
        return rowCount === 1;
      },

      async release(currency, amount) {
        await db.query(
          "UPDATE accounts SET balance = balance + $2 WHERE currency = $1",
          [currency, amount],
        );
      },

      async credit(currency, amount) {
        await db.query(
          "UPDATE accounts SET balance = balance + $2 WHERE currency = $1",
          [currency, amount],
        );
      },
    },

    rates: {
      async all() {
        const { rows } = await db.query(
          "SELECT base_currency, counter_currency, rate FROM rates ORDER BY base_currency, counter_currency",
        );
        const rates = {};
        for (const row of rows) {
          rates[row.base_currency] ??= {};
          rates[row.base_currency][row.counter_currency] = row.rate;
        }
        return rates;
      },

      async put(baseCurrency, counterCurrency, rate) {
        await db.query(
          `INSERT INTO rates (base_currency, counter_currency, rate) VALUES ($1, $2, $3)
           ON CONFLICT (base_currency, counter_currency) DO UPDATE SET rate = EXCLUDED.rate`,
          [baseCurrency, counterCurrency, rate],
        );
      },

      async remove(baseCurrency, counterCurrency) {
        await db.query(
          "DELETE FROM rates WHERE base_currency = $1 AND counter_currency = $2",
          [baseCurrency, counterCurrency],
        );
      },
    },

    exchanges: {
      async all() {
        const { rows } = await db.query(
          `SELECT ${ENTRY_COLUMNS} FROM exchanges ORDER BY seq`,
        );
        return rows.map(toEntry);
      },

      // H-35: the cursor is the seq of the last entry a page answered
      // (cursor.js). One row past the limit tells whether a next page exists.
      async page({ after, limit }) {
        const { rows } = await db.query(
          `SELECT seq, ${ENTRY_COLUMNS} FROM exchanges
            WHERE seq > $1 ORDER BY seq LIMIT $2`,
          [positionAfter(after), limit + 1],
        );
        return toPage(rows, limit);
      },

      // Served by the two account indexes in schema.js.
      async byAccount(accountId, { after, limit }) {
        const { rows } = await db.query(
          `SELECT seq, ${ENTRY_COLUMNS} FROM exchanges
            WHERE seq > $1
              AND (request->>'baseAccountId' = $2
                OR request->>'counterAccountId' = $2)
            ORDER BY seq LIMIT $3`,
          [positionAfter(after), accountId, limit + 1],
        );
        return toPage(rows, limit);
      },

      async byId(id) {
        const { rows } = await db.query(
          `SELECT ${ENTRY_COLUMNS} FROM exchanges WHERE id = $1`,
          [id],
        );
        return rows[0] ? toEntry(rows[0]) : null;
      },

      async append(entry) {
        await db.query(
          `INSERT INTO exchanges (id, ts, ok, request, exchange_rate, counter_amount, obs, failure)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
          [
            entry.id,
            entry.ts,
            entry.ok,
            JSON.stringify(entry.request),
            entry.exchangeRate ?? null,
            entry.counterAmount,
            entry.obs,
            entry.failure ?? null,
          ],
        );
      },
    },
  };
}

// Runs fn on one connection inside one transaction: every write fn makes
// commits together, or none does. Callers keep slow work, such as transfers,
// out of fn: the transaction holds its row locks until fn returns.
export function createPgAtomically(pool) {
  return async (fn) => {
    const client = await pool.connect();
    // A checked-out client has no listener of the pool's: if the db drops the
    // connection, its `error` event would end the process. The failed query
    // rejects on its own, so the event only needs catching.
    const onError = (err) => {
      console.error("Database connection failed in a transaction:", err);
    };
    client.on("error", onError);

    let failure;
    try {
      await client.query("BEGIN");
      const result = await fn(createPgRepositories(client));
      await client.query("COMMIT");
      return result;
    } catch (err) {
      failure = err;
      // On a broken connection ROLLBACK fails too; the caller gets fn's error.
      await client.query("ROLLBACK").catch(() => {});
      throw err;
    } finally {
      client.off("error", onError);
      // With an error, the pool closes the client instead of reusing it.
      client.release(failure);
    }
  };
}

// Connects and checks the store is seeded. Throws if the database cannot be
// reached, a table is missing, or accounts or rates are empty: the service
// never answers from an empty store (H-04). `mise run app:deploy` seeds it.
export async function connectStore(connectionString) {
  const pool = new pg.Pool({ connectionString });
  // An idle connection that breaks (the db restarts) is reported here. Without
  // a listener the pool's `error` event ends the process.
  pool.on("error", (err) => {
    console.error("Idle database connection failed:", err);
  });

  try {
    const { rows } = await pool.query(
      `SELECT (SELECT count(*) FROM accounts)::int AS accounts,
              (SELECT count(*) FROM rates)::int AS rates`,
    );
    if (rows[0].accounts === 0 || rows[0].rates === 0) {
      throw new Error(
        `the store is not seeded (${rows[0].accounts} accounts, ${rows[0].rates} rates): run mise run app:deploy`,
      );
    }
  } catch (err) {
    await pool.end();
    throw err;
  }

  return pool;
}
