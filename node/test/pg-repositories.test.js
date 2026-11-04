import assert from "node:assert/strict";
import { mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { after, describe, test } from "node:test";

import pg from "pg";

import { createExchange } from "../exchange.js";
import {
  createPgAtomically,
  createPgRepositories,
} from "../pg-repositories.js";
import { createSchema, loadState, seed } from "../seed.js";
import { repositoryContract } from "./repositories.contract.js";

// A Postgres URL to run the suite against, e.g. a postgres:18 container:
// TEST_DATABASE_URL=postgres://... mise run app:test. Without it the suite
// skips, so the tests need no database.
const url = process.env.TEST_DATABASE_URL;
const skip = !url && "TEST_DATABASE_URL is not set";
const pool = url ? new pg.Pool({ connectionString: url }) : null;

after(() => pool?.end());

async function emptyDatabase() {
  await pool.query("DROP SCHEMA public CASCADE; CREATE SCHEMA public");
}

repositoryContract(
  "postgres",
  async (state) => {
    await emptyDatabase();
    await createSchema(pool);
    await loadState(pool, state);
    return {
      repositories: createPgRepositories(pool),
      atomically: createPgAtomically(pool),
    };
  },
  { rollsBack: true, skip },
);

describe("atomically on a broken connection", { skip }, () => {
  test("rejects, commits nothing and keeps the process alive when the db drops the connection", async () => {
    await emptyDatabase();
    await createSchema(pool);
    await loadState(pool, {
      accounts: [{ id: 1, currency: "ARS", balance: 1_000_000 }],
      rates: { USD: { ARS: 1000 } },
      log: [],
    });
    // Its own pool, named, so the test can end exactly its connection, the
    // way a db restart ends every connection.
    const doomed = new pg.Pool({
      connectionString: url,
      application_name: "doomed",
    });
    doomed.on("error", () => {});

    await assert.rejects(
      createPgAtomically(doomed)(async ({ accounts }) => {
        await accounts.credit("ARS", 1);
        await pool.query(
          "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE application_name = 'doomed'",
        );
        await accounts.credit("ARS", 1);
      }),
    );
    // The socket's close arrives after the query fails.
    await new Promise((resolve) => setTimeout(resolve, 200));

    const { rows } = await pool.query(
      "SELECT balance FROM accounts WHERE currency = 'ARS'",
    );
    assert.equal(rows[0].balance, 1_000_000);
    await doomed.end();
  });
});

describe("seed", { skip }, () => {
  const shippedState = new URL("../state/", import.meta.url).pathname;

  async function shipped(name) {
    return readFile(path.join(shippedState, `${name}.json`), "utf8");
  }

  async function tableExists(name) {
    const { rows } = await pool.query("SELECT to_regclass($1) AS t", [
      `public.${name}`,
    ]);
    return rows[0].t !== null;
  }

  // A copy of the shipped state with one file replaced.
  async function stateWith(file, contents) {
    const dir = await mkdtemp(path.join(tmpdir(), "state-"));
    for (const name of ["accounts", "rates", "log"]) {
      await writeFile(path.join(dir, `${name}.json`), await shipped(name));
    }
    await writeFile(path.join(dir, file), contents);
    return dir;
  }

  test("loads the shipped state", async () => {
    await emptyDatabase();
    assert.equal(await seed({ connectionString: url }), "seeded");

    const repositories = createPgRepositories(pool);
    assert.deepEqual(
      await repositories.accounts.all(),
      JSON.parse(await shipped("accounts")),
    );
    assert.deepEqual(await repositories.rates.all(), {
      BRL: { ARS: 297.06 },
      EUR: { ARS: 1761 },
      USD: { ARS: 1513 },
    });
    assert.deepEqual(await repositories.exchanges.all(), []);
  });

  test("a second seed refuses and changes nothing", async () => {
    await emptyDatabase();
    await seed({ connectionString: url });
    await createPgRepositories(pool).accounts.setBalance(1, 7);

    await assert.rejects(seed({ connectionString: url }), /already has accounts/);
    assert.equal(
      await seed({ connectionString: url, ifEmpty: true }),
      "already seeded",
    );
    assert.equal(
      (await createPgRepositories(pool).accounts.byCurrency("ARS")).balance,
      7,
    );
  });

  test("a truncated accounts.json fails and creates nothing", async () => {
    await emptyDatabase();
    const accounts = await shipped("accounts");
    const stateDir = await stateWith(
      "accounts.json",
      accounts.slice(0, accounts.length / 2),
    );

    await assert.rejects(seed({ connectionString: url, stateDir }), SyntaxError);
    assert.equal(await tableExists("accounts"), false);
  });

  test("a write that fails halfway rolls the whole seed back", async () => {
    await emptyDatabase();
    const duplicate = JSON.stringify([
      { id: 1, currency: "ARS", balance: 1 },
      { id: 2, currency: "ARS", balance: 2 },
    ]);
    const stateDir = await stateWith("accounts.json", duplicate);

    await assert.rejects(
      seed({ connectionString: url, stateDir }),
      /duplicate key/,
    );
    assert.equal(await tableExists("accounts"), false);
  });
});

describe("H-14", { skip }, () => {
  test("two replicas on separate connection pools share balances and log through the database", async () => {
    await emptyDatabase();
    await createSchema(pool);
    await loadState(pool, {
      accounts: [
        { id: 1, currency: "ARS", balance: 1_000_000 },
        { id: 2, currency: "USD", balance: 1_000 },
      ],
      rates: { ARS: { USD: 0.001 }, USD: { ARS: 1000 } },
      log: [],
    });
    const otherPool = new pg.Pool({ connectionString: url });
    try {
      const replica = (p) =>
        createExchange({
          repositories: createPgRepositories(p),
          atomically: createPgAtomically(p),
          transfer: async () => true,
        });
      const first = replica(pool);
      const second = replica(otherPool);
      const request = {
        baseCurrency: "ARS",
        counterCurrency: "USD",
        baseAccountId: 101,
        counterAccountId: 102,
        baseAmount: 1000,
      };

      await first.exchange({ ...request });
      await second.exchange({ ...request });

      for (const service of [first, second]) {
        const accounts = await service.getAccounts();
        assert.deepEqual(
          accounts.map((account) => account.balance),
          [1_002_000, 998],
        );
        assert.equal((await service.getLog({ limit: 100 })).items.length, 2);
      }
    } finally {
      await otherPool.end();
    }
  });
});
