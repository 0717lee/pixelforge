# PixelForge 开发交接

更新日期：2026-09-24。本文描述当前源码的维护范围与验收边界，无需聊天记录。

## 最终目标

提供可在 native、JavaScript、wasm-gc 使用的 MoonBit 图像处理库，以及 CLI 和浏览器 Playground。保留图像滤镜、几何变换、绘图、分析、其他格式编解码与可复现的 Web 产物。当前像素库不包含 AV1 解码器，也不通过依赖或 vendor 引入替代实现。

AVIF 仅保留格式探测、轻量 metadata 和浏览器专用编码适配。Playground 加载 AVIF 依赖浏览器原生图片支持；native CLI 的 `info` 只读 AVIF metadata，`convert` 明确拒绝 AVIF 像素输入与输出。

## 当前移除范围与接口变化

本轮移除根目录 220 个 `av1*.mbt` / `avif*.mbt` 源码和测试文件、对应生成器、2,344 个专用 fixture 及变换语法参考文档；同时移除 Web/Worker 的纯解码绑定和专用验证路径。生成的 JS/WASM 产物已同步重建。

这是破坏性 API 变更：原 AV1 解码与状态类型、AVIF 像素解码、网格合成、动画和详细容器解析接口不再提供。格式探测、`image_metadata` 与浏览器编码适配保留。以 [pkg.generated.mbti](pkg.generated.mbti) 和 [CHANGELOG](CHANGELOG.md) 为接口依据。

旧实现与验收过程保留在 Git 历史中，见 [来源版本交接](https://github.com/0717lee/pixelforge/blob/6f0c711c54f89d34f3e2ef97cde7a0a45458583d/HANDOFF.md)。删除当前源码文件不改变已公开的历史内容。

## 结构与维护责任

| 路径 | 责任 |
| --- | --- |
| `image.mbt` 与图像处理模块 | RGBA 图像、滤镜、绘图、几何变换和分析 |
| `png.mbt`、`gif.mbt`、`qoi.mbt`、`bmp.mbt`、`tiff.mbt`、WebP 模块 | 保留的像素编解码能力 |
| `external_codecs*` | JPEG/WebP 适配与浏览器专用 AVIF 编码 |
| `formats.mbt` | 格式识别和轻量容器信息 |
| `cmd/cli` | 文件/十六进制输入、metadata、像素转换与滤镜管线 |
| `web/` | Playground、浏览器加载、主线程与 Worker 图像处理 |
| `wasmcore/` | 线性内存 WASM 像素处理绑定 |
| `scripts/build-web.mjs`、`web/dist/` | 生成和验证随仓库分发的 Web 产物 |

CLI 使用方式见 [cmd/cli/README.md](cmd/cli/README.md)。依赖与许可见 [moon.mod](moon.mod) 和 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 构建与验证

固定 MoonBit 编译器为 `0.10.11+6ff76a5f9`；native 需要 C 工具链，Web 检查需要 Node.js。在仓库根目录运行：

```sh
moon version --all
moon update
moon check
moon info
moon test --target js
moon test --target wasm-gc
moon test --target native
node scripts/build-web.mjs
node scripts/check-canonicalize-moon-js.mjs
node scripts/build-web.mjs --check
node scripts/check-browser-codecs.mjs
node verify-wasm.mjs
moon run --target native cmd/cli -- --help
git diff --check
```

关键成功路径包括保留格式的解码/转换、滤镜与 PNG 导出、主线程/Worker 处理及 WASM 绑定。边界验证包括 AVIF metadata-only `info`、AVIF 像素转换明确失败，以及不支持 AVIF 的浏览器能够报告加载失败。

验收时还需检查源码、公开接口及重建产物中没有已移除的解码算法或调用。旧解码器测试总数和独立像素记录不计入当前结果。

## 本轮验证记录

2026-09-24，本次清理的本地验证结果：

- `moon check`、`moon info`、`moon fmt` 完成；native、JavaScript、wasm-gc 各 **248/248** 项测试通过。新增 8 组纯容器测试，覆盖 AVIF 品牌、主图属性关联、宽 ID/索引、box 长度、截断和越界。
- Web 产物已重建，`build-web --check`、数值字面量规范化检查、浏览器编解码适配契约检查与 `verify-wasm` 全部通过。
- Playwright 在真实 Chromium 中加载 16×16 AVIF；JS/WASM × 主线程/Worker 四种组合的反色结果逐字节一致，alpha 保持正确，PNG 下载成功，浏览器控制台无错误或警告。这验证了该浏览器的原生支持，不代表所有浏览器均支持 AVIF。
- native CLI 成功读取真实 AVIF 的 16×16 主图尺寸及 `metadata_only=true`；PNG 经滤镜管线转为 QOI 并可重新读取。AVIF 像素输入和输出均以明确错误及非零退出码拒绝，未写出目标文件。
- `cmd/ppm`、`cmd/showcase` 和 CLI 帮助运行成功；`git diff --check` 通过。
- 源码、公开接口和生成 JS 已检查，无旧 AV1 解码算法或调用残留。AVIF metadata 仅读取主图关联的 `ispe`；无主图尺寸的纯轨道序列不在该 probe 的支持范围内。

本记录对应当前 Unreleased 清理变更；远端 CI 状态以对应提交的 [Actions 记录](https://github.com/0717lee/pixelforge/actions/workflows/ci.yml) 为准。
