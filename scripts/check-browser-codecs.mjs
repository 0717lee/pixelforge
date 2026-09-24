#!/usr/bin/env node
// Runtime check against independent libavif RGBA fixtures. No DOM decoder is
// available: AVIF must use the generated MoonBit binding in both entry points.
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { once } from "node:events";
import { Worker } from "node:worker_threads";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const binding = await import(pathToFileURL(path.join(root, "web", "dist", "web.js")));
for (const name of ["decode_avif_rgba", "decode_avif_animation"]) {
  assert.equal(typeof binding[name], "function", `${name} missing; run node scripts/build-web.mjs first`);
}
const codecs = await import(pathToFileURL(path.join(root, "web", "codecs.js")));
const fixture = (...parts) => readFile(path.join(root, "tests", "fixtures", ...parts));
const nativeHooks = {
  createImageBitmap: globalThis.createImageBitmap,
  Image: globalThis.Image,
  createObjectURL: URL.createObjectURL,
};
let hostCalls = 0;
const forbidHostDecode = () => { hostCalls++; throw new Error("host AVIF decoder must not be used"); };
globalThis.createImageBitmap = forbidHostDecode;
globalThis.Image = forbidHostDecode;
URL.createObjectURL = forbidHostDecode;

const workerModule = pathToFileURL(path.join(root, "web", "worker.js")).href;
const bootstrap = `
  import { parentPort } from "node:worker_threads";
  globalThis.self = { postMessage: (data, transfer) => parentPort.postMessage(data, transfer) };
  const forbidden = () => { throw new Error("host worker AVIF decode must not be used"); };
  globalThis.createImageBitmap = forbidden;
  globalThis.Image = forbidden;
  URL.createObjectURL = forbidden;
  parentPort.on("message", data => self.onmessage({ data }));
  await import(${JSON.stringify(workerModule)});
`;
const worker = new Worker(new URL(`data:text/javascript,${encodeURIComponent(bootstrap)}`), { type: "module" });
let nextToken = 0;
async function workerDecode(bytes) {
  const input = Uint8Array.from(bytes);
  const token = ++nextToken;
  const pending = once(worker, "message");
  worker.postMessage({ type: "decode-avif", token, buffer: input.buffer }, [input.buffer]);
  const [response] = await pending;
  assert.equal(response.type, "decode-avif");
  assert.equal(response.token, token);
  return response;
}
function checkPixels(frame, width, height, expected, label) {
  assert.equal(frame.width, width, `${label} width`);
  assert.equal(frame.height, height, `${label} height`);
  assert.deepEqual(Buffer.from(frame.data), expected, `${label} independent RGBA pixels`);
}

