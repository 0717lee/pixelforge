# Changelog

## 0.17.4 (2026-09-09)

- Added the portable `cmd/cli` codec utility with `info` and `convert` commands.
- Added deterministic hexadecimal input/output so the utility works on native,
  JS, and wasm-gc without a target-specific filesystem dependency.
- Added adaptive PNG row filters and fixed-Huffman DEFLATE output with lossless
  round-trip coverage.
- Added multi-frame GIF metadata decoding and deterministic MSE/PSNR/SSIM
  image-quality metrics.
- Added Sauvola/local-mean thresholding, connected-component region statistics,
  and common 8-bit grayscale/palette PNG decode paths with `tRNS` support.
- Added deterministic format sniffing and lightweight dimension metadata for
  JPEG, WebP, AVIF and TIFF containers, plus an 8-neighbour LBP texture
  descriptor and histogram.
- Added zero-copy tile/row traversal, Harris corner detection, and WASM
  identity fast paths that avoid allocating for no-op or unknown dispatches.
- Added HOG descriptors, deterministic thresholded contours, and bounded
  Zhang--Suen skeletonization for advanced computer-vision workflows.
- Added JPEG decode/encode and lossless WebP encode adapters through
  `mizchi/image`, browser-target AVIF encoding, and a restricted baseline TIFF
  decoder for uncompressed chunky 8-bit grayscale/RGB/RGBA strips.
- Fixed target-specific AVIF adapter selection so wasm-gc and native web builds
  compile without importing the browser-only encoder.
- Added browser-native WebP/AVIF decode adapters with `createImageBitmap` and
  HTML image fallback, wired into the Playground upload path.
- Extended TIFF decoding to multiple strips, tiled images, PackBits/LZW
  compression, and a bounded BigTIFF subset with overflow-safe malformed-input
  checks.

## 0.17.3

### 修复与工程化
- Playground 的 Worker 渲染加入代际校验，避免切换图片或线程模式时旧结果覆盖新结果。
- Playground 增加上传失败、尺寸限制、缩放提示和下载错误反馈。
- WASM 验证、Web 构建产物和 CI 检查链路改为可复现并在失败时正确退出。
- 核心图像构造增加尺寸与溢出保护；补充编解码器畸形输入测试。
- 补充安全策略、贡献指南、行为准则和 Issue/PR 模板。
- 新增类型安全的 `Filter` / `Pipeline` API，支持可复用的顺序处理管线。
- Playground 支持带参数的操作栈、上移/下移、删除、撤销、重做和清空。

## 0.13.1 (2026-08-19)

### 文档
- README（中英）新增“与 MoonBit 生态中其他图像库的关系”章节，说明与 millow / MoonVision / shunge/image 的定位差异与 PixelForge 独有能力

## 0.13.0 (2026-07-31)

### 新增
- 直方图 API：`histogram_luma()`（复用 Otsu 的 256 桶 BT.601 分桶）与 `histogram_rgb()`（逐通道）
- HSL 色彩空间：`rgb_to_hsl` / `hsl_to_rgb`（与 HSV 风格一致、精确 8 位往返）与 `adjust_lightness(delta)`（保色相明暗调整）
- Playground：新增实时亮度直方图面板（经 `luma_histogram` js 绑定，每次渲染后更新）
- `cmd/showcase`：扩展“噪声 → 中值降噪 → 感知哈希”分析自检（受控平坦色块，median 必然降噪）

### 变更
- 单元测试从 163 个增加到 172 个

## 0.12.0 (2026-07-31)

### 新增
- 双三次缩放：`resize_bicubic(w, h)`，Catmull-Rom 4×4 核、中心对齐采样，同尺寸缩放为恒等
- 感知哈希：`average_hash()` / `difference_hash()` 返回 64 位指纹，`hamming_distance(a, b)` 度量相似度；区域均值缩略图保证跨后端确定性
- 确定性噪声：`add_gaussian_noise(seed, sigma)`（CLT 12 均匀和）与 `add_salt_pepper(seed, density)`，64 位 LCG 驱动，同 seed 逐字节可重现

### 变更
- 单元测试从 147 个增加到 163 个（含反相恰好翻转全部 64 位、中值滤波清除 ≥75% 椒盐噪声等强断言）

## 0.11.0 (2026-07-30)

代码审查驱动的加固（三视角审查后全量修复）：

### 变更
- `Stats` 结构由 `pub(all)` 收窄为 `pub`（只读），避免将字段集冻结进发布包的 semver 契约（便于日后扩展字段）
- `auto_contrast` 改为四舍五入除法，与 `stats`/`levels` 的舍入口径一致
- `Image::stats` 对空图（0×0）早返回全零结果，不再留下 min=255>max=0 的不自洽值
- `moon.mod` 的 exclude 新增 `cmd/`，不再将 demo 可执行包打进发布包

