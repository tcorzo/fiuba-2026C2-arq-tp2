// The process entry point: loads the state, starts the timers and binds the
// port. It exports nothing, so a test has no reason to import it: it builds
// the app with createApp() over a memory store instead (H-21).
import { compose } from "./compose.js";
import { transfer } from "./transfer.js";

const app = await compose({ transfer });
const port = 3000;

app.listen(port, () => {
  console.log(`Exchange API listening on port ${port}`);
});
