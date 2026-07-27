# Changelog

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
