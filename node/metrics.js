// The only module in node/ that talks to the metrics agent. The rest of the
// service calls the functions below, so every metric name is decided in this
// file.
//
// The agent is the Datadog agent Ansible installs on every VMSS instance
// (ansible/vmss_setup.yml). Its DogStatsD listens on 127.0.0.1:8125, and it
// tags every metric with the instance's `host`, so nothing here names the
// instance.
//
// Names are fixed; what varies goes in a tag (`route:`, `status:`,
// `outcome:`). tp1 sent to Graphite, which has no tags, so it wrote the
// replica and the route into the name. In Datadog that would be one metric per
// node and route: a dashboard would need a new query for every new instance.
//
// Durations are distributions, not timers: Datadog computes their percentiles
// over the samples of every node. A timer is aggregated by each agent, and the
// p95 of two nodes cannot be taken from the p95 of each.
import { StatsD } from "hot-shots";

import config from "./config.js";

// Off only for the overhead probe: the same scenario, with and without the
// instrument. The baseline is the received code plus this instrumentation.
export const metricsEnabled = process.env.METRICS_ENABLED !== "false";

const client = metricsEnabled
  ? new StatsD({
      host: config.metricsHost,
      port: config.metricsPort,
      // Not "exchange.": Datadog reserves that namespace for its Microsoft
      // Exchange Server integration, treats every metric under it as an
      // integration metric and refuses to configure its tags, so the
      // distributions' percentiles cannot be enabled.
      prefix: "arvault.",
      // Uncached, every send resolves the host through dns.lookup, which runs
      // on the libuv threadpool: the instrument would compete with the
      // service it measures.
      cacheDns: true,
      maxBufferSize: 1024,
      // Below the agent's 10 s flush, so batching never pushes a sample into
      // the next interval.
      bufferFlushInterval: 250,
      // A metrics fault must never take down the service under test. UDP loses
      // packets silently anyway; a send error is no different.
      errorHandler: () => {},
    })
  : null;

export function msSince(startedAt) {
  return Number(process.hrtime.bigint() - startedAt) / 1e6;
}

// ── HTTP ────────────────────────────────────────────────────────────────────

// `route` is a label from the allow-list in http.js, never the URL, so a
// caller cannot mint new series.
export function recordHttpDuration(route, ms) {
  client?.distribution("http.duration", ms, [`route:${route}`]);
}

export function countHttpStatus(route, code) {
  client?.increment("http.responses", 1, [`route:${route}`, `status:${code}`]);
}

export function gaugeResponseBytes(route, bytes) {
  client?.gauge("http.response.bytes", bytes, [`route:${route}`]);
}

// Errors answered by error-handler.js, by code. The code comes from the fixed
// set in errors.js, never from the request.
export function countHandledError(code) {
  client?.increment("http.errors", 1, [`code:${code.toLowerCase()}`]);
}

// ── Runtime ─────────────────────────────────────────────────────────────────

export function gaugeEventLoopLag({ p50, p99, max }) {
  client?.gauge("runtime.eventloop.lag.p50", p50);
  client?.gauge("runtime.eventloop.lag.p99", p99);
  client?.gauge("runtime.eventloop.lag.max", max);
}

export function gaugeHeap({ used, rss }) {
  client?.gauge("runtime.heap.used", used);
  client?.gauge("runtime.heap.rss", rss);
}

// The cgroup limits of the process, when it has any. tp1's containers had
// them; pm2 on a VMSS instance sets none, and the gauges are then not sent.
export function gaugeContainerLimits({ cpuNs, memoryBytes }) {
  if (cpuNs != null) {
    client?.gauge("runtime.limit.cpu_ns", cpuNs);
  }
  if (memoryBytes != null) {
    client?.gauge("runtime.limit.memory_bytes", memoryBytes);
  }
}

// ── Exchange ────────────────────────────────────────────────────────────────

// From after ARCA's validation to the response: the same span as tp1's.
//
// Not "exchange.duration": Datadog accepted a tag configuration for
// arvault.exchange.duration and dropped it within a minute, and its UI could
// not enable percentiles on it either. A new name with the same type and tags
// kept them. The cause was not found.
export function recordExchangeDuration(ms) {
  client?.distribution("exchange.processing.duration", ms);
}

// "attempted" or "ok".
export function countExchangeOutcome(outcome) {
  client?.increment("exchange.outcomes", 1, [`outcome:${outcome}`]);
}

export function countExchangeFailure(cause) {
  client?.increment("exchange.failures", 1, [`cause:${cause}`]);
}

// Lab only. These are the house's cash positions, sent in plain text to an
// agent on the same host. A production deployment would drop this gauge and
// reconcile GET /accounts before and after each run against the exchange log
// instead; nothing else in this file exposes business data.
export function gaugeAccountBalance(currency, balance) {
  client?.gauge("accounts.balance", balance, [`currency:${currency}`]);
}

// ── ARCA ────────────────────────────────────────────────────────────────────

// Every validation, whatever its outcome.
export function recordArcaValidationDuration(ms) {
  client?.distribution("arca.validation.duration", ms);
}

// "approved", "rejected" or "error".
export function countArcaValidation(outcome) {
  client?.increment("arca.validation.outcomes", 1, [`outcome:${outcome}`]);
}
