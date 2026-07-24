# PixelForge

> 一个纯 [MoonBit](https://www.moonbitlang.cn/) 实现的图像处理库，附带一个在浏览器里实时运行的 Playground。
> 后端无关的核心库可编译到 **JavaScript / WebAssembly (wasm-gc & 线性内存 wasm) / native**。

![PixelForge 浏览器 Playground](assets/playground-original.png)

*同一界面一键切换 13 种滤镜与 JS / WebAssembly 双引擎——以 Sobel 边缘检测为例：*

![Sobel 边缘检测](assets/playground-sobel.png)

---

## ✨ 特性

- **13 种滤镜**：灰度、反色、亮度、对比度、高斯/盒式模糊、锐化、浮雕、拉普拉斯边缘、Sobel 边缘、棕褐色、二值化、像素化、中值降噪、直方图均衡。
- **通用卷积引擎**：`Kernel` + `Image::convolve`，可自定义任意奇数尺寸卷积核。
- **纯整数、确定性**：滤镜数学尽量用整数（如亮度权重 ×1000），结果可复现、**25 个单元测试全部手算验证**。
- **零依赖**：只用 `moonbitlang/core`，不引入任何第三方库。
- **多后端 + 零拷贝互操作**：js 后端下 `FixedArray[Byte]` 就是 `Uint8Array`，与 canvas 的 `Uint8ClampedArray` 零拷贝互通；线性内存 wasm 后端导出 `memory`，宿主直接批量读写像素。
- **浏览器 Playground**：拖拽 / 粘贴 / 上传图片，实时滤镜，JS/WASM 引擎切换与性能对比。

## 📦 项目结构

```
pixelforge/
├── image.mbt              # Image 数据结构、像素读写、clamp_byte
├── filters_basic.mbt      # map_rgb 引擎 + 灰度/反色/亮度/对比度
├── convolution.mbt        # Kernel + convolve + 模糊/锐化/浮雕/边缘/Sobel
├── filters_advanced.mbt   # 棕褐色/二值化/像素化/中值/直方图均衡
├── dispatch.mbt           # Image::apply_filter_id 统一派发（各绑定共用）
├── *_test.mbt             # 25 个确定性测试（黑盒 + 白盒）
├── cmd/main/              # 原生 CLI 示例（moon run cmd/main）
├── web/                   # 浏览器绑定 + Playground（HTML/CSS/JS）
│   ├── bindings.mbt       #   js 后端绑定 apply_filter（零拷贝）
│   ├── dist/web.js        #   已构建的 MoonBit→JS 产物
│   ├── dist/wasmcore.wasm #   已构建的线性内存 wasm 产物
│   └── index.html / playground.js / style.css
├── wasmcore/              # 线性内存 wasm 绑定（alloc/process + 导出 memory）
└── serve.mjs              # 零依赖静态服务器
```

## 🚀 快速开始

先安装 [MoonBit 工具链](https://www.moonbitlang.cn/download/)。

```bash
moon test              # 运行 25 个单元测试
moon run cmd/main      # 运行原生示例（生成图像并跑滤镜，打印校验和）
```

启动浏览器 Playground（`web/dist/` 中已包含构建好的产物）：

```bash
node serve.mjs         # 然后打开 http://localhost:8123
```

如需从源码重新构建 Web 产物：

```bash
moon build --release --target js     # 生成 _build/js/release/build/web/web.js
moon build --release --target wasm   # 生成 _build/wasm/release/build/wasmcore/wasmcore.wasm
# 将上述两个产物复制到 web/dist/ 下（web.js、wasmcore.wasm）
```

## 🧑‍💻 库用法

```moonbit
// 从 RGBA 字节缓冲区（w*h*4）构造图像
let img = @pixelforge.Image::from_bytes(width, height, rgba_bytes)

// 链式调用滤镜（每个滤镜返回一张新图，不修改原图）
let stylized = img.grayscale().sobel()
let soft = img.blur().brightness(20)

// 自定义卷积核
let kernel = @pixelforge.Kernel::new(3, [0.0, -1.0, 0.0, -1.0, 5.0, -1.0, 0.0, -1.0, 0.0], 1.0, 0.0)
let sharp = img.convolve(kernel)

// 按数字 id 派发（供各宿主绑定 / CLI 共用）
let out = img.apply_filter_id(8, 0.0) // 8 = Sobel

// 取回处理后的像素
let bytes = out.data // FixedArray[Byte]，长度 = width*height*4
```

## 🎛️ 滤镜清单

| id | 滤镜 | 方法 | `amount` |
| --- | --- | --- | --- |
| 0 | 灰度 | `grayscale()` | — |
| 1 | 反色 | `invert()` | — |
| 2 | 亮度 | `brightness(delta)` | −255..255 |
| 3 | 对比度 | `contrast(factor)` | 0.0..3.0 |
| 4 | 高斯模糊 | `blur()` | — |
| 5 | 锐化 | `sharpen()` | — |
| 6 | 浮雕 | `emboss()` | — |
| 7 | 拉普拉斯边缘 | `edges()` | — |
| 8 | Sobel 边缘 | `sobel()` | — |
| 9 | 棕褐色 | `sepia()` | — |
| 10 | 二值化 | `threshold(level)` | 阈值（默认 128） |
| 11 | 像素化 | `pixelate(block)` | 块大小（默认 8） |
| 12 | 中值降噪 | `median()` | — |
| 13 | 直方图均衡 | `histogram_equalize()` | — |

## 🏗️ 架构与多后端

核心库完全后端无关。两个宿主绑定包分别演示两种进出 MoonBit 的方式：

- **`web/`（js 后端）**：MoonBit 的 `FixedArray[Byte]` 编译为 JS `Uint8Array`，因此 canvas 的 `ImageData.data`（`Uint8ClampedArray`）可以**零拷贝**直接传入 `apply_filter`。
- **`wasmcore/`（线性内存 wasm 后端）**：链接时用 `export-memory-name` 导出线性 `memory`；`alloc(len)` 返回的指针**直接指向数据**（实测零 header 偏移），宿主用 `Uint8Array` 视图批量写入像素后调用 `process`。

> **一个诚实的性能观察**：在浏览器里对同一套滤镜做基准对比，MoonBit 的 **js 后端反而比线性内存 wasm 快约 4–5×**。原因是 V8 对 JS 后端产物做了深度 JIT 优化，而 wasm 路径还多了进/出线性内存的拷贝与运行时开销。这说明"WASM 一定更快"是一种误解——Playground 保留了引擎切换与对比按钮，你可以自己复现这个结论。

## ✅ 测试

```bash
moon test                 # 默认后端（wasm-gc）
moon test --target js     # js 后端
```

25 个测试覆盖每个滤镜，期望值均为手工推导（脉冲响应、平场不变性、已知边缘、直方图重映射等），在 wasm-gc 与 js 后端下均通过。

## 📮 发布到 mooncakes.io

> 模块名为 `0717lee/pixelforge`。其他 MoonBit 项目可通过 `moon add 0717lee/pixelforge` 添加依赖。

```bash
moon login             # 登录 mooncakes.io
moon publish           # 发布
```

## 📄 许可证

[Apache-2.0](LICENSE)
