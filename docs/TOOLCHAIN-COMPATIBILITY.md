# 工具链兼容验证（2026-11-11）

按 MoonBit 开源大赛组委会统一维护提醒，使用官方当前发布工具链重新验证。

## 实际工具链（`moon version --all`）

```
moon     0.1.20261104 (940aa18 2026-11-04)
moonc    v0.10.20+65efd5b93 (2026-11-05)
moonrun  0.1.20261104 (940aa18 2026-11-04)
```

CI 固定版本：`0.10.20+65efd5b93`（`ci.yml`、`copilot-setup-steps.yml`）；本地激活方式见 `CONTRIBUTING.md` 与 `scripts/use-toolchain.ps1`。

## 标准入口验证结果

| 项目 | 结果 |
|---|---|
| `moon check` | 0 errors（170 warnings） |
| `moon build` | 通过 |
| `moon test`（wasm-gc） | 287/287 |
| `moon test --target js` | 287/287 |
| `moon test --target native` | 287/287 |
| `moon run cmd/quickstart` | `2x1 PNG round-trip OK` |
| `moon run --target native cmd/cli -- --help` | 通过 |
| `node scripts/build-web.mjs --check` | `OK web/dist/web.js`、`OK web/dist/wasmcore.wasm` |

CI 覆盖 wasm-gc / js / native 三目标的检查与测试，并额外执行 `moon info` 接口漂移检查、JS 数值字面量规范化、Web 产物可复现性、浏览器 codec 适配器、线性内存 wasm、Worker、CLI、文档示例与可发布包内容等验证。

## 适配记录

- `web/dist/web.js` 与 `web/dist/wasmcore.wasm` 已用 0.10.20 重新生成并提交，保证 `scripts/build-web.mjs --check` 在 CI 中不报 stale。
- `scripts/use-toolchain.ps1` 的正则原先误写为 `v0.10.16+97801ee1b`，已修正为 `v0.10.20+65efd5b93`。
- 警告为 `test_unqualified_package` 等提示，0 error；`moon info` 未产生接口文件漂移。

## 平台限制

`native` 目标需要平台 C 编译器；CLI 示例不随 mooncakes 库包发布，需使用仓库源码。
