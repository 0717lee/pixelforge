// Minimal dependency-free static server for the Playground. Serves the web/
// directory so the ES module + its relative ./dist/web.js import resolve.
import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { extname, join, normalize } from "node:path";

const rootDir = join(fileURLToPath(new URL(".", import.meta.url)), "web");
const port = 8123;
const types = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".map": "application/json",
  ".wasm": "application/wasm",
  ".json": "application/json",
  ".png": "image/png",
  ".svg": "image/svg+xml",
};

createServer(async (req, res) => {
  try {
    let urlPath = decodeURIComponent(new URL(req.url, "http://localhost").pathname);
    if (urlPath === "/") urlPath = "/index.html";
    const filePath = normalize(join(rootDir, urlPath));
    if (!filePath.startsWith(rootDir)) {
      res.writeHead(403).end("403 Forbidden");
      return;
    }
    const data = await readFile(filePath);
    res.writeHead(200, { "content-type": types[extname(filePath)] || "application/octet-stream" });
    res.end(data);
  } catch {
    res.writeHead(404, { "content-type": "text/plain; charset=utf-8" }).end("404 Not Found");
  }
}).listen(port, () => console.log(`PixelForge Playground running at http://localhost:${port}`));
