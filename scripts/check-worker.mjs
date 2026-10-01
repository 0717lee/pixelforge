#!/usr/bin/env node
// Exercise the actual browser worker module in Node worker_threads, bridging
// only its host messaging and fetch APIs. Pixel processing uses real JS/WASM.
import assert from "node:assert/strict";
import { Worker } from "node:worker_threads";
import { apply_filter } from "../web/dist/web.js";

const moduleUrl = new URL("../web/worker.js", import.meta.url).href;
const wasmUrl = new URL("../web/dist/wasmcore.wasm", import.meta.url).href;
const bootstrap = `
import { parentPort, workerData } from 'node:worker_threads';
import { readFile } from 'node:fs/promises';
globalThis.self = { postMessage: (message, transfer) => parentPort.postMessage(message, transfer) };
globalThis.fetch = async () => {
  if (!workerData.wasm) throw new Error('WASM unavailable for regression');
  const bytes = await readFile(new URL(workerData.wasmUrl));
  return { arrayBuffer: async () => bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) };
};
await import(workerData.moduleUrl);
parentPort.on('message', data => self.onmessage({data}));
`;

function response(worker, send) {
  return new Promise((resolve, reject) => {
    const cleanup = () => {
      clearTimeout(timer);
      worker.off("message", done);
      worker.off("error", fail);
    };
    const done = value => { cleanup(); resolve(value); };
    const fail = error => { cleanup(); reject(error); };
    const timer = setTimeout(() => fail(new Error("Worker response timed out")), 15000);
    worker.once("message", done);
    worker.once("error", fail);
    send?.();
  });
}

for (const wasm of [true, false]) {
  const worker = new Worker(new URL(`data:text/javascript,${encodeURIComponent(bootstrap)}`), {
    workerData: { wasm, moduleUrl, wasmUrl },
  });
  try {
    assert.equal((await response(worker)).ready, true);
    let seq = 0;
    const request = async (engine, overrides = {}) => {
      const buffer = Uint8Array.of(10, 20, 30, 255, 40, 50, 60, 128).buffer;
      const message = { seq: ++seq, generation: 7, engine, w: 2, h: 1, buffer, ops: [{ id: 1, amount: 0 }], ...overrides };
      const result = await response(worker, () => worker.postMessage(message, message.buffer instanceof ArrayBuffer ? [message.buffer] : []));
      assert.equal(result.seq, seq);
      assert.equal(result.generation, 7);
      if (message.buffer instanceof ArrayBuffer) assert.equal(message.buffer.byteLength, 0);
      return result;
    };
    for (const engine of ["js", "wasm"]) {
      const result = await request(engine);
      if (engine === "wasm" && !wasm) {
        assert.match(result.error, /WebAssembly/);
        assert.equal(result.buffer, undefined);
      } else {
        assert.equal(result.error, undefined);
        assert.equal(result.engine, engine);
        assert.deepEqual(new Uint8Array(result.buffer), apply_filter(Uint8Array.of(10,20,30,255,40,50,60,128), 2, 1, 1, 0));
      }
    }
    for (const overrides of [{w:0}, {buffer:new Uint8Array(8)}, {ops:{}}, {ops:[{id:1, amount:Infinity}]}]) {
      assert.ok((await request("js", overrides)).error);
    }
    assert.ok((await request("unknown")).error);
    // A rejected request must not poison subsequent work in the same worker.
    assert.equal((await request("js")).error, undefined);
  } finally {
    await worker.terminate();
  }
}
console.log("OK Worker: real JS/WASM pixels, explicit unavailable engine, transfer ownership, validation and recovery");
