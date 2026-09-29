# PixelForge 开发交接

更新日期：2026-09-29。当前版本为 **0.19.0**。本文描述维护范围与验收边界；用户接入见 [README](README.md)，升级路径见 [迁移说明](docs/MIGRATION.md)。

## 0.19.0 当前变更

- Playground 与 Worker 通过 `web/wasm-pipeline.js` 共享缓冲区所有权：同长度复用，长度变化替换实例；重复渲染不再持续分配输入缓冲。
- 最近邻缩放使用 Int64 计算采样位置，支持合法的长条图；最近邻、双线性、双三次对空图输出目标尺寸透明图像。
- BigTIFF 大小端格式探测、轻量尺寸 metadata 和 CLI 入口贯通，CLI 复用核心格式识别。
- 中英文 README、CLI 指南、贡献指南、迁移/发布说明与版本标识同步；文档示例、实际 CLI 转换及 WASM 内存回归进入 CI。
- 性能说明改为带环境和工作负载的 `scripts/benchmark.mjs`，不再沿用未记录条件的速度倍率。
- `.moonignore` 限定库包内容，排除 `_refs`、`tmp*` 实验目录、旧 fixture 和 Python 缓存；`check-package.mjs` 验证实际打包清单。

当前变更的验证记录见本文末尾；下方 2026-09-24 记录属于前一次清理。

## 最终目标

提供可在 native、JavaScript、wasm-gc 使用的 MoonBit 图像处理库，以及 CLI 和浏览器 Playground。保留图像滤镜、几何变换、绘图、分析、其他格式编解码与可复现的 Web 产物。当前像素库不包含 AV1 解码器，也不通过依赖或 vendor 引入替代实现。

AVIF 仅保留格式探测、轻量 metadata 和 JS 宿主编码适配。编码只接受不透明图像，依赖浏览器 Canvas AVIF 编码或 Node.js 中的外部 `ffmpeg`。Playground 加载 AVIF 依赖浏览器原生图片支持；native CLI 的 `info` 只读 AVIF metadata，`convert` 拒绝 AVIF 像素输入与输出。

## 当前移除范围与接口变化

本轮移除根目录 220 个 `av1*.mbt` / `avif*.mbt` 源码和测试文件、对应生成器、2,344 个专用 fixture 及变换语法参考文档；同时移除 Web/Worker 的纯解码绑定和专用验证路径。生成的 JS/WASM 产物已同步重建。

这是破坏性 API 变更：原 AV1 解码与状态类型、AVIF 像素解码、网格合成、动画和详细容器解析接口不再提供。格式探测、`image_metadata` 与浏览器编码适配保留。以 [pkg.generated.mbti](pkg.generated.mbti) 和 [CHANGELOG](CHANGELOG.md) 为接口依据。

