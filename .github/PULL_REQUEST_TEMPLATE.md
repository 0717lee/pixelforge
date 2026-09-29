## What changed

Describe the behavior change and why it is needed.

## Validation

- [ ] `moon check`
- [ ] `moon test`
- [ ] `moon test --target js`
- [ ] `moon test --target native`
- [ ] `node scripts/build-web.mjs` (when web or MoonBit code changed)
- [ ] `node verify-wasm.mjs` (when wasm bindings or generated artifacts changed)
- [ ] `node scripts/check-cli.mjs`
- [ ] `node scripts/check-docs.mjs`
- [ ] `node scripts/check-package.mjs`
- [ ] Real-browser JS/WASM and main-thread/Worker smoke check (when web behavior changed)

## Checklist

- [ ] Tests cover the change or explain why they are not needed.
- [ ] Generated `web/dist` artifacts are synchronized.
- [ ] Both READMEs, affected API comments and version/release notes describe the same behavior.
- [ ] No credentials, build directories, or personal documents are included.
