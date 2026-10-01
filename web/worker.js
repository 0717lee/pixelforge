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
    if (!(buffer instanceof ArrayBuffer) || buffer.byteLength !== w * h * 4) throw new Error("像素缓冲区大小无效");
    if (engine !== "js" && engine !== "wasm") throw new Error("未知的处理引擎");
    if (engine === "wasm" && !wasmPipeline) throw new Error("Worker 中的 WebAssembly 引擎不可用，请选择 JS");
    const operations = ops ?? [];
    if (!Array.isArray(operations) || operations.some(op => !op || !Number.isInteger(op.id) || !Number.isFinite(op.amount))) {
      throw new Error("滤镜参数必须包含整数 ID 和有限数值");
    }
    const t0 = performance.now();
    let data = new Uint8ClampedArray(buffer);
    if (engine === "wasm") data = wasmPipeline.apply(data, w, h, operations);
    else for (const op of operations) data = apply_filter(data, w, h, op.id, op.amount);
    if (data.byteLength !== w * h * 4) throw new Error("滤镜返回了无效的像素长度");
    const out = data.byteOffset === 0 && data.buffer.byteLength === data.byteLength ? data : data.slice();
    self.postMessage({ seq, generation, engine, w, h, buffer: out.buffer, ms: performance.now() - t0 }, [out.buffer]);
  } catch (err) {
    self.postMessage({ seq, generation, w, h, error: err?.message || String(err) });
  }
};

self.postMessage({ ready: true });
