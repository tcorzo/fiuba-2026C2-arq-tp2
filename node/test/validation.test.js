import assert from "node:assert/strict";
import { describe, test } from "node:test";

import {
  NotFoundError,
  UnknownCurrencyError,
  UnsupportedPairError,
} from "../errors.js";
import { memoryService } from "./helpers.js";

// Rates as the service ships them since H-08: one direction per pair, ARS holds
// none of its own.
function seed() {
  return {
    accounts: [
      { id: 1, currency: "ARS", balance: 1_000_000 },
      { id: 2, currency: "USD", balance: 1_000 },
    ],
    rates: { ARS: {}, USD: { ARS: 1000 } },
    log: [],
  };
}

function countingTransfer() {
  const calls = [];
  const transfer = async (from, to, amount) => {
    calls.push({ from, to, amount });
    return true;
  };
  return { transfer, calls };
}

async function build(state = seed()) {
  const { transfer, calls } = countingTransfer();
  const service = memoryService(state, transfer);
  return { service, calls, state };
}

const request = {
  baseCurrency: "ARS",
  counterCurrency: "USD",
  baseAccountId: 101,
  counterAccountId: 102,
  baseAmount: 1000,
};

describe("H-01: exchange validates before it operates", () => {
  test("a pair stored in one direction is tradable in both", async () => {
    const { service } = await build();

    const forward = await service.exchange({ ...request });
    const backward = await service.exchange({
      ...request,
      baseCurrency: "USD",
      counterCurrency: "ARS",
      baseAmount: 1,
    });

    assert.equal(forward.ok, true);
    assert.equal(backward.ok, true);
  });

  for (const [name, override] of [
    ["an unknown base currency", { baseCurrency: "XXX" }],
    ["an unknown counter currency", { counterCurrency: "XXX" }],
    ["an inherited property name", { baseCurrency: "constructor" }],
  ]) {
    test(`${name} is rejected without touching the state`, async () => {
      const { service, calls } = await build();

      await assert.rejects(
        service.exchange({ ...request, ...override }),
        UnknownCurrencyError,
      );

      assert.equal(calls.length, 0);
      assert.equal((await service.getLog({ limit: 100 })).items.length, 0);
      assert.deepEqual(
        (await service.getAccounts()).map((account) => account.balance),
        [1_000_000, 1_000],
      );
    });
  }

  test("known currencies with no rate between them are rejected", async () => {
    const { service } = await build();

    await assert.rejects(
      service.exchange({ ...request, counterCurrency: "ARS" }),
      UnsupportedPairError,
    );
  });
});

describe("H-01: setRate validates before it writes", () => {
  test("an unknown currency is rejected and nothing is written", async () => {
    const { service, state } = await build();

    await assert.rejects(
      service.setRate({ baseCurrency: "XXX", counterCurrency: "ARS", rate: 2 }),
      UnknownCurrencyError,
    );
    assert.deepEqual(state.rates, { ARS: {}, USD: { ARS: 1000 } });
  });

  test("a known currency without a rates entry gets one, not a crash", async () => {
    const state = seed();
    state.accounts.push({ id: 3, currency: "EUR", balance: 1_000 });
    const { service } = await build(state);

    await service.setRate({
      baseCurrency: "EUR",
      counterCurrency: "ARS",
      rate: 1761,
    });

    assert.equal((await service.getRates()).EUR.ARS, 1761);
  });
});

describe("H-01: setAccountBalance does not ignore an unknown account", () => {
  test("an unknown id is a NotFoundError and nothing changes", async () => {
    const { service } = await build();

    await assert.rejects(service.setAccountBalance(99, 5), NotFoundError);
    assert.deepEqual(
      (await service.getAccounts()).map((account) => account.balance),
      [1_000_000, 1_000],
    );
  });

  test("a known id still sets the balance", async () => {
    const { service } = await build();

    await service.setAccountBalance(2, 5);

    assert.equal((await service.getAccounts())[1].balance, 5);
  });
});
