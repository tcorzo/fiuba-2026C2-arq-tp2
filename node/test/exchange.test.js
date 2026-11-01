import assert from "node:assert/strict";
import { describe, test } from "node:test";

import pg from "pg";

import { createExchange } from "../exchange.js";
import {
  createMemoryAtomically,
  createMemoryRepositories,
} from "../memory-repositories.js";
import {
  createPgAtomically,
  createPgRepositories,
} from "../pg-repositories.js";
import { memoryService } from "./helpers.js";

function seed() {
  return {
    accounts: [
      { id: 1, currency: "ARS", balance: 1_000_000 },
      { id: 2, currency: "USD", balance: 1_000 },
    ],
    rates: { ARS: { USD: 0.001 }, USD: { ARS: 1000 } },
  };
}

// Answers each call with the next scripted result, and records the call.
function scriptedTransfer(...results) {
  const calls = [];
  const transfer = async (from, to, amount) => {
    calls.push({ from, to, amount });
    return results.length > 0 ? results.shift() : true;
  };
  return { transfer, calls };
}

const request = {
  baseCurrency: "ARS",
  counterCurrency: "USD",
  baseAccountId: 101,
  counterAccountId: 102,
  baseAmount: 1000,
};

async function build(transfer, state = seed()) {
  return memoryService({ log: [], ...state }, transfer);
}

async function balances(service) {
  return (await service.getAccounts()).map((account) => account.balance);
}

describe("H-23", () => {
  test("both transfers succeed, so balances move and one entry is logged", async () => {
    const { transfer, calls } = scriptedTransfer(true, true);
    const service = await build(transfer);

    const result = await service.exchange({ ...request });

    assert.equal(result.ok, true);
    assert.equal(result.counterAmount, 1);
    assert.deepEqual(calls, [
      { from: 101, to: 1, amount: 1000 },
      { from: 2, to: 102, amount: 1 },
    ]);
    assert.deepEqual(await balances(service), [1_001_000, 999]);
    assert.equal((await service.getLog({ limit: 100 })).items.length, 1);
  });

  // H-12 starts the deposit with the withdrawal, so a failed withdrawal no
  // longer stops it, and nothing reverses it. The dependency never fails
  // (README, "Tener en cuenta"); this pins the risk the tactic accepts.
  test("a failed withdrawal is rejected, and the deposit already sent is not reversed", async () => {
    const { transfer, calls } = scriptedTransfer(false, true);
    const service = await build(transfer);

    const result = await service.exchange({ ...request });

    assert.equal(result.ok, false);
    assert.equal(result.obs, "Could not withdraw from clients' account");
    assert.deepEqual(calls, [
      { from: 101, to: 1, amount: 1000 },
      { from: 2, to: 102, amount: 1 },
    ]);
    assert.deepEqual(await balances(service), [1_000_000, 1_000]);
  });

  test("a failed deposit refunds the client and is rejected", async () => {
    const { transfer, calls } = scriptedTransfer(true, false, true);
    const service = await build(transfer);

    const result = await service.exchange({ ...request });

    assert.equal(result.ok, false);
    assert.equal(result.obs, "Could not transfer to clients' account");
    assert.deepEqual(calls[2], { from: 1, to: 101, amount: 1000 });
    assert.deepEqual(await balances(service), [1_000_000, 1_000]);
  });

  test("insufficient internal funds never calls the dependency", async () => {
    const { transfer, calls } = scriptedTransfer();
    const service = await build(transfer);

    const result = await service.exchange({ ...request, baseAmount: 2_000_000 });

    assert.equal(result.ok, false);
    assert.equal(result.obs, "Not enough funds on counter currency account");
    assert.equal(calls.length, 0);
  });
});

