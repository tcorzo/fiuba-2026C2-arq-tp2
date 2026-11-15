// Measures how many name lookups per second Node completes on this machine,
// the way Artillery's HTTP engine resolves the target: dns.lookup, which runs
// getaddrinfo on libuv's thread pool (4 threads unless UV_THREADPOOL_SIZE says
// otherwise). Every lookup starts at once; the wait of each one is its queue
// time plus its own resolution.
//
//   node perf/dns-bench.mjs <hostname> <lookups>
import dns from 'node:dns/promises';

const [host, count] = [process.argv[2], Number(process.argv[3])];
const waits = [];
const start = performance.now();
await Promise.all(
  Array.from({ length: count }, async () => {
    const t = performance.now();
    await dns.lookup(host);
    waits.push(performance.now() - t);
  }),
);
const seconds = (performance.now() - start) / 1000;
waits.sort((a, b) => a - b);
const at = (q) => waits[Math.min(count - 1, Math.floor(count * q))].toFixed(1);
console.log(
  `host=${host} pool=${process.env.UV_THREADPOOL_SIZE ?? 4} lookups=${count} ` +
    `lookups_per_s=${(count / seconds).toFixed(0)} wait_median_ms=${at(0.5)} ` +
    `wait_p95_ms=${at(0.95)} wait_max_ms=${waits[count - 1].toFixed(0)}`,
);
