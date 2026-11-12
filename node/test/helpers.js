import { createExchange } from "../exchange.js";
import {
  createMemoryAtomically,
  createMemoryRepositories,
} from "../memory-repositories.js";

// A fake ARCA port that answers every call with `answer` (a validation, or an
// error to throw), and records the DNIs it was asked about.
export function fakeArca(answer = { ok: true, authorizationCode: "test-code" }) {
  const calls = [];
  return {
    calls,
    async validate(dni) {
      calls.push(dni);
      if (answer instanceof Error) throw answer;
      return answer;
    },
  };
}

// An exchange service over a given state in memory, and no database behind it.
// ARCA approves every DNI unless the test hands it another port.
export function memoryService(state, transfer, arca = fakeArca()) {
  const repositories = createMemoryRepositories(state);
  return createExchange({
    repositories,
    atomically: createMemoryAtomically(repositories),
    transfer,
    arca,
  });
}
