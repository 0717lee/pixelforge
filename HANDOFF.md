# PixelForge 开发交接

更新日期：2026-09-24。本文描述 AV1/AVIF 分库后的维护边界，不需要聊天记录或临时开发目录。

## 最终目标

PixelForge 提供图像处理、其他格式编解码、CLI 和浏览器 Playground；纯 MoonBit AV1/AVIF 解码核心由独立的 `0717lee/moonav1` 维护。消费者继续通过 PixelForge 的公开入口使用解码结果，既有 `Image`、滤镜和动画时序保持一致，解码实现只维护一份。

核心算法完整目标、原生像素参考和解码回归由本地独立 MoonAV1 库维护。本仓库负责固定快照、适配层、宿主接线、交互和最终发布产物，快照说明见 [vendor/moonav1/README.md](vendor/moonav1/README.md)。

## 当前状态

来源是 PixelForge `6f0c711c54f89d34f3e2ef97cde7a0a45458583d`。迁移提交 `e366566e95b59173738bdb9bbbc5376550bd92cb` 将解码调用改为独立库，后续快照提交补齐未发布阶段的自包含依赖。维护者选择保留历史与现有功能，以新增提交分离维护边界。

`0717lee/moonav1@0.1.0` 作为本地独立库维护，尚未创建公开仓库或发布到 Mooncakes。PixelForge 随源码携带 `vendor/moonav1` 固定来源提交的快照，并通过已提交的 `moon.work` 使用它；消费者无需同级 MoonAV1 目录或未发布的 registry 包。快照是生成物，解码实现仍只在独立库维护。

