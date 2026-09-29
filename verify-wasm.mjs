// Standalone check of the genuine-WebAssembly binding (run: `node verify-wasm.mjs`).
// Bulk-copies pixels into the module's exported linear memory, runs real
// filters in WebAssembly, and reads the results back — mirroring what the
// Playground does. Uses the committed artifact in web/dist so it runs from a
// fresh clone without a MoonBit build.
import { readFile } from "node:fs/promises";
import assert from "node:assert/strict";
import { apply_filter } from "./web/dist/web.js";
import { WasmPipeline } from "./web/wasm-pipeline.js";

const bytes = await readFile(new URL("./web/dist/wasmcore.wasm", import.meta.url));
const { instance } = await WebAssembly.instantiate(bytes, {});
const { memory, alloc, process, process_in_place } = instance.exports;

if (!(memory instanceof WebAssembly.Memory)) {
  throw new Error("wasmcore.wasm does not export a linear memory named `memory`");
}
if (typeof alloc !== "function" || typeof process !== "function") {
  throw new Error("wasmcore.wasm must export alloc and process functions");
}
if (typeof process_in_place !== "function") {
  throw new Error("wasmcore.wasm must export process_in_place for reusable pipelines");
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

function runPipelineInPlace(src, w, h, ops) {
  const len = w * h * 4;
  if (src.length !== len) throw new Error("invalid pipeline input length");
  const p = alloc(len);
  if (!Number.isInteger(p) || p < 0 || p + len > memory.buffer.byteLength) {
    throw new Error(`alloc returned invalid pointer ${p} for ${len} bytes`);
  }
  new Uint8Array(memory.buffer, p, len).set(src);
  for (const [id, amount] of ops) {
    const returned = process_in_place(p, w, h, id, amount);
    if (returned !== p) throw new Error(`process_in_place moved buffer ${p} -> ${returned}`);
    if (p + len > memory.buffer.byteLength) throw new Error("buffer fell outside linear memory");
  }
  return Array.from(new Uint8Array(memory.buffer).subarray(p, p + len));
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
check(
  "wasm in-place pipeline reuses pointer",
  runPipelineInPlace(src, 2, 2, [[1, 0], [0, 0], [2, 10]]),
  [114, 114, 114, 128, 255, 255, 255, 255, 10, 10, 10, 255, 246, 246, 246, 40],
);
const stressSrc = new Array(64).fill(0).map((_, i) => i & 255);
const stressOps = Array.from({ length: 200 }, (_, i) => [i % 2, 0]);
const stress = runPipelineInPlace(stressSrc, 4, 4, stressOps);
check("wasm in-place stress length", [stress.length], [64]);
check("wasm in-place stress preserves alpha", [stress[3], stress[7]], [3, 7]);
const identitySrc = [7, 8, 9, 10, 11, 12, 13, 14];
const identityPtr = alloc(identitySrc.length);
new Uint8Array(memory.buffer, identityPtr, identitySrc.length).set(identitySrc);
const identityReturned = process_in_place(identityPtr, 1, 2, 999, 0);
check("wasm unknown filter keeps pointer", [identityReturned], [identityPtr]);
check("wasm unknown filter keeps bytes", Array.from(new Uint8Array(memory.buffer).subarray(identityPtr, identityPtr + identitySrc.length)), identitySrc);

// Exercise the actual host used by both the Playground and Worker. A new
// input allocation on every render previously grew memory without a bound.
const pipeline = new WasmPipeline(await WebAssembly.compile(bytes));
const pixels = Uint8ClampedArray.from({ length: 256 * 256 * 4 }, (_, i) => i % 251);
const operations = [{ id: 1, amount: 0 }, { id: 4, amount: 0 }, { id: 2, amount: 10 }];
let expected = pixels;
for (const { id, amount } of operations) expected = apply_filter(expected, 256, 256, id, amount);
const first = pipeline.apply(pixels, 256, 256, operations);
assert.deepEqual(Array.from(first), Array.from(expected));
for (let i = 0; i < 5; i++) pipeline.apply(pixels, 256, 256, operations);
const warmBytes = pipeline.instance.exports.memory.buffer.byteLength;
let last;
for (let i = 0; i < 200; i++) last = pipeline.apply(pixels, 256, 256, operations);
assert.equal(pipeline.instance.exports.memory.buffer.byteLength, warmBytes, "WASM memory must plateau after warmup");
assert.deepEqual(Array.from(last), Array.from(expected));
assert.deepEqual(Array.from(first), Array.from(expected), "later renders must not overwrite earlier results");
console.log(`PASS 200 repeated renders: stable WASM memory at ${warmBytes} bytes, JS/WASM pixels agree`);

for (let round = 0; round < 10; round++) {
  for (const [width, height] of [[2, 3], [128, 128], [3, 2], [256, 256]]) {
    const input = Uint8ClampedArray.from({ length: width * height * 4 }, (_, i) => (i + round) % 256);
    const output = pipeline.apply(input, width, height, [{ id: 1, amount: 0 }]);
    assert.deepEqual(Array.from(output), Array.from(apply_filter(input, width, height, 1, 0)));
    assert.ok(pipeline.instance.exports.memory.buffer.byteLength <= warmBytes, "image changes must not accumulate old allocations");
  }
}
assert.throws(() => pipeline.apply(new Uint8Array(1), 1, 1, []), /Invalid WASM/);
console.log("PASS repeated image-size changes and independent output buffers");

if (failures > 0) {
  console.error(`WASM verification failed: ${failures} check(s)`);
  process.exitCode = 1;
} else {
  console.log("WASM verification passed");
}
