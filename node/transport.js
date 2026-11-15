// H-38: the Node process terminates TLS. The Azure load balancer is layer 4
// and only forwards TCP, so the service has two listeners: the app over
// HTTPS, and a plain HTTP one whose only answer is a redirect to HTTPS.
// server.js binds them; this module builds the request handlers and has no
// effects of its own.

// One year, as tp1's nginx sent it. A browser that saw it once never tries
// plain HTTP again for this host.
export const HSTS = "max-age=31536000";

// The app behind the HTTPS listener: every response carries HSTS.
export function withHsts(app) {
  return (req, res) => {
    res.setHeader("Strict-Transport-Security", HSTS);
    app(req, res);
  };
}

// The plain HTTP listener. 308, not 301 or 302: it keeps the method and the
// body, so a POST /exchange is not replayed as a GET (tp1, H-38). The port in
// the Host header is dropped: the client reaches HTTPS on the default 443,
// which the load balancer maps to this process.
export function redirectToHttps(req, res) {
  const host = (req.headers.host ?? "").replace(/:\d+$/, "");
  if (host === "") {
    res.writeHead(400).end();
    return;
  }
  res.writeHead(308, { Location: `https://${host}${req.url}` }).end();
}