旧实现与验收过程保留在 Git 历史中，见 [来源版本交接](https://github.com/0717lee/pixelforge/blob/6f0c711c54f89d34f3e2ef97cde7a0a45458583d/HANDOFF.md)。删除当前源码文件不改变已公开的历史内容。

## 结构与维护责任

| 路径 | 责任 |
| --- | --- |
| `image.mbt` 与图像处理模块 | RGBA 图像、滤镜、绘图、几何变换和分析 |
| `png.mbt`、`gif.mbt`、`qoi.mbt`、`bmp.mbt`、`tiff.mbt`、WebP 模块 | 保留的像素编解码能力 |
| `external_codecs*` | JPEG/WebP 适配与 JS 宿主 AVIF 编码 |
| `formats.mbt` | 格式识别和轻量容器信息 |
| `cmd/cli` | 文件/十六进制输入、metadata、像素转换与滤镜管线 |
| `web/` | Playground、浏览器加载、主线程与 Worker 图像处理 |
| `wasmcore/` | 线性内存 WASM 像素处理绑定 |
| `scripts/build-web.mjs`、`web/dist/` | 生成和验证随仓库分发的 Web 产物 |

CLI 使用方式见 [cmd/cli/README.md](https://github.com/0717lee/pixelforge/blob/main/cmd/cli/README.md)。依赖与许可见 [moon.mod](moon.mod) 和 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

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
node scripts/check-cli.mjs
node scripts/check-docs.mjs
node scripts/check-package.mjs
moon run --target native cmd/cli -- --help
git diff --check
```

关键成功路径包括保留格式的解码/转换、滤镜与 PNG 导出、主线程/Worker 处理及 WASM 绑定。边界验证包括 AVIF metadata-only `info`、AVIF 像素转换明确失败，以及不支持 AVIF 的浏览器能够报告加载失败。

验收时还需检查源码、公开接口及重建产物中没有已移除的解码算法或调用。旧解码器测试总数和独立像素记录不计入当前结果。

## 2026-09-24 清理验证记录

2026-09-24，本次清理的本地验证结果：

- `moon check`、`moon info`、`moon fmt` 完成；native、JavaScript、wasm-gc 各 **248/248** 项测试通过。新增 8 组纯容器测试，覆盖 AVIF 品牌、主图属性关联、宽 ID/索引、box 长度、截断和越界。
- Web 产物已重建，`build-web --check`、数值字面量规范化检查、浏览器编解码适配契约检查与 `verify-wasm` 全部通过。
- Playwright 在真实 Chromium 中加载 16×16 AVIF；JS/WASM × 主线程/Worker 四种组合的反色结果逐字节一致，alpha 保持正确，PNG 下载成功，浏览器控制台无错误或警告。这验证了该浏览器的原生支持，不代表所有浏览器均支持 AVIF。
- native CLI 成功读取真实 AVIF 的 16×16 主图尺寸及 `metadata_only=true`；PNG 经滤镜管线转为 QOI 并可重新读取。AVIF 像素输入和输出均以明确错误及非零退出码拒绝，未写出目标文件。
- `cmd/ppm`、`cmd/showcase` 和 CLI 帮助运行成功；`git diff --check` 通过。
- 源码、公开接口和生成 JS 已检查，无旧 AV1 解码算法或调用残留。AVIF metadata 仅读取主图关联的 `ispe`；无主图尺寸的纯轨道序列不在该 probe 的支持范围内。

以上是前次清理的历史记录；远端 CI 状态以对应提交的 [Actions 记录](https://github.com/0717lee/pixelforge/actions/workflows/ci.yml) 为准。

## 2026-09-29 本地验证记录

- 固定工具链：`moonc 0.10.11+6ff76a5f9` / `moon 0.1.20260827`；Windows x64，Node.js 24.12.0。
- `moon check` 通过；native、JavaScript、wasm-gc 各 **252/252** 项测试通过。新增回归覆盖长条图采样、三种缩放的空图行为、TIFF/BigTIFF 双字节序和截断/越界 metadata。
- `moon info` 完成，根库公开签名无变化；新增 quickstart 包接口。格式化保留在本轮修改的源码文件内。
- Web 产物重建与 `--check`、数字字面量规范化、浏览器适配契约检查通过。实际共享 WASM 宿主在 256×256、反色/模糊/亮度管线预热后连续 200 次渲染保持 **786,432 字节**线性内存，像素与 JS 一致；重复切换尺寸也通过。
- native CLI 对两种字节序 BigTIFF 完成 `info` 与转换；PNG 经灰度/亮度管线转 QOI，再转 BMP 后像素符合独立整数期望值。AVIF metadata 读取成功，AVIF 转换及错误管线以非零状态拒绝且不创建输出文件。
- 两份 README 的完整示例与 `cmd/quickstart` 一致，并在三后端运行成功。另按安装步骤创建独立项目，安装已发布 `0.18.0`，运行同一示例成功。Windows 上 `moon new` 的 README 符号链接权限提示不影响示例运行。
- Playwright 驱动实际 Chromium 验证：17×9 PNG 上传，JS/WASM × 主线程/Worker 四组合得到预期 RGBA `(243,211,179,255)`；排序、撤销/重做、Worker/WASM 下切换 31×13、4×7、17×9 成功；下载 PNG 的签名和尺寸正确，控制台无错误或警告。
- Node 基准脚本完成像素一致性和环境/工作负载/median/p95 输出。时间数据只用于该次本机工作负载，不作为跨设备速度结论。
- 文档链接、版本/格式表与可运行示例检查通过；发布包检查排除本地参考和临时文件。归档位于 `_build/publish/0717lee-pixelforge-0.19.0.zip`。

以上为本地验证记录。版本入口：[mooncakes 包与 API](https://mooncakes.io/docs/0717lee/pixelforge)、[GitHub v0.19.0](https://github.com/0717lee/pixelforge/releases/tag/v0.19.0)。远端验证以对应提交的 Actions 日志为准。后续发布按 [发布指南](docs/RELEASING.md) 执行；旧 `0.18.0` 包及其文档保留历史内容。
