import { positionAfter } from "./cursor.js";

// Adapters of the ports in ports.js over plain objects in memory. Tests build
// them with a given state; nothing here touches the disk.
//
// Every operation is async, although nothing here waits: the Postgres adapter
// does.
// Query strings arrive as text while the request stored the ids as sent, so
// both sides are compared as strings.
function tookPart(entry, accountId) {
  return (
    String(entry.request.baseAccountId) === accountId ||
    String(entry.request.counterAccountId) === accountId
  );
}

export function createMemoryRepositories({ accounts, rates, log }) {
  function findAccountByCurrency(currency) {
    for (let account of accounts) {
      if (account.currency == currency) {
        return account;
      }
    }

    return null;
  }

  function findAccountById(id) {
    for (let account of accounts) {
      if (account.id == id) {
        return account;
      }
    }

    return null;
  }

  return {
    accounts: {
      async all() {
        return accounts;
      },

      async byCurrency(currency) {
        return findAccountByCurrency(currency);
      },

      // Answers whether the account exists, so the caller can refuse an unknown
      // one instead of reporting a write that never happened (H-01).
      async setBalance(accountId, balance) {
        const account = findAccountById(accountId);

        if (account == null) {
          return false;
        }
        account.balance = balance;
        return true;
      },

      // H-06: takes the amount out of the currency's account only if it is
      // there. The check and the debit run with no await between them, so no
      // other request can read the balance in between. Written as !(>=), the
      // received check negated, so a NaN amount is still refused.
      async reserve(currency, amount) {
        const account = findAccountByCurrency(currency);

        if (!(account.balance >= amount)) {
          return false;
        }
        account.balance -= amount;
        return true;
      },

      // Gives back what reserve() took, when the exchange does not complete.
      async release(currency, amount) {
        findAccountByCurrency(currency).balance += amount;
      },

      // `+=` is kept as the received code wrote it: a delta with a sign would
      // coerce a string amount that `+=` concatenates.
      async credit(currency, amount) {
        findAccountByCurrency(currency).balance += amount;
      },
    },

    rates: {
      async all() {
        return rates;
      },

      // A known currency with no rates entry of its own gets one: the caller has
      // already checked that the currency exists (H-01).
      async put(baseCurrency, counterCurrency, rate) {
        rates[baseCurrency] ??= {};
        rates[baseCurrency][counterCurrency] = rate;
      },

      async remove(baseCurrency, counterCurrency) {
        delete rates[baseCurrency]?.[counterCurrency];
      },
    },

    exchanges: {
      async all() {
        return log;
      },

      async append(entry) {
        log.push(entry);
      },

      // The cursor is how many entries come before the next page (cursor.js).
      async page({ after, limit }) {
        const start = positionAfter(after);
        const end = start + limit;
        return {
          items: log.slice(start, end),
          next: end < log.length ? String(end) : null,
        };
      },

      // A scan of the whole log: the memory adapter only backs tests.
      async byAccount(accountId, { after, limit }) {
        const items = [];
        for (let i = positionAfter(after); i < log.length; i++) {
          if (!tookPart(log[i], accountId)) {
            continue;
          }
          if (items.length === limit) {
            return { items, next: String(log.indexOf(items.at(-1)) + 1) };
          }
          items.push(log[i]);
        }
        return { items, next: null };
      },

      async byId(id) {
        return log.find((entry) => entry.id === id) ?? null;
      },
    },
  };
}

// No rollback: if fn throws after its first write, that write stays. Nothing
// in fn waits on I/O, so no other request runs between its writes.
export function createMemoryAtomically(repositories) {
  return (fn) => fn(repositories);
}
