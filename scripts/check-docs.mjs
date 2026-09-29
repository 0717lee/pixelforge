#!/usr/bin/env node
// Guard the concrete documentation contracts: runnable examples, version
// labels, codec coverage and links into this checkout.
import assert from "node:assert/strict";
import { readFile, access } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const read = (file) => readFile(path.join(root, file), "utf8");
const normalize = (text) => text.replace(/\r\n/g, "\n").trim();
const version = (await read("moon.mod")).match(/^version\s*=\s*"([^"]+)"/m)[1];
const source = normalize(await read("cmd/quickstart/main.mbt"));
const config = normalize(await read("cmd/quickstart/moon.pkg"));
for (const file of ["README.md", "README.en.md"]) {
  const doc = await read(file);
  assert.ok(doc.includes(`\`${version}\``), `${file}: source version is missing`);
  assert.ok(doc.includes(`moon add 0717lee/pixelforge@${version}`), `${file}: install command version differs`);
  const blocks = [...doc.matchAll(/```moonbit\r?\n([\s\S]*?)\r?\n```/g)].map((match) => normalize(match[1]));
  assert.ok(blocks.includes(source), `${file}: quickstart source differs from the executable`);
  assert.ok(blocks.includes(config), `${file}: quickstart package configuration differs`);
  const formats = [...doc.matchAll(/^\| (PNG|GIF|QOI|BMP|JPEG|WebP|TIFF|AVIF) \|/gm)].map((match) => match[1]);
  assert.deepEqual(formats, ["PNG", "GIF", "QOI", "BMP", "JPEG", "WebP", "TIFF", "AVIF"]);
}
assert.ok((await read("CHANGELOG.md")).includes(`## ${version}`), "changelog version differs");
assert.ok((await read("cmd/cli/main.mbt")).includes(`PixelForge CLI ${version}`), "CLI version differs");

const listing = spawnSync("git", ["ls-files", "--cached", "--others", "--exclude-standard", "-z"], { cwd: root, encoding: "utf8" });
if (listing.error) throw listing.error;
assert.equal(listing.status, 0, listing.stderr);
const files = [...new Set(listing.stdout.split("\0"))].filter((file) => file.endsWith(".md"));
let links = 0;
for (const file of files) {
  for (const match of (await read(file)).matchAll(/!?\[[^\]]*\]\(([^\s)]+)(?:\s+[^)]*)?\)/g)) {
    const href = match[1];
    if (/^(?:[a-z][a-z\d+.-]*:|#)/i.test(href)) continue;
    const target = path.resolve(root, path.dirname(file), decodeURIComponent(href.split("#")[0]));
    await access(target).catch(() => assert.fail(`${file}: missing local link ${href}`));
    links++;
  }
}
for (const target of ["wasm-gc", "js", "native"]) {
  const result = spawnSync("moon", ["run", "--target", target, "cmd/quickstart"], { cwd: root, encoding: "utf8" });
  if (result.error) throw result.error;
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.equal(result.stdout.trim(), "2x1 PNG round-trip OK");
}
console.log(`OK docs: ${version}, bilingual quickstart on 3 targets, 8 codecs, ${links} local links in ${files.length} Markdown files`);
