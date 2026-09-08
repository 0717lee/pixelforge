// PixelForge Playground — drives the MoonBit image-processing library from the
// browser through TWO backends:
//   * "js"   — MoonBit compiled to JS; FixedArray[Byte] IS a Uint8Array, so the
//              canvas buffer crosses in with zero copies.
//   * "wasm" — MoonBit compiled to a linear-memory WebAssembly module; pixels
//              are bulk-copied into the exported memory via a Uint8Array view.
import { apply_filter, encode_png, luma_histogram } from "./dist/web.js";

// Load the genuine-WASM module (no imports required). Fall back to JS if it
// cannot be loaded for any reason.
async function loadWasm() {
  try {
    const res = await fetch("./dist/wasmcore.wasm");
    const { instance } = await WebAssembly.instantiate(await res.arrayBuffer(), {});
    return instance;
  } catch (err) {
    console.warn("WASM module unavailable, falling back to the JS backend.", err);
    return null;
  }
}
const wasmInstance = await loadWasm();

// Off-main-thread pipeline: a module worker running the exact same MoonBit
// code. Pixel buffers are posted as transferables (no structured clone).
let worker = null;
let workerReady = false;
let workerSeq = 0;
let renderGeneration = 0;
let sourceLoadToken = 0;
const MAX_FILE_BYTES = 20 * 1024 * 1024;
const MAX_PIXELS = 16_000_000;
const MAX_DIMENSION = 8192;

function setStatus(message, kind = "info") {
  const el = $("status");
  if (!el) return;
  el.textContent = message;
  el.dataset.kind = kind;
}

function invalidateWorkerResults() {
  renderGeneration += 1;
  workerSeq += 1;
}

function disableWorker(message) {
  const wasWorkerMode = threading === "worker";
  workerReady = false;
  if (worker) worker.terminate();
  worker = null;
  if (typeof threadsEl !== "undefined") {
    const workerChip = threadsEl.querySelector('[data-thread="worker"]');
    if (workerChip) workerChip.disabled = true;
  }
  if (threading === "worker") {
    threading = "main";
    if (typeof threadsEl !== "undefined") threadsEl.querySelectorAll(".chip").forEach((c) => c.classList.toggle("active", c.dataset.thread === "main"));
  }
  if (wasWorkerMode && originalData) render();
  setStatus(message, "error");
}

try {
  worker = new Worker(new URL("./worker.js", import.meta.url), { type: "module" });
  worker.addEventListener("message", (e) => {
    const payload = e.data || {};
    if (payload.ready) { workerReady = true; return; }
    const { seq, generation, buffer, ms, w, h, error } = payload;
    if (seq !== workerSeq || generation !== renderGeneration || w !== imgW || h !== imgH) return;
    if (error) {
      setStatus(`Worker 处理失败：${error}`, "error");
      return;
    }
    if (!buffer || buffer.byteLength !== w * h * 4) {
      setStatus("Worker 返回了无效的像素缓冲区。", "error");
      return;
    }
    try {
      ctx.putImageData(new ImageData(new Uint8ClampedArray(buffer), w, h), 0, 0);
      updateStats(ms);
      setStatus("处理完成。", "success");
    } catch (err) {
      setStatus(`无法显示 Worker 结果：${err.message || err}`, "error");
    }
  });
  worker.addEventListener("error", (e) => disableWorker(`Worker 不可用，已切换到主线程：${e.message || "未知错误"}`));
  worker.addEventListener("messageerror", () => disableWorker("Worker 消息无法解析，已切换到主线程。"));
} catch (err) {
  console.warn("Worker unavailable, staying on the main thread.", err);
}

