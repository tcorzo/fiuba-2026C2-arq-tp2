import { readFileSync } from "node:fs";
import { monitorEventLoopDelay } from "node:perf_hooks";

import {
  gaugeContainerLimits,
  gaugeEventLoopLag,
  gaugeHeap,
  metricsEnabled,
} from "./metrics.js";

// The libuv sampling interval. The histogram records the whole interval
// between timer fires, not only the late part, so an idle loop reads back
// about this value. Subtracting it makes an idle service read zero instead of
// a permanent 10 ms, at the cost of under-reporting a long stall by at most
// one resolution.
const LOOP_RESOLUTION_MS = 10;

function lagAboveResolution(nanoseconds) {
  return Math.max(0, nanoseconds / 1e6 - LOOP_RESOLUTION_MS);
}

// cgroup v2, as tp1 read it inside its containers. "max" means no limit,
// which is how tp1's received docker-compose.yml ran, and pm2 on a VMSS
// instance sets none either; the gauge is then left out rather than sent as
// a number no percentage can be taken against.
function readCgroup(file) {
  try {
    return readFileSync(`/sys/fs/cgroup/${file}`, "utf8").trim();
  } catch {
    return "max";
  }
}

// CPU time the container may use per second of wall time, in nanoseconds: the
// unit cAdvisor's cpu_cumulative_usage grows in. "25000 100000" -> 250000000.
function cpuLimitNs() {
  const [quota, period] = readCgroup("cpu.max").split(" ");
  return quota === "max" ? null : (Number(quota) * 1e9) / Number(period);
}

function memoryLimitBytes() {
  const limit = readCgroup("memory.max");
  return limit === "max" ? null : Number(limit);
}

// Once a second: event-loop lag, which is what a blocked loop (H-11)
// costs every request; the heap, where all the state lives (H-09); and the
// container limits the dashboard reads CPU and memory against.
export function startRuntimeMetrics() {
  if (!metricsEnabled) return;

  // Read once: a limit does not change during a run. Re-sent every tick all
  // the same, because statsd drops a gauge that goes one flush without a value
  // (deleteIdleStats).
  const limits = { cpuNs: cpuLimitNs(), memoryBytes: memoryLimitBytes() };

  // Sampled every 10 ms by libuv, so it catches pauses a once-a-second poll
  // would miss. Published as gauges: a statsd timer fed one value per second
  // has no meaningful percentile.
  const histogram = monitorEventLoopDelay({ resolution: LOOP_RESOLUTION_MS });
  histogram.enable();

  // Unref'd: a pending tick must never be what keeps the process alive.
  setInterval(() => {
    gaugeEventLoopLag({
      p50: lagAboveResolution(histogram.percentile(50)),
      p99: lagAboveResolution(histogram.percentile(99)),
      max: lagAboveResolution(histogram.max),
    });
    histogram.reset();

    const { heapUsed, rss } = process.memoryUsage();
    gaugeHeap({ used: heapUsed, rss });
    gaugeContainerLimits(limits);
  }, 1000).unref();
}
