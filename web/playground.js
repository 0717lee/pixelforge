// PixelForge Playground — drives the MoonBit image-processing library from the
// browser through TWO backends:
//   * "js"   — MoonBit compiled to JS; FixedArray[Byte] IS a Uint8Array, so the
//              canvas buffer crosses in with zero copies.
//   * "wasm" — MoonBit compiled to a linear-memory WebAssembly module; pixels
//              are bulk-copied into the exported memory via a Uint8Array view.
import { apply_filter, encode_png } from "./dist/web.js";

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
try {
  worker = new Worker(new URL("./worker.js", import.meta.url), { type: "module" });
  worker.addEventListener("message", (e) => {
    if (e.data.ready) { workerReady = true; return; }
    const { seq, buffer, ms } = e.data;
    if (seq !== workerSeq) return; // a newer render superseded this one
    ctx.putImageData(new ImageData(new Uint8ClampedArray(buffer), imgW, imgH), 0, 0);
    updateStats(ms);
  });
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
const filtersEl = $("filters");
const enginesEl = $("engines");
const brightnessEl = $("brightness");
const contrastEl = $("contrast");

let originalData = null;
let imgW = 0;
let imgH = 0;
let activeFilters = []; // ordered stack of filter ids; empty = original
let brightness = 0;
let contrast = 1;
let engine = "js"; // default to the faster zero-copy backend; WASM is a toggle
let threading = "main"; // "main" | "worker"

// Reinterpret a MoonBit-returned Uint8Array as clamped for ImageData, no copy.
function asClamped(buf) {
  if (buf instanceof Uint8ClampedArray) return buf;
  return new Uint8ClampedArray(buf.buffer, buf.byteOffset, buf.length);
}

// Genuine-WASM filter: bulk-copy src into linear memory, process, copy result
// out (memory may have grown during the call, so re-view before reading).
function applyFilterWasm(src, w, h, id, amount) {
  const ex = wasmInstance.exports;
  const len = w * h * 4;
  const ptr = ex.alloc(len);
  new Uint8Array(ex.memory.buffer, ptr, len).set(src);
  const resPtr = ex.process(ptr, w, h, id, amount);
  return new Uint8ClampedArray(new Uint8Array(ex.memory.buffer).subarray(resPtr, resPtr + len));
}

function applyOne(data, w, h, id, amount, eng) {
  return eng === "wasm" ? applyFilterWasm(data, w, h, id, amount) : apply_filter(data, w, h, id, amount);
}

// The pipeline as a flat op list (shared by main-thread and worker paths).
function pipelineOps() {
  const ops = [];
  if (brightness !== 0) ops.push({ id: FILTER.BRIGHTNESS, amount: brightness });
  if (contrast !== 1) ops.push({ id: FILTER.CONTRAST, amount: contrast });
  for (const id of activeFilters) ops.push({ id, amount: 0 });
  return ops;
}

// Non-destructive pipeline: brightness -> contrast -> discrete filter, from a
// fresh copy of the source, on the requested engine.
function runPipeline(eng) {
  let data = new Uint8ClampedArray(originalData.data);
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
}

function render() {
  if (!originalData) return;
  if (threading === "worker" && workerReady) {
    // Copy the source (we still need it) and hand the copy to the worker.
    const copy = new Uint8ClampedArray(originalData.data);
    workerSeq += 1;
    worker.postMessage(
      { seq: workerSeq, buffer: copy.buffer, w: imgW, h: imgH, ops: pipelineOps(), engine },
      [copy.buffer],
    );
    return; // the worker message handler paints and updates stats
  }
  const t0 = performance.now();
  const data = runPipeline(engine);
  const elapsed = performance.now() - t0;
  ctx.putImageData(new ImageData(asClamped(data), imgW, imgH), 0, 0);
  updateStats(elapsed);
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
    chip.classList.toggle("active", id === -1 ? activeFilters.length === 0 : activeFilters.includes(id));
  }
}

