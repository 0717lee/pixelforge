# PixelForge

[![CI](https://github.com/0717lee/pixelforge/actions/workflows/ci.yml/badge.svg)](https://github.com/0717lee/pixelforge/actions/workflows/ci.yml)

简体中文 | [English](README.en.md)

PixelForge 是使用 MoonBit 编写的 RGBA8 图像处理库，提供滤镜、几何变换、绘图、分析和编解码，以及 native CLI 和浏览器 Playground。核心支持 JavaScript、wasm-gc 和 native；Playground 另提供线性内存 WebAssembly 引擎。

**当前版本为 `0.19.0`。** 本版移除了旧 AV1/AVIF 解析和像素解码接口，从 `0.18.0` 升级前请阅读[迁移说明](docs/MIGRATION.md)。历史 GitHub `v1.0.0` 对应早期 `0.10.0` 包，不代表当前版本。版本历史见 [CHANGELOG](CHANGELOG.md)。

**未发布开发版：** 新增基于 `0717lee/moonav1@0.2.0` 的 `avif_decode(bytes)` 和 CLI AVIF 输入转换。下方格式表描述当前源码；通过上述版本号安装的 `0.19.0` 不含此功能。开发工具链固定为 `moonc 0.10.14+7d59c7ec9`，激活方式见 [贡献指南](CONTRIBUTING.md)。

## 快速开始

安装 [MoonBit 工具链](https://www.moonbitlang.com/download/)，新建项目并添加依赖：

```sh
moon new pixel-demo --user demo_user
cd pixel-demo
moon add 0717lee/pixelforge@0.19.0
```

将 `cmd/main/moon.pkg` 设置为：

```moonbit
import {
  "0717lee/pixelforge",
}

pkgtype(kind: "executable")
```

将 `cmd/main/main.mbt` 替换为以下完整示例：

```moonbit
///|
fn main {
  let image = @pixelforge.Image::new(2, 1)
  image.set_pixel(0, 0, b'\xFF', b'\x00', b'\x00', b'\xFF')
  image.set_pixel(1, 0, b'\x00', b'\xFF', b'\x00', b'\xFF')
  let pipeline = @pixelforge.Pipeline::new()
    .append(@pixelforge.Filter::Grayscale)
    .append(@pixelforge.Filter::Brightness(10))
  let processed = image.apply_pipeline(pipeline)
  let png = @pixelforge.png_encode(processed)
  let decoded = match @pixelforge.png_decode(png) {
    Some(value) => value
    None => abort("PNG decoding failed")
  }
  if decoded.data != processed.data {
    abort("PNG round-trip changed pixels")
  }
  println("\{decoded.width}x\{decoded.height} PNG round-trip OK")
}
```

运行 `moon run cmd/main`，预期输出 `2x1 PNG round-trip OK`。切换后端使用 `--target js` 或 `--target native`；native 需要平台 C 编译器。仓库内的同一示例见 [cmd/quickstart](https://github.com/0717lee/pixelforge/blob/main/cmd/quickstart/main.mbt)，可用 `moon run cmd/quickstart` 验证当前源码。

## 功能与 API

| 类别 | 主要能力 |
| --- | --- |
| 滤镜与色调 | 灰度、反色、亮度、对比度、阈值、棕褐色、像素化、中值、直方图均衡、色调分离、gamma、暗角、饱和度、色相、HSL 亮度、色阶、自动对比度 |
| 卷积与边缘 | 自定义 `Kernel` / `convolve`，高斯与盒式模糊、锐化、浮雕、Laplacian、Sobel、Scharr、Canny、双边滤波、锐化蒙版 |
| 几何与绘图 | 裁剪、填充、翻转、旋转、仿射矩阵、最近邻/双线性/双三次缩放，线/矩形/圆，5×7 位图文字，source-over 与八种混合模式 |
| 分析与特征 | RGB/luma 直方图与统计，Otsu/Sauvola/局部均值阈值，形态学、骨架、连通域/区域统计/轮廓、Harris、HOG、LBP、积分图、距离变换、泛洪填充 |
| 比较与噪声 | aHash/dHash/汉明距离，MSE/PSNR/SSIM，确定性高斯与椒盐噪声，Floyd–Steinberg 抖动 |
| 组合与遍历 | 类型化 `Filter` / `Pipeline`、数字 id 派发、共享像素的 `for_each_tile` / `for_each_row` |

当前公开签名见 [pkg.generated.mbti](pkg.generated.mbti)，参数说明在对应源码注释中。[mooncakes API 文档](https://mooncakes.io/docs/0717lee/pixelforge) 对应已发布版本。

`Image` 按行存储 RGBA 字节，长度必须为 `width * height * 4`。`from_bytes` 包装原缓冲区，修改缓冲区也会改变图像；需要独立所有权时使用 `copy()`。滤镜、几何变换和管线返回新图像；`set_pixel`、绘图与文字方法原地修改图像。tile/row 与原图共享像素。

`mse` / `psnr` 比较 RGBA 四通道；`luma_mse` / `ssim` 使用 Rec.601 亮度并忽略 alpha。`ssim` 使用整幅图像的单个总体统计窗口，相同尺寸的空图返回 1。默认情况下，双线性/双三次缩放分别插值 RGBA 通道，不进行预乘 alpha 转换。

开发版的 `image.thumbnail(320, 240)` 使用按透明度加权的双线性采样，将图像按比例缩至边界内，
不裁剪、不放大小图，并返回独立缓冲。短边向下取整且至少为 1 像素；非正边界按 1
处理，空图像保留原尺寸。CLI 对应参数为 `--fit 320x240`，要求两个边界均为正整数，
缩放在滤镜之前执行。

缩略图会避免完全透明像素的残留 RGB 污染可见颜色。需要指定输出尺寸时，可调用
`image.resize_bilinear(320, 240, alpha_weighted=true)`；省略该参数仍保留原有的
RGBA 独立插值行为。加权模式输出普通 RGBA，重采样后透明度舍入为零的像素置为透明黑，
同尺寸缩放保留所有字节。计算使用原通道值，不进行线性光转换。

## 格式与后端支持

“核心”指 JavaScript、wasm-gc 和 native。Playground 图片加载使用浏览器解码器，其支持范围与核心编解码器分开。

| 格式 | 核心解码 | 核心编码 | 主要边界 |
| --- | --- | --- | --- |
| PNG | 支持 | 支持 | 非交错、8-bit 灰度/灰度透明/调色板/RGB/RGBA；tRNS；CRC-32/Adler-32 校验；输出 RGBA8 |
| GIF | 支持 | 支持 | LZW、交错、透明索引；编码单帧、最多 256 个调色板项，alpha < 128 视为透明，超限 abort |
| QOI | 支持 | 支持 | RGBA 无损往返 |
| BMP | 支持 | 支持 | 无压缩 24/32-bit；24-bit 输出不保留 alpha |
| JPEG | 支持 | 支持 | `mizchi/image` 的 baseline JPEG；有损，不保留 alpha；`jpeg_encode(image, quality)` |
| WebP | Lossless VP8L | Lossless VP8L | 解码 predictor、cross-color、subtract-green、color-indexing 变换；不解码有损 VP8 |
| TIFF | 支持子集 | 不支持 | classic：chunky 8-bit 灰度/RGB/RGBA，多条带或 tiles，未压缩/PackBits/LZW/Deflate，Predictor=2；BigTIFF：单条带，未压缩/PackBits/LZW，偏移和值在支持的 Int 范围内 |
| AVIF | MoonAV1 RGBA8 解码 | JS 宿主适配 | `avif_decode` 支持 js/wasm-gc/native；解码范围遵循 MoonAV1 0.2.0；编码只接受不透明图像，浏览器需支持 Canvas AVIF 编码，依赖在 Node.js 中使用本地 `ffmpeg`；native/wasm-gc 编码 abort |

`detect_image_format()` 识别签名；`image_metadata()` 读取支持的尺寸信息，均不证明完整像素数据可解码。TIFF/BigTIFF 支持大小端探测。AVIF metadata 读取主图关联的 `ispe`，不支持无主图尺寸的纯轨道序列。

`gif_decode_all()` 返回帧图像及位置、延迟、透明索引和 disposal 元数据，调用方负责播放和帧合成；`gif_decode()` 返回首帧。`avif_decode()` 返回 AVIF 主图的独立 RGBA8 缓冲，支持 MoonAV1 的静态图、alpha 和网格路径；无效、不支持或超过解码资源限制的输入返回 `None`。该适配接口不提供动画播放。

处理算子使用 `moonbitlang/core`；AVIF 解码使用 `0717lee/moonav1`；JPEG 编解码、WebP 编码与 AVIF 编码适配使用 `mizchi/image`，native CLI 使用 `moonbitlang/x/fs`。依赖版本和许可见 [moon.mod](moon.mod) 与 [第三方说明](THIRD_PARTY_NOTICES.md)。

## 错误、尺寸和参数

- 像素解码返回 `Image?`（多帧 GIF 返回帧数组选项）；格式错误或不支持的变体返回 `None`，由调用方处理。
- `Image::new` / `from_bytes` 对负尺寸、超过 100,000,000 像素或缓冲区长度不匹配执行 `abort`。`abort` 是终止当前执行的 panic，不是可通过 `catch` 恢复的普通解码错误。坐标越界、比较/合成尺寸不匹配也会 abort。
- 任一边为零的图像合法。三个缩放方法将目标边长至少设为 1；空源图生成该尺寸的透明图像。其他算子按各自文档使用。
- 编码器可能因格式限制而 abort；先检查格式支持、尺寸、GIF 调色板或 AVIF alpha 条件。宿主应按内存预算限制输入文件大小和像素数。
- `Pipeline` 与数字派发共用默认规则：阈值 ≤ 0 使用 128，像素块 < 2 使用 8，色阶数 < 2 使用 4，gamma ≤ 0 使用 2.2，暗角 ≤ 0 使用 0.5，Canny 高阈值 ≤ 0 使用 100。需要显式零值时直接调用 `threshold(0)` / `vignette(0.0)`。数字 id 对照表见 [dispatch.mbt](dispatch.mbt)。

## 浏览器 Playground 与性能

在仓库根目录运行（需要 Node.js 22 或更新版本）：

```sh
node serve.mjs
```

打开 [localhost:8123](http://localhost:8123)。支持上传/拖拽/粘贴、参数化管线、撤销/重做、JS/WASM 切换、Worker 和 PNG 下载。GIF 保留动画预览，处理管线编辑载入帧；WebP/AVIF 加载依赖浏览器原生支持。

上传限制为 20 MiB、16,000,000 像素、单边 8192；预览最长边缩放到 1024，下载也使用预览尺寸。处理原始分辨率请使用库或 CLI。

主线程和 Worker 通过 [WasmPipeline](web/wasm-pipeline.js) 管理线性内存：同缓冲区长度复用像素分配，长度变化则替换实例，让旧实例可被回收。直接使用低层 `alloc` 的宿主也须管理实例生命周期，不能每次渲染无限分配。

JS/WASM 的快慢取决于输入、滤镜、宿主和拷贝成本。页面对比使用当前预览和管线，每引擎预热一次，再运行十次取平均；包含像素复制和计算，不含解码、绘制或 Worker 通信。可复现的 Node.js 基准：

```sh
node scripts/benchmark.mjs
```

脚本报告 Node/操作系统/CPU、固定输入与操作、预热/采样次数、median/p95 和 WASM 内存；先校验两引擎像素一致，再计时。这些结果不代表浏览器性能，也不构成通用速度倍率。

## CLI

```sh
moon run --target native cmd/cli -- --help
moon run --target native cmd/cli -- info --input input.tiff
moon run --target native cmd/cli -- convert --from png --to qoi --pipeline grayscale,contrast:1.2 --input input.png --output output.qoi
```

`info` 对 AVIF 仅读 metadata；`convert` 支持 AVIF 输入，可应用滤镜后输出 PNG、QOI 等格式，AVIF 输出仍不支持。例如：`moon run --target native cmd/cli -- convert --from avif --to png --pipeline grayscale --input input.avif --output output.png`。格式、管线、退出和文件覆盖行为见 [CLI 文档](https://github.com/0717lee/pixelforge/blob/main/cmd/cli/README.md)。CLI 示例不随 mooncakes 库包发布，需使用仓库源码。

## 开发与贡献

工具链、验证命令、规范和 Web 产物更新见 [CONTRIBUTING](CONTRIBUTING.md)。[HANDOFF](HANDOFF.md) 记录维护范围和验收证据；[发布指南](docs/RELEASING.md) 说明版本、包文档与 GitHub Release 的同步步骤。

根目录为核心及单元测试；`cmd/` 为示例；`web/` 为 Playground；`wasmcore/` 为线性内存绑定；`scripts/` 为构建、文档、CLI 和性能验证。

反馈问题请附版本、后端和最小复现。安全问题按 [SECURITY](SECURITY.md) 私下报告；参与规范见 [CODE_OF_CONDUCT](CODE_OF_CONDUCT.md)。

## 许可证

[Apache-2.0](LICENSE)，依赖归属见 [THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES.md)。
