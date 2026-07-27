// PixelForge Web Worker — runs the same MoonBit pipeline off the main
// thread. Both engines are supported: the js backend is imported as a
// module, the linear-memory wasm module is instantiated locally. Pixel
// buffers travel in and out as transferables, so large images never block
// the UI and never get structured-clone copied.
import { apply_filter } from "./dist/web.js";

let wasmInstance = null;
try {
  const res = await fetch("./dist/wasmcore.wasm");
  const { instance } = await WebAssembly.instantiate(await res.arrayBuffer(), {});
  wasmInstance = instance;
} catch {
  // JS backend remains available; the main thread already reports this.
}

function applyFilterWasm(src, w, h, id, amount) {
  const ex = wasmInstance.exports;
  const len = w * h * 4;
  const ptr = ex.alloc(len);
  new Uint8Array(ex.memory.buffer, ptr, len).set(src);
  const resPtr = ex.process(ptr, w, h, id, amount);
  return new Uint8ClampedArray(new Uint8Array(ex.memory.buffer).subarray(resPtr, resPtr + len));
}

function applyOne(data, w, h, id, amount, engine) {
  return engine === "wasm" && wasmInstance
    ? applyFilterWasm(data, w, h, id, amount)
    : apply_filter(data, w, h, id, amount);
}

// { seq, buffer, w, h, ops: [{ id, amount }], engine } ->
// { seq, buffer, ms } (buffer transferred back).
self.onmessage = (e) => {
  const { seq, buffer, w, h, ops, engine } = e.data;
  const t0 = performance.now();
  let data = new Uint8ClampedArray(buffer);
  for (const op of ops) data = applyOne(data, w, h, op.id, op.amount, engine);
  const out = data.buffer.byteLength === w * h * 4 ? data : data.slice();
  self.postMessage({ seq, buffer: out.buffer, ms: performance.now() - t0 }, [out.buffer]);
};

self.postMessage({ ready: true });