// Filter ids must match @pixelforge.Image::apply_filter_id.
const FILTER = { GRAYSCALE: 0, INVERT: 1, BRIGHTNESS: 2, CONTRAST: 3, BLUR: 4, SHARPEN: 5, EMBOSS: 6, EDGES: 7, SOBEL: 8, SEPIA: 9, THRESHOLD: 10, PIXELATE: 11, MEDIAN: 12, HISTEQ: 13, FLIP_H: 14, FLIP_V: 15, POSTERIZE: 16, GAMMA: 17, VIGNETTE: 18, SCHARR: 19, CANNY: 20, OTSU: 21, DITHER: 22 };

const $ = (id) => document.getElementById(id);
const canvas = $("canvas");
const ctx = canvas.getContext("2d", { willReadFrequently: true });
const stage = $("stage");
const dropHint = $("dropHint");
const animationPreview = $("animationPreview");
const filtersEl = $("filters");
const enginesEl = $("engines");
const pipelineListEl = $("pipelineList");

let originalData = null;
let imgW = 0;
let imgH = 0;
let animationUrl = null;
let animationPreviewActive = false;
// Ordered non-destructive operation stack. Each operation is { id, amount }.
let activeFilters = [];
let undoStack = [];
let redoStack = [];
let editingHistory = false;
let engine = "js"; // default to the faster zero-copy backend; WASM is a toggle
let threading = "main"; // "main" | "worker"

const FILTER_META = {
  0: { name: "灰度" }, 1: { name: "反色" }, 2: { name: "亮度", min: -120, max: 120, step: 1, default: 20, format: (v) => `${Math.round(v)}` },
  3: { name: "对比度", min: 0, max: 3, step: 0.05, default: 1.2, format: (v) => Number(v).toFixed(2) },
  4: { name: "高斯模糊" }, 5: { name: "锐化" }, 6: { name: "浮雕" }, 7: { name: "拉普拉斯边缘" }, 8: { name: "Sobel 边缘" }, 9: { name: "棕褐色" },
  10: { name: "二值化", min: 1, max: 255, step: 1, default: 128, format: (v) => `${Math.round(v)}` },
  11: { name: "像素化", min: 2, max: 64, step: 1, default: 8, format: (v) => `${Math.round(v)} px` },
  12: { name: "中值降噪" }, 13: { name: "直方图均衡" }, 14: { name: "水平翻转" }, 15: { name: "垂直翻转" },
  16: { name: "色调分离", min: 2, max: 32, step: 1, default: 4, format: (v) => `${Math.round(v)} 级` },
  17: { name: "伽马校正", min: 0.1, max: 4, step: 0.1, default: 2.2, format: (v) => Number(v).toFixed(1) },
  18: { name: "暗角", min: 0, max: 1, step: 0.05, default: 0.5, format: (v) => Number(v).toFixed(2) },
  19: { name: "Scharr 边缘" }, 20: { name: "Canny 边缘", min: 1, max: 255, step: 1, default: 100, format: (v) => `${Math.round(v)}` },
  21: { name: "Otsu 阈值" }, 22: { name: "抖动二值" },
};

// Reinterpret a MoonBit-returned Uint8Array as clamped for ImageData, no copy.
function asClamped(buf) {
  if (buf instanceof Uint8ClampedArray) return buf;
  return new Uint8ClampedArray(buf.buffer, buf.byteOffset, buf.length);
}

// Genuine-WASM pipeline: allocate one linear-memory input buffer, apply every
// operation in place, then copy the final result out (memory may have grown
// during a call, so each view is recreated).
function applyPipelineWasm(src, w, h, ops) {
  const ex = wasmInstance.exports;
  const len = w * h * 4;
  const ptr = ex.alloc(len);
  new Uint8Array(ex.memory.buffer, ptr, len).set(src);
  for (const op of ops) {
    if (typeof ex.process_in_place === "function") {
      const returned = ex.process_in_place(ptr, w, h, op.id, op.amount);
      if (returned !== ptr) throw new Error("WASM in-place buffer pointer changed");
    } else {
      const resultPtr = ex.process(ptr, w, h, op.id, op.amount);
      const memoryView = new Uint8Array(ex.memory.buffer);
      if (resultPtr < 0 || resultPtr + len > memoryView.byteLength) throw new Error("WASM returned an invalid result pointer");
      new Uint8Array(ex.memory.buffer, ptr, len).set(memoryView.subarray(resultPtr, resultPtr + len));
    }
  }
  return new Uint8ClampedArray(new Uint8Array(ex.memory.buffer).subarray(ptr, ptr + len));
}

