// Prints the raw body of every POST /exchange and the JSON type of its dni.
import http from "node:http";
http.createServer((req, res) => {
  let body = "";
  req.on("data", (c) => (body += c));
  req.on("end", () => {
    if (req.method === "POST" && req.url === "/exchange") {
      const dni = JSON.parse(body).dni;
      console.log(`${body}  typeof dni=${typeof dni}`);
    }
    res.writeHead(200, { "content-type": "application/json" });
    res.end("{}");
  });
}).listen(18080, "127.0.0.1", () => console.error("listening on 127.0.0.1:18080"));
