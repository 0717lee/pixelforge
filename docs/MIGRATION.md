# 0.18.0 → 0.19.0

## 简体中文

使用 `moon add 0717lee/pixelforge@0.19.0` 显式升级依赖。`0.18.0` 保留原有包内容和历史文档；GitHub 的历史 `v1.0.0` 与本次版本号无关。

### 移除的接口

已发布 `0.18.0` 中的 `av1_decode`、`av1_frame_info`、`av1_msac_read_first`、`av1_sequence_info`、`avif_container_parse`，以及 `Av1FrameInfo`、`Av1SequenceInfo`、`AvifContainer` 不再导出。之后开发快照中增加的 AV1 状态、AVIF 像素/网格/动画接口也不保留。

| 原用途 | 0.19.0 接入方式 |
| --- | --- |
| 判断 AVIF 格式 | `detect_image_format(bytes)`，匹配 `Some(Avif)` |
| 读取支持的主图尺寸 | `image_metadata(bytes)`，显式处理 `None`；不读取完整容器或 AV1 状态 |
| 浏览器显示与编辑 AVIF | 由浏览器原生解码，再把 Canvas RGBA 缓冲交给 `Image::from_bytes`；浏览器不支持时报告失败 |
| native AVIF 像素转换 | 本库不再提供；由宿主选择并接入独立解码器，然后传入 RGBA8 |
| AVIF 编码 | 保留 `avif_encode` 的 JS 宿主适配；不透明图像及编码环境要求见 README 格式表 |

图像处理、PNG/GIF/QOI/BMP、JPEG 适配、WebP Lossless 与 TIFF 的公开签名保持不变。新版本修复最近邻缩放整数溢出；三种缩放对合法空图输出目标尺寸的透明像素。目标边长小于 1 时仍钳制为 1。BigTIFF 探测、metadata 和 native CLI 与已有解码子集贯通。

自定义 WASM 宿主应复用输入缓冲区；输入长度改变时更换实例以释放旧分配。仓库的 `web/wasm-pipeline.js` 同时供主线程和 Worker 使用。升级源码时一并重建 Web 产物。

## English

Upgrade explicitly with `moon add 0717lee/pixelforge@0.19.0`. The `0.18.0` package and its historical documentation remain available. The historical GitHub `v1.0.0` marker is unrelated to this version.

### Removed APIs

The published `0.18.0` APIs `av1_decode`, `av1_frame_info`, `av1_msac_read_first`, `av1_sequence_info`, `avif_container_parse`, and the types `Av1FrameInfo`, `Av1SequenceInfo`, `AvifContainer` are no longer exported. AV1 state and AVIF pixel/grid/animation APIs from later development snapshots are also removed.

| Previous use | Integration in 0.19.0 |
| --- | --- |
| Identify AVIF | Match `Some(Avif)` from `detect_image_format(bytes)` |
| Read supported primary-image dimensions | Call `image_metadata(bytes)` and handle `None`; this does not parse the full container or AV1 state |
| Display/edit AVIF in a browser | Decode through the browser, then wrap Canvas RGBA bytes with `Image::from_bytes`; report unsupported-browser failures |
| Convert AVIF pixels on native | Choose and integrate an independent host decoder, then supply RGBA8 to PixelForge |
| Encode AVIF | `avif_encode` remains a JS host adapter; see the README format table for opaque-image and encoder requirements |

Public signatures for image processing, PNG/GIF/QOI/BMP, JPEG adapters, WebP Lossless and TIFF are unchanged. Nearest resize no longer overflows its sample-position arithmetic. All three resizers produce transparent pixels at the requested size for valid empty sources; target dimensions below 1 still clamp to 1. BigTIFF detection, metadata and native CLI now reach the existing decoder subset.

Custom WASM hosts should reuse their input buffer and replace the instance when its length changes. The repository's `web/wasm-pipeline.js` is shared by the main thread and Worker. Rebuild Web artifacts when updating source.
