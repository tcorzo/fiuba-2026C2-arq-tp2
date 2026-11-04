import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

import pg from "pg";

import config from "./config.js";
import { createPgRepositories } from "./pg-repositories.js";
import { SCHEMA } from "./schema.js";

const STATE_DIR = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  "state",
);

export async function createSchema(db) {
  await db.query(SCHEMA);
}

// Inserts a state in the shape of state/*.json. Exchanges go through the
// repository, so a seeded entry is stored exactly as the service stores one.
export async function loadState(db, { accounts, rates, log }) {
  const repositories = createPgRepositories(db);

  for (const account of accounts) {
    await db.query(
      "INSERT INTO accounts (id, currency, balance) VALUES ($1, $2, $3)",
      [account.id, account.currency, account.balance],
    );
  }
  for (const [baseCurrency, counters] of Object.entries(rates)) {
    for (const [counterCurrency, rate] of Object.entries(counters)) {
      await repositories.rates.put(baseCurrency, counterCurrency, rate);
    }
  }
  for (const entry of log) {
    await repositories.exchanges.append(entry);
  }
}

async function readState(stateDir) {
  const read = async (name) =>
    JSON.parse(await readFile(path.join(stateDir, `${name}.json`), "utf8"));
  return {
    accounts: await read("accounts"),
    rates: await read("rates"),
    log: await read("log"),
  };
}

// Creates the schema and loads the state in one transaction: the database ends
// up with all of it or none of it. Refuses a database that already has
// accounts, unless ifEmpty, which leaves it as it is.
export async function seed({
  connectionString,
  stateDir = STATE_DIR,
  ifEmpty = false,
}) {
  const state = await readState(stateDir);
  const client = new pg.Client({ connectionString });
  await client.connect();

  try {
    await client.query("BEGIN");
    await createSchema(client);

    const { rows } = await client.query(
      "SELECT count(*)::int AS n FROM accounts",
    );
    if (rows[0].n > 0) {
      if (!ifEmpty) {
        throw new Error(
          "the store already has accounts: seed only an empty database",
        );
      }
      await client.query("ROLLBACK");
      return "already seeded";
    }

    await loadState(client, state);
    await client.query("COMMIT");
    return "seeded";
  } catch (err) {
    await client.query("ROLLBACK");
    throw err;
  } finally {
    await client.end();
  }
}

// `node seed.js [--if-empty]`. ansible/vmss_deploy.yml runs it with --if-empty
// on one VMSS instance: the database is reachable only from inside the VNet.
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    const outcome = await seed({
      connectionString: config.databaseUrl,
      ifEmpty: process.argv.includes("--if-empty"),
    });
    console.log(`Store ${outcome}`);
  } catch (err) {
    console.error("Seeding the store failed:", err);
    process.exit(1);
  }
}
