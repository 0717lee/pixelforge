#!/usr/bin/env node
// Reproducible host-side benchmark; no image I/O, canvas or Worker transport.
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import os from "node:os";
import { apply_filter } from "../web/dist/web.js";
import { WasmPipeline } from "../web/wasm-pipeline.js";

const width = 512, height = 512, warmup = 5, samples = 20;
const operations = [{ id: 0, amount: 0 }, { id: 4, amount: 0 }, { id: 2, amount: 10 }];
const source = Uint8ClampedArray.from({ length: width * height * 4 }, (_, i) => i % 251);
const wasm = new WasmPipeline(await WebAssembly.compile(await readFile(new URL("../web/dist/wasmcore.wasm", import.meta.url))));
const runners = {
  js() {
    let pixels = new Uint8ClampedArray(source);
    for (const { id, amount } of operations) pixels = apply_filter(pixels, width, height, id, amount);
    return pixels;
  },
  wasm() { return wasm.apply(new Uint8ClampedArray(source), width, height, operations); },
};
assert.deepEqual(Buffer.from(runners.js()), Buffer.from(runners.wasm()));
for (let i = 0; i < warmup; i++) { runners.js(); runners.wasm(); }
const timings = { js: [], wasm: [] };
for (let i = 0; i < samples; i++) {
  // Alternate order to reduce a systematic first/second-engine bias.
  for (const engine of i % 2 ? ["wasm", "js"] : ["js", "wasm"]) {
    const start = performance.now();
    runners[engine]();
    timings[engine].push(performance.now() - start);
  }
}
const results = {};
for (const [engine, values] of Object.entries(timings)) {
  values.sort((a, b) => a - b);
  results[engine] = {
    medianMs: (values[samples / 2 - 1] + values[samples / 2]) / 2,
    p95Ms: values[Math.ceil(samples * 0.95) - 1],
  };
}
const manifest = await readFile(new URL("../moon.mod", import.meta.url), "utf8");
console.log(JSON.stringify({
  version: manifest.match(/^version\s*=\s*"([^"]+)"/m)[1],
  node: process.version, platform: `${os.platform()} ${os.release()} ${os.arch()}`, cpu: os.cpus()[0].model,
  width, height, input: "RGBA byte at index i = i % 251", operations, warmup, samples,
  measured: "source/result copying and filters; excludes decoding, canvas and Worker transport",
  pixelEquality: true, results, wasmMemoryBytes: wasm.instance.exports.memory.buffer.byteLength,
}, null, 2));
