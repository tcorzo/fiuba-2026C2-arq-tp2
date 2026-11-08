// The ARCA adapter: POST {uri}/validar with { dni }. The wire contract is the
// course's (`dni`, `ok`, `codigoAutorizacion`); the port it implements speaks
// English (ports.js, ArcaPort).
//
// No retry: a 500, a timeout or a malformed body is an ArcaUnavailableError,
// and the request answers 502 (issue #14).
import { ArcaUnavailableError } from "./errors.js";

export function createArcaClient({ uri, timeoutMs }) {
  const url = `${uri.replace(/\/+$/, "")}/validar`;

  async function validate(dni) {
    // One signal for the whole call: connecting, the status and the body.
    const signal = AbortSignal.timeout(timeoutMs);

    let response;
    try {
      response = await fetch(url, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ dni }),
        signal,
      });
    } catch (error) {
      throw unavailable(error);
    }

    if (response.status !== 200) {
      // Frees the connection for the next call.
      await response.body?.cancel().catch(() => {});
      throw new ArcaUnavailableError(`status_${response.status}`);
    }

    let body;
    try {
      body = await response.json();
    } catch (error) {
      throw error?.name === "TimeoutError"
        ? unavailable(error)
        : new ArcaUnavailableError("malformed_body", { cause: error });
    }

    if (body?.ok === true && typeof body.codigoAutorizacion === "string" && body.codigoAutorizacion !== "") {
      return { ok: true, authorizationCode: body.codigoAutorizacion };
    }
    if (body?.ok === false) {
      return { ok: false };
    }
    throw new ArcaUnavailableError("malformed_body");
  }

  return { validate };
}

function unavailable(error) {
  const reason = error?.name === "TimeoutError" ? "timeout" : "unreachable";
  return new ArcaUnavailableError(reason, { cause: error });
}
