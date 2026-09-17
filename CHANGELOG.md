# Changelog

## Unreleased

- Added the AV1 loop-restoration decode pipeline. The entropy layer grows
  `read_literal`, the finite-alphabet `ns(n)` decoder and the `subexp(n,k)`
  reader with the inverse recentering, all on the arithmetic decoder;
  per-superblock unit reads fill a per-tile LR entropy state before each
  root superblock and feed the frame-level unit grid. Deblocked rows are
  snapshotted at every internal stripe boundary (64 luma, 8 chroma, halved
  for 4:2:0) into a stripe store that the source view reads with
  top/bottom pairing and frame-edge replication, and the scalar Wiener and
  SGR-projection filters apply on the upscaled post-CDEF frame at native
  8/10/12-bit depth. Wiener uses the per-depth round0/inter-round pair, the
  symmetric seven-tap layout and an intermediate clamp that never touches
  legal samples; SGR runs both box passes with the cdef-domain intermediate,
  the r0=0 self-replacement branch, the xqd offset clamps and the a2/b2
  index rounding. All-None planes and None units bypass filtering entirely.
- Verified the filters against dav1d pixel ground truth: one 97x65 10-bit
  4:2:0 restoration frame decoded with and without the filters is
  byte-identical to the dav1d CLI, cross-checked against FFmpeg's libdav1d,
  matching all 9,539 decoded samples (9,429 of which the restoration changes
  relative to the no-restoration control). Forty-six new tests cover the
  entropy readers, the pre-superblock unit syntax, the stripe store and
  source view, and the Wiener/SGR kernels against hand-computed values and a
  standalone Python reference simulator over four 120x16 planes. Full suite:
  1052/1052.

- Added AV1 loop-restoration header parsing, configuration validation and
  unit-grid layout. The uncompressed header reads per-plane lr_type codes in
  Y/U/V order (`00` None, `01` Switchable, `10` Wiener, `11` Sgrproj), the
  luma unit-size bits under SB64/SB128 and the 4:2:0 lr_uv_shift halving;
  all-None configurations take the implicit U256 without size bits, and the
  CodedLossless versus AllLossless gates stay distinct. The optional
  `Av1RestorationConfig` propagates through every decode entry point, and the
  grid layout mirrors `av1_alloc_restoration_struct` on the upscaled plane
  dimensions with the `av1_lr_count_units` tail rule.
- Verified against one untouched libaom encode with active Wiener on every
  plane (97x65 10-bit 4:2:0, superres denominator 12): the deterministic
  noise fixture regenerates byte-identically and its FFmpeg trace_headers
  transcript locks the parsed sequence, frame, CDEF, tx-mode and restoration
  fields. The trace's tx_mode ordinal uses FFmpeg's ONLY_4X4/LARGEST/SELECT
  numbering, where ordinal 1 is TX_MODE_LARGEST and the expected
  tx_mode_select is false; CDEF secondary strengths keep the parse-time remap
  of coded 3 to 4. Full suite: 1006/1006.

- Added normative AV1 horizontal super-resolution decoding at 8/10/12 bits.
  The header parses use_superres plus the coded denominator (nine through
  sixteen), derives the entropy-coded frame_width against the display width
  and keeps both dimensions distinct through tile geometry. The fixed 8-tap
  phase interpolation upscales complete native-depth planes after deblocking
  and CDEF, with Q14 stepping, half-error phase correction and outer-edge
  replication per the pinned libaom scalar path. CodedLossless and AllLossless
  stay distinct when scaling occurs, active restoration syntax is still
  consumed, and allow_intrabc only appears without scaling.
- Verified the kernel against 780 original-C normatives cases covering all
  bit depths, both plane groups, phases, strides and padding. Eighteen
  complete dual-dav1d references cover denominators 9–16, color/mono,
  8/10/12 bits, odd crops and two-tile seams; two constructed q0 headers
  exercise the screen-content and restoration syntax gates.

- Added native 8/10/12-bit AV1 palette decoding, including all 2–8-color
  probabilities, direct-MI neighbor caches, signed V deltas, diagonal index
  traversal and coded-edge padding. Palette predictions retain ordinary
  transform residuals, CfL and filter-intra syntax gates.
- Verified palette colors with 21 entropy transcripts and indices with 1,365
  original-C contexts and 112 complete maps. Twenty-one independently decoded
  full streams cover cache resets inside 128-pixel superblocks, chroma owners,
  palette/FI/CfL combinations and transform selection with nonzero AC.

