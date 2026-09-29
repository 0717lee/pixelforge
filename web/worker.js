// PixelForge Web Worker — runs the same MoonBit pipeline off the main
// thread. Both engines are supported: the js backend is imported as a
// module, the linear-memory wasm module is instantiated locally. Pixel
// buffers travel in and out as transferables, so large images never block
// the UI and never get structured-clone copied.
import { apply_filter } from "./dist/web.js";
import { WasmPipeline } from "./wasm-pipeline.js";

let wasmPipeline = null;
const MAX_PIXELS = 16_000_000;
try {
  const res = await fetch("./dist/wasmcore.wasm");
  wasmPipeline = new WasmPipeline(await WebAssembly.compile(await res.arrayBuffer()));
} catch {
  // JS backend remains available; the main thread already reports this.
}

// { seq, generation, buffer, w, h, ops: [{ id, amount }], engine } ->
// { seq, generation, w, h, buffer, ms } (buffer transferred back), or error.
self.onmessage = (e) => {
  const { seq, generation, buffer, w, h, ops, engine } = e.data || {};
  try {
    if (!Number.isInteger(w) || !Number.isInteger(h) || w < 1 || h < 1 || w * h > MAX_PIXELS) {
      throw new Error("图像尺寸超出 Worker 限制");
    }
    if (!buffer || buffer.byteLength !== w * h * 4) throw new Error("像素缓冲区大小无效");
    const t0 = performance.now();
    let data = new Uint8ClampedArray(buffer);
    if (engine === "wasm" && wasmPipeline) data = wasmPipeline.apply(data, w, h, ops || []);
    else for (const op of ops || []) data = apply_filter(data, w, h, op.id, op.amount);
    const out = data.byteLength === w * h * 4 ? data : data.slice();
    self.postMessage({ seq, generation, w, h, buffer: out.buffer, ms: performance.now() - t0 }, [out.buffer]);
  } catch (err) {
    self.postMessage({ seq, generation, w, h, error: err?.message || String(err) });
  }
};

self.postMessage({ ready: true });
