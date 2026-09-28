/**
 * Node dev server for the browser test console (harness/index.html).
 *
 * Its ONLY jobs are: serve index.html, and proxy the browser's /v1/* and
 * /healthz calls to the Python backend so the browser never holds a token or a
 * key. In production the real Android app talks to the Python backend directly
 * with a real Supabase JWT; this file is a local convenience, never deployed.
 *
 * It holds no Anthropic/WHO/DB secret. The one thing it injects is a DEV bearer
 * token, which the backend accepts only when DEV_MODE=1.
 *
 *   Terminal 1:  DEV_MODE=1 uvicorn app.main:app --port 8000
 *   Terminal 2:  node harness/server.js           # open http://localhost:5173
 *
 * No dependencies — Node 18+ standard library only.
 */
const http = require("http");
const fs = require("fs");
const path = require("path");

const PORT = process.env.HARNESS_PORT || 5173;
const BACKEND = process.env.BACKEND_URL || "http://127.0.0.1:8000";
const DEV_TOKEN = process.env.DEV_TOKEN || "dev-L2"; // backend maps this to a verified L2 clinician when DEV_MODE=1

function proxy(req, res, bodyChunks) {
  const target = new URL(req.url, BACKEND);
  const body = Buffer.concat(bodyChunks);
  const r = http.request(
    target,
    {
      method: req.method,
      headers: { ...req.headers, host: target.host, authorization: `Bearer ${DEV_TOKEN}` },
    },
    (up) => {
      res.writeHead(up.statusCode || 502, up.headers);
      up.pipe(res);
    }
  );
  r.on("error", (e) => {
    res.writeHead(502, { "content-type": "application/json" });
    res.end(JSON.stringify({ error: "backend_unreachable", detail: String(e), hint: `is the Python backend up at ${BACKEND}?` }));
  });
  r.end(body);
}

const server = http.createServer((req, res) => {
  const chunks = [];
  req.on("data", (c) => chunks.push(c));
  req.on("end", () => {
    // API + dev helpers → proxy to Python
    if (req.url.startsWith("/v1/") || req.url === "/healthz" || req.url.startsWith("/dev/")) {
      return proxy(req, res, chunks);
    }
    // static: only index.html is served
    const file = req.url === "/" ? "index.html" : req.url.replace(/^\//, "");
    const full = path.join(__dirname, path.basename(file));
    if (path.basename(file) === "index.html" && fs.existsSync(full)) {
      res.writeHead(200, { "content-type": "text/html; charset=utf-8" });
      return res.end(fs.readFileSync(full));
    }
    res.writeHead(404, { "content-type": "text/plain" });
    res.end("not found");
  });
});

server.listen(PORT, () => {
  console.log(`YourCounselor dev console  →  http://localhost:${PORT}`);
  console.log(`proxying /v1, /healthz, /dev  →  ${BACKEND}   (dev token: ${DEV_TOKEN})`);
});
