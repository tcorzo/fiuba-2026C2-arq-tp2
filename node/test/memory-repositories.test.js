import {
  createMemoryAtomically,
  createMemoryRepositories,
} from "../memory-repositories.js";
import { repositoryContract } from "./repositories.contract.js";

repositoryContract("memory", async (state) => {
  const repositories = createMemoryRepositories(state);
  return { repositories, atomically: createMemoryAtomically(repositories) };
});
