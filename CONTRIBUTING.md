# Contributing to PixelForge

Thanks for helping improve PixelForge. Small, focused pull requests are easiest to review.

## Development setup

Install the MoonBit version pinned in `.github/workflows/ci.yml` (currently `0.1.20260827`). Then run:

```sh
moon check
moon test
moon test --target js
moon test --target native
node scripts/build-web.mjs
node verify-wasm.mjs
```

`node scripts/build-web.mjs` regenerates the committed files in `web/dist/`. Run it whenever MoonBit sources or browser bindings change and include the resulting artifacts in the pull request. CI checks that these files are reproducible.

## Pull requests

Describe the user-visible behavior and include tests for bug fixes or new behavior. Keep unrelated formatting and generated-file churn out of the diff. Do not commit credentials, local build directories, or personal documents.

The repository currently has existing formatting drift, so CI intentionally does not run a whole-repository formatter gate. Format touched MoonBit files using the project's normal formatter when practical.