- Added all five filter-intra modes at native 8/10/12-bit precision, with shared
  mode probabilities, per-transform prediction and ordinary residual/CfL
  reconstruction. Skipped and lossless blocks retain their filter syntax;
  transform-type probabilities use the selected filter's normative direction.
- Verified 2,520 original-C predictor cases (601,920 native samples), plus
  seventeen complete dual-dav1d streams covering every mode, nonzero AC,
  transform-size selection, sub-eight-pixel ownership and cropped edges.

- Added native-depth frame deblocking before CDEF, including cross-tile edges,
  per-plane transform-size maps, full four-sample lanes at cropped edges and
  the 4/6/8/14-tap scalar kernels. Transform maps are allocated only when an
  effective loop-filter level is nonzero.
- Parsed all four loop-filter levels, sharpness and signed reference/mode delta
  updates, with intra-specific strength and plane gates. Raw AV1, AVIF, alpha
  and isolated/grouped tile entry points propagate the parsed configuration.
- Verified 1,776 scalar edges and 512 threshold combinations against original
  libaom C. Eighteen dual-dav1d frame cases cover all depths, color/mono,
  CDEF composition, seams, crops and signed updates; varying mode deltas alone
  leaves intra output unchanged. Eleven cases preserve complete original
  libaom streams, while seven explicitly reconstruct only filter headers.

- Added all eight directional intra predictors, independent Y/UV angle deltas,
  integer interpolation, edge filtering and edge upsampling at 8/10/12 bits.
  The sequence's edge-filter flag now reaches every raw AV1/AVIF/tile entry.
- Preserved terminal partition context for top-right/bottom-left availability,
  including VERT_A/B, sub-eight-pixel chroma owners, tile boundaries and the
  64-pixel processing units inside 128-pixel blocks. Smooth-neighbor context
  uses each plane's coding modes rather than the current transform's mode.
- Checked the directional kernel against 672 original libaom C cases and
  complete tile decoding against 20 dual-dav1d references. Constructed cases
  prove visible effects of mixed partitions and independent Y/UV smooth context.

- Added CfL chroma prediction with shared adaptive sign/alpha probabilities,
  full reconstructed luma TX storage in Q3, sub-eight-pixel ownership, padded
  chroma footprints, signed rounding and prediction clipping before residuals.
  Seventeen original libaom cases and seven constructed cases compare
  complete native YUV and OBU/AVIF RGBA output at 8/10/12 bits.
- Corrected HEIF grid payload syntax, primary-item selection, sized dimg
  references and iloc/idat bounds. Automatic AVIF decoding now handles grids
  with validated tile properties, chroma alignment, equal cells and crop bounds.
  Fifteen actual libavif-decoded grids cover color/mono, all three depths,
  ordered distinct tiles, wide fields and idat storage; malformed graph and
  geometry regressions also exercise the public decode entry points.
- Assembled grids in native Y/UV precision and enabled grid alpha auxiliaries,
  including mixed av01/grid pairs. Grid metadata inherits validated cell
  configuration, and alpha is normalized once after native plane composition.
  Five actual libavif references cover three depths and both mixed layouts.
- Added eight deterministic lossy small-rectangle streams with independently
  decoded AC pixels in all four 4-axis rectangular transform geometries.

- Added 4x4, 4x8, 8x4, 4x16 and 16x4 coding blocks, including normative
  sub-eight-pixel chroma ownership, mode syntax and transform traversal.
- Added eight original libaom small-block cases and eight constructed lossless
  rectangle conformance streams, verified by dav1d CLI and FFmpeg before
  comparing native planes and public AV1/AVIF output on all three targets.
- Bound alpha selection to the primary item's auxl relationship and standard
  auxC alpha type. Selected malformed alpha now fails composition; shape and
  bit depth must match. Actual 8/10/12-bit paired AVIF files cover the binding.
- Corrected iloc version-one counts and construction methods, ipma item-ID and
  association widths, zero property indices and representable extent bounds.
  Valid idat/wide-ID variants match libavif; overflowing extents are rejected.

- Added 64x128, 128x64 and 128x128 coding blocks. Residuals follow the
  normative 64x64-chunk then plane order while retaining complete coding-plane
  skip contexts, native samples and shared coefficient state.
- Capped large-block transforms at Y64/UV32 and preserved real SELECT depths
  and lossless 4x4 traversal. Palette syntax is omitted on 128-axis blocks.