function applyOne(data, w, h, id, amount, eng) {
  return eng === "wasm" ? applyPipelineWasm(data, w, h, [{ id, amount }]) : apply_filter(data, w, h, id, amount);
}

// The pipeline as a flat op list (shared by main-thread and worker paths).
function pipelineOps() {
  return activeFilters.map((op) => ({ id: op.id, amount: op.amount }));
}

function syncAnimationPreview() {
  if (!animationPreview) return;
  animationPreview.hidden = !(animationPreviewActive && activeFilters.length === 0);
}

function revokeAnimationUrl() {
  if (animationUrl) URL.revokeObjectURL(animationUrl);
  animationUrl = null;
  animationPreviewActive = false;
  if (animationPreview) {
    animationPreview.removeAttribute("src");
    animationPreview.hidden = true;
  }
}

// Non-destructive pipeline from a fresh copy of the source, on the requested
// engine. The order is exactly the order shown in the operation list.
function runPipeline(eng) {
  let data = new Uint8ClampedArray(originalData.data);
  if (eng === "wasm") return applyPipelineWasm(data, imgW, imgH, pipelineOps());
  for (const op of pipelineOps()) data = applyOne(data, imgW, imgH, op.id, op.amount, eng);
  return data;
}

function updateStats(ms) {
  $("statSize").textContent = `${imgW} × ${imgH}`;
  const engineName = engine === "wasm" ? "WebAssembly" : "JS 后端";
  $("statEngine").textContent = threading === "worker" ? `${engineName} · Worker` : engineName;
  $("statTime").textContent = `${ms.toFixed(2)} ms`;
  const mpPerSec = imgW * imgH / 1e6 / (ms / 1000);
  $("statThroughput").textContent = ms > 0 ? `${mpPerSec.toFixed(1)} MP/s` : "—";
  drawHistogram();
}

// Live luma histogram of whatever is currently on the canvas, computed by
// the library's own histogram_luma through the js binding.
function drawHistogram() {
  const hc = $("histCanvas");
  if (!hc || !originalData) return;
  const hctx = hc.getContext("2d");
  const pixels = ctx.getImageData(0, 0, imgW, imgH).data;
  const bins = luma_histogram(new Uint8Array(pixels.buffer.slice(0)), imgW, imgH);
  let max = 1;
  for (let i = 0; i < 256; i++) if (bins[i] > max) max = bins[i];
  hctx.clearRect(0, 0, hc.width, hc.height);
  hctx.fillStyle = "rgba(96, 165, 250, 0.9)";
  for (let i = 0; i < 256; i++) {
    const h = Math.round(bins[i] / max * (hc.height - 4));
    if (h > 0) hctx.fillRect(i, hc.height - h, 1, h);
  }
}

function render() {
  if (!originalData) return;
  if (threading === "worker" && workerReady) {
    // Copy the source (we still need it) and hand the copy to the worker.
    const copy = new Uint8ClampedArray(originalData.data);
    workerSeq += 1;
    try {
      worker.postMessage(
        { seq: workerSeq, generation: renderGeneration, buffer: copy.buffer, w: imgW, h: imgH, ops: pipelineOps(), engine },
        [copy.buffer],
      );
    } catch (err) {
      disableWorker(`Worker 发送失败，已切换到主线程：${err.message || err}`);
    }
    return; // the worker message handler paints and updates stats
  }
  try {
    const t0 = performance.now();
    const data = runPipeline(engine);
    const elapsed = performance.now() - t0;
    ctx.putImageData(new ImageData(asClamped(data), imgW, imgH), 0, 0);
    updateStats(elapsed);
    setStatus("处理完成。", "success");
  } catch (err) {
    setStatus(`处理失败：${err.message || err}`, "error");
  }
}

