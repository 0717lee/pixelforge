// PixelForge Playground — drives the MoonBit image-processing library from the
// browser through TWO backends:
//   * "js"   — MoonBit compiled to JS; FixedArray[Byte] IS a Uint8Array, so the
//              canvas buffer crosses in with zero copies.
//   * "wasm" — MoonBit compiled to a linear-memory WebAssembly module; pixels
//              are bulk-copied into the exported memory via a Uint8Array view.
import { apply_filter } from "./dist/web.js";

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

// Filter ids must match @pixelforge.Image::apply_filter_id.
const FILTER = { GRAYSCALE: 0, INVERT: 1, BRIGHTNESS: 2, CONTRAST: 3, BLUR: 4, SHARPEN: 5, EMBOSS: 6, EDGES: 7, SOBEL: 8, SEPIA: 9, THRESHOLD: 10, PIXELATE: 11, MEDIAN: 12, HISTEQ: 13 };

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
let currentFilter = -1;
let brightness = 0;
let contrast = 1;
let engine = "js"; // default to the faster zero-copy backend; WASM is a toggle

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

// Non-destructive pipeline: brightness -> contrast -> discrete filter, from a
// fresh copy of the source, on the requested engine.
function runPipeline(eng) {
  let data = new Uint8ClampedArray(originalData.data);
  if (brightness !== 0) data = applyOne(data, imgW, imgH, FILTER.BRIGHTNESS, brightness, eng);
  if (contrast !== 1) data = applyOne(data, imgW, imgH, FILTER.CONTRAST, contrast, eng);
  if (currentFilter >= 0) data = applyOne(data, imgW, imgH, currentFilter, 0, eng);
  return data;
}

function updateStats(ms) {
  $("statSize").textContent = `${imgW} × ${imgH}`;
  $("statEngine").textContent = engine === "wasm" ? "WebAssembly" : "JS 后端";
  $("statTime").textContent = `${ms.toFixed(2)} ms`;
  const mpPerSec = imgW * imgH / 1e6 / (ms / 1000);
  $("statThroughput").textContent = ms > 0 ? `${mpPerSec.toFixed(1)} MP/s` : "—";
}

function render() {
  if (!originalData) return;
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

function setActiveChip(id) {
  for (const chip of filtersEl.querySelectorAll(".chip")) {
    chip.classList.toggle("active", Number(chip.dataset.filter) === id);
  }
}

function setActiveEngine(eng) {
  for (const chip of enginesEl.querySelectorAll(".chip")) {
    chip.classList.toggle("active", chip.dataset.engine === eng);
  }
}

function resetControls() {
  currentFilter = -1;
  brightness = 0;
  contrast = 1;
  brightnessEl.value = "0";
  contrastEl.value = "100";
  $("brightnessVal").textContent = "0";
  $("contrastVal").textContent = "1.00";
  setActiveChip(-1);
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
$("benchBtn").addEventListener("click", runBenchmark);
$("compareBtn").addEventListener("click", compareEngines);

for (const chip of filtersEl.querySelectorAll(".chip")) {
  chip.addEventListener("click", () => {
    currentFilter = Number(chip.dataset.filter);
    setActiveChip(currentFilter);
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