- Added 19 original libaom/dav1d large-block cases: color/mono at 8/10/12 bits,
  actual SELECT depths one and two, horizontal/vertical rectangles, cropped
  frame edges and source-exact lossless planes. All native samples and public
  AV1/AVIF pixels are compared, with scalar libavif references for mono RGB.

- Shared the native-depth intra traversal and CDEF path with monochrome images
  and auxiliary alpha, including AC, lossless WHT, multiple tiles and supported
  predictors. Removed the old size-limited single-DC alpha probes.
- Added nine original monochrome libaom/dav1d cases and three real-item alpha
  containers. Native Y is compared before conversion; grayscale and alpha use
  actual scalar libavif references, including full-depth lossless ramps.
- Converted high-bit-depth alpha with rounded UNORM scaling, preserving small
  coverage values and both endpoints. Monochrome RGB also respects full and
  limited sample ranges.
- Required AVIF configuration bit depth and monochrome flags to agree with the
  AV1 sequence header before accepting the stage input.
- Routed CLI AVIF conversion through alpha composition. Native AVIF-to-PNG
  checks at 8/10/12 bits preserve every alpha sample and the primary RGB pixels.

- Replaced speculative single-block tile probes with a shared MSAC traversal
  that decodes modes and residuals in partition order across superblocks.
  Supported coding blocks span 8..128 pixels per axis, including rectangles.
- Integrated intra transform-depth selection, including 8x8 signalling,
  16x16 depth-two transforms, rectangular splitting and neighbour updates.
- Added tile decoding for V/H with zero angle delta, SMOOTH, SMOOTH_V/H and
  PAETH, with complete adaptive Y/UV mode rows and mode-derived transforms.
- Added 45 libaom/dav1d reference cases with exact coded-depth YUV comparisons
  and public RGBA comparisons, including real tx_mode_select bitstreams.
- Corrected ADST/FLIPADST axis dispatch, identity axes, rectangular transform
  normalization and wide multiplication for high-bit-depth ADST4/identity.
- Removed the obsolete eight-byte high-bit-depth residual limit. Real
  8/10/12-bit luma cosine, two-dimensional gradient and mixed-YUV AC fixtures
  now exercise the shared coefficient decoder against full dav1d references.
- Routed zero-quantizer intra blocks through per-4x4 coefficient decoding,
  lossless inverse WHT and sequential prediction. Corrected historical
  lossless pixel expectations using independently decoded planar samples.
- Corrected partition geometry and syntax order. Geometry APIs now return
  rectangular Av1SbBlock leaves with width/height instead of square size;
  only SPLIT recurses, and the internal tile walker invokes each block's
  decoder before reading later partition symbols. Standalone partition
  probes remain separate from the complete tile syntax.
- Corrected the standalone CDEF kernel's direction offsets, damping, signed
  rounding, clipping and 4:2:0 chroma grid. Its 8/10/12-bit output is checked
  against 58,632 libaom reference samples.
- Integrated frame CDEF parameters, per-64x64 entropy indices, direction and
  variance search, and native-depth strength adjustment. Complete padded YUV
  planes are assembled before filtering across tile edges and converting to RGB.
- Added eight original CDEF-on libaom/dav1d cases at 8/10/12 bits, with exact
  YUV, raw OBU RGBA and remuxed AVIF RGBA comparisons. Same-stream CDEF-disabled
  references confirm actual filter changes, including both tile seam directions
  and an odd-sized frame.
- Corrected monochrome quantizer and restoration field counts, preserving
  frame-header alignment and independently verified zero-CDEF alpha streams.
- Corrected frame-OBU alignment and little-endian multi-byte tile lengths.
  Added nine unmodified libaom/dav1d fixtures covering 2x1, 1x2 and 2x2 tile
  grids at 8/10/12-bit, with every decoded pixel compared.
- Corrected variable-transform CDF selection, retained adaptation across
  trees, recorded sibling transform dimensions and rejected excessive entropy
  padding. The isolated tree API is not a complete inter-frame tile decoder.
- Corrected rectangular coefficient size/position contexts, 1D coefficient
  neighbours, U/V probability sharing and rectangular residual state extents.
- Added uniform multi-tile reduced-still frame-header parsing, checked tile
  size-prefix extraction, and bounded raster stitching for supported intra
  tiles. Multi-tile inputs now avoid feeding group prefixes into tile entropy.