let rafPending = false;
function scheduleRender() {
  if (rafPending) return;
  rafPending = true;
  requestAnimationFrame(() => { rafPending = false; render(); });
}

function setActiveChips() {
  for (const chip of filtersEl.querySelectorAll(".chip")) {
    const id = Number(chip.dataset.filter);
    chip.classList.toggle("active", id === -1 ? activeFilters.length === 0 : activeFilters.some((op) => op.id === id));
  }
}

function setActiveEngine(eng) {
  for (const chip of enginesEl.querySelectorAll(".chip")) {
    chip.classList.toggle("active", chip.dataset.engine === eng);
  }
}

function resetControls() {
  activeFilters = [];
  undoStack = [];
  redoStack = [];
  setActiveChips();
  renderPipelineList();
  updateHistoryButtons();
  syncAnimationPreview();
}

function snapshot() { return activeFilters.map((op) => ({ ...op })); }
function recordHistory() {
  undoStack.push(snapshot());
  if (undoStack.length > 50) undoStack.shift();
  redoStack = [];
  updateHistoryButtons();
}
function updateHistoryButtons() {
  $("undoBtn").disabled = undoStack.length === 0;
  $("redoBtn").disabled = redoStack.length === 0;
}
function applyStack(next, { history = true } = {}) {
  if (history) recordHistory();
  activeFilters = next.map((op) => ({ id: op.id, amount: op.amount }));
  setActiveChips();
  renderPipelineList();
  syncAnimationPreview();
  invalidateWorkerResults();
  scheduleRender();
}
function renderPipelineList() {
  if (!pipelineListEl) return;
  pipelineListEl.replaceChildren();
  if (activeFilters.length === 0) {
    const empty = document.createElement("p");
    empty.className = "pipeline-empty";
    empty.textContent = "点击上方滤镜添加操作。";
    pipelineListEl.appendChild(empty);
    updateHistoryButtons();
    return;
  }
  activeFilters.forEach((op, index) => {
    const meta = FILTER_META[op.id] || { name: `滤镜 ${op.id}` };
    const item = document.createElement("div");
    item.className = "pipeline-item";
    item.dataset.index = String(index);
    const header = document.createElement("div");
    header.className = "pipeline-item-header";
    const title = document.createElement("span");
    title.className = "pipeline-item-title";
    title.textContent = `${index + 1}. ${meta.name}`;
    header.appendChild(title);
    const actions = document.createElement("div");
    actions.className = "pipeline-item-actions";
    for (const [action, text] of [["up", "↑"], ["down", "↓"], ["remove", "×"]]) {
      const button = document.createElement("button");
      button.className = "pipeline-action";
      button.type = "button";
      button.dataset.action = action;
      button.textContent = text;
      button.title = action === "remove" ? "移除" : action === "up" ? "上移" : "下移";
      button.disabled = (action === "up" && index === 0) || (action === "down" && index === activeFilters.length - 1);
      actions.appendChild(button);
    }
    header.appendChild(actions);
    item.appendChild(header);
    if (meta.min != null) {
      const label = document.createElement("label");
      label.className = "slider pipeline-control";
      const text = document.createElement("span");
      text.innerHTML = `<span>参数</span><b>${meta.format(op.amount)}</b>`;
      const input = document.createElement("input");
      input.type = "range";
      input.min = String(meta.min); input.max = String(meta.max); input.step = String(meta.step); input.value = String(op.amount);
      input.dataset.role = "amount";
      label.append(text, input);
      item.appendChild(label);
    }
    pipelineListEl.appendChild(item);
  });
  updateHistoryButtons();
}