function setActiveEngine(eng) {
  for (const chip of enginesEl.querySelectorAll(".chip")) {
    chip.classList.toggle("active", chip.dataset.engine === eng);
  }
}

function resetControls() {
  activeFilters = [];
  brightness = 0;
  contrast = 1;
  brightnessEl.value = "0";
  contrastEl.value = "100";
  $("brightnessVal").textContent = "0";
  $("contrastVal").textContent = "1.00";
  setActiveChips();
}

function useImageSource(source) {
  const sw = source.naturalWidth || source.width;
  const sh = source.naturalHeight || source.height;
  const scale = Math.min(1, 1024 / Math.max(sw, sh));
  imgW = Math.max(1, Math.round(sw * scale));
  imgH = Math.max(1, Math.round(sh * scale));
  canvas.width = imgW;
  canvas.height = imgH;
  ctx.drawImage(source, 0, 0, imgW, imgH);
  originalData = ctx.getImageData(0, 0, imgW, imgH);
  dropHint.classList.add("hidden");
  resetControls();
  render();
}

function loadFile(file) {
  if (!file || !file.type.startsWith("image/")) return;
  const url = URL.createObjectURL(file);
  const img = new Image();
  img.onload = () => { useImageSource(img); URL.revokeObjectURL(url); };
  img.src = url;
}

// A colorful procedural scene so the demo is usable with zero setup.
function loadSample() {
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
$("resetBtn").addEventListener("click", () => { resetControls(); render(); });
$("downloadBtn").addEventListener("click", () => {
  if (!originalData) return;
  // Encode with the library's own pure-MoonBit PNG encoder — the download
  // is a file produced by @pixelforge.png_encode, not canvas.toBlob.
  const pixels = ctx.getImageData(0, 0, imgW, imgH).data;
  const bytes = encode_png(new Uint8Array(pixels.buffer.slice(0)), imgW, imgH);
  const blob = new Blob([bytes], { type: "image/png" });
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = "pixelforge.png";
  a.click();
  URL.revokeObjectURL(a.href);
});
$("benchBtn").addEventListener("click", runBenchmark);
$("compareBtn").addEventListener("click", compareEngines);

for (const chip of filtersEl.querySelectorAll(".chip")) {
  chip.addEventListener("click", () => {
    const id = Number(chip.dataset.filter);
    if (id === -1) {
      activeFilters = [];
    } else {
      const at = activeFilters.indexOf(id);
      if (at >= 0) activeFilters.splice(at, 1);
      else activeFilters.push(id);
    }
    setActiveChips();
    render();
  });
}

for (const chip of enginesEl.querySelectorAll(".chip")) {
  chip.addEventListener("click", () => {
    if (chip.dataset.engine === "wasm" && !wasmInstance) return;
    engine = chip.dataset.engine;
    setActiveEngine(engine);
    render();
  });
}

// Reflect the default engine; disable WASM if the module failed to load.
if (!wasmInstance) {
  enginesEl.querySelector('[data-engine="wasm"]').disabled = true;
}
setActiveEngine(engine);

// Threading toggle: main thread vs module worker.
const threadsEl = $("threads");
for (const chip of threadsEl.querySelectorAll(".chip")) {
  chip.addEventListener("click", () => {
    if (chip.dataset.thread === "worker" && !worker) return;
    threading = chip.dataset.thread;
    for (const c of threadsEl.querySelectorAll(".chip")) {
      c.classList.toggle("active", c.dataset.thread === threading);
    }
    render();
  });
}
if (!worker) {
  threadsEl.querySelector('[data-thread="worker"]').disabled = true;
}

brightnessEl.addEventListener("input", () => {
  brightness = Number(brightnessEl.value);
  $("brightnessVal").textContent = String(brightness);
  scheduleRender();
});
contrastEl.addEventListener("input", () => {
  contrast = Number(contrastEl.value) / 100;
  $("contrastVal").textContent = contrast.toFixed(2);
  scheduleRender();
});

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
