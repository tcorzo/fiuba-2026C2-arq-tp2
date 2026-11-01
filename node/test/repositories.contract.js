import assert from "node:assert/strict";
import { describe, test } from "node:test";

// One suite for every adapter of the ports in ports.js. setup(state) builds
// the adapter over that state and answers { repositories, atomically }.
export function repositoryContract(
  name,
  setup,
  { rollsBack = false, skip = false } = {},
) {
  const state = () => ({
    accounts: [
      { id: 1, currency: "ARS", balance: 1_000_000 },
      { id: 2, currency: "USD", balance: 1_000 },
    ],
    rates: { USD: { ARS: 1000 } },
    log: [],
  });

  const entry = (id) => ({
    id,
    ts: new Date("2026-09-30T00:00:00.000Z"),
    ok: true,
    // Ids as a client may send them: the log keeps the request as received.
    request: {
      baseCurrency: "ARS",
      counterCurrency: "USD",
      baseAccountId: "101",
      counterAccountId: 102,
      baseAmount: 1000,
    },
    exchangeRate: 0.001,
    counterAmount: 1,
    obs: null,
    failure: null,
  });

  describe(`${name} repositories`, { skip }, () => {
    test("accounts.all answers every account, ordered by id", async () => {
      const { repositories } = await setup(state());
      assert.deepEqual(await repositories.accounts.all(), state().accounts);
    });

    test("byCurrency answers the account, or null", async () => {
      const { repositories } = await setup(state());
      assert.deepEqual(
        await repositories.accounts.byCurrency("USD"),
        state().accounts[1],
      );
      assert.equal(await repositories.accounts.byCurrency("EUR"), null);
    });

    test("setBalance answers whether the account exists", async () => {
      const { repositories } = await setup(state());
      assert.equal(await repositories.accounts.setBalance("2", 5), true);
      assert.equal(await repositories.accounts.setBalance("99", 5), false);
      assert.equal(await repositories.accounts.setBalance("abc", 5), false);
      assert.equal((await repositories.accounts.byCurrency("USD")).balance, 5);
    });

    test("reserve takes the amount only if it is there", async () => {
      const { repositories } = await setup(state());
      assert.equal(await repositories.accounts.reserve("USD", 600), true);
      assert.equal(await repositories.accounts.reserve("USD", 600), false);
      assert.equal(
        (await repositories.accounts.byCurrency("USD")).balance,
        400,
      );
    });

    test("release and credit add to the balance", async () => {
      const { repositories } = await setup(state());
      await repositories.accounts.release("USD", 10);
      await repositories.accounts.credit("USD", 5);
      assert.equal(
        (await repositories.accounts.byCurrency("USD")).balance,
        1_015,
      );
    });

    test("20 concurrent reserves of 60 % of the balance: exactly one passes", async () => {
      const { repositories } = await setup(state());
      const results = await Promise.all(
        Array.from({ length: 20 }, () =>
          repositories.accounts.reserve("USD", 600),
        ),
      );
      assert.equal(results.filter(Boolean).length, 1);
      assert.equal(
        (await repositories.accounts.byCurrency("USD")).balance,
        400,
      );
    });

    test("rates.all answers { base: { counter: rate } }", async () => {
      const { repositories } = await setup(state());
      assert.deepEqual(await repositories.rates.all(), { USD: { ARS: 1000 } });
    });

    test("rates.put adds or replaces a rate, rates.remove drops one", async () => {
      const { repositories } = await setup(state());
      await repositories.rates.put("ARS", "EUR", 0.0005);
      await repositories.rates.put("USD", "ARS", 1513);
      await repositories.rates.remove("USD", "ARS");
      const rates = await repositories.rates.all();
      assert.equal(rates.ARS.EUR, 0.0005);
      assert.equal(rates.USD?.ARS, undefined);
    });

    test("exchanges.all answers entries in append order, as appended", async () => {
      const { repositories } = await setup(state());
      await repositories.exchanges.append(entry("op-a"));
      await repositories.exchanges.append(entry("op-b"));
      assert.deepEqual(await repositories.exchanges.all(), [
        entry("op-a"),
        entry("op-b"),
      ]);
    });

    describe("H-35", () => {
      // Five entries: op-0 to op-4. Accounts 101 and 102 take part in op-0,
      // op-2 and op-4; 201 and 202 in op-1 and op-3.
      async function fiveEntries() {
        const { repositories } = await setup(state());
        for (let i = 0; i < 5; i++) {
          const mine = i % 2 === 0;
          await repositories.exchanges.append({
            ...entry(`op-${i}`),
            request: {
              ...entry(`op-${i}`).request,
              baseAccountId: mine ? "101" : "201",
              counterAccountId: mine ? 102 : 202,
            },
          });
        }
        return repositories.exchanges;
      }

      const ids = (page) => page.items.map((item) => item.id);

      test("exchanges.page answers at most limit entries, in append order, and a cursor to the rest", async () => {
        const exchanges = await fiveEntries();
        const first = await exchanges.page({ limit: 2 });
        assert.deepEqual(ids(first), ["op-0", "op-1"]);
        assert.equal(typeof first.next, "string");

        const second = await exchanges.page({ after: first.next, limit: 2 });
        assert.deepEqual(ids(second), ["op-2", "op-3"]);

        const last = await exchanges.page({ after: second.next, limit: 2 });
        assert.deepEqual(ids(last), ["op-4"]);
        assert.equal(last.next, null);
      });

      test("exchanges.page answers no cursor when the page ends the log exactly", async () => {
        const exchanges = await fiveEntries();
        const page = await exchanges.page({ limit: 5 });
        assert.equal(page.items.length, 5);
        assert.equal(page.next, null);
      });

      test("exchanges.byAccount pages the entries an account took part in, as base or counter", async () => {
        const exchanges = await fiveEntries();
        const first = await exchanges.byAccount("101", { limit: 2 });
        assert.deepEqual(ids(first), ["op-0", "op-2"]);

        const last = await exchanges.byAccount("101", {
          after: first.next,
          limit: 2,
        });
        assert.deepEqual(ids(last), ["op-4"]);
        assert.equal(last.next, null);

        // The counter side, stored as a number, matches its text too.
        assert.deepEqual(ids(await exchanges.byAccount("202", { limit: 5 })), [
          "op-1",
          "op-3",
        ]);
        assert.deepEqual(ids(await exchanges.byAccount("999", { limit: 5 })), []);
      });

      test("exchanges.byId answers the entry with that id, or null", async () => {
        const exchanges = await fiveEntries();
        assert.equal((await exchanges.byId("op-3")).id, "op-3");
        assert.equal(await exchanges.byId("op-9"), null);
      });

      test("a cursor this adapter did not issue is a ValidationError", async () => {
        const exchanges = await fiveEntries();
        for (const after of ["abc", "-1", "1.5", "1e3"]) {
          await assert.rejects(exchanges.page({ after, limit: 2 }), {
            name: "ValidationError",
          });
          await assert.rejects(exchanges.byAccount("101", { after, limit: 2 }), {
            name: "ValidationError",
          });
        }
      });
    });

    test("atomically commits every write of fn", async () => {
      const { repositories, atomically } = await setup(state());
      await atomically(async ({ accounts, exchanges }) => {
        await accounts.credit("ARS", 1000);
        await exchanges.append(entry("op-a"));
      });
      assert.equal(
        (await repositories.accounts.byCurrency("ARS")).balance,
        1_001_000,
      );
      assert.equal((await repositories.exchanges.all()).length, 1);
    });

    test(
      "atomically commits nothing when fn throws",
      { skip: !rollsBack && "the memory adapter has no rollback" },
      async () => {
        const { repositories, atomically } = await setup(state());
        await assert.rejects(
          atomically(async ({ accounts }) => {
            await accounts.credit("ARS", 1000);
            throw new Error("boom");
          }),
          /boom/,
        );
        assert.equal(
          (await repositories.accounts.byCurrency("ARS")).balance,
          1_000_000,
        );
      },
    );
  });
}