function useImageSource(source) {
  const sw = source.naturalWidth || source.width;
  const sh = source.naturalHeight || source.height;
  if (!sw || !sh || sw > MAX_DIMENSION || sh > MAX_DIMENSION || sw * sh > MAX_PIXELS) {
    setStatus(`图片尺寸过大（${sw} × ${sh}），限制为最长边 ${MAX_DIMENSION}px 且不超过 ${MAX_PIXELS.toLocaleString()} 像素。`, "error");
    return false;
  }
  const scale = Math.min(1, 1024 / Math.max(sw, sh));
  imgW = Math.max(1, Math.round(sw * scale));
  imgH = Math.max(1, Math.round(sh * scale));
  canvas.width = imgW;
  canvas.height = imgH;
  ctx.drawImage(source, 0, 0, imgW, imgH);
  originalData = ctx.getImageData(0, 0, imgW, imgH);
  dropHint.classList.add("hidden");
  resetControls();
  invalidateWorkerResults();
  setStatus(scale < 1 ? `图片已缩放到 ${imgW} × ${imgH} 用于预览。` : "图片已载入。", scale < 1 ? "info" : "success");
  render();
  return true;
}

function loadFile(file) {
  const token = ++sourceLoadToken;
  if (!file) return;
  if (!file.type.startsWith("image/")) {
    setStatus("请选择常见图片文件。", "error");
    return;
  }
  if (file.size > MAX_FILE_BYTES) {
    setStatus(`图片文件过大（${(file.size / 1024 / 1024).toFixed(1)} MB），限制为 ${MAX_FILE_BYTES / 1024 / 1024} MB。`, "error");
    return;
  }
  revokeAnimationUrl();
  const url = URL.createObjectURL(file);
  const isGif = file.type === "image/gif" || /\.gif$/i.test(file.name || "");
  if (isGif) {
    animationUrl = url;
    animationPreviewActive = true;
    if (animationPreview) animationPreview.src = url;
    syncAnimationPreview();
  }
  const img = new Image();
  const cleanup = () => { if (!isGif) URL.revokeObjectURL(url); };
  img.onload = () => {
    cleanup();
    if (token !== sourceLoadToken) {
      if (isGif && animationUrl === url) revokeAnimationUrl();
      return;
    }
    useImageSource(img);
  };
  img.onerror = () => {
    cleanup();
    if (isGif && animationUrl === url) revokeAnimationUrl();
    if (token === sourceLoadToken) setStatus("图片无法读取或格式不受支持。", "error");
  };
  img.src = url;
}

// A colorful procedural scene so the demo is usable with zero setup.
function loadSample() {
  sourceLoadToken += 1;
  revokeAnimationUrl();
  imgW = 900;
  imgH = 600;
  canvas.width = imgW;
  canvas.height = imgH;
  const g = ctx.createLinearGradient(0, 0, imgW, imgH);
  g.addColorStop(0, "#6d28d9");
  g.addColorStop(0.5, "#2563eb");
  g.addColorStop(1, "#0ea5e9");
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, imgW, imgH);
  for (const [color, x, y, r] of [["#f472b6", 210, 180, 120], ["#fbbf24", 690, 190, 90], ["#34d399", 730, 430, 140], ["#fb7185", 320, 460, 100]]) {
    ctx.fillStyle = color;
    ctx.beginPath();
    ctx.arc(x, y, r, 0, Math.PI * 2);
    ctx.fill();
  }
  ctx.strokeStyle = "rgba(255,255,255,0.65)";
  ctx.lineWidth = 3;
  for (let x = 0; x <= imgW; x += 90) {
    ctx.beginPath();
    ctx.moveTo(x, 0);
    ctx.lineTo(x, imgH);
    ctx.stroke();
  }
  ctx.fillStyle = "#ffffff";
  ctx.font = "bold 96px 'Segoe UI', system-ui, sans-serif";
  ctx.textBaseline = "middle";
  ctx.fillText("MoonBit", 120, 300);
  originalData = ctx.getImageData(0, 0, imgW, imgH);
  dropHint.classList.add("hidden");
  resetControls();
  invalidateWorkerResults();
  setStatus("示例图片已载入。", "success");
  render();
}

