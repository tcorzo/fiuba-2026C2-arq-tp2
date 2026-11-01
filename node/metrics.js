// The only module in node/ that talks to statsd. The rest of the service calls
// the functions below, so every metric name is decided in this file.
//
// Counters and gauges carry the worker segment (`w0.`); timers do not. statsd
// has to see every sample of a timer under one name to compute a percentile:
// averaging the p99 of each worker does not give the p99.
import { hostname } from "node:os";
import { StatsD } from "hot-shots";

// Off only for the overhead probe: the same scenario, with and without the
// instrument. The baseline is the received code plus this instrumentation.
export const metricsEnabled = process.env.METRICS_ENABLED !== "false";

// One value per replica, so that H-13's replicas do not overwrite each
// other's gauges: counters would still add up across replicas sharing one
// value, but a gauge is last-write-wins per segment. METRICS_WORKER lets a
// single, non-replicated run pin a stable name (e.g. "w0"); every replica of
// a scaled service gets the same environment, so it stays unset there and
// this falls back to the hostname: one per VMSS instance here, one per
// container in tp1's docker-compose.perf.yml.
const worker = process.env.METRICS_WORKER ?? hostname();

const client = metricsEnabled
  ? new StatsD({
      host: process.env.METRICS_HOST ?? "graphite",
      port: Number(process.env.METRICS_PORT ?? 8125),
      prefix: "exchange.",
      // Uncached, every send resolves the host through dns.lookup, which runs
      // on the libuv threadpool the state writes also use (H-11): the
      // instrument would compete for the resource it measures.
      cacheDns: true,
      maxBufferSize: 1024,
      // Below the 1 s statsd flush, so batching never pushes a sample into the
      // next interval.
      bufferFlushInterval: 250,
      // A metrics fault must never take down the service under test. UDP loses
      // packets silently anyway; a send error is no different.
      errorHandler: () => {},
    })
  : null;

function perWorker(name) {
  return `${worker}.${name}`;
}

export function msSince(startedAt) {
  return Number(process.hrtime.bigint() - startedAt) / 1e6;
}

// ── HTTP ────────────────────────────────────────────────────────────────────

export function recordHttpDuration(route, ms) {
  client?.timing(`http.${route}.duration`, ms);
}

export function countHttpStatus(route, code) {
  client?.increment(perWorker(`http.${route}.status.${code}`));
}

export function gaugeResponseBytes(route, bytes) {
  client?.gauge(perWorker(`http.${route}.response.bytes`), bytes);
}

// Errors answered by error-handler.js, by code. The code comes from the fixed
// set in errors.js, never from the request, so it cannot mint new series.
export function countHandledError(code) {
  client?.increment(perWorker(`http.errors.${code.toLowerCase()}`));
}

// ── Runtime ─────────────────────────────────────────────────────────────────

export function gaugeEventLoopLag({ p50, p99, max }) {
  client?.gauge(perWorker("runtime.eventloop.lag.p50"), p50);
  client?.gauge(perWorker("runtime.eventloop.lag.p99"), p99);
  client?.gauge(perWorker("runtime.eventloop.lag.max"), max);
}

export function gaugeHeap({ used, rss }) {
  client?.gauge(perWorker("runtime.heap.used"), used);
  client?.gauge(perWorker("runtime.heap.rss"), rss);
}

// The limits the kernel applies to this container. The dashboard divides CPU
// and memory by these instead of by a value typed into it, so a percentage
// can never be taken against a profile other than the one the run had.
export function gaugeContainerLimits({ cpuNs, memoryBytes }) {
  if (cpuNs != null) {
    client?.gauge(perWorker("runtime.limit.cpu_ns"), cpuNs);
  }
  if (memoryBytes != null) {
    client?.gauge(perWorker("runtime.limit.memory_bytes"), memoryBytes);
  }
}

// ── Exchange ────────────────────────────────────────────────────────────────

export function recordExchangeDuration(ms) {
  client?.timing("exchange.duration", ms);
}

// "attempted" or "ok".
export function countExchangeOutcome(outcome) {
  client?.increment(perWorker(outcome));
}

export function countExchangeFailure(cause) {
  client?.increment(perWorker(`failed.${cause}`));
}

// statsd reads a leading sign as a change: "-500|g" subtracts 500 from the
// gauge instead of setting it. A negative balance is exactly what these gauges
// exist to catch (H-06, H-07), so it is sent right after a 0: statsd sets a
// gauge that holds 0 instead of adding to it.
//
// Lab only. These are the house's cash positions, sent in plain text to a
// statsd anyone on the network can read. A production deployment would drop
// this gauge and reconcile GET /accounts before and after each run against
// the exchange log instead; nothing else in this file exposes business data.
export function gaugeAccountBalance(currency, balance) {
  const stat = perWorker(`accounts.balance.${currency}`);
  if (balance < 0) client?.gauge(stat, 0);
  client?.gauge(stat, balance);
}

// ── State write path ────────────────────────────────────────────────────────

// Two timers, not one: serializing blocks the event loop, writing does not.
export function recordStateSave(file, { serializeMs, writeMs, bytes }) {
  client?.timing(`state.${file}.serialize`, serializeMs);
  client?.timing(`state.${file}.write`, writeMs);
  client?.gauge(perWorker(`state.${file}.bytes`), bytes);
}

export function countStateSaveOverlap(file) {
  client?.increment(perWorker(`state.${file}.save.overlaps`));
}

export function gaugeLogLength(entries) {
  client?.gauge(perWorker("state.log.length"), entries);
}
