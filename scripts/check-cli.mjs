#!/usr/bin/env node
// Real native CLI file/hex round trips and rejection paths, using small
// generated containers rather than a checked-in binary fixture collection.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtemp, readFile, writeFile, rm, access } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { encode_png } from "../web/dist/web.js";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const build = spawnSync("moon", ["build", "--target", "native", "cmd/cli"], { cwd: root, encoding: "utf8" });
if (build.error) throw build.error;
assert.equal(build.status, 0, build.stdout + build.stderr);
const executable = path.join(root, "_build/native/debug/build/cmd/cli/cli.exe");

function run(args, failure = null) {
  const result = spawnSync(executable, args, { cwd: root, encoding: "utf8" });
  if (result.error) throw result.error;
  if (failure) {
    assert.notEqual(result.status, 0, `unexpected success: ${args.join(" ")}`);
    assert.match(result.stdout + result.stderr, failure);
  } else {
    assert.equal(result.status, 0, result.stdout + result.stderr);
  }
  return result.stdout;
}

function bigTiff(little) {
  const data = Buffer.alloc(213);
  function uint(p, value, size) {
    for (let i = 0; i < size; i++) data[p + (little ? i : size - 1 - i)] = i < 4 ? (value >>> (8 * i)) & 255 : 0;
  }
  data.write(little ? "II" : "MM");
  uint(2, 43, 2); uint(4, 8, 2); uint(8, 16, 8); uint(16, 9, 8);
  [[256, 4, 1], [257, 4, 1], [258, 3, 8], [259, 3, 1], [262, 3, 1],
    [273, 16, 212], [277, 3, 1], [278, 4, 1], [279, 16, 1]].forEach(([tag, kind, value], i) => {
    const p = 24 + i * 20;
    uint(p, tag, 2); uint(p + 2, kind, 2); uint(p + 4, 1, 8);
    uint(p + 12, value, kind === 3 ? 2 : kind === 4 ? 4 : 8);
  });
  data[212] = 99;
  return data;
}

function u32(value) {
  const bytes = Buffer.alloc(4);
  bytes.writeUInt32BE(value);
  return bytes;
}
function box(kind, ...parts) {
  const payload = Buffer.concat(parts);
  return Buffer.concat([u32(payload.length + 8), Buffer.from(kind), payload]);
}
const avif = Buffer.concat([
  box("ftyp", Buffer.from("avif"), u32(0)),
  box("meta", u32(0),
    box("pitm", u32(0), Buffer.from([0, 1])),
    box("iprp",
      box("ipco", box("ispe", u32(0), u32(2), u32(1))),
      box("ipma", u32(0), u32(1), Buffer.from([0, 1, 1, 1])))),
]);