- Preserved non-uniform tile superblock boundaries through the public stage-one
  metadata and routed supported bounded tile images by their explicit origins.
- Added AV1 partition CDF/MSAC decoding for NONE, HORZ, VERT, SPLIT and
  extended geometry symbols, with recursive raster leaf output and W8–W128
  neighbour contexts.
- Added bounded `show_existing_frame` envelope parsing with timing/frame-ID
  fields and explicit eight-slot reference-state validation; reference pixel
  storage and inter prediction remain separate stages.
- Added an eight-slot copy-on-store reference image state and a safe
  show-existing resolver for decoded RGBA frames.
- Extended the bounded tx-mode coefficient path to AV1 64x32/32x64
  rectangular leaves, including adjusted 32x32 coefficient storage, correct
  transform-size contexts, scan ordering, and 4:2:0 typed reconstruction.
- Primary AVIF stage input now remains decodable when the container carries a
  validated auxiliary alpha item; `avif_decode_rgba()` can reach its automatic
  alpha composition path without weakening auxiliary-item validation.
- Added a pure MoonBit single-tile AV1 path for 64x64 reduced-still, 8-bit
  4:2:0 frames with DC intra prediction, square DCT_DCT coefficient decoding,
  and luma/chroma residual reconstruction. The path is validated against
  external libaom/dav1d flat and non-constant fixtures and emits RGBA.
- Added bounded SPLIT four-child tile decoding, 8–12-bit quantization-aware
  reconstruction, monochrome alpha SPLIT decoding, and safe rejection of
  unsupported complex high-bit-depth residual streams.
- Added pure MoonBit grid tile extraction/composition and animation sample
  extraction, decoding, and timestamp-based frame selection APIs.
- Wired the normative integer inverse-DCT path into the bounded single-DC
  reconstruction and accepted 128x128-superblock 64x64 frames.
- Added `avif_stage1_input()` for validated AVIF-to-tile handoff; general block
  partitioning and inter-frame syntax remain staged work while bounded alpha
  and high-bit-depth reconstruction are available.
- Added an explicit 8-bit full-range YUV420→RGBA conversion path and threaded
  the sequence `color_range` flag through the bounded decoder.
- Added 32x32 single-tile neutral DC reconstruction with the W32 and chroma
  transform contexts.
- Enabled native CLI AVIF input through the bounded pure MoonBit decoder.
- Added a normative integer AV1 inverse-transform module for DCT and lossless
  4x4 WHT paths, plus reproducible libaom/dav1d AV1 and AVIF reference fixtures.
- Added single-DC chroma residual decoding for the bounded AV1 tile path.
- Added bounded pure MoonBit validation and reconstruction for AVIF auxiliary
  alpha items (`auxl`/`auxC`) and their `iloc` extents.
- Added pure MoonBit monochrome 8-bit alpha tile decoding and four-block plane
  reconstruction helpers for the next AV1 partition stage.
- Added validated 10-bit reduced-still frame-envelope parsing; high-bit-depth
  coefficient entropy and pixel reconstruction remain the next stage.

## 0.18.0 (2026-09-09)

- Added a bounded AVIF ISO BMFF primary-item parser with `ftyp`/`meta`,
  `pitm`, `iinf`/`infe`, `iloc`, `iprp`/`ipco`/`ipma`, `ispe`, `av1C`, `nclx`,
  and `mdat`/`idat` validation.
- Added pure MoonBit AV1 OBU framing, reduced-still sequence-header parsing,
  frame-envelope checks, and a bounded MSAC boolean foundation.
- The 0.18.0 release stopped before AV1 tile entropy decoding; the unreleased
  follow-up now covers only the bounded single-tile DC path.

## 0.17.7 (2026-09-09)

- Added complete pure MoonBit VP8L transform decoding for Predictor,
  cross-color, Subtract Green, and Color Indexing streams, including transform
  subimages, spatially varying Huffman groups, and the full close-distance map.
- Added native and JS regression fixtures for predictor/cross-color and color
  indexing WebP files.

## 0.17.6 (2026-09-09)

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
- Added TIFF zlib/Deflate decompression and Predictor=2 horizontal differencing
  for classic strips and tiles, with cross-target regression fixtures.
- Added pure MoonBit VP8L WebP Lossless decoding for the encoder's subtract-
  green and color-cache streams, with native CLI input support.

## 0.17.5

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
