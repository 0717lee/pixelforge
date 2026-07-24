// Standalone check of the genuine-WebAssembly binding (run: `node verify-wasm.mjs`).
// Bulk-copies pixels into the module's exported linear memory, runs real
// filters in WebAssembly, and reads the results back — mirroring what the
// Playground does. Uses the committed artifact in web/dist so it runs from a
// fresh clone without a MoonBit build.
import { readFile } from "node:fs/promises";

const bytes = await readFile("./web/dist/wasmcore.wasm");
const { instance } = await WebAssembly.instantiate(await bytes, {});
const { memory, alloc, process } = instance.exports;

function runFilter(src, w, h, id, amount) {
  const len = w * h * 4;
  const p = alloc(len);
  new Uint8Array(memory.buffer, p, len).set(src); // bulk write, zero per-byte FFI
  const r = process(p, w, h, id, amount);
  // Re-view memory in case process() grew it, then copy the result out.
  return Array.from(new Uint8Array(memory.buffer).subarray(r, r + len));
}

const check = (label, got, want) => {
  const ok = JSON.stringify(got) === JSON.stringify(want);
  console.log(`${ok ? "PASS" : "FAIL"} ${label} -> ${JSON.stringify(got)}`);
  if (!ok) console.log(`  want -> ${JSON.stringify(want)}`);
};

const src = [100, 200, 30, 128, 0, 0, 0, 255, 255, 255, 255, 255, 10, 20, 30, 40];
check("wasm invert (id 1)", runFilter(src, 2, 2, 1, 0), [155, 55, 225, 128, 255, 255, 255, 255, 0, 0, 0, 255, 245, 235, 225, 40]);
check("wasm grayscale (id 0)", runFilter(src, 2, 2, 0, 0), [150, 150, 150, 128, 0, 0, 0, 255, 255, 255, 255, 255, 18, 18, 18, 40]);
// A convolution filter allocates internally — good pointer-stability stress.
check("wasm gaussian blur runs (id 4) length", [runFilter(src, 2, 2, 4, 0).length], [16]);
