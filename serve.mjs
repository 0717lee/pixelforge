// Minimal dependency-free static server for the Playground. Serves the web/
// directory so the ES module + its relative ./dist/web.js import resolve.
import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { extname, join, relative, resolve, isAbsolute, sep } from "node:path";

const rootDir = resolve(join(fileURLToPath(new URL(".", import.meta.url)), "web"));
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
    if (req.method !== "GET" && req.method !== "HEAD") {
      res.writeHead(405, { allow: "GET, HEAD" }).end("405 Method Not Allowed");
      return;
    }
    let urlPath = decodeURIComponent(new URL(req.url || "/", "http://localhost").pathname);
    if (urlPath === "/") urlPath = "/index.html";
    const filePath = resolve(rootDir, `.${urlPath}`);
    const rel = relative(rootDir, filePath);
    if (rel === ".." || rel.startsWith(`..${sep}`) || isAbsolute(rel) || filePath === rootDir) {
      res.writeHead(403).end("403 Forbidden");
      return;
    }
    const data = await readFile(filePath);
    res.writeHead(200, { "content-type": types[extname(filePath)] || "application/octet-stream" });
    if (req.method === "HEAD") { res.end(); return; }
    res.end(data);
  } catch (err) {
    if (err instanceof URIError) {
      res.writeHead(400, { "content-type": "text/plain; charset=utf-8" }).end("400 Bad Request");
      return;
    }
    res.writeHead(404, { "content-type": "text/plain; charset=utf-8" }).end("404 Not Found");
  }
}).listen(port, "127.0.0.1", () => console.log(`PixelForge Playground running at http://127.0.0.1:${port}`));
