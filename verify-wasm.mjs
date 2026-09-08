// Standalone check of the genuine-WebAssembly binding (run: `node verify-wasm.mjs`).
// Bulk-copies pixels into the module's exported linear memory, runs real
// filters in WebAssembly, and reads the results back — mirroring what the
// Playground does. Uses the committed artifact in web/dist so it runs from a
// fresh clone without a MoonBit build.
import { readFile } from "node:fs/promises";

const bytes = await readFile(new URL("./web/dist/wasmcore.wasm", import.meta.url));
const { instance } = await WebAssembly.instantiate(bytes, {});
const { memory, alloc, process } = instance.exports;

if (!(memory instanceof WebAssembly.Memory)) {
  throw new Error("wasmcore.wasm does not export a linear memory named `memory`");
}
if (typeof alloc !== "function" || typeof process !== "function") {
  throw new Error("wasmcore.wasm must export alloc and process functions");
}

function runFilter(src, w, h, id, amount) {
  if (!Number.isInteger(w) || !Number.isInteger(h) || w <= 0 || h <= 0) {
    throw new Error(`invalid dimensions ${w}x${h}`);
  }
  const len = w * h * 4;
  if (src.length !== len) {
    throw new Error(`input length ${src.length} does not match ${w}x${h} RGBA buffer (${len})`);
  }
  const p = alloc(len);
  if (!Number.isInteger(p) || p < 0 || p + len > memory.buffer.byteLength) {
    throw new Error(`alloc returned invalid pointer ${p} for ${len} bytes`);
  }
  new Uint8Array(memory.buffer, p, len).set(src); // bulk write, zero per-byte FFI
  const r = process(p, w, h, id, amount);
  if (!Number.isInteger(r) || r < 0 || r + len > memory.buffer.byteLength) {
    throw new Error(`process returned invalid pointer ${r} for ${len} bytes`);
  }
  // Re-view memory in case process() grew it, then copy the result out.
  return Array.from(new Uint8Array(memory.buffer).subarray(r, r + len));
}

let failures = 0;
const check = (label, got, want) => {
  const ok = JSON.stringify(got) === JSON.stringify(want);
  console.log(`${ok ? "PASS" : "FAIL"} ${label} -> ${JSON.stringify(got)}`);
  if (!ok) {
    failures += 1;
    console.log(`  want -> ${JSON.stringify(want)}`);
  }
};

const src = [100, 200, 30, 128, 0, 0, 0, 255, 255, 255, 255, 255, 10, 20, 30, 40];
check("wasm invert (id 1)", runFilter(src, 2, 2, 1, 0), [155, 55, 225, 128, 255, 255, 255, 255, 0, 0, 0, 255, 245, 235, 225, 40]);
check("wasm grayscale (id 0)", runFilter(src, 2, 2, 0, 0), [150, 150, 150, 128, 0, 0, 0, 255, 255, 255, 255, 255, 18, 18, 18, 40]);
// A convolution filter allocates internally — good pointer-stability stress.
check("wasm gaussian blur runs (id 4) length", [runFilter(src, 2, 2, 4, 0).length], [16]);

if (failures > 0) {
  console.error(`WASM verification failed: ${failures} check(s)`);
  process.exitCode = 1;
} else {
  console.log("WASM verification passed");
}
