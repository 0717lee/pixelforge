# Contributing to PixelForge

Thanks for helping improve PixelForge. Small, focused pull requests are easiest to review.

## Development setup

Use the compiler release pinned in [ci.yml](https://github.com/0717lee/pixelforge/blob/main/.github/workflows/ci.yml):
`moonc v0.10.14+7d59c7ec9`. Its bundled CLI reports `moon 0.1.20260920`.
These are different components of the same toolchain; the installer takes the
**compiler release**, not the CLI date version. Confirm with `moon version --all`.
Native builds require a platform C compiler. Scripts require Node.js 22 or newer.

On Windows, activate an isolated installation in the current PowerShell session:

```powershell
. ./scripts/use-toolchain.ps1
# Or: . ./scripts/use-toolchain.ps1 -Toolchain C:/path/to/moonbit
moon version --all
```

The script requires the exact pinned compiler and defaults to
`$env:USERPROFILE/.moon/toolchains/0.10.14`. On Unix, install the same release:

```sh
curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash -s -- 0.10.14+7d59c7ec9
export PATH="$HOME/.moon/bin:$PATH"
```

From the repository root:

```sh
moon update
moon check
moon info
moon test --target wasm-gc
moon test --target js
moon test --target native
node scripts/build-web.mjs
node scripts/build-web.mjs --check
node scripts/check-canonicalize-moon-js.mjs
node scripts/check-browser-codecs.mjs
node verify-wasm.mjs
node scripts/check-cli.mjs
node scripts/check-docs.mjs
node scripts/check-package.mjs
git diff --check
```

`build-web.mjs` regenerates committed `web/dist/` artifacts. Run it whenever
MoonBit sources or bindings change and include changed artifacts. Its `--check`
mode builds into `_build/` and compares outputs without rewriting `web/dist/`.
CI verifies their reproducibility with the pinned compiler.

`check-cli.mjs` builds the native executable and checks real file and hex
conversions; temporary files are isolated and removed. `check-docs.mjs` compares
both README examples with `cmd/quickstart`, runs that example on all three
targets, and checks version labels, format rows and local Markdown links.
`verify-wasm.mjs` exercises the host shared by the Playground and Worker,
including 200 repeated renders and changes of image size.

`check-package.mjs` creates a local archive through `moon package --list` and
rejects reference trees, temporary files and files hidden only by local Git
ignores. Publishing policy lives in `.moonignore`; no upload is performed.

For a focused MoonBit regression, use `moon test --target js resize_test.mbt`
or another test file. For performance measurements, run
`node scripts/benchmark.mjs`; record the reported environment and workload.

Browser-facing changes also need a real-browser smoke check: load an image,
apply/reorder/undo filters in JS/WASM and main-thread/Worker modes, switch image
sizes, and download a PNG. The Node browser-codec check uses mocks and does not
replace that integration check.

## Pull requests

Describe the user-visible behavior and include tests for bug fixes or new behavior. Keep unrelated formatting and generated-file churn out of the diff. Do not commit credentials, local build directories, or personal documents.

Run `moon info` and format touched files with `moonfmt -w path/to/file.mbt`.
On the pinned toolchain, `moon fmt` formats containing packages even when given
file paths, so inspect its diff before keeping unrelated formatting changes.
Review `.mbti` diffs as public API changes. Existing untouched formatting drift
is not a reason to reformat the entire repository in a focused pull request.

When behavior changes, update both READMEs, affected API comments and the
changelog. Keep published package behavior separate from development behavior.
Release preparation and proposed notes are in [docs/RELEASING.md](docs/RELEASING.md).
