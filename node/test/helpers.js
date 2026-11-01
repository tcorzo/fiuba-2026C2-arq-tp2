import { createExchange } from "../exchange.js";
import {
  createMemoryAtomically,
  createMemoryRepositories,
} from "../memory-repositories.js";

// An exchange service over a given state in memory, and no database behind it.
export function memoryService(state, transfer) {
  const repositories = createMemoryRepositories(state);
  return createExchange({
    repositories,
    atomically: createMemoryAtomically(repositories),
    transfer,
  });
}