原实现、个人阶段诊断和历史验收记录保留在 [来源提交的 HANDOFF](https://github.com/0717lee/pixelforge/blob/6f0c711c54f89d34f3e2ef97cde7a0a45458583d/HANDOFF.md)。迁移使用新增提交，不把既有实现重新计作新开发，也不改写原始历史。

## 目录和责任

| 路径 | 责任 |
| --- | --- |
| `codec_moonav1.mbt` | AV1/AVIF 公开类型及函数重导出；Image/动画包装；公开参考槽和时间选择语义 |
| `codec_moonav1_test.mbt` | 像素类型、网格、引用数组修改及复制隔离的消费者回归 |
| `vendor/moonav1`、`moon.work` | 固定提交的解码源码、内嵌测试、接口与许可；仓库内 workspace 接入 |
| `scripts/vendor-moonav1.mjs` | 从已提交的独立库修订生成快照，或离线核验已登记的来源和文件 |
| `image.mbt`、图像处理模块 | PixelForge 像素类型、滤镜、绘图和分析 |
| `external_codecs*` | JPEG/WebP 与浏览器 AVIF 编码适配，AVIF 编码不属于 MoonAV1 |
| `web/bindings.mbt`、`web/codecs.js`、`web/worker.js` | 静态/动画解码绑定与主线程/Worker 集成 |
| `scripts/build-web.mjs`、`web/dist` | 同步 JS/WASM 产物，支持模块及根目录 moon.work 的构建布局 |
| `tests/fixtures/avif-grid`、`avif-animation-alpha`、`avif-premultiplied-alpha` | 应用层独立像素与时序验收所需副本；完整来源在 MoonAV1 |
| `cmd/cli` | 文件输入、转换、过滤与输出 |

解码源码与测试的维护归属已迁至 MoonAV1。快照包含 222 个 MoonBit 文件、模块/包配置、公开接口、许可证、第三方声明与 PROVENANCE；README 由同步工具生成。完整 fixture、生成器和独立库 CI 不进入快照；本仓库保留三组浏览器集成所需 fixture。Image 相关 API 使用保留缓冲区的薄适配；公开参考数组可修改，store/show-existing 的复制隔离语义保留。

## 本地接入与验证

固定编译器 `0.10.11+6ff76a5f9`。仓库已提交的 `moon.work` 使用仓库内快照：

```moonbit
members = [".", "vendor/moonav1"]
```

完整检出 PixelForge 后可直接验证，不需要维护者的个人路径。快照来源提交和文件清单由同步工具登记；CI 离线检查快照，不访问尚未发布的 MoonAV1 包。

```sh
node scripts/vendor-moonav1.mjs --check
moon check
moon test --target js
moon test --target wasm-gc
moon test --target native
moon info
moon fmt
node scripts/build-web.mjs
node scripts/check-canonicalize-moon-js.mjs
node scripts/build-web.mjs --check
node scripts/check-browser-codecs.mjs
node verify-wasm.mjs
moon run --target native cmd/cli -- --help
git diff --check
```

默认 `moon test` 覆盖 workspace 中两个模块，合计 1548 项（MoonAV1 1306 + PixelForge 242）；CI 使用这个完整范围。单独检查消费者时加 `-p 0717lee/pixelforge`，单独检查快照中的解码测试时加 `-p 0717lee/moonav1`，无需再重复完整套件。独立库自身保留三后端 CI 配置，尚未公开托管。普通 Moon 测试无需外部解码器。Web/Worker 验证禁止宿主 AVIF 解码并逐字节对照已保留的独立 RGBA。

## 迁移候选的本地验证记录

- MoonAV1 初始独立包候选：native、JS、wasm-gc 各 1306/1306；源参考 2344 文件逐个哈希保持一致。
- PixelForge 迁移候选：三目标各 242/242（原有 240 项，加 2 项适配边界回归）。
- Web 产物生成及严格复现检查、数字规范化、静态/动画/高位深 prem 独立像素、实际 Worker 与 WASM 集成通过。
- native CLI：10-bit YCgCo prem 图转 QOI 后用 Pillow 独立解码，1024 字节 RGBA 与参考完全相同；12-bit 彩色 grid 的 QOI 与分库前逐字节相同。
- 原有 1546 项是分库前 PixelForge 总数，不能继续作为分库后的本仓库测试数。

以上是初始独立包与迁移候选的本地证据，不代替固定快照接入后的最终主线验证。依赖接入方式已确定为仓库内快照；本轮不创建公开 MoonAV1 仓库或发布 Mooncakes。

## 固定快照的最终验证记录

以下为 2026-09-24 固定快照接入后的实测，不复用上节候选结果：

| 检查 | 结果 |
| --- | --- |
| MoonAV1 来源 | `9f0f0c31a3ab35f169836223e6505b584882a15a`；记录于 `vendor/moonav1/snapshot.json` |
| 离线快照校验 | 229 个文件校验通过；228 个来源文件与源 Git 提交字节相同，README 为生成说明 |
| 依赖解析、接口与格式 | `moon update`、`moon info`、`moon fmt`、`moon check` 成功；check 为 72 条原有告警、0 错误 |
| JavaScript | 全 workspace 1548/1548 通过 |
| wasm-gc | 全 workspace 1548/1548 通过 |
| native | 全 workspace 1548/1548 通过 |
| Web 产物 | 严格字节复现检查通过，生成物与迁移候选一致；JS 数字规范化检查通过 |
| 主线程/Worker | 8/10/12-bit grid、alpha/prem 动画、独立像素、时序和错误路径通过，宿主 AVIF 解码被禁用 |
| 线性内存 WASM | 滤镜、原地管线、内存与 alpha 保留检查通过 |
| native CLI | 10-bit YCgCo prem AVIF 转 QOI，用 Pillow 独立解码后全部 1024 字节 RGBA 与参考一致 |
| 差异与文档 | `git diff --check` 通过；迁移文档与快照说明的相对文件链接无缺失 |

[GitHub CI](https://github.com/0717lee/pixelforge/actions/workflows/ci.yml) 在干净 Ubuntu 检出中运行依赖解析、快照检查、三后端全套测试、Web/Worker/WASM 与 CLI；按具体提交查看远端运行结论。远端检出无需本地同级 MoonAV1 仓库，也不需要发布该包。

`avif-grid/manifest.json` 明确不要求彩色 grid 的最近邻 RGBA 与外部 `scalar.rgba` 一致。不要误把后者作为该转换策略的零差异金值；原生像素、单色图和 prem 参考各按自身契约验收。

## 颜色、许可证与异常

MoonAV1 输出 straight RGBA8；原生高位深样本保留至解码/合成结束，RGBA 遵循源 primaries/transfer 和最近邻色度上采样，不做 HDR 色调映射。PQ 四通道的独立高精度金值与 zimg 差 1 的约定继承原实现。静态和动画的错误输入继续明确拒绝，不以浏览器解码兜底。

`THIRD_PARTY_NOTICES.md` 继续保留快照和浏览器产物包含的 MoonAV1 上游声明。新失败样本先区分核心、适配和宿主层；核心修复在独立 MoonAV1 库完成、补独立像素回归并提交后，在 PixelForge 根目录执行：

```sh
node scripts/vendor-moonav1.mjs ../moonav1
node scripts/vendor-moonav1.mjs --check
node scripts/build-web.mjs
```

同步命令的参数是独立库检出目录，仅维护者更新快照时需要；普通检出和 CI 使用仓库内快照。不要直接编辑 `vendor/moonav1`。更新后完成适用验证并检查来源提交与文件清单；公开仓库和包发布另行决定。
