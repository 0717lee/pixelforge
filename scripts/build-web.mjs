#!/usr/bin/env node
// Build and synchronize the browser artifacts consumed by web/index.html.
// Usage:
//   node scripts/build-web.mjs          # build MoonBit targets and copy artifacts
//   node scripts/build-web.mjs --check  # build targets and fail when web/dist is stale
import { cp, mkdir, readFile } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import path from "node:path";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const checkOnly = process.argv.includes("--check");

function runMoon(args) {
  const result = spawnSync("moon", args, {
    cwd: root,
    stdio: "inherit",
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(`moon ${args.join(" ")} failed with exit code ${result.status}`);
  }
}

runMoon(["build", "--release", "--target", "js"]);
runMoon(["build", "--release", "--target", "wasm"]);

const artifacts = [
  ["_build/js/release/build/web/web.js", "web/dist/web.js"],
  ["_build/wasm/release/build/wasmcore/wasmcore.wasm", "web/dist/wasmcore.wasm"],
];

for (const [source, destination] of artifacts) {
  const sourcePath = path.join(root, source);
  const destinationPath = path.join(root, destination);
  const sourceBytes = await readFile(sourcePath);
  let destinationBytes;
  try {
    destinationBytes = await readFile(destinationPath);
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
  }
  const same = destinationBytes && Buffer.compare(sourceBytes, destinationBytes) === 0;
  if (checkOnly) {
    if (!same) {
      throw new Error(`${destination} is stale; run node scripts/build-web.mjs and commit the generated artifact`);
    }
    console.log(`OK ${destination}`);
  } else {
    await mkdir(path.dirname(destinationPath), { recursive: true });
    await cp(sourcePath, destinationPath);
    console.log(`COPIED ${source} -> ${destination}`);
  }
}