describe("H-12", () => {
  // Holds every transfer until the test lets it go, so the test sees which
  // transfers are in flight at the same moment. No timer is involved.
  function heldTransfer() {
    const pending = [];
    const transfer = (from, to, amount) =>
      new Promise((resolve) => pending.push({ from, to, amount, resolve }));
    return { transfer, pending };
  }

  // Lets the exchange run until it waits on the transfers.
  async function settle(pending, count) {
    for (let turn = 0; turn < 100 && pending.length < count; turn++) {
      await new Promise((resolve) => setImmediate(resolve));
    }
  }

  test("both transfers are in flight before either one finishes", async () => {
    const { transfer, pending } = heldTransfer();
    const service = await build(transfer);

    const running = service.exchange({ ...request });
    await settle(pending, 2);

    assert.deepEqual(
      pending.map(({ from, to, amount }) => ({ from, to, amount })),
      [
        { from: 101, to: 1, amount: 1000 },
        { from: 2, to: 102, amount: 1 },
      ],
    );

    for (const call of pending) call.resolve(true);
    const result = await running;

    assert.equal(result.ok, true);
    assert.deepEqual(await balances(service), [1_001_000, 999]);
    assert.equal((await service.getLog({ limit: 100 })).items.length, 1);
  });
});

describe("H-06", () => {
  // Resolves true after a delay, like the received dependency, so the
  // exchanges overlap in their transfers the way they do under load.
  function delayedTransfer(ms) {
    return () => new Promise((resolve) => setTimeout(() => resolve(true), ms));
  }

  test("of 20 concurrent exchanges that each need most of the balance, exactly one passes", async () => {
    // 990,000 ARS at 0.001 is 990 USD: one fits in 1,000 USD, two do not.
    const service = await build(delayedTransfer(50));

    const results = await Promise.all(
      Array.from({ length: 20 }, () =>
        service.exchange({ ...request, baseAmount: 990_000 }),
      ),
    );

    const usd = (await service.getAccounts()).find((a) => a.currency === "USD");
    assert.equal(results.filter((result) => result.ok).length, 1);
    assert.ok(usd.balance >= 0, `USD ended at ${usd.balance}`);
    assert.equal((await service.getLog({ limit: 100 })).items.length, 20);
  });
});

describe("H-22", () => {
  test("two exchange instances in one process do not share state", async () => {
    const { transfer } = scriptedTransfer();
    const first = await build(transfer);
    const second = await build(transfer);

    await first.exchange({ ...request });

    assert.equal((await first.getLog({ limit: 100 })).items.length, 1);
    assert.deepEqual(await balances(first), [1_001_000, 999]);
    assert.equal((await second.getLog({ limit: 100 })).items.length, 0);
    assert.deepEqual(await balances(second), [1_000_000, 1_000]);
  });

  test("building the postgres adapter opens no connection", () => {
    const pool = new pg.Pool({
      connectionString: "postgres://nobody@127.0.0.1:1/none",
    });

    createPgRepositories(pool);
    createPgAtomically(pool);

    assert.equal(pool.totalCount, 0);
  });
});

describe("H-14", () => {
  // Two instances over one store, as two replicas over one database.
  function replicasOverOneStore(transfer) {
    const repositories = createMemoryRepositories({ log: [], ...seed() });
    const replica = () =>
      createExchange({
        repositories,
        atomically: createMemoryAtomically(repositories),
        transfer,
      });
    return [replica(), replica()];
  }

  test("an exchange on one replica shows in the balances and the log of the other", async () => {
    const { transfer } = scriptedTransfer();
    const [first, second] = replicasOverOneStore(transfer);

    await first.exchange({ ...request });

    assert.deepEqual(await balances(second), [1_001_000, 999]);
    assert.equal((await second.getLog({ limit: 100 })).items.length, 1);
  });

  test("exchanges split across two replicas add up", async () => {
    const { transfer } = scriptedTransfer();
    const [first, second] = replicasOverOneStore(transfer);

    await Promise.all([
      first.exchange({ ...request }),
      second.exchange({ ...request }),
    ]);

    assert.deepEqual(await balances(first), [1_002_000, 998]);
    assert.deepEqual(await balances(second), [1_002_000, 998]);
    assert.equal((await first.getLog({ limit: 100 })).items.length, 2);
  });
});