### 修复
- `cmd/showcase`：PNG 往返失败时改为 `abort`（使 CI 端到端冒烟测试能真正失败，而非静默通过）；诊断行移到 `P3` 魔数之后，保证输出为合规 PPM；背景新增一次 `box_blur` 滤镜，使展示覆盖更多招牌 API

## 0.10.0 / v1.0.0 (2026-07-30)

首个稳定版里程碑：公开 API 进入稳定期，后续遵循语义化版本（主版号内保持向后兼容）。

> 说明：mooncakes.io 目前要求主版号为 0，故该里程碑在 mooncakes 上以 **0.10.0** 发布；GitHub 保留 **v1.0.0** tag/release 作为稳定版标记。

### 新增
- 图像统计：`stats()` 返回逐通道 min/max/mean 与 luma 统计（Int64 累加，防溢出）
- 自动对比度：`auto_contrast()` 将 luma 线性拉伸至全量程，保持色相
- 色阶：`levels(black, white, gamma)` 窗口重映射与中间调 gamma
- 综合展示 CLI：`cmd/showcase` 组合绘图、位图文字、混合、滤镜与 PNG 编解码往返自检；CI 新增端到端冒烟测试

### 变更
- 单元测试从 141 个增加到 147 个；累计 27 个功能模块、约 6200 行有效 MoonBit 代码

## 0.9.0 (2026-07-30)

### 新增
- 积分图与 O(1) 盒式模糊：`integral_image()` 构建 Int64 求和面积表（防溢出），`Integral::rect_sum()` 四次查询得任意矩形和，`box_blur(radius)` 任意半径每像素 O(1)
- 泛洪填充：`flood_fill(x, y, r, g, b, a, tolerance)`，四连通显式栈种子填充，逐通道容差
- 距离变换：`distance_transform(threshold)`，两遍 chamfer (3,4) 距离，归一化为灰度

### 变更
- 单元测试从 126 个增加到 141 个

## 0.8.0 (2026-07-30)

### 新增
- 锐化蒙版：`unsharp_mask(radius, amount)`，复用可分离高斯提取高频细节并回叠
- 裁剪与填充：`crop(x, y, w, h)`（自动限幅，空选区降为 1x1）、`pad(l, t, r, b, color)`（颜色边框）；`crop∘pad` 无损往返
- Playground：dither_mono 接入派发表 id 22，新增 Otsu（21）与抖动（22）滤镜按钮，重建 web 产物

### 变更
- 单元测试从 117 个增加到 126 个

## 0.7.0 (2026-07-30)

### 新增
- Otsu 自动阈值：`otsu_threshold()` 类间方差最大化（Double 累加避免大图整数溢出），`otsu()` 一键二值化，接入派发表 id 21
- Floyd–Steinberg 抖动：`dither_grayscale(levels)` / `dither_mono()`，经典 7/16、3/16、5/16、1/16 误差扩散
- 连通域标记：`label_components(threshold)` 返回标签图与数量，`count_components` 便捷计数（四连通、显式栈泛洪填充）

### 变更
- 模块清单由 moon fmt 归一化回 moon.mod（exclude 保留在 options() 块内，发布包仍排除 assets 与个人文档）
- 单元测试从 102 个增加到 117 个

## 0.6.2 (2026-07-30)

### 变更
- 将 `moon.mod` 迁移为 `moon.mod.json`，并通过 `exclude` 字段将 `assets/`、`_screenshots/` 及个人文档排除出发布包（发布包从 83 项减至 72 项，图片仍保留在 GitHub 供 README 显示）

## 0.6.1 (2026-07-30)

### 安全
- 从发布包中移除非项目文档（项目申报书）并加固 `.gitignore`，防止个人信息随 `moon publish` 打包（感谢 @Nanaloveyuki 在 #30 中的友善提醒）；旧版本包已联系平台处理

## 0.6.0 (2026-07-30)

### 新增
- GIF 解码：`gif_decode`，支持 GIF87a/89a、全局/局部色表、图形控制扩展透明索引、变长 LSB-first LZW（含 KwKwK 与 4096 项字典上限）、四遍交错；畸形输入返回 `None`
- 双边滤波：`bilateral(radius, sigma_space, sigma_range)`，空间高斯 × luma 引导的值域高斯，保边平滑

### 变更
- 单元测试从 95 个增加到 102 个（含著名 1×1 透明 GIF 常量、手工汇编的 2×2 四色 GIF LZW 位流、双边 vs 高斯的保边对比等），达成申报目标 100+

