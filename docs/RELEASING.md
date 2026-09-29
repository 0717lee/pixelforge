# Releasing PixelForge

This checkout documents **0.19.0**. Its source package, CLI, installation
instructions and GitHub release use the same version. It includes breaking
AV1/AVIF API removal; do not overwrite old tags or reuse published package versions.

## Prepare the release

1. Complete the checks in [CONTRIBUTING](../CONTRIBUTING.md), including the
   runnable bilingual quickstart, native CLI file tests and bounded WASM memory.
2. Review [CHANGELOG](../CHANGELOG.md), [migration notes](MIGRATION.md), the public
   interface diff and [third-party notices](../THIRD_PARTY_NOTICES.md).
3. Before publication, align the module, CLI, both README version paragraphs and
   install commands with the release version. Update migration instructions and
   date the changelog entry. Keep historical release entries intact.
4. Run `node scripts/check-docs.mjs` again and inspect `moon package --list`
   before creating the distributable package. CLI examples, local build output,
   screenshots, personal documents and local reference trees are excluded by
   `.moonignore`. Git's local/global ignore rules do not define package contents.
5. Review the final diff and use the maintainer's authorization for committing,
   pushing, package publication and the GitHub tag/release. CI and verification
   scripts perform validation only; they do not publish anything.

## Publish and verify

Publish the approved commit with `moon publish`, and create GitHub tag/release
`v0.19.0` from the same commit. Use the release description below. After the
registry updates, verify its version label, README, generated API and a fresh
`moon add 0717lee/pixelforge@0.19.0` quickstart. Confirm the GitHub release points
to the approved commit and its CI is green. Update the release status in the
handoff with the registry and release links.

Historical `0.18.0` documentation describes that package and should remain
available. Publishing a new version updates the latest package documentation;
editing `main` alone does not change the registry's published README.

## 0.19.0 release description

Title: **0.19.0 — WASM memory, resize and BigTIFF fixes**

PixelForge now reuses its WebAssembly pixel buffer across renders and replaces
the instance when the buffer size changes. Main-thread and Worker pipelines
share the same lifecycle, with repeated-render memory and pixel regressions.

Nearest-neighbor resizing uses overflow-safe sample arithmetic, and all three
resizers return transparent output for empty sources. BigTIFF identification,
metadata and native CLI conversion now reach the existing decoder subset in
both byte orders.

This release removes the old AV1/AVIF parser and pixel-decoding APIs. AVIF
signature detection, supported primary-image metadata, browser-native loading
and the JS encoding adapter remain. See the migration guide before upgrading.

Both READMEs now contain a runnable example, format/backend matrix, explicit
error and ownership contracts, and reproducible benchmark instructions. CI
checks documentation examples, native file conversion and WASM memory behavior.