const directory = await mkdtemp(path.join(tmpdir(), "pixelforge-cli-"));
try {
  const manifest = await readFile(path.join(root, "moon.mod"), "utf8");
  const version = manifest.match(/^version\s*=\s*"([^"]+)"/m)[1];
  assert.equal(run(["--help"]).split(/\r?\n/)[0], `PixelForge CLI ${version}`);
  for (const little of [true, false]) {
    const data = bigTiff(little);
    const info = run(["info", "--input-hex", data.toString("hex")]);
    assert.match(info, /format=tiff\r?\nwidth=1\r?\nheight=1/);
    const converted = run(["convert", "--from", "tiff", "--to", "bmp", "--input-hex", data.toString("hex")]);
    const bmp = Buffer.from(converted.match(/hex=([0-9a-f]+)/)[1], "hex");
    assert.deepEqual([...bmp.subarray(bmp.readUInt32LE(10))], [99, 99, 99, 255]);
    run(["info", "--input-hex", data.subarray(0, 40).toString("hex")], /TIFF decode failed/);
  }

  const input = path.join(directory, "input.png");
  const qoi = path.join(directory, "filtered.qoi");
  const bmpPath = path.join(directory, "filtered.bmp");
  const png = encode_png(Uint8Array.of(255, 0, 0, 255, 0, 255, 0, 255), 2, 1);
  await writeFile(input, png);
  run(["convert", "--from", "png", "--to", "qoi", "--pipeline", "grayscale,brightness:10", "--input", input, "--output", qoi]);
  assert.match(run(["info", "--input", qoi]), /format=qoi\r?\nwidth=2\r?\nheight=1/);
  run(["convert", "--from", "qoi", "--to", "bmp", "--input", qoi, "--output", bmpPath]);
  const bmp = await readFile(bmpPath);
  // Integer luma truncates: floor(255 * 299/1000) + 10 = 86;
  // floor(255 * 587/1000) + 10 = 159.
  assert.deepEqual([...bmp.subarray(bmp.readUInt32LE(10))], [86, 86, 86, 255, 159, 159, 159, 255]);

  const thumbnailPath = path.join(directory, "thumbnail.bmp");
  const thumbnailInfo = run(["convert", "--from", "png", "--to", "bmp", "--fit", "1x1", "--pipeline", "threshold:100", "--input", input, "--output", thumbnailPath]);
  assert.match(thumbnailInfo, /width=1\r?\nheight=1/);
  const thumbnail = await readFile(thumbnailPath);
  assert.equal(thumbnail.readInt32LE(18), 1);
  assert.equal(Math.abs(thumbnail.readInt32LE(22)), 1);
  // Fit first: average red/green -> (128,128,0), luma 113 -> white.
  // Threshold first would yield black/white, whose average is gray instead.
  assert.deepEqual([...thumbnail.subarray(thumbnail.readUInt32LE(10))], [255, 255, 255, 255]);
  const noUpscale = run(["convert", "--from", "png", "--to", "bmp", "--fit", "100x100", "--input-hex", Buffer.from(png).toString("hex")]);
  assert.match(noUpscale, /width=2\r?\nheight=1/);
  const transparentPng = encode_png(Uint8Array.of(255, 0, 0, 0, 0, 0, 255, 255), 2, 1);
  const alphaFit = run(["convert", "--from", "png", "--to", "bmp", "--fit", "1x1", "--input-hex", Buffer.from(transparentPng).toString("hex")]);
  const alphaBmp = Buffer.from(alphaFit.match(/hex=([0-9a-f]+)/)[1], "hex");
  // BMP BGRA: transparent red must not tint the surviving blue pixel.
  assert.deepEqual([...alphaBmp.subarray(alphaBmp.readUInt32LE(10))], [255, 0, 0, 128]);

  const avifPath = path.join(directory, "metadata.avif");
  await writeFile(avifPath, avif);
  assert.match(run(["info", "--input", avifPath]), /format=avif\r?\nwidth=2\r?\nheight=1\r?\nmetadata_only=true/);
  const rejected = path.join(directory, "rejected.bin");
  for (const [extra, message] of [
    [["--unknown", "value"], /unknown option/],
    [["--to", "bmp"], /duplicate option/],
    [["--fit", "--pipeline", "invert"], /missing value for --fit/],
    [["--pipeline", "gamma:NaN"], /finite number|invalid number/],
    [["--pipeline", "contrast:Infinity"], /finite number|invalid number/],
  ]) {
    run(["convert", "--from", "png", "--to", "bmp", "--input", input, "--output", rejected, ...extra], message);
    await assert.rejects(access(rejected), { code: "ENOENT" });
  }
  run(["info", "--input", input, "--fit", "1x1"], /unknown option/);
  run(["convert", "--from", "png", "--to", "invalid", "--input", input, "--output", rejected], /unsupported output format invalid/);
  run(["convert", "--from", "png", "--to", "bmp", "--input-hex", Buffer.from(png).toString("hex"), "--output", rejected], /--output requires file input/);
  for (const fit of ["", "0x1", "1x0", "-1x2", "2", "2x", "x2", "2x3x4", "ax2", "2147483648x1"]) {
    run(["convert", "--from", "png", "--to", "bmp", "--fit", fit, "--input", input, "--output", rejected], /--fit requires positive WIDTHxHEIGHT/);
    await assert.rejects(access(rejected), { code: "ENOENT" });
  }
  for (const [args, message] of [
    [["--from", "avif", "--to", "png", "--input", avifPath], /AVIF decode failed/],
    [["--from", "png", "--to", "avif", "--input", input], /AVIF encoding requires a browser/],
    [["--from", "png", "--to", "qoi", "--pipeline", "unknown", "--input", input], /unknown pipeline operation/],
    [["--from", "png", "--to", "qoi", "--pipeline", "brightness:bad", "--input", input], /invalid integer/],
  ]) {
    run(["convert", ...args, "--output", rejected], message);
    await assert.rejects(access(rejected), { code: "ENOENT" });
  }
  const sample = path.join(root, "assets/avif/grayscale.avif");
  const expected = await readFile(path.join(root, "assets/avif/grayscale.rgba"));
  const avifPng = path.join(directory, "avif.png");
  const avifBmp = path.join(directory, "avif.bmp");
  run(["convert", "--from", "avif", "--to", "png", "--pipeline", "invert", "--input", sample, "--output", avifPng]);
  run(["convert", "--from", "png", "--to", "bmp", "--input", avifPng, "--output", avifBmp]);
  const filtered = await readFile(avifBmp);
  assert.equal(filtered.readInt32LE(18), 4);
  assert.equal(Math.abs(filtered.readInt32LE(22)), 2);
  const offset = filtered.readUInt32LE(10);
  for (let y = 0; y < 2; y++) {
    const row = filtered.readInt32LE(22) < 0 ? y : 1 - y;
    for (let x = 0; x < 4; x++) {
      const p = (y * 4 + x) * 4;
      const q = offset + (row * 4 + x) * 4;
      assert.deepEqual([...filtered.subarray(q, q + 4)], [255 - expected[p + 2], 255 - expected[p + 1], 255 - expected[p], expected[p + 3]]);
    }
  }
  const sampleBytes = await readFile(sample);
  const truncated = path.join(directory, "truncated.avif");
  await writeFile(truncated, sampleBytes.subarray(0, sampleBytes.length - 1));
  run(["convert", "--from", "avif", "--to", "png", "--input", truncated, "--output", rejected], /AVIF decode failed/);
  await assert.rejects(access(rejected), { code: "ENOENT" });
  console.log("OK native CLI: version, BigTIFF, PNG/pipeline/QOI/BMP, AVIF/libdav1d pixels, thumbnail dimensions and filter order, rejected conversions");
} finally {
  await rm(directory, { recursive: true, force: true });
}
