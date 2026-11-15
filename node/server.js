// The process entry point: loads the state, starts the timers and binds the
// ports. It exports nothing, so a test has no reason to import it: it builds
// the app with createApp() over a memory store instead (H-21).
//
// H-38: the process terminates TLS itself. The app answers only over HTTPS;
// plain HTTP gets a 308 to HTTPS and never reaches it.
import { readFileSync } from "node:fs";
import http from "node:http";
import https from "node:https";

import { compose } from "./compose.js";
import config from "./config.js";
import { transfer } from "./transfer.js";
import { redirectToHttps, withHsts } from "./transport.js";

const app = await compose({ transfer });

const tls = {
  cert: readFileSync(config.tlsCertPath),
  key: readFileSync(config.tlsKeyPath),
  minVersion: "TLSv1.2",
};

https.createServer(tls, withHsts(app)).listen(config.httpsPort, () => {
  console.log(`Exchange API listening on port ${config.httpsPort} (HTTPS)`);
});

http.createServer(redirectToHttps).listen(config.redirectPort, () => {
  console.log(`Redirecting HTTP on port ${config.redirectPort} to HTTPS`);
});
