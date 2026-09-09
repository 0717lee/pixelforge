#!/usr/bin/env node
// Static contract check for the browser-only WebP/AVIF adapters.  The CI
// environment does not have a DOM decoder, so runtime pixel decoding is
// exercised by the Playground/browser smoke test instead.
import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const codecs = await readFile(path.join(root, "web", "codecs.js"), "utf8");
const playground = await readFile(path.join(root, "web", "playground.js"), "utf8");

for (const marker of [
  'export function browserCodecKind',
  'export async function decodeBrowserImage',
  'export const decodeWebP',
  'export const decodeAVIF',
  'createImageBitmap',
  'URL.createObjectURL',
]) {
  if (!codecs.includes(marker)) throw new Error(`web/codecs.js is missing ${marker}`);
}
for (const marker of [
  'from "./codecs.js"',
  'browserCodecKind(file)',
  'decodeBrowserImage(file, browserCodec)',
]) {
  if (!playground.includes(marker)) throw new Error(`web/playground.js is missing ${marker}`);
}
console.log("OK browser WebP/AVIF decode adapter contract");

