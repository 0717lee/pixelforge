## What changed

Describe the behavior change and why it is needed.

## Validation

- [ ] `moon check`
- [ ] `moon test`
- [ ] `moon test --target js`
- [ ] `moon test --target native`
- [ ] `node scripts/build-web.mjs` (when web or MoonBit code changed)
- [ ] `node verify-wasm.mjs` (when wasm bindings or generated artifacts changed)

## Checklist

- [ ] Tests cover the change or explain why they are not needed.
- [ ] Generated `web/dist` artifacts are synchronized.
- [ ] No credentials, build directories, or personal documents are included.
