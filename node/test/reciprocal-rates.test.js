import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { describe, test } from "node:test";

import { createExchange } from "../exchange.js";
import {
  createMemoryAtomically,
  createMemoryRepositories,
} from "../memory-repositories.js";
import { fakeArca } from "./helpers.js";

// The state the repo ships, read from disk and never written back.
async function shipped(name) {
  const file = new URL(`../state/${name}.json`, import.meta.url);
  return JSON.parse(await readFile(file, "utf8"));
}

async function build() {
  const repositories = createMemoryRepositories({
    accounts: await shipped("accounts"),
    rates: await shipped("rates"),
    log: [],
  });
  const service = createExchange({
    repositories,
    atomically: createMemoryAtomically(repositories),
    transfer: async () => true,
    arca: fakeArca(),
  });
  return { service, repositories };
}

function exchange(service, baseCurrency, counterCurrency, baseAmount) {
  return service.exchange({
    baseCurrency,
    counterCurrency,
    baseAccountId: 101,
    counterAccountId: 102,
    baseAmount,
  });
}

// Float noise only: the received rates drifted by 1e-3 to 1e-2.
const FLOAT_NOISE = 1e-9;

describe("H-08", () => {
  test("the shipped rates store one direction per pair", async () => {
    const { repositories } = await build();
    const rates = await repositories.rates.all();

    for (const base of Object.keys(rates)) {
      for (const counter of Object.keys(rates[base])) {
        assert.equal(
          rates[counter]?.[base],
          undefined,
          `${base} -> ${counter} is also stored as ${counter} -> ${base}`,
        );
      }
    }
  });

  for (const currency of ["BRL", "EUR", "USD"]) {
    test(`ARS -> ${currency} -> ARS returns what was sent`, async () => {
      const { service } = await build();

      const out = await exchange(service, "ARS", currency, 1000);
      const back = await exchange(service, currency, "ARS", out.counterAmount);

      assert.equal(out.ok, true);
      assert.equal(back.ok, true);
      assert.ok(
        Math.abs(back.counterAmount - 1000) / 1000 <= FLOAT_NOISE,
        `1000 ARS came back as ${back.counterAmount}`,
      );
    });
  }

  test("GET /rates shows every pair in both directions, reciprocal", async () => {
    const { service } = await build();
    const view = await service.getRates();

    for (const currency of ["BRL", "EUR", "USD"]) {
      const product = view[currency].ARS * view.ARS[currency];
      assert.ok(Math.abs(product - 1) <= FLOAT_NOISE, `${currency}: ${product}`);
    }
  });
});

describe("H-29", () => {
  const cases = [
    { currency: "USD", rate: 1513 },
    { currency: "EUR", rate: 1761 },
    { currency: "BRL", rate: 297.06 },
  ];

  for (const { currency, rate } of cases) {
    test(`setRate ${currency} -> ARS = ${rate} keeps a precise reciprocal`, async () => {
      const { service } = await build();

      await service.setRate({
        baseCurrency: currency,
        counterCurrency: "ARS",
        rate,
      });

      const view = await service.getRates();
      const product = view[currency].ARS * view.ARS[currency];
      assert.equal(view[currency].ARS, rate);
      assert.ok(Math.abs(product - 1) <= FLOAT_NOISE, `${currency}: ${product}`);
    });
  }

  test("setRate writes no reciprocal next to the rate", async () => {
    const { service, repositories } = await build();

    await service.setRate({
      baseCurrency: "USD",
      counterCurrency: "ARS",
      rate: 1513,
    });

    assert.equal((await repositories.rates.all()).ARS.USD, undefined);
  });

  test("setting the other direction replaces the stored pair", async () => {
    const { service, repositories } = await build();

    await service.setRate({
      baseCurrency: "ARS",
      counterCurrency: "USD",
      rate: 0.001,
    });

    const rates = await repositories.rates.all();
    assert.equal(rates.ARS.USD, 0.001);
    assert.equal(rates.USD?.ARS, undefined);
    assert.equal((await service.getRates()).USD.ARS, 1 / 0.001);
  });
});
