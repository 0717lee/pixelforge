#!/usr/bin/env node
// Update from a committed local MoonAV1 revision, or verify the stored snapshot.
//   node scripts/vendor-moonav1.mjs ../moonav1
//   node scripts/vendor-moonav1.mjs --check
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { mkdir, mkdtemp, readFile, readdir, rm, rmdir, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const destination = path.join(root, "vendor", "moonav1");
const manifestPath = path.join(destination, "snapshot.json");
const digest = (bytes) => createHash("sha256").update(bytes).digest("hex");
const required = ["moon.mod", "moon.pkg", "pkg.generated.mbti", "LICENSE", "THIRD_PARTY_NOTICES.md", "PROVENANCE.md"];

function destinationFile(name) {
  if (!/^[A-Za-z0-9_][A-Za-z0-9_.-]*$/.test(name)) {
    throw new Error(`Invalid snapshot filename: ${name}`);
  }
  return path.join(destination, name);
}

async function verify() {
  const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
  if (manifest.module !== "0717lee/moonav1" || !/^[0-9a-f]{40}$/.test(manifest.revision)) {
    throw new Error("Invalid MoonAV1 snapshot identity");
  }
  const expected = Object.keys(manifest.files).sort();
  const actual = (await readdir(destination)).filter((name) => name !== "snapshot.json").sort();
  if (JSON.stringify(expected) !== JSON.stringify(actual)) {
    throw new Error("MoonAV1 snapshot file list changed; update from its source repository");
  }
  for (const name of expected) {
    const bytes = await readFile(destinationFile(name));
    if (digest(bytes) !== manifest.files[name]) {
      throw new Error(`MoonAV1 snapshot differs from ${manifest.revision}: ${name}`);
    }
  }
  console.log(`OK MoonAV1 ${manifest.revision}: ${expected.length} pinned files`);
}

const args = process.argv.slice(2);
if (args.length === 1 && args[0] === "--check") {
  await verify();
} else {
  if (args.length !== 1 || args[0].startsWith("--")) {
    throw new Error("Usage: node scripts/vendor-moonav1.mjs <local-source-directory> | --check");
  }
  const source = path.resolve(root, args[0]);
  const git = (...gitArgs) => execFileSync("git", ["-C", source, ...gitArgs], { encoding: "utf8" });
  const revision = git("rev-parse", "HEAD").trim();
  const tracked = git("ls-tree", "--name-only", revision).trim().split("\n");
  const selected = tracked.filter((name) => name.endsWith(".mbt") || required.includes(name)).sort();
  for (const name of required) {
    if (!selected.includes(name)) throw new Error(`MoonAV1 source is missing ${name}`);
  }
  for (const name of selected) destinationFile(name);
  const moduleText = git("show", `${revision}:moon.mod`);
  if (!/^name = "0717lee\/moonav1"$/m.test(moduleText)) {
    throw new Error("Source repository is not the MoonAV1 module");
  }
  // Never include uncommitted changes in a snapshot labelled with a Git revision.
  if (git("status", "--porcelain", "--", ...selected).trim()) {
    throw new Error("Commit changes to the selected MoonAV1 files before updating its snapshot");
  }
  await mkdir(destination, { recursive: true });
  let previous = null;
  try {
    previous = JSON.parse(await readFile(manifestPath, "utf8"));
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
  }
  const temporary = await mkdtemp(path.join(tmpdir(), "pixelforge-moonav1-"));
  const archive = path.join(temporary, "source.tar");
  try {
    git("archive", "--format=tar", `--output=${archive}`, revision, "--", ...selected);
    execFileSync("tar", ["-xf", archive, "-C", destination]);
  } finally {
    // Both targets are explicit children of the directory created above.
    await rm(archive, { force: true });
    await rmdir(temporary);
  }
  for (const name of Object.keys(previous?.files ?? {})) {
    if (name !== "README.md" && !selected.includes(name)) {
      await rm(destinationFile(name));
    }
  }
  const sourceBaseline = "6f0c711c54f89d34f3e2ef97cde7a0a45458583d";
  await writeFile(path.join(destination, "README.md"), `# MoonAV1 dependency snapshot

This is a pinned copy of the independently maintained **0717lee/moonav1** module.
Source revision: **${revision}**. It is included so a fresh PixelForge checkout
can build without an unpublished registry package or a sibling source directory.
MoonAV1 has no public repository or Mooncakes release at this stage.

The authoritative local project is the workspace's sibling **moonav1** directory.
Do not edit this snapshot. Commit changes there, then run from PixelForge:

    node scripts/vendor-moonav1.mjs ../moonav1
    node scripts/vendor-moonav1.mjs --check

The checked-in **moon.work** resolves the versioned import to this directory.
The snapshot includes the decoder's embedded tests, public interface and licenses;
reference-generation tools and the full fixture corpus remain in MoonAV1.
PixelForge retains its browser/Worker integration fixtures.

Use **avif_decode_rgba**, **avif_decode_animation**, or **av1_decode** for decoding;
see [the public interface](pkg.generated.mbti). RGBA output is straight RGBA8;
there is no encoder or HDR tone mapping. [Source provenance](PROVENANCE.md) and
[third-party notices](THIRD_PARTY_NOTICES.md) retain the original attribution.
The [pre-extraction implementation and reference documentation](https://github.com/0717lee/pixelforge/tree/${sourceBaseline})
remain available in PixelForge history. Extraction does not remove that history
or reclassify the previous work as new implementation.
`);
  const files = {};
  for (const name of [...selected, "README.md"].sort()) {
    files[name] = digest(await readFile(destinationFile(name)));
  }
  await writeFile(manifestPath, JSON.stringify({ module: "0717lee/moonav1", revision, files }, null, 2) + "\n");
  await verify();
}
