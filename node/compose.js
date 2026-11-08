import { createArcaClient } from "./arca.js";
import config from "./config.js";
import { createExchange } from "./exchange.js";
import { createApp } from "./http.js";
import {
  connectStore,
  createPgAtomically,
  createPgRepositories,
} from "./pg-repositories.js";
import { startRuntimeMetrics } from "./runtime-metrics.js";

// The one place that decides what wraps what. server.js hands it the real
// transfer service; a test rig outside the image can hand it another.
export async function compose({ transfer }) {
  startRuntimeMetrics();

  const pool = await connectStore(config.databaseUrl);
  const exchange = createExchange({
    repositories: createPgRepositories(pool),
    atomically: createPgAtomically(pool),
    transfer,
    arca: createArcaClient({
      uri: config.arcaUri,
      timeoutMs: config.arcaTimeoutMs,
    }),
  });

  return createApp(exchange);
}
