// The ports exchange.js depends on. JSDoc only: an adapter is any object with
// these methods, and node/test/repositories.contract.js is what checks that two
// adapters behave the same.

/**
 * @typedef {{ id: number, currency: string, balance: number }} Account
 *
 * @typedef {object} AccountRepository
 * @property {() => Promise<Account[]>} all  ordered by id
 * @property {(currency: string) => Promise<Account|null>} byCurrency
 * @property {(id: string|number, balance: number) => Promise<boolean>} setBalance  false: no such account
 * @property {(currency: string, amount: number) => Promise<boolean>} reserve  false: not enough funds, nothing taken
 * @property {(currency: string, amount: number) => Promise<void>} release  gives back what reserve took
 * @property {(currency: string, amount: number) => Promise<void>} credit
 *
 * @typedef {object} RateRepository
 * @property {() => Promise<Record<string, Record<string, number>>>} all  { base: { counter: rate } }
 * @property {(base: string, counter: string, rate: number) => Promise<void>} put
 * @property {(base: string, counter: string) => Promise<void>} remove
 *
 * @typedef {{ items: object[], next: string|null }} Page
 *   items in append order; next is the `after` of the following page, null
 *   on the last one. A cursor is opaque: only the adapter that issued it
 *   reads it, and one it did not issue is a ValidationError (H-35).
 *
 * @typedef {object} ExchangeRepository
 * @property {() => Promise<object[]>} all  in append order. No route reads it (H-35): tests and tools only
 * @property {(entry: object) => Promise<void>} append
 * @property {(cursor: { after?: string, limit: number }) => Promise<Page>} page  at most limit entries
 * @property {(accountId: string, cursor: { after?: string, limit: number }) => Promise<Page>} byAccount  entries the account took part in, as base or counter
 * @property {(id: string) => Promise<object|null>} byId
 *
 * @typedef {{ accounts: AccountRepository, rates: RateRepository,
 *             exchanges: ExchangeRepository }} Repositories
 *
 * ARCA's DNI validation (arca.js). `ok: false` is a rejection; a call that
 * gives no usable answer throws ArcaUnavailableError instead.
 * @typedef {{ ok: true, authorizationCode: string } | { ok: false }} ArcaValidation
 * @typedef {object} ArcaPort
 * @property {(dni: string) => Promise<ArcaValidation>} validate
 *
 * Runs fn with repositories whose writes commit together or not at all.
 * @typedef {<T>(fn: (repositories: Repositories) => Promise<T>) => Promise<T>} Atomically
 */

export {};
