# PixelForge 开发交接

更新日期：2026-09-24。本文描述 AV1/AVIF 分库后的维护边界，不需要聊天记录或临时开发目录。

## 最终目标

PixelForge 提供图像处理、其他格式编解码、CLI 和浏览器 Playground；纯 MoonBit AV1/AVIF 解码核心由独立的 `0717lee/moonav1` 维护。消费者继续通过 PixelForge 的公开入口使用解码结果，既有 `Image`、滤镜和动画时序保持一致，解码实现只维护一份。

核心算法完整目标、原生像素参考和解码回归由 MoonAV1 的 HANDOFF 负责。本仓库负责适配层、宿主接线、交互和最终发布产物。

## 当前状态

这是本地迁移候选。来源是 PixelForge `6f0c711c54f89d34f3e2ef97cde7a0a45458583d`。独立库在工作区同级 `moonav1`，包名为 `0717lee/moonav1@0.1.0`；公开仓库与 Mooncakes 尚未发布。PixelForge 远端尚未变更。

原实现、个人阶段诊断和历史验收记录保留在 [来源提交的 HANDOFF](https://github.com/0717lee/pixelforge/blob/6f0c711c54f89d34f3e2ef97cde7a0a45458583d/HANDOFF.md)。迁移使用新增提交，不把既有实现重新计作新开发，也不改写原始历史。

## 目录和责任

| 路径 | 责任 |
| --- | --- |
| `codec_moonav1.mbt` | AV1/AVIF 公开类型及函数重导出；Image/动画包装；公开参考槽和时间选择语义 |
| `codec_moonav1_test.mbt` | 像素类型、网格、引用数组修改及复制隔离的消费者回归 |
| `image.mbt`、图像处理模块 | PixelForge 像素类型、滤镜、绘图和分析 |
| `external_codecs*` | JPEG/WebP 与浏览器 AVIF 编码适配，AVIF 编码不属于 MoonAV1 |
| `web/bindings.mbt`、`web/codecs.js`、`web/worker.js` | 静态/动画解码绑定与主线程/Worker 集成 |
| `scripts/build-web.mjs`、`web/dist` | 同步 JS/WASM 产物，支持模块及根目录 moon.work 的构建布局 |
| `tests/fixtures/avif-grid`、`avif-animation-alpha`、`avif-premultiplied-alpha` | 应用层独立像素与时序验收所需副本；完整来源在 MoonAV1 |
| `cmd/cli` | 文件输入、转换、过滤与输出 |

220 个解码源码/测试文件、对应生成器和完整参考集已经迁出本候选工作树。Image 相关 API 使用保留缓冲区的薄适配；公开参考数组可修改，store/show-existing 的复制隔离语义保留。

## 本地接入与验证

固定编译器 `0.10.11+6ff76a5f9`。新库尚未发布时，PixelForge 根目录可创建不提交的 `moon.work`：

```moonbit
members = [".", "../moonav1"]
```

发布后 `moon.mod` 的版本化依赖可以直接从 Mooncakes 安装，无需 workspace。不要把个人绝对路径写入提交。

```sh
moon check
moon test --target js -p 0717lee/pixelforge
moon test --target wasm-gc -p 0717lee/pixelforge
moon test --target native -p 0717lee/pixelforge
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

`-p` 限定消费者包，避免在本地 workspace 重复编译 MoonAV1 的完整参考测试；新库应在其目录独立运行三后端测试。普通 Moon 测试无需外部解码器。Web/Worker 验证禁止宿主 AVIF 解码并逐字节对照已保留的独立 RGBA。

## 本地验证记录

- MoonAV1：native、JS、wasm-gc 各 1306/1306；源参考 2344 文件逐个哈希保持一致。
- PixelForge 临时消费者：三目标各 242/242（原有 240 项，加 2 项适配边界回归）。
- Web 产物生成及严格复现检查、数字规范化、静态/动画/高位深 prem 独立像素、实际 Worker 与 WASM 集成通过。
- native CLI：10-bit YCgCo prem 图转 QOI 后用 Pillow 独立解码，1024 字节 RGBA 与参考完全相同；12-bit 彩色 grid 的 QOI 与分库前逐字节相同。
- 原有 1546 项是分库前 PixelForge 总数，不能继续作为分库后的本仓库测试数。

以上是临时迁移工作树的本地证据。最终依赖发布、主工作区应用、提交推送及远端 CI 仍待完成；不得据此声称远端迁移已经结束。

`avif-grid/manifest.json` 明确不要求彩色 grid 的最近邻 RGBA 与外部 `scalar.rgba` 一致。不要误把后者作为该转换策略的零差异金值；原生像素、单色图和 prem 参考各按自身契约验收。

## 颜色、许可证与异常

MoonAV1 输出 straight RGBA8；原生高位深样本保留至解码/合成结束，RGBA 遵循源 primaries/transfer 和最近邻色度上采样，不做 HDR 色调映射。PQ 四通道的独立高精度金值与 zimg 差 1 的约定继承原实现。静态和动画的错误输入继续明确拒绝，不以浏览器解码兜底。

`THIRD_PARTY_NOTICES.md` 继续保留被浏览器产物包含的 MoonAV1 上游声明。新失败样本先区分核心、适配和宿主层；核心修复提交到 MoonAV1 并补独立像素回归，再更新本仓库依赖和生成产物。