try {
  const [ready] = await once(worker, "message");
  assert.equal(ready.ready, true);
  const grids = JSON.parse(await fixture("avif-grid", "manifest.json"));
  for (const depth of [8, 10, 12]) {
    const record = grids.fixtures.find((item) => item.name === `mono_1x2_${depth}bit`);
    assert.ok(record, `missing ${depth}-bit grid fixture`);
    const bytes = await fixture("avif-grid", record.file);
    const expected = await fixture("avif-grid", record.scalar_rgba_file);
    const [width, height] = record.dimensions;
    checkPixels(binding.decode_avif_rgba(bytes), width, height, expected, `${depth}-bit direct binding`);
    const main = await codecs.decodeBrowserImage(new Blob([bytes], { type: "image/avif" }), "avif");
    assert.equal(main.animated, false);
    assert.equal(main.frames.length, 1);
    checkPixels(main.frames[0], width, height, expected, `${depth}-bit main adapter`);
    const response = await workerDecode(bytes);
    assert.equal(response.error, undefined);
    checkPixels(response.image.frames[0], width, height, expected, `${depth}-bit worker adapter`);
  }

  for (const depth of [8, 10, 12]) {
    const name = `alpha_sequence_${depth}bit`;
    const bytes = await fixture("avif-animation-alpha", `${name}.avif`);
    const direct = binding.decode_avif_animation(bytes);
    const main = await codecs.decodeAVIF(new Blob([bytes], { type: "image/avif" }));
    const response = await workerDecode(bytes);
    assert.equal(response.error, undefined);
    assert.equal(main.animated, true);
    for (const [label, animation] of [["binding", direct], ["main", main], ["worker", response.image]]) {
      assert.equal(animation.timescale, 1000, `${depth}-bit ${label} timescale`);
      assert.equal(animation.frames.length, 3);
      for (let index = 0; index < 3; index++) {
        const frame = animation.frames[index];
        assert.equal(frame.timestamp, [0, 100, 300][index]);
        assert.equal(frame.duration, [100, 200, 300][index]);
        const expected = await fixture("avif-animation-alpha", `${name}_frame${index}.rgba`);
        checkPixels(frame.image || frame, 16, 16, expected, `${depth}-bit ${label} frame ${index}`);
      }
    }
  }

  // These independent references distinguish native-depth unpremultiplication
  // from unpremultiplying already quantized RGBA8, including Float rounding.
  const premultiplied = JSON.parse(await fixture("avif-premultiplied-alpha", "manifest.json"));
  for (const name of ["static_matrix0_12bit", "animation_matrix0_12bit", "static_matrix8_10bit", "animation_matrix8_10bit"]) {
    const record = premultiplied.cases.find((item) => item.name === name);
    assert.ok(record?.premultiplied, `missing premultiplied fixture ${name}`);
    assert.ok(record.frames.some((frame) => frame.post8_mismatches > 0), `${name} must distinguish native-depth rounding`);
    const bytes = await fixture("avif-premultiplied-alpha", record.file);
    const direct = record.animated ? binding.decode_avif_animation(bytes) : { frames: [binding.decode_avif_rgba(bytes)] };
    const main = await codecs.decodeAVIF(new Blob([bytes], { type: "image/avif" }));
    const response = await workerDecode(bytes);
    assert.equal(response.error, undefined, `${name} worker decode`);
    assert.equal(main.animated, record.animated);
    assert.equal(response.image.animated, record.animated);
    for (const [label, decoded] of [["binding", direct], ["main", main], ["worker", response.image]]) {
      assert.equal(decoded.frames.length, record.frames.length, `${name} ${label} frame count`);
      for (const timing of record.frames) {
        const frame = decoded.frames[timing.index];
        if (record.animated) {
          assert.equal(decoded.timescale, timing.timescale, `${name} ${label} timescale`);
          assert.equal(frame.timestamp, timing.timestamp, `${name} ${label} timestamp`);
          assert.equal(frame.duration, timing.duration, `${name} ${label} duration`);
        }
        const expected = await fixture("avif-premultiplied-alpha", `${record.reference}_frame${timing.index}.rgba`);
        checkPixels(frame.image || frame, premultiplied.width, premultiplied.height, expected, `${name} ${label} frame ${timing.index}`);
      }
    }
  }

  for (const name of ["misaligned_alpha_time", "alpha_depth_mismatch", "truncated_alpha_samples"]) {
    const bytes = await fixture("avif-animation-alpha", `${name}.avif`);
    assert.throws(() => codecs.decodeAVIFBytes(bytes), /invalid|unsupported/);
    const response = await workerDecode(bytes);
    assert.match(response.error, /invalid|unsupported/);
    assert.equal(response.image, undefined);
  }
  assert.throws(() => codecs.decodeAVIFBytes(Uint8Array.of(0, 1, 2)), /invalid|unsupported/);
  await assert.rejects(codecs.decodeAVIF(new Blob([], { type: "image/png" })), /expected image\/avif/);
  assert.equal(hostCalls, 0, "AVIF used a browser decoder");

  // Preserve the existing WebP bitmap ownership contract.
  let closed = false;
  const bitmap = { width: 2, height: 1, close() { closed = true; } };
  globalThis.createImageBitmap = async () => bitmap;
  const webp = await codecs.decodeWebP(new Blob([Uint8Array.of(0)], { type: "image/webp" }));
  assert.equal(webp.source, bitmap);
  webp.close();
  assert.equal(closed, true);
  console.log("OK pure MoonBit AVIF: 8/10/12-bit grids and alpha animations, high-depth premultiplied identity/YCgCo, binding/main/worker pixel parity, invalid sequences rejected; WebP lifecycle preserved");
} finally {
  await worker.terminate();
  globalThis.createImageBitmap = nativeHooks.createImageBitmap;
  globalThis.Image = nativeHooks.Image;
  URL.createObjectURL = nativeHooks.createObjectURL;
}