function runBenchmark() {
  if (!originalData) {
    $("benchResult").textContent = "请先载入图片";
    return;
  }
  const iterations = 20;
  runPipeline(engine); // warm up
  const t0 = performance.now();
  for (let i = 0; i < iterations; i++) runPipeline(engine);
  const avg = (performance.now() - t0) / iterations;
  const mpPerSec = imgW * imgH / 1e6 / (avg / 1000);
  $("benchResult").textContent = `平均 ${avg.toFixed(2)} ms/次 · ${mpPerSec.toFixed(1)} MP/s（${iterations} 次，${imgW}×${imgH}）`;
}

function benchEngine(eng, iterations) {
  if (eng === "wasm" && !wasmInstance) return null;
  runPipeline(eng); // warm up
  const t0 = performance.now();
  for (let i = 0; i < iterations; i++) runPipeline(eng);
  return (performance.now() - t0) / iterations;
}

function compareEngines() {
  if (!originalData) {
    $("benchResult").textContent = "请先载入图片";
    return;
  }
  const iterations = 10;
  const wasmMs = benchEngine("wasm", iterations);
  const jsMs = benchEngine("js", iterations);
  const fmt = (ms) => (ms == null ? "N/A" : `${ms.toFixed(2)} ms`);
  let ratio = "";
  if (wasmMs && jsMs) {
    ratio = wasmMs <= jsMs ? ` · WASM 快 ${(jsMs / wasmMs).toFixed(2)}×` : ` · JS 快 ${(wasmMs / jsMs).toFixed(2)}×`;
  }
  $("benchResult").textContent = `WASM ${fmt(wasmMs)} / JS ${fmt(jsMs)}（各 ${iterations} 次${ratio}）`;
}

// --- Wiring ---------------------------------------------------------------
$("uploadBtn").addEventListener("click", () => $("fileInput").click());
$("fileInput").addEventListener("change", (e) => loadFile(e.target.files[0]));
$("sampleBtn").addEventListener("click", loadSample);
$("resetBtn").addEventListener("click", () => { invalidateWorkerResults(); resetControls(); render(); });
$("downloadBtn").addEventListener("click", () => {
  if (!originalData) return;
  // Encode with the library's own pure-MoonBit PNG encoder — the download
  // is a file produced by @pixelforge.png_encode, not canvas.toBlob.
  const pixels = ctx.getImageData(0, 0, imgW, imgH).data;
  try {
    const bytes = encode_png(new Uint8Array(pixels.buffer.slice(0)), imgW, imgH);
    const blob = new Blob([bytes], { type: "image/png" });
    const a = document.createElement("a");
    const url = URL.createObjectURL(blob);
    a.href = url;
    a.download = "pixelforge.png";
    a.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
    setStatus("PNG 下载已开始。", "success");
  } catch (err) {
    setStatus(`导出 PNG 失败：${err.message || err}`, "error");
  }
});
$("benchBtn").addEventListener("click", runBenchmark);
$("compareBtn").addEventListener("click", compareEngines);

for (const chip of filtersEl.querySelectorAll(".chip")) {
  chip.addEventListener("click", () => {
    const id = Number(chip.dataset.filter);
    if (id === -1) {
      if (activeFilters.length) applyStack([]);
      return;
    } else {
      const at = activeFilters.findIndex((op) => op.id === id);
      const next = activeFilters.slice();
      if (at >= 0) next.splice(at, 1);
      else {
        const meta = FILTER_META[id] || {};
        next.push({ id, amount: meta.default ?? 0 });
      }
      applyStack(next);
    }
  });
}

