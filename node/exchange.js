import { nanoid } from "nanoid";

import {
  NotFoundError,
  UnknownCurrencyError,
  UnsupportedPairError,
} from "./errors.js";
import {
  countExchangeFailure,
  countExchangeOutcome,
  gaugeAccountBalance,
  msSince,
  recordExchangeDuration,
} from "./metrics.js";

// Builds an exchange service over the given repositories and transfer
// service. Each call returns an instance with its own state (H-22), and the
// transfer it calls is the one it is handed (H-23). The service holds no state
// of its own: every read and write goes through the ports in ports.js.
export function createExchange({ repositories, atomically, transfer }) {
  //returns all internal accounts
  async function getAccounts() {
    return repositories.accounts.all();
  }

  //sets balance for an account
  async function setAccountBalance(accountId, balance) {
    // Silently ignoring it answered 200 for a write that never happened.
    if (!(await repositories.accounts.setBalance(accountId, balance))) {
      throw new NotFoundError(`Account ${accountId} not found`);
    }
  }

  // Only one direction of each pair is ever stored; the other is derived here.
  // Storing both let them drift apart independently, which is the actual cause
  // of H-08 (the shipped rates.json) and H-29 (every setRate afterwards).
  async function getRates() {
    const rates = await repositories.rates.all();
    const view = {};
    for (const base of Object.keys(rates)) {
      view[base] = { ...rates[base] };
    }
    for (const base of Object.keys(rates)) {
      for (const counter of Object.keys(rates[base])) {
        view[counter] ??= {};
        if (!Object.hasOwn(view[counter], base)) {
          view[counter][base] = 1 / rates[base][counter];
        }
      }
    }
    return view;
  }

  // internal - the rate for base -> counter, stored directly or derived from
  // its reciprocal. Never touches an unknown currency's entry, so a currency
  // with no rates object of its own falls through to undefined instead of
  // throwing.
  function getRate(rates, baseCurrency, counterCurrency) {
    if (Object.hasOwn(rates, baseCurrency) && Object.hasOwn(rates[baseCurrency], counterCurrency)) {
      return rates[baseCurrency][counterCurrency];
    }
    if (Object.hasOwn(rates, counterCurrency) && Object.hasOwn(rates[counterCurrency], baseCurrency)) {
      return 1 / rates[counterCurrency][baseCurrency];
    }
    return undefined;
  }

  // H-35: one page of the transaction log, never the whole of it.
  async function getLog(cursor) {
    return repositories.exchanges.page(cursor);
  }

  // H-15: the client-facing view of the log. The store finds the entry by its
  // id, and pages an account's entries, instead of the service scanning the
  // whole log (H-35).
  async function findExchangeById(id) {
    return repositories.exchanges.byId(id);
  }

  async function getExchangesByAccount(accountId, cursor) {
    return repositories.exchanges.byAccount(accountId, cursor);
  }

  // Sets the rate for baseCurrency -> counterCurrency and drops any reciprocal
  // stored for the reverse direction, so the pair always has exactly one
  // source of truth (getRate/getRates derive the other side on read).
  async function setRate(rateRequest) {
    const { baseCurrency, counterCurrency, rate } = rateRequest;

    // Not the pair: PUT /rates is how a pair gets created.
    await assertKnownCurrencies(baseCurrency, counterCurrency);

    // The rate and the reciprocal it replaces change together.
    await atomically(async ({ rates }) => {
      await rates.put(baseCurrency, counterCurrency, rate);
      await rates.remove(counterCurrency, baseCurrency);
    });
  }

  //executes an exchange operation
  async function exchange(exchangeRequest) {
    const {
      baseCurrency,
      counterCurrency,
      baseAccountId: clientBaseAccountId,
      counterAccountId: clientCounterAccountId,
      baseAmount,
    } = exchangeRequest;

    // Before "attempted": a request rejected here never reached the exchange
    // (H-01 used to count it as attempted and never finish it).
    await assertTradablePair(baseCurrency, counterCurrency);

    const startedAt = process.hrtime.bigint();
    countExchangeOutcome("attempted");

    //get the exchange rate
    const exchangeRate = getRate(await repositories.rates.all(), baseCurrency, counterCurrency);
    //compute the requested (counter) amount
    const counterAmount = baseAmount * exchangeRate;
    //find our account on the provided (base) currency
    const baseAccount = await repositories.accounts.byCurrency(baseCurrency);
    //find our account on the counter currency
    const counterAccount = await repositories.accounts.byCurrency(counterCurrency);

    // The base amount this exchange credits, applied with its log entry.
    let credit;

    //construct the result object with defaults
    const exchangeResult = {
      id: nanoid(),
      ts: new Date(),
      ok: false,
      request: exchangeRequest,
      exchangeRate: exchangeRate,
      counterAmount: 0.0,
      obs: null,
      // H-34: the cause of an `ok: false`, machine-readable, so the HTTP layer
      // can tell a business rejection from a dependency failure.
      failure: null,
    };

    // H-06: reserve the funds on the counter currency account before the
    // transfers, instead of checking them here and debiting them after.
    // Concurrent exchanges now see each other's reservations.
    if (await repositories.accounts.reserve(counterCurrency, counterAmount)) {
      // H-12: neither transfer uses what the other returns, so both start at
      // once and the exchange waits for the slower one instead of their sum.
      // The dependency always succeeds (README, "Tener en cuenta"). Were the
      // withdrawal to fail, the deposit already sent would not be reversed.
      const [withdrawn, deposited] = await Promise.all([
        //try to transfer from clients' base account
        transfer(clientBaseAccountId, baseAccount.id, baseAmount),
        //try to transfer to clients' counter account
        transfer(counterAccount.id, clientCounterAccountId, counterAmount),
      ]);
      if (withdrawn) {
        if (deposited) {
          //all good, update balances; the counter amount left with reserve()
          credit = { currency: baseCurrency, amount: baseAmount };
          exchangeResult.ok = true;
          exchangeResult.counterAmount = counterAmount;
          countExchangeOutcome("ok");
        } else {
          //could not transfer to clients' counter account, return base amount to client
          await transfer(baseAccount.id, clientBaseAccountId, baseAmount);
          await repositories.accounts.release(counterCurrency, counterAmount);
          exchangeResult.obs = "Could not transfer to clients' account";
          exchangeResult.failure = "deposit_failed";
          countExchangeFailure("deposit_failed");
        }
      } else {
        //could not withdraw from clients' account
        await repositories.accounts.release(counterCurrency, counterAmount);
        exchangeResult.obs = "Could not withdraw from clients' account";
        exchangeResult.failure = "withdraw_failed";
        countExchangeFailure("withdraw_failed");
      }
    } else {
      //not enough funds on internal counter account
      exchangeResult.obs = "Not enough funds on counter currency account";
      exchangeResult.failure = "insufficient_internal_funds";
      countExchangeFailure("insufficient_internal_funds");
    }

    //log the transaction and return it; a credit commits with its log entry
    if (credit) {
      await atomically(async ({ accounts, exchanges }) => {
        await accounts.credit(credit.currency, credit.amount);
        await exchanges.append(exchangeResult);
      });
    } else {
      await repositories.exchanges.append(exchangeResult);
    }

    // Under a workload that should leave the net unchanged, drift here is H-06,
    // H-07 or H-08.
    for (const account of await repositories.accounts.all()) {
      gaugeAccountBalance(account.currency, account.balance);
    }
    recordExchangeDuration(msSince(startedAt));

    return exchangeResult;
  }

  // internal - the service can only trade what it holds, so a currency is known
  // when an internal account exists for it. Asking the accounts (not the rates)
  // keeps "constructor" and other inherited names out, and does not depend on
  // how the rates are stored.
  async function assertKnownCurrencies(...currencies) {
    for (const currency of currencies) {
      if ((await repositories.accounts.byCurrency(currency)) == null) {
        throw new UnknownCurrencyError(currency);
      }
    }
  }

  // internal - known currencies and a rate between them, asked the same way the
  // exchange asks it (getRate), so a pair stored in one direction only is
  // tradable in both.
  async function assertTradablePair(baseCurrency, counterCurrency) {
    await assertKnownCurrencies(baseCurrency, counterCurrency);

    const rates = await repositories.rates.all();
    if (getRate(rates, baseCurrency, counterCurrency) === undefined) {
      throw new UnsupportedPairError(baseCurrency, counterCurrency);
    }
  }

  return {
    getAccounts,
    setAccountBalance,
    getRates,
    setRate,
    getLog,
    findExchangeById,
    getExchangesByAccount,
    exchange,
  };
}
