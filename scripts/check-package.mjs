#!/usr/bin/env node
// Inspect Moon's actual archive input list; local/global Git ignores do not
// protect a release from accidentally including local reference material.
import assert from "node:assert/strict";
import { existsSync, statSync, readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const packaged = spawnSync("moon", ["package", "--list"], { cwd: root, encoding: "utf8", maxBuffer: 16 * 1024 * 1024 });
if (packaged.error) throw packaged.error;
assert.equal(packaged.status, 0, packaged.stdout + packaged.stderr);
const files = (packaged.stdout + packaged.stderr).split(/\r?\n/).filter((file) => {
  const absolute = path.join(root, file);
  return file && existsSync(absolute) && statSync(absolute).isFile();
}).map((file) => file.replaceAll("\\", "/"));
for (const required of ["moon.mod", "moon.pkg", "README.md", "README.en.md", "pkg.generated.mbti", "LICENSE", "THIRD_PARTY_NOTICES.md", "web/dist/web.js", "web/dist/wasmcore.wasm"]) {
  assert.ok(files.includes(required), `package is missing ${required}`);
}
const listed = spawnSync("git", ["ls-files", "--cached", "--others", "--exclude-standard", "-z"], { cwd: root, encoding: "utf8" });
if (listed.error) throw listed.error;
assert.equal(listed.status, 0, listed.stderr);
const sourceFiles = new Set(listed.stdout.split("\0"));
for (const file of files) {
  assert.ok(sourceFiles.has(file), `unexpected local file in package: ${file}`);
  assert.ok(!/^(?:_refs|_build|tests|tmp[^/]*|cmd|assets)\//.test(file), `excluded directory in package: ${file}`);
}
const packagedFiles = new Set(files);
for (const file of files.filter((file) => file.endsWith(".md"))) {
  const contents = readFileSync(path.join(root, file), "utf8");
  for (const match of contents.matchAll(/!?\[[^\]]*\]\(([^\s)]+)(?:\s+[^)]*)?\)/g)) {
    const href = match[1];
    if (/^(?:[a-z][a-z\d+.-]*:|#)/i.test(href)) continue;
    const target = path.posix.normalize(path.posix.join(path.posix.dirname(file), decodeURIComponent(href.split("#")[0])));
    assert.ok(packagedFiles.has(target), `${file}: packaged documentation links to excluded file ${href}`);
  }
}
console.log(`OK package: ${files.length} source files; docs/artifacts and local links present; no local reference or temporary files`);