pipelineListEl.addEventListener("click", (event) => {
  const button = event.target.closest("button[data-action]");
  if (!button) return;
  const item = button.closest(".pipeline-item");
  const index = Number(item?.dataset.index);
  if (!Number.isInteger(index) || !activeFilters[index]) return;
  const next = activeFilters.slice();
  const action = button.dataset.action;
  if (action === "remove") next.splice(index, 1);
  if (action === "up" && index > 0) [next[index - 1], next[index]] = [next[index], next[index - 1]];
  if (action === "down" && index < next.length - 1) [next[index + 1], next[index]] = [next[index], next[index + 1]];
  applyStack(next);
});

pipelineListEl.addEventListener("pointerdown", (event) => {
  if (event.target.matches("input[data-role=amount]")) {
    if (!editingHistory) { recordHistory(); editingHistory = true; }
  }
});
pipelineListEl.addEventListener("pointerup", () => { editingHistory = false; });
pipelineListEl.addEventListener("change", () => { editingHistory = false; });
pipelineListEl.addEventListener("input", (event) => {
  const input = event.target.closest("input[data-role=amount]");
  if (!input) return;
  const item = input.closest(".pipeline-item");
  const index = Number(item?.dataset.index);
  if (!Number.isInteger(index) || !activeFilters[index]) return;
  const amount = Number(input.value);
  activeFilters[index].amount = amount;
  const value = item.querySelector(".pipeline-control b");
  const meta = FILTER_META[activeFilters[index].id];
  if (value && meta) value.textContent = meta.format(amount);
  setActiveChips();
  syncAnimationPreview();
  invalidateWorkerResults();
  scheduleRender();
});

$("clearPipelineBtn").addEventListener("click", () => { if (activeFilters.length) applyStack([]); });
$("undoBtn").addEventListener("click", () => {
  if (!undoStack.length) return;
  redoStack.push(snapshot());
  activeFilters = undoStack.pop();
  setActiveChips(); renderPipelineList(); syncAnimationPreview(); invalidateWorkerResults(); scheduleRender();
});
$("redoBtn").addEventListener("click", () => {
  if (!redoStack.length) return;
  undoStack.push(snapshot());
  activeFilters = redoStack.pop();
  setActiveChips(); renderPipelineList(); syncAnimationPreview(); invalidateWorkerResults(); scheduleRender();
});

for (const chip of enginesEl.querySelectorAll(".chip")) {
  chip.addEventListener("click", () => {
    if (chip.dataset.engine === "wasm" && !wasmInstance) return;
    engine = chip.dataset.engine;
    invalidateWorkerResults();
    setActiveEngine(engine);
    render();
  });
}

// Reflect the default engine; disable WASM if the module failed to load.
if (!wasmInstance) {
  enginesEl.querySelector('[data-engine="wasm"]').disabled = true;
  setStatus("WebAssembly 加载失败，已使用 JS 后端。", "error");
}
setActiveEngine(engine);

// Threading toggle: main thread vs module worker.
const threadsEl = $("threads");
for (const chip of threadsEl.querySelectorAll(".chip")) {
  chip.addEventListener("click", () => {
    if (chip.dataset.thread === "worker" && !worker) return;
    threading = chip.dataset.thread;
    invalidateWorkerResults();
    for (const c of threadsEl.querySelectorAll(".chip")) {
      c.classList.toggle("active", c.dataset.thread === threading);
    }
    render();
  });
}
if (!worker) {
  threadsEl.querySelector('[data-thread="worker"]').disabled = true;
}

stage.addEventListener("dragover", (e) => { e.preventDefault(); stage.classList.add("dragover"); });
stage.addEventListener("dragleave", () => stage.classList.remove("dragover"));
stage.addEventListener("drop", (e) => {
  e.preventDefault();
  stage.classList.remove("dragover");
  loadFile(e.dataTransfer.files?.[0]);
});
window.addEventListener("paste", (e) => {
  const item = [...(e.clipboardData?.items || [])].find((i) => i.type.startsWith("image/"));
  if (item) loadFile(item.getAsFile());
});

loadSample();