## 0.5.0 (2026-07-28)

### 新增
- 可分离高斯模糊：`gaussian(radius)` 任意半径（二项式权重，行列两次 1D 扫描，每像素 O(r)；半径 1 与 3×3 高斯核一致）
- 图层合成：`composite(top, mode)` Porter-Duff source-over，`BlendMode` 含 Normal/Multiply/Screen/Overlay/Darken/Lighten/Difference/Add，纯整数舍入运算
- 位图文字：内置 5×7 字体（数字/A–Z/基本标点），`draw_char`/`draw_text` 整数倍缩放、小写折叠、自动裁剪
- 英文版 README（README.en.md），中英互链

### 变更
- 单元测试从 81 个增加到 95 个（全部手算验证，含逐模式合成期望值、字形精确像素数、高斯脉冲对称性等）

## 0.4.0 (2026-07-27)

### 新增
- 仿射变换：`Affine` 2×3 矩阵类型（旋转/平移/缩放/错切构造器、`then` 复合、`invert` 求逆）与 `Image::affine`（逆映射 + 双线性采样，未覆盖区域透明）；便捷方法 `rotate(degrees)`（绕中心任意角度）与 `translate(dx, dy)`
- 绘图原语：`draw_line`（Bresenham）、`draw_rect`/`fill_rect`、`draw_circle`（中点圆）/`fill_circle`，全部自动边界裁剪
- PNG 编解码：`png_encode`（8 位 RGBA，stored DEFLATE 块）与 `png_decode`（完整 inflate：stored/固定/动态 Huffman，逐块 CRC-32 与 zlib Adler-32 校验，全部 5 种行滤波，支持 RGB/RGBA）
- Playground：Web Worker 后台线程开关（双引擎均可在 Worker 中运行，像素缓冲区 transferable 传输）；下载按钮改用自家 `png_encode`（新增 `encode_png` js 绑定）

### 变更
- 单元测试从 62 个增加到 81 个（含 CRC-32/Adler-32 公开参考向量、手工汇编的固定 Huffman/LZ77 位流、rotate(90) 与 rotate90 逐字节一致性等）

## 0.3.0 (2026-07-27)

### 新增
- 形态学运算：`erode` / `dilate` / `morph_open` / `morph_close`（3×3 结构元）
- 色彩空间：`rgb_to_hsv` / `hsv_to_rgb` / `rgb_to_ycbcr` / `ycbcr_to_rgb`，及 `saturate`（饱和度）与 `hue_rotate`（色相旋转）滤镜
- QOI 编解码：`qoi_encode` / `qoi_decode`，完整实现 QOI 规范全部 6 种 op，无损往返，畸形输入返回 `None`
- BMP 编解码：`bmp_encode` / `bmp_decode`，无压缩 24/32 位，支持自上而下（负高度）位图
- Canny 边缘检测：`canny(low, high)`，含非极大值抑制与 8 连通滞后阈值追踪；接入派发表 id 20 与 Playground

### 变更
- 统一派发表 `Image::apply_filter_id` 扩展至 id 0–20
- 单元测试从 39 个增加到 62 个（含编码字节精确长度、无损往返、阶跃边缘几何等手算用例）

## 0.2.0 (2026-07-27)

### 新增
- 几何变换：`flip_horizontal` / `flip_vertical` / `rotate90`
- 缩放：`resize_nearest` / `resize_bilinear`（中心对齐采样，同尺寸缩放为恒等）
- 新滤镜：`posterize`（色调分离）、`gamma`（伽马校正）、`vignette`（暗角）、`scharr`（Scharr 边缘）
- CLI：`cmd/ppm` 示例，向 stdout 输出 PPM (P3) 图像（`moon run cmd/ppm > edges.ppm`）
- Playground：滤镜可叠加成管线、处理结果一键下载 PNG、新增伽马/暗角/Scharr/翻转/色调分离按钮
- GitHub Actions CI：`moon check` + wasm-gc/js 双后端测试 + Web 产物构建

### 变更
- Sobel 与 Scharr 共享同一梯度边缘引擎（内部重构，行为不变）
- 统一派发表 `Image::apply_filter_id` 扩展至 id 0–19
- 单元测试从 25 个增加到 39 个

## 0.1.0 (2026-07-24)

- 首个发布：`Image`/`Kernel` 核心类型，13 种滤镜与通用卷积引擎
- js 后端零拷贝浏览器绑定 + 线性内存 wasm 绑定（导出 memory）
- 浏览器 Playground（拖拽/粘贴/上传、JS/WASM 引擎切换与性能对比）
- 原生 CLI 示例、25 个确定性单元测试、发布至 mooncakes.io
