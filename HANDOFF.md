# PixelForge 开发交接

更新日期：2026-09-23（第六十一次推进）。适用对象：首次接手本项目的开发者、维护者或代码代理。本文从项目目标、代码基线到验收步骤提供完整入口，不需要先阅读聊天记录或取得原作者的临时文件。除外部链接外，文件路径均相对仓库根目录。

**当前结论（2026-09-23，第六十一次推进）：AVIF/AV1 解码主线仍未完成，但阶段 B 已闭合、阶段 C 的 inter 工具门大部分已闭合，阶段 D 的三帧动画已闭合。** 具体地说：`inter_cdf_inherit_64x64` 已从 `[3992,842,928]` 变为 `[0,0,0]`（生产开关 `av1_cdf_load_enabled` 已开启，OBU 与 dav1d 真值未动，见第 10 节第四十三次推进）；compound（含 distance/difference 加权与 interintra）、skip mode（三帧序列）、OBMC/warped motion 的语法门、屏幕内容/调色板、时间运动矢量和平移型全局运动均已解除且逐样本一致（`inter_compound_64x64`/`inter_distcomp_64x64`/`inter_diffwtd_64x64`/`inter_interintra_64x64`/`inter_skipmode_64x64`/`inter_globalmv_64x64` 等，见第 10 节第五十九至六十一次推进）；三帧动画容器（BMFF + 状态解码 + 时间戳选帧）已由 `avif_grid_animation_test.mbt` 与 `av1_inter_reference_wbtest.mbt` 的两个三帧用例钉住。**仍未闭合的三项**：(1) LOCALWARP 与 ROTZOOM/AFFINE 全局运动，都需要 AV1 §7.11.3.5 的逐像素 warp 预测网格；(2) segmentation 的 `segment_id` 符号与 feature 应用（`segmentation_params` 语法已全量解析，但 libaom 不发分段流，翻 enable 位会让每块读 seg_id 从而导致熵错位，判定成本过高，见第五十九次推进）；(3) 上述门之外的收尾：README/证据/CI 一致性（阶段 E）。现在 native/js/wasm-gc 为 1255/1255 全绿。

以下第 5 段是这一路的历史记录（阶段 B 的收敛过程），保留以便复现诊断方法：

**当前结论：AVIF/AV1 解码主线尚未完成。第 4 节两项交付问题已解决（Web 产物重建、CLI 示例补 `--target native`）；参考帧熵上下文继承的快照/保存/装载机制已落地并被隔离测试验证。第十四次推进取得三项决定性证据（补充四十七）：(1) **生产配置（不继承）下我方对 `inter_cdf_inherit_64x64` 的 inter 帧输出与 dav1d 对未补丁孪生流 `inter_minimal_64x64` 的输出逐样本相同**，围栏值 `[3992,842,928]` 就是 dav1d 自身"开补丁 vs 不开补丁"的纯继承效应而非我方错误，阶段 B 剩余工作严格收敛为"让继承开启的输出等于 dav1d 开补丁的输出"；(2) 继承开启并放开越读守卫后，分歧定位到 **inter 帧第一个 luma 叶（32x32, tx_ctx=3, eob=41）扫描位置 k=31 的 `coeff_base`**（我方 level 2、黄金 level 1），chroma 块 (0,0) 已完全正确；(3) **所有被继承的系数 CDF 行经规范默认值 + 关键帧实际符号序列复算逐位精确**（`base[3][21]`/`base[3][22]`/`base_eob[3][1]`/`eob` 四行全部吻合），行值假设被彻底排除。第四至八次推进把分歧定位到第一块 32x32 luma 变换扫描位置 k=31 的 `coeff_base`（base ctx 22 行）；第九次推进取得 dav1d 源码、建成 MSAC 状态级取证工具、并用独立 Python 模型证明关键帧第一叶在给定状态下与规范逐位一致；第十、十一次推进取得 aomenc/dav1d 1.2.1/FFmpeg 三件套、可逐字节复现 fixture 并建成参数化 bisection 流程；**查明该 fixture 是“用默认 CDF 编码、再补丁开启继承”的流，且 `symbol_max_bits >= -14` 守卫是最小样本的唯一阻塞**（放开后 7 类输入全部 `[0,0,0]`），剩余分歧隔离到关键帧色度（仅周期 3 纹理触发），详见第 10 节。**

## 1. 最终目标

**完成 PixelForge 的纯 MoonBit AVIF/AV1 像素解码主线，交付可以通过公开 API、native CLI 和浏览器集成实际使用的完整实现。native、JavaScript、wasm-gc 的核心解码必须保持一致，解码过程不得依赖浏览器原生 AVIF 解码或宿主编解码后端来补足核心能力。**

目标覆盖静态 AVIF、辅助 alpha、网格图像和包含帧间预测的动画，并补齐这些场景需要的 AV1 语法、熵状态、像素重建与滤波。既有图像格式、滤镜、分析 API 和 Playground 保持可用。最终应交付代码、参考样本、测试、准确的中英文能力说明、可复现的 Web 产物和通过的 CI。

具体完成范围如下；此表定义目标，不表示各项现在均已完成。

| 能力 | 最终要求 |
| --- | --- |
| 原生精度与颜色 | 8/10/12-bit，单色及 4:2:0、4:2:2、4:4:4；保留原生样本进行解码与合成，正确处理声明的颜色与范围信息 |
| 帧内重建 | 通用合法分区、多块、多 superblock、多 tile，完整 DC/AC 系数熵解码、整数逆变换、Y/U/V 残差和各类帧内预测 |
| 量化与滤波 | 相关 segmentation、量化及 delta 语法；去块、CDEF、superres、Wiener/SGR 恢复滤波及其顺序和边界正确；处理适用的 film grain |
| 帧间重建 | 通用帧头、参考帧管理、CDF 保存/恢复、运动矢量与候选堆栈、参考缩放、亚像素插值、帧间残差和滤波；补齐 compound、warped、temporal MV、skip、全局运动等仍被拒绝的工具及合法组合 |
| 特殊编码路径 | 正确处理适用的 intrabc、屏幕内容、无损、show-existing-frame 和参考状态更新，不遗留会使目标内合法码流错误重建的语法门 |
| AVIF 容器与合成 | 主图项、辅助 alpha、grid 及其组合能从实际容器自动解码；尺寸、色度对齐、色彩信息和透明度合成正确 |
| 动画 | 按序解码真实关键帧和帧间帧，维护跨帧状态，正确返回帧像素、帧次序、时间戳和时长；包含三帧以上序列的证据 |
| 使用与交付 | 公开入口、CLI、Web/worker 路径可用；源码、生成产物、测试和文档一致；外部参考证据能由接手者复现 |

### 最终验收标准

以下条件全部满足，才能把主线标记为完成：

1. 上表能力已接入实际解码路径，有对应的公开入口和可观察结果；辅助函数、头信息解析或单一简化样本不足以证明能力完成。
2. 原生 Y/U/V 与 alpha 样本对独立解码器逐样本一致；覆盖高位深非中性值、AC、边界、tile 接缝、跨帧状态及主要工具组合。RGBA 按明确的色彩转换/色度上采样约定验证，不能把不同转换策略的输出冒称逐字节一致。
3. 已知错误样本归零。尤其 `inter_cdf_inherit_64x64` 必须从 `[3992, 842, 928]` 变为 `[0, 0, 0]`，保留原 OBU 和独立像素真值；不得删样本、排除错误区域或将错误数量当作最终成功断言。
4. native、JS、wasm-gc 的适用测试通过，Web 产物复现检查、WASM 集成、CLI 冒烟以及 CI 通过。异常和资源限制行为明确，不能把合法但尚未实现的工具无声解码为错误画面。
5. 各能力的样本来源、工具版本、命令、预期结果和实际覆盖范围已记录；README、接口和版本说明与实际行为一致，接手者取得同一代码版本即可重跑验收。

本目标的范围是完整解码主线。修复单个 CDF 问题、完成一个阶段或获得全绿单测后，仍须按本表检查后续阶段。

## 2. 取得正确的代码版本

项目仓库：[0717lee/pixelforge](https://github.com/0717lee/pixelforge)。MoonBit 包名 `0717lee/pixelforge`，当前源码的 [moon.mod](moon.mod) 版本为 `0.18.0`；版本号本身不代表上述目标已验收。

本交接依据的本地分支为 `main`，基线提交为：

```text
eee85ffd9e2af2c9ee32d88bd62d327d6e5de16a
```

2026-09-20 只读查询到远端 `main` 为 `0694838eb10ba7d2844f62bc774e0fdd417e1f8d`，本地基线超前 266 个提交。因此，**仅克隆该次查询时的远端 main 无法取得本交接的完整代码**。交付方必须同时提供含上述基线的分支、Git bundle 或完整仓库副本，并移交需要保留的未提交差异。接收方核对：

```sh
git rev-parse HEAD
git status --short
git log -5 --oneline
```

收到完整工作树时不要用 reset/checkout 覆盖其未提交工作。本文件可随仓库一起传递；不要求接收方拥有原开发者的个人目录、代理技能包或对话历史。

### 本地差异快照

下面是添加本交接文件及 README 导航之前的审查快照，后续以 `git status` 为准：80 个已跟踪文件存在未提交差异，78 修改、2 删除，暂存区为空。

| 类别 | 数量 | 2026-09-20 审查结果 |
| --- | ---: | --- |
| MoonBit 源码与测试 | 72 | HEAD 与工作区分别经同版 `moonfmt -` 规范化，72/72 输出一致；没有剩余逻辑差异 |
| 生成接口 `.mbti` | 4 | 仅末尾空行变化，接口未改变 |
| `moon.mod` | 1 | 原有 import 段前移，依赖版本不变 |
| `cmd/cli/moon.pkg` | 1 | 新增 `supported_targets = "native"`，属于目标范围变化 |
| `web/dist` | 2 | 删除 `web.js`、`wasmcore.wasm`，导致下述交付阻塞 |

不要根据大型数组格式化产生的 diff 行数估算新增功能。当前工作树中的格式化与已提交主线功能是两件事。

**（2026-09-21 第十二次推进后的快照）**：`git status` 为 **20 个已跟踪文件修改 + 2 个未跟踪**（`HANDOFF.md`、[av1_frame_cdfs.mbt](av1_frame_cdfs.mbt)），暂存区为空。第十二次推进按 AGENTS.md 跑了 `moon info && moon fmt`：`moon info` 未改变任何 `.mbti`；`moon fmt` 把 9 个本就已修改的 `.mbt`（`av1_alpha_decode` / `av1_frame_map` / `av1_frame_planes` / `av1_inter_mode` / `av1_inter_tile` / `av1_intra_tile` / `av1_mc_oracle_wbtest` / `av1_tile_decode` / `webp_transform_test`）连同之前未格式化的约 70 个无关文件一起重排，无关文件的格式化已用 `git checkout --` 全部回退，上述 9 个文件保留了格式化结果（语义不变，`git diff -w` 与格式化前一致）。本轮另修复了 [av1_msac.mbt](av1_msac.mbt) 与 [av1_coeff_decode.mbt](av1_coeff_decode.mbt) 的 CRLF 行尾残留（HEAD 为 LF）并移除两处上次遗留的死插桩（`av1_msac_trace`/`av1_msac_trace_on`、`av1_coeff_dump`/`av1_coeff_dump_on`），这两个文件现已与 HEAD 无差异。

## 3. 环境与可直接运行的检查

命令均从仓库根目录执行，适用于安装好工具的 Windows、Linux 或 macOS。正常检查不需要重新编码 fixture，也不依赖私有临时文件。

| 工具 | 用途与要求 |
| --- | --- |
| Git | 取得和核对完整代码、样本与变更 |
| MoonBit | 安装 [.github/workflows/ci.yml](.github/workflows/ci.yml) 中 `MOONBIT_VERSION` 固定的编译器，目前为 `0.10.11+6ff76a5f9`；对应本次实测 Moon CLI 为 `0.1.20260827` |
| Node.js | JS 测试、Web 构建和 WASM 验证；本次实测为 `v24.12.0` |
| 平台 C 编译工具链 | MoonBit native 编译；按 MoonBit 对本平台的要求安装 |
| Python、aomenc、dav1d、FFmpeg | 仅在重新生成/核验外部参考样本时需要，见第 8 节 |

已有完整代码后运行：

```sh
moon version --all
node --version
moon update
moon check
moon test --target wasm-gc
moon test --target js
moon test --target native
node scripts/build-web.mjs --check
node verify-wasm.mjs
moon run --target native cmd/cli -- --help
git diff --check
```

`moon update` 解析 [moon.mod](moon.mod) 中的注册表依赖。安装步骤和编译器版本以 CI 为准；[CONTRIBUTING.md](CONTRIBUTING.md) 中较旧的 CLI 日期不能替代编译器版本。

要修复当前缺失/过期 Web 产物，额外执行下面的**生成操作**，检查并保留生成文件，再重复校验：

```sh
node scripts/build-web.mjs
node scripts/build-web.mjs --check
node verify-wasm.mjs
```

## 4. 最近一次实测结果与阻塞

以下结果来自 2026-09-20、上述基线及差异快照。它们不是任意后续 checkout 的保证，接手后应重跑第 3 节。

| 检查 | 结果 |
| --- | --- |
| `moon check` | 通过，64 warnings / 0 errors；存在既有未使用表与辅助函数警告 |
| JS / wasm-gc / native 全量测试 | 各 **1255/1255** 通过（2026-09-23 第六十一次推进后） |
| Web 产物复现检查 | ~~失败~~ **已解决（2026-09-20 二次接手）**：重建后 `--check` 两个文件均 OK |
| WASM 集成验证 | ~~失败~~ **已解决**：`node verify-wasm.mjs` 全部 PASS |
| 默认目标 CLI help | 失败：默认 wasm-gc 不受当前 CLI 支持（native-only 定位，见 P2） |
| 明确 `--target native` 的 CLI help | 通过 |
| `git diff --check` | 通过 |

**P1：恢复 Web 产物。** ~~[web/playground.js](web/playground.js) 与 [web/worker.js](web/worker.js) 仍导入 `dist/web.js`、加载 `dist/wasmcore.wasm`；[构建校验](scripts/build-web.mjs) 和 [WASM 验证](verify-wasm.mjs) 也需要它们。按第 3 节生成并核验。~~ **已完成**：按第 3 节重建并通过两项校验（见第 10 节）。

**P2：同步 CLI 目标与示例。** ~~[cmd/cli/moon.pkg](cmd/cli/moon.pkg) 已限制 native，但 [CLI README](cmd/cli/README.md) 的 hex 示例仍省略目标参数。~~ **已完成**：native-only 定位确认（默认目标实测报错），README 的 hex 示例已补 `--target native`，CLI 文件模式冒烟通过。若今后恢复跨目标 hex 能力，应同时实现并验证对应目标。

## 5. 主线已完成到哪里

现有代码和参考样本已覆盖高位深帧内重建、方向预测、filter-intra、调色板、去块、CDEF、superres、Wiener/SGR、alpha/grid 以及部分动画路径。通用帧头、八槽参考帧、亚像素运动补偿和受限单参考 inter 也已有实现。完整差异与来源分别见 [CHANGELOG](CHANGELOG.md) 和 [fixture 目录](tests/fixtures)。不能用已有样本推断所有合法工具组合均已完成。

inter fixture 的预期定义分两处：生成器输出的八个在
[scripts/emit-av1-inter-test.py](scripts/emit-av1-inter-test.py) 的 `SPECS`，其余由
[scripts/generate-av1-inter-reference.py](scripts/generate-av1-inter-reference.py)
生成并在 [av1_inter_reference_wbtest.mbt](av1_inter_reference_wbtest.mbt) 末尾手工维护
（另有若干独立生成器脚本：lossless/obmc/screen/palette/warped/temporalmv）。

| 状态 | 样本 |
| --- | --- |
| inter 帧原生样本精确 | `inter_minimal_64x64`、`inter_still_64x64`、`inter_shift_64x64`、`inter_edge_64x16`、`inter_lf_delta_64x64`、`inter_primary_ref_64x64`、`inter_cdf_inherit_64x64`（`[0,0,0]`）、`inter_lossless_64x64`、`inter_obmc_64x64`、`inter_screen_content_64x64`、`inter_palette_64x64`、`inter_warped_64x64`、`inter_temporalmv_64x64` |
| inter 工具门已闭合且逐样本精确 | `inter_compound_64x64`、`inter_distcomp_64x64`、`inter_diffwtd_64x64`、`inter_interintra_64x64`、`inter_globalmv_64x64`（平移型全局运动） |
| 三帧序列 | `inter_skipmode_64x64`：三个时间单元逐一精确，第三帧靠 skip mode 同时引用前两帧 |
| 所有开关全开的 general 码流 | `general_inter_64x64`：compound / overlapped / warped motion / temporal MV 全部实现，逐样本精确 |
| 仍拒绝的组合 | 仓库内没有 fixture 选中 LOCALWARP、ROTZOOM/AFFINE 全局运动或启用的 segmentation feature；一旦选中，`av1_read_motion_mode` 或帧门会整帧拒绝 |

2026-09-22 第四十三次推进后，八个 inter 样本全部达到像素精确（含 `inter_cdf_inherit_64x64`），`av1_cdf_load_enabled` 已启用并被该样本的 `[0,0,0]` 围栏钉住；全绿测试自此等价于阶段 B 的 inter 验收。根因与复现方法见第 10 节第四十三次推进（含插桩 dav1d 的构建与使用）。

第九次推进（2026-09-21）后的定位：该样本的第一个分歧符号是 inter 帧第一块 32x32 luma 变换扫描位置 k=31（坐标 (3,4)）的 `coeff_base`（base ctx 22 行），我们解出 level 2、dav1d 黄金为 1（k=32 的 level 2 双方一致）。关键帧第一叶已被独立 Python 模型证明在给定状态下与规范逐位一致，因此剩余根因在该叶之前 7 个符号的 CDF 行/上下文选择；具体入口见第 10 节第九次推进。

第十次推进（2026-09-21）**修正了对该样本性质的理解**：它是 `inter_minimal_64x64` 的帧头补丁——`primary_ref_frame` 由 7（PRIMARY_REF_NONE）改为 0，而 bitstream 的 inter 帧符号是 libaom **用默认 CDF 编的**。dav1d 1.2.1 解同一条流时开/不开补丁的第 1 帧相差 3996/6144 个样本（全在 luma），证明“继承解码”在这条流上本来就会解出另一张图。因此本样本的验收含义是**逐符号复现 dav1d 的继承解码**。第十次推进还把失败隔离到一个 49 字节最小样本（全平两帧），并证实：关键帧全平 + inter 帧带图案时继承开启仍能 `[0,0,0]` 精确——**继承机制本身工作正常**。详见第 10 节第十次推进。

第十一次推进（2026-09-21）**把阻塞项收敛为一个具体守卫**：在参数化 bisection 流程（同一 `MINIMAL_FLAGS` + 同一补丁，golden 取 dav1d 对开补丁码流的解码）下，放开 `symbol_max_bits >= -14` 后 7 类输入全部 `[0,0,0]`（全平同图、全平+图案、`shift`、平滑 luma+纹理色度、纹理 luma+平滑色度、周期 2/4/5/6/7 色度），**只剩周期 3 色度纹理与仓库 `ramp` 两个样本失败**（分别 `[0,504,0]` 与 `[4029,464,708]`）。失败样本的 inter 帧 tile payload 分别只有 23 与 11 字节，继承解码越读到 `max_bits ≈ -122` 与 `-1046`，因此该守卫是闭合阶段 B 必须先处理的前置项（它来自规范 §8.2 `exit_symbol` 的位流一致性要求，dav1d 不执行；放开会影响 3 个依赖它拒绝截断输入的既有测试，需用符号数上界等不变量替代）。周期 3 样本的符号级取证已把分歧定位到 **inter 帧块2 的 U 平面 txb_skip 读**（我们解出 0=有色度残差，dav1d 解出 1=跳过；dav1d 开补丁输出的 U/V 与关键帧完全相同可证），且所用 CDF 行值已逐步手算验证正确，故根因是**关键帧色度系数段存在不改变像素的符号差异**（周期 3 纹理每块约 276 个 base 符号）。详见第 10 节第十一次推进。

第十二次推进（2026-09-21）**排除了三类根因并把分歧收敛到一个具体变换叶**：用 Python 逐字移植 dav1d 1.2.1 的 `msac.c` 与 [av1_msac.mbt](av1_msac.mbt) 对拍 **1600 万个符号零分歧**（含深度越读补位），并证明适配速率公式 `3+(count>15)+(count>31)+min(floor(log2 n),2)` 与 dav1d 的 `4+(count>>4)+(n_symbols>2)` 完全等价（按字面代入 dav1d 公式会让 253 个测试失败、关键帧也从 `[0,0,0]` 变 `[3035,733,723]`，已回退）——算术、补位、适配速率都不是根因。同时清除了上次遗留的 CRLF 行尾与两处死插桩，`git diff --check` 恢复通过。周期 3 样本在"守卫放开 + 继承开启"下的真实结果是 **`[0, 488, 0]`**（Y/V 全对，只有 U 平面错，且从第 16 行起全错）；打开系数级 trace 后确认 inter 帧只有 3 个带残差的叶，其中 **32x16 色度（U）叶（`eob=245`）是整帧最后一个带残差的读**，分歧就在它内部或它之前的状态。所有继承色度 CDF 行（`eob512`/`extra`/`base_eob`/`base`）从默认值到 inter 帧读取时的适配链已用 dav1d 的更新规则逐步手算验证**逐项相等**，关键帧两个色度叶的 `(c,p,ctx)` 序列 248 项完全相同。⇒ 根因是**某个不改变像素的符号读取与 dav1d 不同**（头号嫌疑 `eob` 类符号）。详见第 10 节第十二次推进。

第十三次推进（2026-09-21）**用强制符号实验把分歧点推到色度叶之前**：对色度叶的 `eob512` 读（状态 `r=51012, v=2051`，行 `[6819,…,2]`）强制符号 0..9 各跑一次，U 错误数为 510/507/504/504/507/512/504/505/**488**/479——无一归零且自然值 8 不突出，结合该行链已验证，说明**进入色度叶的 MSAC 状态与 dav1d 不同**（色度叶是 inter 帧最后一个带残差的读，其后只有 V 叶 1 个 `all_zero`）。同时实测色度叶内 `eob512` 读与第一个系数读之间只有 1 个 `extra` 符号 + 6 个 eob 细化 bool（状态已记录在案）。另一收获：inter 帧的 luma 叶 1、2（32x32，eob 55/28）与关键帧对应叶的 `(c,p,ctx,value)` 序列 55 项中 54 项相同、仅 DC 不同（15 vs 11）——这是 CDF 继承的预期效果，证明**继承到的 luma 行是对的**；并用 `signdc` 行计数与 `base[3][22]` 默认值双向确认 luma/色度系数表没有串表。⇒ 根因是 inter 帧 luma/块级符号里一个**不改变像素的读**（头号仍是 4 个 luma 叶的 `eob`）。详见第 10 节第十三次推进。

根 [README](README.md) / [English README](README.en.md) 的 inter 缺口描述和包版本说明落后于代码；接手时以这里列出的源码、生成器预期、实测和最新提交交叉核对，最终同步两份说明。

## 6. 后续实施顺序

| 阶段 | 工作 | 阶段验收 |
| --- | --- | --- |
| A：恢复交付基线 | 处理第 4 节两项问题，保留原有工作，确认共享代码版本完整 | Web/WASM 校验通过，CLI 示例可运行，工作树差异来源清楚（**已完成**，见第 10 节） |
| B：参考帧熵状态 | 实现系数及非系数 CDF 的快照、按引用恢复、tile/frame 更新门及生命周期 | `inter_cdf_inherit` 对原 dav1d 真值变为 `[0,0,0]`，其余六个精确 inter 样本保持精确，所有目标通过（**机制已落地并隔离验证，样本未闭合**，见第 10 节） |
| C：帧间工具与覆盖 | 补齐仍被工具门拒绝的合法路径，扩展 MV、混合块、参考更新及多 tile 证据 | 每个解除的门有真实重建和外部像素核验；不存在只删除拒绝条件而未解码对应语法的情况 |
| D：完整容器与动画集成 | 将完善后的帧间路径接入实际 AVIF 动画、alpha/grid 组合与公开入口；加入三帧以上参考状态变化 | 每帧原生样本/alpha、RGBA 约定、顺序和时间信息均验证，CLI 与 API 可运行 |
| E：最终验收与交付 | 对照第 1 节逐项补证据，同步中英文文档、产物、CI 和交付版本 | 第 1 节所有条件满足，已知错误清零，给出可获取的提交/版本和验证记录 |

阶段内验收通过后继续下一阶段。若出现工具或数据阻塞，记录准确命令、错误、已验证边界及解除条件；不要将阶段完成写成主线完成。

### B 阶段的直接切入点

- [av1_frame_map.mbt](av1_frame_map.mbt)：`Av1RefFrame`、`av1_frame_map_update`；当前保存图像及部分帧状态，缺少完整熵上下文快照。
- [av1_inter_mode.mbt](av1_inter_mode.mbt)：tile 状态仍从 `av1_inter_cdfs()` 的默认分布初始化。
- [av1_frame_header.mbt](av1_frame_header.mbt)、[av1_frame_planes.mbt](av1_frame_planes.mbt)、[av1_intra_tile.mbt](av1_intra_tile.mbt)：核对 primary reference、CDF 更新门、frame-end 更新门、选定 tile 与 refresh flags 的保存/加载时机；避免跨帧共用可变 CDF 数组造成状态污染。
- [inter fixture 说明](tests/fixtures/av1-inter/README.md) 与测试中的 `assert_eq(bad, [3992, 842, 928])`：用同一 OBU 和真值推进至零差异，不能修改 goldens 掩盖错误。
- **（2026-09-21 第十二、十三次推进）已排除的根因**：MSAC 算术/越读补位、CDF 适配速率（均与 dav1d 1.2.1 对拍/等价证明）；色度叶的 `eob512` 读及其行值（强制符号 0..9 全扫描无一归零）；luma/色度系数表串表（已双向确认分离）。剩余分歧已定位到**进入 inter 帧最后一个 32x16 色度（U）叶之前的 MSAC 状态**（该叶 `eob=245`，Y/V 全对、U 错 488/1024 且从第 16 行起），而 Y 像素全对说明肇事者是一个**不改变像素的读**。直接入口：给 `symbol()` 加符号计数器强制，从 inter 帧第一个符号起对半二分；或对 4 个 luma 叶的 `eob` 读逐个强制为相邻 `eob_pt`。同时准备用符号数上界替换 `-14` 越读守卫（放开后实测 4 个既有测试失败）。

### C、D 阶段的已知缺口

- [av1_inter_tile.mbt](av1_inter_tile.mbt) 的当前检查拒绝 compound、switchable motion、warped、temporal MV、skip mode、intrabc、screen content、coded lossless、非 identity 全局运动等；segmentation 还在帧头拒绝。逐项检查实际调用路径。
- **（2026-09-21 移除）矩形 `Coeff_Base_Ctx_Offset` 不需要修**：第八次推进记录的“19 组索引错误”经逐格枚举证明是误报，现有实现与 go-av1 权威表零差异（详见第 10 节第八次推进条目下的更正）。阶段 C 不需为此引入 TX_SIZE 全序。
- MV 外部样本只覆盖 magnitude class 1、4。class 0/2/3 可用现有工具设计小于 2 像素非整数位移、约 6/12 像素非周期源；class 5–10 受当前编码器搜索范围限制。详细证据见 inter fixture README。
- 去块尚需混合 intra/inter 的 chroma block 样本固定 step 4.b、未命中的引用行及 chroma edge widening。
- 当前 fixture 说明中的 `load_previous` 块邻居上下文在单 tile 条件下被当前帧覆盖，不应重复列为单 tile 待补样本；temporal `ref_frame_mvs` 是另一机制，多 tile 路径需单独核验。
- 动画不能仅验证帧数或时间戳。公开入口包括 `avif_decode_rgba`、`avif_decode_grid_auto`、`avif_decode_animation`、`avif_decode_animation_frame` 和 `avif_decode_animation_samples`；签名见 [pkg.generated.mbti](pkg.generated.mbti)。

## 7. 最近关键提交

| 提交 | 接手时要理解的内容 |
| --- | --- |
| `eee85ff` | 保存 inherited CDF 的已知错误计数，明确下一项正确性目标 |
| `714b92c` | 两字节帧头补丁触达 primary reference 分支，冻结 CDF 的证据边界 |
| `a8b3675` | 去块强度使用边缘所属引用与模式 |
| `42b34e0` | NEARMV 可取第二个候选 |
| `36e3f68` | MV magnitude 位索引修复 |

使用 `git show <提交>` 查看完整实现；这里不重复已有 diff。

## 8. 参考样本与跨机器复现

日常测试使用已提交的样本和嵌入式白盒测试。`inter_cdf_inherit_64x64.obu`、对应 `.reference.yuv`、manifest、trace 和测试都属于交接代码的一部分；不需要原作者的临时日志才能定位问题。

重新生成参考样本时：

1. 阅读相应 fixture README、manifest 与生成器，保留原始 OBU、参考像素及哈希；记录真实工具版本与完整命令。
2. inter 工具链最近核对为 aomenc/libaom `3.6.0`、dav1d `1.2.1`，脚本使用 FFmpeg `9.0.1` 的 `trace_headers`。不同构建可能产生不同编码字节，不能用“版本号相同”替代 OBU/像素比对。
3. [generate-av1-inter-reference.py](scripts/generate-av1-inter-reference.py) 的 `AOMENC`、`DAV1D`、`FFMPEG` 三个常量**在 2026-09-21 的本机上就是可用路径**（`D:\ProgramData\anaconda3\Library\bin\aomenc.EXE` / `dav1d.EXE`、WinGet 的 `ffmpeg-9.0.1-full_build-shared`），其中 `dav1d --version` 报 **1.2.1**，正是产出黄金真值的版本；用同一 `MINIMAL_FLAGS` 重编码 `ramp` 并施加同一补丁可得与提交件逐字节相同的 OBU 与 `.reference.yuv`（已 `cmp` 验证）。若换机器仍可按第 8 节末尾的 Python 入口用 `shutil.which` 覆盖这三个常量。这是生成工具的现有限制，不是解码库的运行时依赖。
4. [craft_av1_fixture.py](scripts/craft_av1_fixture.py) 的部分构造工具依赖本地 `_refs/go-av1/cdf`。如果要使用，应依据源码和 [THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES.md) 获取对应参考源并锁定修订；不要假定收到的代码副本包含该缓存。普通 `moon test` 不需要重跑它。
5. 在隔离副本运行生成器。[generate-av1-inter-reference.py](scripts/generate-av1-inter-reference.py) 的 `--check` 仍写 input/trace；[generate-av1-restoration-frame-reference.py](scripts/generate-av1-restoration-frame-reference.py) 当前注册了 `--check` 却未解析参数，仍会生成并改写测试。不能把所有 `--check` 都当成只读。
6. 构造码流必须由独立解码器核验；只证明本项目 writer 与 reader 自洽不能替代外部像素证据。既有记录中，上述旧编码器构建出现三帧以上编码崩溃和约 ±32 像素 MV 搜索限制；这是特定构建的观察，后续多帧/大 MV 需更换或重新验证工具构建。

在**隔离代码副本的根目录**，将 `aomenc`、`dav1d`、`ffmpeg` 放入 PATH 后，可用以下命令核验 inter 样本。PowerShell 和常用 POSIX shell 均可传入这段 Python；它按上面的说明会重编码并写 fixture 工作文件，不能在需要保持只读的副本中运行。

```sh
python -c "
import importlib.util
import shutil
import sys
script = 'scripts/generate-av1-inter-reference.py'
spec = importlib.util.spec_from_file_location('inter_reference', script)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
for field, executable in [('AOMENC', 'aomenc'), ('DAV1D', 'dav1d'), ('FFMPEG', 'ffmpeg')]:
    path = shutil.which(executable)
    if path is None:
        raise SystemExit('Missing executable: ' + executable)
    setattr(module, field, path)
sys.argv = [script, '--check']
module.main()
"
```

二进制 fixture 保持原始 bytes，遵守 [.gitattributes](.gitattributes)。Python 源码读写明确指定 UTF-8。单文件格式化使用 `moonfmt -w FILE`；`moon fmt PATH` 不能当作只格式化该文件的保证。

## 9. 接手记录与可选辅助方式

每完成一个阶段，在本文件更新：代码 revision、实现范围、独立样本、实际命令与退出结果、剩余缺口、下一阶段入口。保留“已实现”“已由外部真值验证”“已知错误”之间的区分；不要只更新测试数量。

如使用代码代理，可选用 `systematic-debugging`、`verification-before-completion`、`code-quality-review` 和 `handoff` 对应的排错、验证、审查与交接方法。它们不是构建依赖；未安装任何代理技能的开发者也可以按本文命令和源码入口完成工作。

## 10. 2026-09-20 第二至第十三次接手记录（阶段 A 完成，阶段 B 机制已验证、剩余分歧隔离到关键帧色度周期 3 纹理；强制符号实验通道已证不可用，相关结论挂起）

基线仍为 `eee85ffd`；本节省略了提交，全部改动位于工作区（`git status` 可见，暂存区为空）。

### 已完成：阶段 A（恢复交付基线）

- `node scripts/build-web.mjs` 重建 `web/dist/web.js` 与 `web/dist/wasmcore.wasm`；`node scripts/build-web.mjs --check` 两个文件均 OK；`node verify-wasm.mjs` 全部 PASS（wasm invert / grayscale / gaussian / in-place pipeline / unknown filter 共 10 项）。
- [cmd/cli/README.md](cmd/cli/README.md) 的 hex 示例已补 `--target native`（默认 wasm-gc 目标被 `supported_targets = "native"` 拒绝，实测报错 `Package ... does not support target backend 'wasm-gc'`）。CLI 冒烟：`moon run --target native cmd/cli -- --help`、`info --input tiny.png`、`convert --from png --to qoi` 均正常。

### 已完成：阶段 B 机制（熵上下文快照），加载开关关闭

新文件 [av1_frame_cdfs.mbt](av1_frame_cdfs.mbt) 定义 `Av1FrameCdfs`：68 张 CDF 表的行主序快照（分区树 5、intra tile 状态 39、inter 模式行 21、loop restoration 选择器 3），含捕获/深拷/按表恢复辅助函数，布局与本文件头注释中的表序一致。落点：

- [av1_frame_map.mbt](av1_frame_map.mbt)：`Av1RefFrame` 增加 `cdfs`；`Av1FrameMap` 增加 `mut saved_cdfs`（`None` = 从未写入，等价于规范默认值）；`av1_frame_map_update` 接受 `cdfs?`，`disable_frame_end_update_cdf` 为 0 时把 context_update_tile_id tile 的终态写入帧上下文并按刷新槽共享（§8.3/§7.20），为 1 时刷新槽继承上一帧上下文。
- [av1_intra_tile.mbt](av1_intra_tile.mbt)：`av1_decode_intra_tile_state` 增加 `frame_cdfs?`/`cdfs_out?`；tile 的分区树、块表、loop-restoration 选择器均从继承快照播种，结束时把 tile 0 的终态推入 sink。
- [av1_frame_planes.mbt](av1_frame_planes.mbt)：`av1_decode_tile_planes` 透传快照并回传捕获结果；`av1_decode_frame_planes` 按 §6.10 计算 `inherited`（`primary_ref_frame` 指名槽位→深拷贝该槽快照；`PRIMARY_REF_NONE`→默认），并存入 `av1_frame_map_update`。
- [av1_inter_mode.mbt](av1_inter_mode.mbt)：`av1_inter_info` 的 inter 模式行从快照恢复（`av1_inter_cdfs_of`）。
- 四个既有调用点（[av1_tile_decode.mbt](av1_tile_decode.mbt) ×3、[av1_alpha_decode.mbt](av1_alpha_decode.mbt) ×1）改为解构三元组；[av1_mc_oracle_wbtest.mbt](av1_mc_oracle_wbtest.mbt) 的参考帧构造补 `cdfs: None`。

**加载开关**：`av1_cdf_load_enabled`（[av1_frame_cdfs.mbt](av1_frame_cdfs.mbt)）当前为 `false`。保存/捕获/播种代码路径始终运行并被隔离测试覆盖；关闭时 `inherited` 恒为 `None`，行为与基线完全一致，1186/1186 全绿（wasm-gc / js / native 实测）。打开开关后两个 `inter_cdf_inherit_64x64` 测试转为失败（inter 帧解码被拒），因此保持关闭。

### 已验证边界（均对照规范摘录 `_refs/av1spec0*.md` 与 dav1d 1.2.1 源码）

- 快照机制：分区/intra/inter/lr 四组共 14 个投毒值经捕获→恢复全部落回原表原行（临时白盒测试，已删）。
- 我们与 dav1d 的默认 CDF 表：脚本集合比对 3035 行，仅 19 行缺失（filter_intra 行为动态构造、delta_q/intrabc 等未实现表），inter 相关表逐行一致。
- MSAC 适配公式、partition/skip/is_inter/y_mode/uv_mode/angle_delta/cfl/filter_intra/VARTX/txsz/mode-tree（§7.10.2.14）上下文、MV 钳制、eob_pt→eob 映射（§5.11.39）、extra search、DRL 读取条件均与规范一致；dav1d 的 `newmv/globalmv/refmv` 上下文组装经核对与规范等价。
- 关键帧 CDF 适配链抽样验证：w64/w32 分区行、skip 行的适配前后值均可由默认值+符号序列复算。

### 剩余缺口（阶段 B 未闭合）

2026-09-20 第三次推进（深度定位）后的结论：**分歧不在熵机制，而在系数段的某个上下文/行选择**。已完成的定位工作：

- **快照机制**：四组共 14 个投毒值经捕获→恢复全部落回原表原行（临时白盒测试，已删）。
- **默认表**：与 dav1d 1.2.1 源码逐行集合比对（3035 行），仅 19 行缺失（filter_intra 行为动态构造、delta_q/intrabc 等未实现表），inter 相关表完全一致。
- **算术解码器**：用 Python 按 `_refs/av1spec09.md` 独立实现 MSAC，对真实 fixture payload 交叉验证前 8 个符号，与本解码器逐符号一致（含 range/value 状态）。
- **inter 帧前 8 个符号被位流强制**：partition@64=SPLIT、partition@32=NONE、skip=0、is_inter=1、single_ref(1,1)→ALTREF、new_mv=0(NEWMV)、mv_joint=3。解码所得 MV=(-30,-4)（预测为全局 MV (0,0)）。此前“黄金帧第一块真实 MV=(0,0)”的推断**是错的**：该分析对越界参考用了 128 填充（应为边缘钳位），且关键帧是纯水平渐变（垂直 MV 不影响预测、水平 MV 无法从像素确定）。
- **脱 sync 定位在第一块的系数段**：tile 解码共读 1075 个符号、`symbol_max_bits=-1046`（关键帧为干净的 69 个符号/-11）；第一块 1019/1024 样本错误，而 MV/插值滤波符号已被证明强制正确。
- inter 帧为 TX_MODE_LARGEST（trace 值 1），无 vartx/tx_depth 符号，本解码器处理正确（已排除该路径）。
- 系数段已逐一核对且与规范一致：txb_skip ctx（§8.3 readAllZero 七分支）、eob_pt→eob 映射、extra 表按 txSzCtx 索引、inter tx type set3（TX_32X32 分支）。

**系数路径已逐项核对且全部与规范/go-av1/dav1d 一致**（2026-09-20 第三次推进补充）：txb_skip ctx（§8.3 readAllZero）、txSzCtx（32x32→3，与 libaom/dav1d 一致）、eob_pt→eob 映射与系数个数（我们的 eob = 规范计数 = dav1d eob+1，两种循环等价）、eob_extra 索引（`[txSzCtx][ptype][eobPt-3]`，与 go-av1 `decode/cdf.go` 注释一致）、inter tx type set3 符号映射（sym1→DCT_DCT、sym0→IDTX，与 dav1d `(idx-1)&IDTX` 一致）、32x32 对角扫描、level/sign 读取顺序（level 从 eob-1 到 0、sign 从 0 到 eob-1，DC sign 先行）、dc_sign ctx（规范 dcSign 符号和模型）。base/br ctx 用 Python 建模 dav1d 的缩放 level 编码（`(tok<<6)|tok`，EOB 与 AC 差一、`(mag+64)>>7`、`>512` 截断）做了数值比对：18750 + 2916 个配置下**零差异**。

**剩余疑点（按优先级）**：1) 继承的 eob/txb_skip 行的**具体数值**——关键帧对这些行的适配次数与符号若与 dav1d 有任何一个不同（例如关键帧最后一次读取多读/少读一个落在尾部填充区的符号，像素不变但行值被污染），inter 帧首个 eob 符号即偏离；2) 关键帧 vartx 树产生的变换尺寸序列（决定哪些行被适配）；3) 某个尚未建模的交互。建议下一步：给 MSAC 加“读取位置-符号”轨迹，对关键帧与 inter 帧各 dump 一份，用规范独立实现复算关键帧全部符号，确认是否还有多余读取。

**复现用的 payload 偏移**（Python 交叉验证用）：关键帧单元 = obu[0:69]，关键帧 tile payload = obu[24:69]（45 字节）；inter 单元 = obu[69:98]，inter tile payload = obu[87:98]（11 字节）。注意 inter 单元以 2 字节 temporal delimiter + 2 字节 frame OBU 头开头，帧头 14 字节。

禁止用修改 goldens 或断言的方式掩盖。

### 第四次推进（2026-09-20）：分歧已定位到具体符号

**结论：dav1d 的黄金 inter 帧确实采用 SPLIT 结构（partition@64=SPLIT → 四个 32x32 块）。我们启用继承后的解码在块结构、MV、eob 与前 9 个系数上与黄金一致；第一个分歧符号是第一块 32x32 luma 变换中扫描位置 k=31 的 `coeff_base` 符号（base ctx 22 行），我们解出 2（level 2），黄金为 1。**

方法与证据（均可在隔离副本复现；本轮临时插桩已全部回退）：

- **黄金帧结构 = SPLIT**：黄金帧行 31→32 平均 |Δ|=9.38（其他行边界约 1.0），列 31→32 为 39.09（源锯齿周期 32）；inter_minimal（默认 CDF 解码）是纯水平渐变（所有行边界 |Δ|=0）。
- **MV/预测正确**：以我们解出的 MV=(-30,-4)（1/8 像素）对关键帧做运动补偿并 dump 第一块预测；黄金减预测的 32×32 二维 DCT 是稀疏低频残差（约 20 个显著系数，全部位于扫描位置 ≤40）→ MV、参考帧、插值滤波与 dav1d 一致。
- **eob 正确**：黄金最后一个非零系数在扫描位置 k=40 → eob=41，与我们解出的 eob（eob_pt=7、extra=0、尾位 1,0,0,0）逐一吻合 → 关键帧适配过的 luma eob 行与 dav1d 一致。
- **第一个分歧符号**：MSAC 逐符号轨迹（记录剩余位预算、符号值、完整 CDF 行）第 34 项 = 第一块 32x32 luma 变换扫描位置 k=31（系数坐标 (3,4)）的 `coeff_base`，行 = luma base[tx_ctx=3][ctx 22]（快照 T28 R148，被关键帧适配）。我们解出 2；黄金残差 DCT 在该位置约 352、k=32 约 696（比值 1.96）→ 黄金系数值为 1。k=40…32 的系数（1,0,0,0,0,0,0,0,2）与黄金逐个一致。
- **已按规范逐项核对且一致**：CDF 适配公式（`_refs/av1spec09.md` §8.2，与 `av1_msac_update_cdf` 完全相同）；`get_coeff_base_ctx`（isEob 四分支、2D 类参考偏移、mag 截断、`Coeff_Base_Ctx_Offset[TX_32X32]` 标准表）；partition ctx（`ctx = left*2 + above`）；`decode_partition` 越界强制规则；`coeff_base` level=符号值、`coeff_base_eob` level=符号值+1。
- **关键帧结构已理清**（修正此前错误记录）：128x128 超块在 64x64 帧内根分区强制 SPLIT（不读符号）；唯一 64x64 子块读 1 个 w64 分区符号（ctx 0，值 NONE），TX_MODE_SELECT 下读 1 个 tx_depth 符号（cdf64）得 depth 1 → 四个 32x32 luma 叶 + 两个 32x32 chroma 叶；共读 **1037** 个符号、`symbol_max_bits` 终值 -6（此前“69 个符号”的记录有误）。2 个 luma 叶与 2 个 chroma 叶带系数（eob_pt 分别 5,5 与 9,9），另 2 个 luma 叶 txb_skip=1。
- **快照适配行集合**（关键帧相对默认值共 19 行）：partition w64 R0、skip R0、y_mode R0、uv_no_cfl R1、angle_delta R0、txb_skip R40/42/46、luma eob R0、luma extra R30、luma base_eob R13、luma base R126/127/129/132/133/134/147/148、luma br R69/70/77、luma sign R0/1、chroma eob R0、chroma extra R34、chroma base_eob R15、chroma base R126/127/128/132/133/147/148/149/150、chroma br R63/77/78、chroma sign R0、tx_depth cdf64 R0。
- **两种单点修复搜索均为阴性**（说明不是单个行值或单个符号值问题）：(a) 行级探针——19 个适配行逐一换回默认值，无一到达 [0,0,0]（最佳 T28 R126→默认：[3794,316,600]）；(b) 强制符号搜索——inter 轨迹 k=0..169 每个符号逐一强制为其他值，无一到达 [0,0,0]（最佳 k=66 v=1：[3319,180,536]）。与“某一行整体不同于 dav1d”或“算术状态提前发散但符号值暂时重合”两种解释都相容。

**剩余疑点（第四次推进后）**：分歧行（base ctx 22，及其前的 base ctx 21）由关键帧适配而来。可能原因按优先级：1) 算术状态在更早使用适配行的符号处（partition w64 ctx0 / skip ctx0 / luma eob / base_eob ctx1 / base ctx21）因区间宽度不同而发散，符号值暂时重合（尖峰 CDF 下常见）；2) 关键帧对 base ctx 21/22 的适配次数与 dav1d 不同（ctx 序列差异不改变关键帧像素）。**建议下一步**：dump 关键帧的 base ctx 序列（按行内容匹配快照表），从关键帧像素反推 intra 预测以恢复系数 level，用规范模型独立复算 ctx 序列并与我们的轨迹逐项对比；或对 base ctx 21/22 两行做“适配次数 ±1 / 不同符号值”变体枚举，以黄金为 oracle 搜索。

### 第五次推进（2026-09-20）：ctx 模型与行变体空间均已穷尽，分歧仍在 I[34]

按第四次推进的建议完成了全部三项工作，结论是**上下文选择与可构造的行值变体都不是根因**：

- **关键帧叶结构完全理清**（修正第四次推进的表述）：带系数的叶共 4 个——2 个 **luma** 32x32 叶（eob=29，eob_pt=6）与 2 个 **chroma** 32x32 叶（eob=379/435，eob_pt=10），另有 2 个 luma 叶 txb_skip=1。luma/chroma 归属由两条独立证据确认：extra 表适配（luma extra[3][3] ↔ eob_pt 6；chroma extra[3][7] ↔ eob_pt 10）与源内容（`ramp` 源的 cb 为周期 5 的垂直纹理、cr 为周期 7 的水平纹理，色度需要密集残差；luma 是周期 32 的平滑斜坡）。第四次推进把两者写反了，但 ctx 序号是以 tx_ctx=3 记录、不受归属影响。
- **上下文模型独立复算零差异**：用 Python 按 `_refs/av1spec09.md` 的 `get_coeff_base_ctx`（isEob 四分支、2D 类参考偏移 `{(0,1),(1,0),(1,1),(0,2),(2,0)}`、`Min(|Quant|,3)` 逐项累加、`Min((mag+1)>>1,4)`、`Coeff_Base_Ctx_Offset[TX_32X32]` 标准表）复算关键帧 4 个叶全部 **872** 个 base 符号与 inter 帧 32x32 叶全部 **41** 个 base 符号的 ctx，与实际记录逐项一致（0 差异）。即我们的 ctx 选择与规范一致。
- **反量化标定**（修正第四次推进的系数刻度）：`acQlookup[128]=176`、TX_32X32 的 `dqDenom=2`（规范 7.12.1），故反量化系数 = level×88；用单系数注入实测 32x32 逆变换增益（DC 1/128、edge 1/88、interior 1/70）后确认黄金残差 DCT 的系数刻度。黄金第一块系数：k40=1、k32=2、**k31=1**（我们为 1、2、**2**）——第四次推进的“第一个分歧在 I[34]”结论在正确刻度下依然成立。
- **inter 帧实际块结构**（我们继承解码下的 dump）：block(0,0)=32x32（partition@32=NONE，已被黄金接缝证实）；其余三个 32x32 块在 I[34] 之后才读分区符号，其更深的分区（16x32/16x8/8x16/4x16 等）不可信。
- **行变体枚举全部阴性**（以黄金为 oracle，逐一注入快照后整帧解码）：
  - base ctx 22 行（关键帧 luma 序列 [0,2,0,0,2,0]）：前缀 0..6、单位置改值、去一项、追加一项——最佳 [3321,280,536]，无一到达 [0,0,0]。
  - base ctx 21 行（30 个 0）：前缀 0/10/20/25/28/29/30/31/32——无一到达。
  - base_eob ctx 1 行（关键帧 luma EOB 序列 [1,1]）：前缀、改值、追加、去项——无一到达。
  - 联合枚举（base_eob × ctx21 前缀、base_eob × ctx22 前缀）——无一到达。
- 结合第四次的强制符号搜索（k=0..169 全值）与行级默认化探针（19 行），**所有“可构造的行值/符号值”假设均被排除**。

**剩余疑点（第五次推进后）**：I[34] 之前的所有适配行（partition w64 ctx0、skip ctx0、luma eob、base_eob ctx1、base ctx21、base ctx22）按我们自己的关键帧读取序列重放都无法复现 dav1d 的效果，且 ctx 模型与规范零差异。剩下两种可能：1) 算术状态在 I[25]–I[33] 之间因某行区间宽度不同而发散，但符号值全部暂时重合（7 个 0 加一个 2，尖峰 CDF 下概率不低——注意 I[25] 的 base_eob 读出的 level 1 与黄金一致，但“值一致”不证明“状态一致”）；2) 关键帧某处存在我们与 dav1d 读取不同、却不改变像素的符号（例如尾部填充区的多余读取污染了某行，或某个 CDF 行被适配了不同次数）。**建议下一步**：(a) 给 MSAC 增加“状态快照+重放”能力，对 I[25]/I[26]/I[33] 三点分别用黄金约束反推可行的 (range,value) 区间，判断哪一点开始不相交；(b) 用规范独立实现完整复算关键帧 1037 个符号（含 bool 与 golomb 尾位），确认第 1037 个符号之后是否还有读取污染了被 inter 帧使用的行；(c) 若仍无法闭合，把本节结论作为阶段 B 的已知边界记录，转入阶段 C/D 的独立工作，避免阻塞主线。

### 第六次推进（2026-09-20）：排除适配开关与 tx_mode 类假设，早期行变体亦全阴

- **trace 级复核帧头**（`tests/fixtures/av1-inter/inter_cdf_inherit_64x64.trace.txt`）：两帧 `disable_cdf_update` 均为 **0**（适配开启，双方一致，“关/开适配不一致”假设排除）；关键帧 `tx_mode=2`（TX_MODE_SELECT）、inter 帧 `tx_mode=1`（TX_MODE_LARGEST）；inter 帧 `base_q_idx=128`、`is_filter_switchable=1`、`segmentation_enabled=0`、`primary_ref_frame=0`、`refresh_frame_flags=2`、`allow_high_precision_mv=0`。
- **推断 Max_Tx_Size_Rect[BLOCK_64X64]=TX_64X64**：inter_minimal 的 inter 帧第一块为 64x64（partition NONE）+ TX_MODE_LARGEST，本解码器以 64x64 变换解码且与 dav1d 逐样本一致，故该表项为 TX_64X64；因此关键帧 64x64 块的 tx_depth 符号用 cdf64 行是正确的（第五次推进曾怀疑此处行选错，现排除）。
- **早期行变体枚举全阴**（以黄金为 oracle）：对 partition w64 ctx0（序列 [0]）、skip ctx0（[0]）、luma eob ctx0（[5,5]）三行做前缀/单位置改值/追加/去项枚举，无一到达 [0,0,0]；部分扰动只把分歧点推后（如 T3 R0 追加一次适配 → [3533,364,536]），与“差异不是单行扰动”一致。
- **inter 帧块结构 dump**（继承解码下）：block(0,0)=32x32（partition@32=NONE，已被黄金接缝证实）；其余块的更深分区（16x32/16x8/8x16/4x16）位于 I[34] 之后，不可信。

**结论**：阶段 B 的样本分歧已定位到 I[34]（第一块 32x32 luma 变换扫描位置 k=31 的 `coeff_base`，base ctx 22 行），且以下空间已全部穷尽——ctx 模型（与规范零差异）、关键帧全部 872+41 个 base 符号的 ctx 复算、六条早期适配行的行值/符号值变体（含联合枚举）、强制符号搜索、行级默认化、适配开关与 tx_mode 假设。剩余只能是“算术状态在 I[25]–I[33] 之间因某行区间宽度不同而发散但符号值暂时重合”或“关键帧存在不改变像素的不可观测读取差异”，需要 MSAC 状态级取证（本机 dav1d 无可用的符号级插桩）或更简单的可复现样本才能继续。

### 第七次推进（2026-09-20）：建立精确 MSAC 模拟器，证明差异不可能来自任何单行替换，根因收敛到关键帧的像素不可辨系数级差

本轮构建了可复用的取证工具并完成系统搜索，结论比第六次推进更进一步：

- **精确 Python MSAC 模拟器**（按 `_refs/av1spec09.md` §8.2 实现，含 renorm 的 max_bits 钳制）：从状态轨迹 S[33]（r55240 v425 b44）起步，复现 I[33]=2、I[34]=2 与 I[34] 后的状态 (32864, 4634, 38)，与本解码器逐位一致。该模拟器可在下一轮直接复用。
- **单行替换全阴**：对 I[0]–I[34] 用到的**全部** CDF 行（partition w64、partition w32、skip、is_inter、single_ref、new_mv、mv_joint、MV 各行、interp、txb_skip、tx_type、luma eob、extra、base_eob、base ctx21、base ctx22）逐一做“默认值+任意适配序列”的替换搜索（含 base_eob×ctx21 联合搜索、eob 默认值 cdf[5]/cdf[6] 二维搜索、txb_skip/extra/tx_type/is_inter 默认值一维搜索），**没有任何单行（或两行联合）替换能使符号序列变成黄金值**（I[34] 由 2 变 1）。
- **关键概念突破：像素一致不锁定符号值**。反量化系数 = level×88，逆变换增益实测（DC 1/128、edge 1/88、interior 1/70，按位置注入单系数标定）。高频位置（如 (0,7)、(0,5)）level 差 1 的像素贡献 ≈ 0.24，被取整掩盖——因此关键帧像素逐样本一致**不能**推出其符号流与 dav1d 一致，快照行完全可以不同而像素不变。这解释了前六轮“像素精确但快照必错”的表面矛盾。
- **黄金侧再次确认**：黄金第一块 k=31（坐标 (3,4)）系数 level=1（C′=355.0 ÷ 增益 3.99×88 ≈ 1.01），k=32（(4,3)）=2（696.4 ÷ 3.90×88 ≈ 2.03），k=40（(4,4)）=1。即 I[33]=2（我们一致）、I[34]=1（我们是 2）。
- **根因收敛**：给定 I[33] 处的状态，base ctx22 行有 496 个可达适配序列能满足黄金（I[33]=2, I[34]=1），其中与我们的序列 [0,2,0,0,2,0] 最接近的可行序列是 **[0,1,0,0,1,0]**（仅两处 2→1）。即：**dav1d 的关键帧把两处 (0,5) 系数解成 level 1，我们解成 level 2**——像素差 ≈0.24 被取整掩盖，但 base ctx22 行（及连带 ctx21/base_eob 等行）的适配值因此不同，inter 帧继承后在 I[34] 分歧。
- **规范侧再次逐项核对无误**：y_mode 在帧内用 TileYModeCdf[Size_Group[MiSize]]（inter 路径）、intra_frame_y_mode 用邻居上下文表（intra 路径，我们两条路径分别用对了表）；uv_mode 在 Max(w,h)≤32 且非无损时用 CflAllowed 表、否则用 NotAllowed 表；partition ctx = left*2+above；Size_Group 表值与规范一致。

**剩余工作（下一步入口）**：找出我们的关键帧为何把 (0,5) 类系数解成 level 2。该系数由 base ctx22 行读出，而 ctx22 的上下文又依赖 (0,7) 的 level（EOB 系数，base_eob 符号）。最可能的分歧源按优先级：1) base_eob 默认行 `defaultCoeffBaseEobCdf[qctx=1][tx=3][plane=0][ctx=1]` = [30755, 31923, 32768, 0] 与 libaom/dav1d 不一致（本机无 dav1d 源码可比对，需取得 `default_coeff_base_eob_cdf` 权威值）；2) (0,7) 的 base_eob 符号读出差异；3) base ctx 模型在 (0,5) 位置的某个边界条件。**取证方法**：用已建好的 Python 模拟器从关键帧第一叶的 txb_skip 符号起完整重放（该叶全部读取都来自默认行，完全确定），把每一行的默认值与 libaom 的 default_coeff_* 表逐行比对，第一处不一致即为根因。

### 第八次推进（2026-09-20）：对照 go-av1 权威源逐项核表，发现矩形变换 ctx offset 索引错误；阶段 B 剩余疑点收窄为一处符号级差异

本轮把 `_refs/go-av1/cdf` 与 `_refs/go-av1/decode` 的权威源码与我们的实现逐项比对（本机无 dav1d 源码，go-av1 的表即规范生成表，且此前与 dav1d 1.2.1 的集合比对一致）：

- **系数默认表全部一致**：`defaultCoeffBaseCdf`（4×5×2×42 全量 0 差异）、`defaultCoeffBaseEobCdf`、`defaultEobPt1024Cdf`、`defaultEobExtraCdf`、`defaultDcSignCdf` 与 go-av1 逐值相同。
- **txSzCtx 公式一致**：`(TxSizeSqr[txSz] + TxSizeSqrUp[txSz] + 1) >> 1`（go-av1 decode/coeff.go:16），TxSizeSqr/TxSizeSqrUp 表值与我们的 av1_tx_size_ctx/av1_tx_size_ctx_rect 对矩形与方形逐项吻合。
- **系数上下文模型一致**：go-av1 decode/coeffctx.go 的 sigRefDiffOffset（2D/vert/horiz 三组）、mag 逐项 Min(|q|,3)、`(mag+1)>>1` 截 4、isEob 四分支与 offset 表都与我们一致。
- **发现一处真实错误（影响矩形变换，阶段 C 需修）**：规范与 go-av1 的 `Coeff_Base_Ctx_Offset` 按 **txSz（TX_SIZE 全序 0..18）** 索引（go-av1 decode/scan_gen.go 的 coeffBaseCtxOffset 共 19 组），我们的 `av1_coeff_base_ctx_offset` 只有 5 组并按 size class 索引。方形变换两者恰好一致（TX_4X4..TX_64X64 → 0..4），**矩形变换（如 16x32、8x32、4x8 等）会取错 offset 组**。本 fixture 全为方形变换故不受影响，但阶段 C 放开矩形/屏幕内容路径前必须修正：把表扩为 19 组并按 txSz 索引（TX_SIZE 全序需在代码中落地）。**（2026-09-21 第九次推进更正：该项经逐格枚举证明是误报——见下。）**
- **（2026-09-21 更正）矩形 ctx offset 并非错误**：用脚本对 19 种 TX_SIZE 的全部可达 (row, col) 逐格枚举，我们的“方形表 + `tx_width<tx_height && row<2 → +11` + `tx_width>tx_height && col<2 → +16`”与 go-av1 19 组 `coeffBaseCtxOffset` **零差异**。原因是所有 tall 组（4x8/8x16/16x32/32x64/4x16/8x32/16x64）前两行都是 11、其余行就是方形表；所有 wide 组（8x4/16x8/32x16/64x32/16x4/32x8/64x16）前两列都是 16、其余列就是方形表；各组中值为 0 的条目都落在该尺寸调整域不可达的行/列上。方形路径的 `av1_coeff_base_ctx_offset[0]`（含 0 项）也与 go-av1 的 TX_4X4 组一致。**阶段 C 不需要为此修改表格或引入 TX_SIZE 全序。**
- **阶段 B 剩余疑点收窄为一处符号级差异**：给定 I[33] 状态，base ctx22 行只有“关键帧两次 (0,5) 系数解成 level 0/1（而非我们的 2）”一类可达序列能满足黄金（可行序列 [0,0,0,0]、[0,1,0,1]、[0,0,0,0,0]、[0,0,0,0,0,0]；我们的 [0,2,0,0,2,0] 不可行）。而 (0,5) 的 base 符号由 ctx22 行（默认+前一次 (0,6) 读的适配）与确定性状态决定，按现已核对的表与公式应可复算——**下一步只需把关键帧第一叶从 txb_skip 到 (0,5) 的十余个符号在 Python 模拟器里完整重放，与规范公式逐步对照，第一个算不对的符号即根因**（模拟器已在第七次推进建成并验证逐位一致）。

### 本次执行命令与结果

```
moon check                          → 64 warnings, 0 errors
moon test --target wasm-gc          → 1186/1186
moon test --target js               → 1186/1186
moon test --target native           → 1186/1186
node scripts/build-web.mjs --check  → OK web/dist/web.js, OK web/dist/wasmcore.wasm
node verify-wasm.mjs                → WASM verification passed
moon run --target native cmd/cli -- --help → usage 输出
git diff --check                    → 通过
git status --short                  → 与第 2 节预期差异集一致（暂存区为空）
```

本轮临时插桩（早期行变体搜索、五个文件的 `symbol_max_bits` 放宽检查、`zz_debug_early` 测试）已全部回退并经上表复验；`av1_cdf_load_enabled` 保持 `false`，inter 帧差异计数维持 `[3992, 842, 928]` 围栏值。注意：用 Python 写回 `.mbt` 文件会把行尾改成 CRLF，回退后必须转回 LF 否则 `git diff --check` 失败。

### 第九次推进（2026-09-21）：取得 dav1d 源码并建成 MSAC 状态级取证，证明关键帧第一叶与规范逐位一致；根因收窄到该叶之前 7 个符号的行/上下文

本轮突破了此前“本机无 dav1d 源码”的限制，取得了 dav1d 1.2.1 的相关源文件（`decodeb.c`、`recon_tmpl.c`、`tables.c`、`msac.c/.h`、`cdf.h`、`dav1d_cdf.c`、`env.h`、`internal.h`、`refmvs.c`），并据此完成了下列逐项核对（此前仅能对照 go-av1）：

- **算术解码器**：`dav1d_msac_decode_symbol_adapt_c` 的区间边界 `((rng>>8)*(cdf[val]>>6)>>1) + EC_MIN_PROB*(n-val)` 与规范 §8.2 的 `EC_MIN_PROB*(N-symbol-1)` 完全一致（dav1d 的 `n_symbols` 参数比规范 N 小 1）；dav1d 用 `#define CDF1(x) (32768-(x))` 以反序存表，等价于我们的 `f = 32768 - cdf[i]`；适配公式、renorm 的 max_bits 钳制、`decode_bool_equi` 的 `((r>>8)<<7)+EC_MIN_PROB` 均与我们逐项相同。dav1d 越过数据末端时移入 1、我们移入 0，但本 fixture 两个帧都只在末尾越读 6/12 位，不影响任何真实符号。
- **关键帧符号顺序**（规范 §5.11.11/5.11.12/5.11.13/5.11.16/5.11.39 与 dav1d `decode_b` 一致）：partition(w64) → skip → y_mode → angle_delta_y → uv_mode →（cfl_alphas / angle_delta_uv / palette / filter_intra 均不读）→ **tx_depth** → txb_skip →（intra 32x32 luma 的 tx_type 由 `t_dim->max + intra >= TX_64X64` 隐式为 DCT_DCT，**不读符号**）→ eob_pt → eob_extra → 尾位 → coeff_base_eob → coeff_base… → dc_sign/sign → golomb。此前记录里“读 1 个 tx_depth 符号得 depth 1”是对的：该符号来自 `TileTx64x64Cdf`（由 `Max_Tx_Depth[MiSize]==4` 选择，只有 2 个符号：depth 0/1），读出 **1** → `Split_Tx_Size[TX_64X64]` = TX_32X32 → 四个 32x32 luma 叶。dav1d 对应 `b->tx = max_txfm_size_for_bs[bs][0]` 后按 `txsz[max-1]` 读同一张表、`while(depth--) b->tx = t_dim->sub`。
- **色度变换尺寸**由 `get_tx_size(plane, TxSize)` = `Max_Tx_Size_Rect[get_plane_residual_size(MiSize, plane)]` 决定，**与 tx_depth 无关**：4:2:0 下 64x64 块的色度为 32x32 → 每个色度平面一个 32x32 叶（共 2 个），与 dav1d `dav1d_max_txfm_size_for_bs[BS_64x64][I420] = TX_32X32` 一致。这解释了此前“两个 32x32 色度叶”的结构。
- **var-tx 二叉树只用于 inter 块**（规范 `is_inter && !skip && TX_MODE_SELECT`；dav1d 只在 `decode_b` 的 intrabc/inter 两处调用 `read_vartx_tree`）；intra 块走单符号 `tx_depth`。我们两条路径分别用对了表。
- **32x32 默认扫描**与 go-av1 `scan_def32x32` 逐值相同（偶数对角 r 递减、奇数对角 r 递增）；`Coeff_Base_Ctx_Offset` 方形组与 go-av1/dav1d `lo_ctx_offsets[0]`（w==h）相同，且该表对称，故 dav1d 按 `[col][row]`、我们按 `[row][col]` 索引在方形上等价。
- **tx_depth / y_mode / uv_mode / angle_delta / txb_skip / skip / partition / is_inter / single_ref 的默认行**逐一与 go-av1 `cdf` 包对应表匹配（如 `DefaultTx64x64Cdf[0]={5782,11475,32768,0}`、`DefaultIntraFrameYModeCdf[0][0]`、`DefaultUvModeCflNotAllowedCdf[1]`、`DefaultAngleDeltaCdf[0]`、`DefaultTxbSkipCdf[1][3][1]`、`DefaultSkipCdf[0]`、`DefaultPartitionW64Cdf[0]`、`DefaultIsInterCdf[0]`、`DefaultSingleRefCdf[1][0..1]`）。
- **`read_ref_frames` 是 7 个参考帧名的二叉树**（go-av1 `singleRef[refCountCtx(fwd,bwd)][idx]`，idx 0/1/5 走 backward、2/4/3 走 forward）；我们的 `av1_read_ref_frames` 的索引与上下文与 go-av1 逐项相同。
- **上下文推导**：tx_depth 的 dav1d `get_tx_ctx` = `(l->tx_intra >= lh) + (a->tx_intra >= lw)`，且 `reset_context` 把 `tx_intra` 初始化为 -1（不可用邻居 → 0），与我们首块取 ctx 0 一致；skip 的 `ctx = (AvailU?Skips[上]:0) + (AvailL?Skips[左]:0)`、y_mode 的 `Intra_Mode_Context[不可用?DC_PRED:邻居模式]` 均与规范一致。
- **新建取证工具**（临时插桩，已回退）：给 `Av1SymbolDecoder` 增加 (range, value, bit_pos, max_bits, 完整 CDF 行, 解出符号) 的逐符号轨迹，并给系数叶加 `leaf s/h/sc/tx` 标记；白盒测试分别 dump 关键帧与 inter 帧（含继承）两份轨迹。**用独立 Python MSAC 模型从记录的关键帧叶起点状态 (r=47936, v=29471, b=31, m=329) 重放第一叶，逐符号复现本解码器**：eob_pt=6、eob_extra=1、尾位 1,0,0 → eob=29；(0,7) level 1、(0,6)=0、(0,5)=2、(0,4)=0，ctx 序列与 `/tmp/keycoeff.txt` 完全一致。**即在给定状态下，我们的第一叶解码与规范逐位一致，不可能是差异来源。**
- **定量定位剩余差异**：(0,5) 读处状态 (r=45273, v=1318)、行 DEF22+[0]=[21985,31527,32511,32768,1]，符号 1 需要 v ∈ [1680, 14796) —— 我们的 v=1318 低于下界 362。inter 侧同样定量：I[34] 处 (r=37016, v=799)、行 [20996,28884,32553,32768,7]，符号 1 需要 v ≥ 4328，而同一 I[33] 状态/行经 renorm 后 v 最多 799，**因此在 I[33] 状态不变的前提下 I[34] 不可能为 1，继承来的 ctx22 行本身必须不同**（独立复现了第七、八次推进的结论）。
- **继承链核对**：inter 帧实际拿到的行与我们的关键帧解码严格对应——partition w64 +[0]、skip +[0]、eob_pt_1024 +[5,5]、base_eob ctx1 +[0,0]、base ctx21 +[0]×30、base ctx22 +[0,2,0,0,2,0]；inter 帧用到的 eob_extra 行（下标 4）与关键帧适配过的行（下标 3）不同，取默认值是合理的。ctx21 的 30 次适配 = 两个带系数 luma 叶各 15 次，已点数确认。

**剩余疑点（第九次推进后，按优先级）**：既然第一叶本身被证明规范正确，差异只能来自该叶之前 7 个符号（partition w64、skip、y_mode、angle_delta_y、uv_mode、tx_depth、txb_skip）产生的 MSAC 状态。这些符号的**取值**都由像素/结构唯一确定（已逐项核对默认行与上下文），但若其中某个符号的 **CDF 行选错**（上下文索引不同而符号值巧合不变），区间宽度就会不同、状态随之偏移 362 以上。优先核查 `av1_tx_depth_context_for_node`（dav1d `get_tx_ctx` 用 `tx_intra` 的 lw/lh 比较，注意 `reset_context` 的 -1 初值与首块无邻居的 0）、`av1_txb_skip_ctx_luma` 的 `whole` 判定（32x32 变换 vs 64x64 块）、以及 y_mode/uv_mode/angle_delta 的索引来源。注意 tx_depth 读处 v=49330 距 depth 0 的边界 49475 只差 145，上下文若错到 ctx 2（行 [16803,22759,32768,0]）会翻转成 64x64 单叶结构——这与像素矛盾，故可反证 ctx 0/1 正确，但说明状态非常贴近边界、极小的行差异即可翻转 (0,5)。

**下一步入口**：用本轮已建成的轨迹工具，对关键帧前 7 个符号逐个做“行替换 + 黄金 oracle”搜索（固定符号取值、只换 CDF 行/上下文），找出哪一处的行宽差异能把 (0,5) 推到 ≥1680；或反过来从 inter 侧反推：给定 I[33] 状态，枚举使 I[34]=1 的 ctx22 行（已知可行序列含 `[0,1,0,0,1,0]`），再反推关键帧需要怎样的前 7 符号行组合。

### 第十次推进（2026-09-21）：取得编码三件套并逐字节复现 fixture，查明样本是“默认 CDF 编码 + 补丁开启继承”；失败隔离到 49 字节最小复现

本轮最重要的突破是**取证能力**：本机已安装 `aomenc`（`D:\ProgramData\anaconda3\Library\bin\aomenc.EXE`）、`dav1d`（**1.2.1，正是产出黄金真值的版本**）、`ffmpeg`（9.0.1）。用 [scripts/generate-av1-inter-reference.py](scripts/generate-av1-inter-reference.py) 的同一套 `MINIMAL_FLAGS` 重新编码 `ramp` 输入并施加同一补丁，得到的 OBU 与 `.reference.yuv` 与仓库提交的 `inter_cdf_inherit_64x64` **逐字节相同**（`cmp` 一致）。第 8 节“生成器路径仍是原机器路径”的限制由此解除：`AOMENC`/`DAV1D`/`FFMPEG` 三个常量在本机就是可用路径。

**关键结论一：该 fixture 的 inter 帧不是用继承 CDF 编码的。** [patch_header_fields](scripts/generate-av1-inter-reference.py) 的注释已说明 `primary_ref_frame` 对两帧流恒为 7（PRIMARY_REF_NONE），因为 libaom 在自己的两帧组内无可继承之物；`inter_cdf_inherit_64x64` 只是把帧头里这 3 位从 7 改成 0。也就是说：**bitstream 的 inter 帧符号是用默认 CDF 编的，而补丁强迫解码器改用关键帧适配后的 CDF 去解**。实测 dav1d 1.2.1 解同一 OBU：开补丁与不开补丁的第 1 帧有 **3996/6144** 个样本不同（全部在 luma，色度完全一致）——即“继承解码”在这条流上本来就会解出另一张图。因此本样本的验收含义是：**我们的继承解码必须逐符号复现 dav1d 的继承解码**，而不是复现“编码器意图”。

**关键结论二：继承机制本身是正确的。** 构造最小样本（64x64、两帧、`MINIMAL_FLAGS`、`--cq-level=32`）并系统变换输入，得到：
- 关键帧全平（luma 100、色度 128）+ inter 帧带图案（100 + x%4）：**继承开启时 inter 帧 `[0,0,0]` 精确**，key 帧也 `[0,0,0]`。这证明快照→装载→按引用恢复→tile 内适配的整条链在真实码流上工作。
- 关键帧全平 + inter 帧与关键帧完全相同（49 字节 OBU）：继承开启时 inter 帧被拒（`INTERBAD=none`）；**不开补丁（`primary_ref_frame=7`）则 `[0,0,0]` 精确**。即失败只与继承有关。

**关键结论三：分歧点的精确定位（49 字节样本）。** 用 MSAC 状态轨迹（本轮重建：记录每个符号的 range/value/bit_pos/max_bits + 完整 CDF 行 + 解出值）对照：
- 不开补丁：读 9 个符号即结束——partition w64→0(NONE)、**skip→1**、is_inter→1、single_ref 树 3 符号→LAST_FRAME、new_mv→1、zero_mv→1、ref_mv→0(GLOBALMV)；inter 帧全块 skip，无残差。Python 独立 MSAC 模拟（默认行 + payload 首 15 位初始化）逐符号复现该序列。
- 开补丁：第 1 个符号改用关键帧适配过的 partition 行（`DEF+adapt(0)` = [20531,…]），其后状态与默认行情形不同，导致第 2 个符号 **skip 读出 0**（默认行情形为 1），随后 is_inter/single_ref(2)/new_mv/zero_mv/ref_mv/txb_skip/eob_pt… 一路错位，20 个符号后 `symbol_max_bits` 到 -16 被 `>= -14` 守卫拒绝。
- 已核验：dav1d 的开补丁输出确实带 luma 残差（luma 83..115、均值 104.1，色度不变），说明 **dav1d 同样读出 skip=0 并继续解出残差**；我们的 skip=0 与 dav1d 一致，**真正的分歧在 skip 之后的符号**（最可能是 single_ref 树或 MV 段），而不是此前判断的 k=31。

**本轮同时确认的事实**：`av1_txb_skip_cdf` 与 go-av1 `DefaultTxbSkipCdf` 780 个整数全同；`defaultEobPt1024Cdf` 与 go-av1 全同；inter 帧继承到的 `eob_pt_1024` 行 `[1404,1431,1751,2596,4085,7177,13951,18507,22889,26046,32768,1]` 恰为默认行 `[393,...]` 按规范公式适配 symbol 0 一次的结果（已手算逐值核对），说明关键帧侧适配与装载都正确。

**下一步入口（阶段 B）**：用 49 字节样本继续向前定位——把开补丁轨迹的每个符号与“若该符号取另一值则后续自洽”做约束求解，或直接对 `av1_read_ref_frames` / `av1_assign_mv` / `av1_inter_tx_type` 的上下文索引做逐项核对（single_ref 的 `refCountCtx`、`drl_mode` 上下文、MV 栈候选数 `NumMvFound` 的判定都会改变读取个数）。另需注意：我们的 renorm 在越过数据末端时补 0，dav1d 补 1（规范公式 `paddedData = newData << (bits-numBits)` 与我们一致）；本样本 tile payload 仅 2 字节，一旦符号数偏多就会进入该区域，**符号数本身是否正确才是根因**。

### 第十一次推进（2026-09-21）：取得编码三件套并逐字节复现 fixture；查明 `-14` 越读守卫是最小样本的唯一阻塞；剩余分歧隔离到关键帧色度（仅周期 3 纹理触发）

本轮最重要的突破是**取证能力**：本机已安装 `aomenc`（`D:\ProgramData\anaconda3\Library\bin\aomenc.EXE`）、`dav1d`（`--version` 报 **1.2.1，正是产出黄金真值的版本**）、`ffmpeg`（9.0.1）。用 [scripts/generate-av1-inter-reference.py](scripts/generate-av1-inter-reference.py) 的同一套 `MINIMAL_FLAGS` 重编码 `ramp` 输入并施加同一补丁，得到的 OBU 与 `.reference.yuv` 与仓库提交的 `inter_cdf_inherit_64x64` **逐字节相同**（`cmp` 一致）。第 8 节“生成器路径仍是原机器路径”的限制由此解除。

**关键结论一：该 fixture 的 inter 帧不是用继承 CDF 编码的。** [patch_header_fields](scripts/generate-av1-inter-reference.py) 的注释已说明 `primary_ref_frame` 对两帧流恒为 7（PRIMARY_REF_NONE）；`inter_cdf_inherit_64x64` 只是把帧头里这 3 位从 7 改成 0。实测 dav1d 1.2.1 解同一条 OBU：开补丁与不开补丁的第 1 帧有 **3996/6144** 个样本不同（全部在 luma，色度完全一致）——即“继承解码”在这条流上本来就会解出另一张图。因此本样本的验收含义是**逐符号复现 dav1d 的继承解码**，而不是复现“编码器意图”。

**关键结论二：`symbol_max_bits >= -14` 守卫是最小样本的唯一阻塞。** 用参数化 fixture 生成器（可调 luma 锯齿幅度、色度周期、色度帧间相位，均用同一 `MINIMAL_FLAGS` + 同一 `primary_ref_frame` 补丁，golden 取 dav1d 对**开补丁**码流的解码）系统测试，在**继承开启**下：

| 输入 | 结果 |
| --- | --- |
| 关键帧全平 + inter 帧带图案 | `[0,0,0]` |
| 关键帧全平 + inter 帧与关键帧相同（49 字节 OBU） | `[0,0,0]` |
| `shift`（正弦平移） | `[0,0,0]` |
| 平滑 luma + 周期 5/7 色度纹理 | `[0,0,0]` |
| 锯齿 luma + 平滑色度 | `[0,0,0]` |
| 锯齿 luma + 周期 2/4/5/6/7 色度纹理 | `[0,0,0]` |
| 锯齿 luma + **周期 3** 色度纹理 | `[0, 504, 0]` |
| 仓库 `ramp` fixture（即 `inter_cdf_inherit_64x64`） | `[4029, 464, 708]` |

这些 `[0,0,0]` 都是在**把 `av1_coeff_decode.mbt` / `av1_intra_tile.mbt` / `av1_palette.mbt` / `av1_palette_index.mbt` / `av1_inter_tile.mbt` / `av1_inter_mode.mbt` 里的 `symbol_max_bits < -14` 与 `av1_inter_tile.mbt` / `av1_cfl.mbt` / `av1_intra_tile.mbt` / `av1_partition_tree.mbt` 里的 `symbol_max_bits >= -14` 全部换成 `true`** 之后取得的；守卫恢复后同一批样本全部回到拒绝/错误。该守卫来自规范 §8.2 `exit_symbol` 的**位流一致性要求**（"It is a requirement of bitstream conformance that SymbolMaxBits is greater than or equal to -14"），dav1d **不执行**这个检查；本解码器把它当安全网。周期 3 与 ramp 两个失败样本的 inter 帧 tile payload 分别只有 23 与 11 字节，继承解码会分别越读到 `max_bits ≈ -122` 与 `-1046`，因此**不放开这个守卫就无法闭合**。放开后有 3 个既有测试依赖它拒绝截断输入（`av1_transform_tree.mbt` "transform tree coefficient walk rejects truncated entropy"、`av1_palette_colors_wbtest.mbt` "palette colors truncated long palette rejects entropy padding overflow"、`av1_cdef_alpha_gate_wbtest.mbt` "alpha rejects missing CDEF index entropy even with zero-strength tables"），需要用别的不变量（例如符号数上界）替代，不能简单删除。

**关键结论二附带验证：MSAC 越读补位与 dav1d 等价。** 规范公式 `paddedData = newData << (bits - numBits)`（numBits=0 时补 0）与 dav1d `ctx_norm` 的 `((dif + 1) << d) - 1`（在 dif 表示下补 1）在 `dif ≈ ~SymbolValue` 的对应关系下逐位一致；已用 Python 独立复算四个临界符号的 (range, value) 转移，与本解码器完全一致。**因此越读补位不是分歧源，符号数/状态才是。**

**关键结论三：CDF 继承与适配机制本身正确。** 对周期 3 失败样本做了符号级取证（临时插桩记录每个符号的 range/value/bit_pos/max_bits + 完整 CDF 行 + 解出值，并在 `av1_intra_transform` 里记录块结构 plane/tx/bw/skip/txctx/skipctx/all_zero 与所用 txb_skip 行）：

- 关键帧结构：一个 64x64 块（partition NONE，tx_depth=1）→ 4 个 32x32 luma 叶（all_zero = 0,0,1,1）+ 2 个 32x32 色度叶（all_zero = 0,0）。
- inter 帧结构：partition VERT → 两个 32x64 块。块1 luma all_zero=0、U/V all_zero=1；块2 luma all_zero=1、**U all_zero=0（分歧点）**、V all_zero=1。dav1d 的开补丁输出经核对：**U/V 与关键帧完全相同（无色度残差），luma 有残差**——即块2 的 U 也应是 all_zero=1。
- 分歧符号的定量：块2 U 的 txb_skip 读处状态 `(r=45196, v=35343)`、行 `[7800, 32768, 4]`，`cur(0)=34324`，故 `v ≥ cur(0)` 解出 0；要解出 1 需 `v < 34324`（差 1019）或行首 ≤ 7040（差 760）。
- **行值已验证正确**：`[7800,32768,4]` = `av1_txb_skip_cdf[1][3][7]`（默认 5583）先由关键帧两次色度读（符号 0,0）适配成 `[8874,...,2]`，再由 inter 帧块1 的 U/V 两次读（符号 1,1）适配成 `[8320,...,3]`、`[7800,...,4]`——逐步手算与轨迹逐值一致。qctx 两侧均为 1。
- 因此分歧只能是**该读之前的 MSAC 状态**，而状态由 inter 帧此前全部符号决定；这些符号里带继承行的有 partition、skip、eob_pt、base ctx21 若干、色度 txb_skip。**根因收敛到关键帧色度系数段存在与 dav1d 不同但不改变像素的符号**（周期 3 纹理 → 每块约 276 个 base 符号、绝大多数为 0，任一位置取不同值都会改变后续状态）。

**本轮同时确认**：`av1_partition_cdfs_of` 每次解码都经 `av1_partition_cdf_state()` 新建状态，不存在跨解码的全局 CDF 污染（早前看似污染的现象实为轨迹数组跨测试累积 + 过滤条件误取 payload 尾部所致）；用 `moon test --target js <单文件>` 可取得干净进程。

**下一步入口（阶段 B）**：(a) 用周期 3 色度的最小样本继续向前定位——把关键帧色度段的每个符号与“黄金约束”（inter 帧块2 U 必须解出 1）做区间求解，第一个使状态越过 34324 的符号即根因；(b) 替换 `-14` 守卫为不依赖越读的安全不变量并同步那 3 个测试；(c) 若需要 dav1d 符号级真值，可用 dav1d 1.2.1 源码（`decodeb.c`/`recon_tmpl.c`/`msac.c`/`tables.c`/`cdf.h` 已在本机）中的 `DEBUG_BLOCK_INFO` 插桩思路指导 Python 侧建模。闭合阶段 B 时把 [av1_inter_reference_wbtest.mbt](av1_inter_reference_wbtest.mbt) 的 `assert_eq(bad, [3992, 842, 928])` 改为 `[0, 0, 0]` 并保留原 OBU 与真值。

下一阶段入口：阶段 B 的可构造假设空间已穷尽（见第五、六次推进）。若要继续闭合，需要 (a) MSAC 状态级取证工具，或 (b) 用 aomenc+dav1d 生成一个更小的、inter 帧自然继承（或补丁后继承）的样本把问题隔离到少数符号；否则应把本节作为阶段 B 的已知边界记录，转入第 6 节阶段 C/D 的独立工作。闭合阶段 B 时把 [av1_inter_reference_wbtest.mbt](av1_inter_reference_wbtest.mbt) 的 `assert_eq(bad, [3992, 842, 928])` 改为 `[0, 0, 0]` 并保留原 OBU 与真值。

### 第十二次推进（2026-09-21）：用 dav1d 1.2.1 源码逐字移植 MSAC 并对拍 1600 万个符号，证明算术/补位/适配速率均无误；分歧精确定位到 inter 帧最后一个 32x16 色度叶，且所有继承 CDF 行链手算自洽

**关键结论一：MSAC 核心算法与 dav1d 逐位一致（本机已有 dav1d 1.2.1 源码 `msac.h`/`msac.c`）。** 用 Python 逐字移植 `dav1d_msac_init` / `ctx_refill` / `ctx_norm` / `dav1d_msac_decode_symbol_adapt_c` / `dav1d_msac_decode_bool_equi_c`（脚本 `/tmp/mbrepro/davmsac3.py`），与 [av1_msac.mbt](av1_msac.mbt) 的模型对拍：

- 4000 条随机流（CDF 符号数 1/2/3/4/5/8/10，payload 取 1/2/3/23 字节以强制深度越读）× 每条 4000 符号 = **16,000,000 个符号，零分歧**，含 `buf_end` 之后的越读补位全程。
- 因此 `symbol` / `renorm` / `read_bits` / 越读补位与 dav1d **完全一致**，第十一次推进"补位不是分歧源"的结论由此从"四个临界符号手算"升级为"全路径对拍"。
- **适配速率公式也完全等价**：本实现 `3 + (count>15) + (count>31) + min(floor(log2 n),2)` 与 dav1d `4 + (count>>4) + (n_symbols>2)` 对所有字母表大小逐一相等——dav1d 的 `n_symbols` 比本实现的 CDF 行符号数少 1（其默认表用 `CDF1(x)=32768-x` 补码存储，恒为 0 的末项不占位）。曾按字面把 dav1d 公式直接代入 `av1_msac_update_cdf`，结果 **253 个测试失败、关键帧也从 `[0,0,0]` 变成 `[3035,733,723]`**，反证原公式正确，已回退。
- ⇒ 根因**不在**算术、越读补位、适配速率这三处。

**关键结论二：仓库里两处上次遗留的死插桩已清除，行尾残留已修复。** [av1_msac.mbt](av1_msac.mbt)（HEAD 为 LF）在工作区曾是 CRLF、[av1_coeff_decode.mbt](av1_coeff_decode.mbt) 同样残留 CRLF，导致 `git diff --check` 失败；两者已转回 LF。同时移除了上次遗留但未回退的 `av1_msac_trace`/`av1_msac_trace_on` 死全局与 `av1_coeff_dump`/`av1_coeff_dump_on` 死插桩。现在 `git status` 回到预期的 **20 个修改 + 2 个未跟踪**（`HANDOFF.md`、`av1_frame_cdfs.mbt`），`git diff --check` 通过。

**关键结论三：周期 3 样本在"守卫放开 + 继承开启"下的真实结果是 `[0, 488, 0]`。** 即 **Y 全对（4096/4096）、V 全对（1024/1024）、只有 U 平面错 488/1024**（第十一次推进记录的 `[0,504,0]` 来自略有不同的守卫替换文件集，差异仅在此）。U 平面第一个错误样本在 index 512 = **第 16 行第 0 列**，第 0–15 行全对、第 16–31 行全错。

**关键结论四：分歧精确定位到 inter 帧的最后一个块——32x16 色度（U）变换叶。** 打开系数级 trace 后（临时插桩记录每个 eob/base/br/sign 读前的 range/value/max_bits 与完整 CDF 行，见下方复现配方）：

| 帧 | 带残差的叶 |
| --- | --- |
| 关键帧 | 2 × 32x32 luma（eob 55 / 28，方形，area 1024）+ 2 × 32x16 色度（eob 248 / 248，矩形，area 512） |
| inter 帧 | 2 × 32x32 luma（eob 55 / 28）+ 2 × 64x32 luma（eob 9 / 164）+ **1 × 32x16 色度（eob 245）** |

inter 帧的色度 V 叶 `all_zero=1`（只读 1 个符号），色度 U 叶是**整帧最后一个带残差的读**，因此它之后的任何污染都不可能发生——分歧就在这个叶内部或它之前的状态。该叶正好覆盖 U 平面第 16–31 行，与"第 16 行起全错"完全吻合。

**关键结论五：所有继承来的色度 CDF 行链都已用 dav1d 的 `update_cdf` 逐步手算验证自洽。** 以 dav1d 1.2.1 源码的更新规则复算，三个关键行从默认值到 inter 帧读取时的值逐项相等：

- `eob512`（area 512 专用，10 符号行）：默认 `[7265,9979,15819,19250,21780,23846,26478,28396,31811,32768,0]` →(符号 8, rate 5)→ `[7038,9668,15325,18649,21100,23101,25651,27509,31840,32768,1]` →(符号 8)→ `[6819,9366,14847,18067,20441,22380,24850,26650,31869,32768,2]`。
- `extra`：`[20297,32768,0]` →(符号 1)→ `[19029,32768,1]` →(符号 1)→ `[17840,32768,2]`。
- `base_eob`：`[29657,31087,32768,0]` →(符号 1)→ `[27804,31192,32768,1]` →(符号 1)→ `[26067,31290,32768,2]`。
- `base` 行计数饱和到 32，链同样一致。
- 另外，关键帧两个色度叶的 `(扫描序号 c, 位置 p, 上下文 x)` 序列 **248 项逐一完全相同**——强自洽信号，说明扫描表与 ctx 模型在该尺寸上稳定。

⇒ 只要关键帧读到的**符号序列**与 dav1d 相同，继承行就是对的。因此根因只能是：**某个不改变像素的符号读取与 dav1d 不同**，它改变了 (a) MSAC 状态，或 (b) 被适配的那一行。头号嫌疑是 `eob` 类符号（eob 只决定读多少个"尾部 0"，多看少看都不改像素，但会改变状态与被适配的行）。

**本轮复现配方（下次可直接用）**：

```bash
cd /c/Users/谦友Lee/Desktop/Project/mb/pixelforge
# 1) 放开越读守卫（8 个文件；备份在 /tmp/mbrepro/guard_bak/）
sed -i 's/decoder\.symbol_max_bits < -14/decoder.symbol_max_bits < -1000000/g; s/decoder\.symbol_max_bits >= -14/decoder.symbol_max_bits >= -1000000/g' \
  av1_coeff_decode.mbt av1_intra_tile.mbt av1_inter_tile.mbt av1_cfl.mbt \
  av1_partition_tree.mbt av1_palette.mbt av1_palette_index.mbt av1_restoration_entropy.mbt
# 2) 打开继承开关：av1_frame_cdfs.mbt 的 av1_cdf_load_enabled = true
# 3) 重新生成最小样本（会写 zz_repro_wbtest.mbt）：
cd /tmp/mbrepro && REPRO_DIR="$(cygpath -w /tmp/mbrepro)" \
  REPO="$(cygpath -w /c/Users/谦友Lee/Desktop/Project/mb/pixelforge)" \
  /d/ProgramData/anaconda3/python pipe6.py 0 3 0
# 4) 在 pixelforge 里 moon test --target js，看 KEYBAD / INTERBAD
```

注意：用 Python 写 `.mbt` 会引入 CRLF，跑完必须 `tr -d '\r'` 转回 LF，否则 `git diff --check` 失败（本轮已踩过两次）。已验证的 dav1d MSAC 对拍脚本在 `/tmp/mbrepro/davmsac3.py`，改动 MSAC 公式后应先跑它回归。

**下一步入口（阶段 B）**：(a) **强制符号实验**——在 inter 帧色度叶的 `eob512` 读处（状态 `r=51012, v=2051`，行 `[6819,9366,14847,18067,20441,22380,24850,26650,31869,32768,2]`）把解出符号强制为 0..9 各跑一次（在 `Av1SymbolDecoder::symbol` 里按该 (range, value, 行长, 行首) 指纹识别并在命中时跳过 break），看哪个值能让 U 平面对齐；无一命中则说明状态已对、问题在该叶内部更晚的读，再沿 245 个 base 读二分。(b) 同一手法向前推到关键帧：关键帧两个色度叶的 eob 都是 248，若 dav1d 的 eob 不同，继承行就会错——可对关键帧色度叶的 `eob`/`extra`/bool 读做同样的强制实验。(c) 替换 `-14` 守卫为符号数上界等不变量并同步那 3 个既有测试（放开后实测有 4 个测试失败：`av1_transform_tree.mbt`、`av1_restoration_entropy_wbtest.mbt`、`av1_palette_colors_wbtest.mbt`、`av1_cdef_alpha_gate_wbtest.mbt`）。闭合阶段 B 时把 [av1_inter_reference_wbtest.mbt](av1_inter_reference_wbtest.mbt) 的 `assert_eq(bad, [3992, 842, 928])` 改为 `[0, 0, 0]` 并保留原 OBU 与真值。

### 第十三次推进（2026-09-21）：强制符号实验证明分歧在色度叶**之前**（进入该叶的 MSAC 状态是错的）；inter 帧 luma 叶复现关键帧符号序列，继承行确认正确

**关键结论一：对色度叶 `eob512` 读做强制符号扫描，证明分歧点在该读之前。** 在 `Av1SymbolDecoder::symbol` 里按 (range=51012, value=2051, 行长 11, 行首 6819) 指纹识别 inter 帧色度叶的 `eob512` 读，把解出符号强制为 0..9 各跑一次，U 平面错误数为：

| 强制符号 | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | **8（自然值）** | 9 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| U 错误数 | 510 | 507 | 504 | 504 | 507 | 512 | 504 | 505 | **488** | 479 |

没有任何一个值能归零，且自然值 8 并不突出。结合第十二次推进已证明 `eob512` 行值链正确，可得：**该读本身不是分歧点，进入色度叶的 MSAC 状态与 dav1d 不同**。因为色度叶是 inter 帧最后一个带残差的读（其后只有 V 叶的 1 个 `all_zero`），分歧只能在它之前的全部符号里。

**关键结论二：色度叶内部、`eob512` 读与第一个系数读之间只有 1 个 `extra` 符号 + 6 个 eob 细化 bool。** 给 `Av1SymbolDecoder::bool` 加trace 后实测这 6 个 bool 的状态为 `(58490,10479)`、`(58376,20959)`、`(58376,41919)`、`(58376,25463)`、`(58376,50927)`、`(58376,43479)`（`max_bits` 从 -357 到 -362），随后即 `beob` 读（`m=-363`）。它们是叶内仅有的中间读，且同样处于错误状态的下游。

**关键结论三：inter 帧的 luma 叶 1、2 几乎逐符号复现关键帧的 luma 叶 1、2。** 两者都是 32x32、`eob` 55 与 28；把 `(扫描序号 c, 位置 p, 上下文 x, 值 v)` 四元组序列逐一对比，55 个系数中 54 个完全相同，**只有 DC 不同（关键帧 15、inter 帧 11）**。这正是 CDF 继承的预期效果（继承行被关键帧的符号适配过，因而倾向于复现它们），同时说明**继承到的 luma 行是对的**、inter 帧 luma 解码在符号级是稳定的。

**关键结论四：luma 与色度的系数 CDF 表确实是分离的。** [av1_intra_tile.mbt](av1_intra_tile.mbt):442-446 按 `plane_index` 选 `state.y_coeff` / `state.uv_coeff`，两者是独立实例；用每叶的 `signdc` 行计数（关键帧 4 叶分别为 0,0,0,1；inter 帧 5 叶为 1,1,2,2,2）与 `base[3][22]` 默认值差异（色度默认 `[23913,31724,32489,32768,0]`，inter 帧 luma 叶 1 看到 `[20400,28042,31658,32768,8]`）双向确认没有串表。

**关键结论五：`base`/`base_eob` 行链在"不触发 `br` 读"的子集上零失配。** 用 Python 按 `(tag, ctx)` 分别跟踪每个 CDF 行并复算适配，所有观测行值与模拟一致（注意：分析时若把 `base`/`br` 两个 tag 行与同一个 `tx` 行错配会得到假失配，必须按"tag 行后紧跟的 tx 行"配对，且 `value>2` 时会多出一个 `br` 行）。

**本轮插桩与复现配方**：force 机制是 `av1_msac.mbt` 里的 `av1_msac_force_on/av1_msac_force_val` 两个全局加 `symbol()` 内按指纹跳过 break；bool trace 是 `av1_msac_bool_trace/av1_msac_bool_trace_on`。样本仍用 `pipe6.py 0 3 0`，守卫放开与继承开启的配方同第十二次推进。本轮已全部回退，`git status` 回到 20 改 + 2 未跟踪，三目标 1186/1186、`build-web --check`、`verify-wasm.mjs` 全绿。

**下一步入口（阶段 B）**：分歧在**进入色度叶之前的状态**，而 Y 平面像素全对，因此嫌疑人是一个**不改变像素的读**——头号仍是 inter 帧 4 个 luma 叶的 `eob`（多看少看尾部 0 都不改像素，但改变状态与被适配的行）。具体做法：(a) 给 `symbol()` 加一个"符号计数器"强制（第 N 次 `symbol()` 调用时强制取值），从 inter 帧第一个符号起对半二分，第一次能让 U 平面归零的强制位置即根因；(b) 或直接对 4 个 luma 叶的 `eob` 读（指纹 = 各自的 (range, value, 行长, 行首)，可从 trace 取）逐个强制为相邻 `eob_pt`；(c) 同时准备用符号数上界替换 `-14` 越读守卫（放开后实测 4 个既有测试失败）。闭合阶段 B 时把 [av1_inter_reference_wbtest.mbt](av1_inter_reference_wbtest.mbt) 的 `assert_eq(bad, [3992, 842, 928])` 改为 `[0, 0, 0]` 并保留原 OBU 与真值。

**第十三次推进补充：inter 帧 luma 叶 1 的 DC 读链已逐符号复算，是下一个具体疑点。** 四个 luma 叶的 DC（`c=0, p=0`）值为：关键帧叶1 **15**、关键帧叶2 **15**、inter 帧叶1 **11**、inter 帧叶2 **15**、inter 帧叶3（txctx=4）**1**、inter 帧叶4（txctx=4）**3**。inter 帧叶1 与关键帧叶1 的 `(c,p,ctx,value)` 序列 54/55 相同，**唯一差别就是这个 DC**，其读链为：

- 关键帧叶1：`base[3][0]` = `[3078,6839,9890,32768,0]`（默认，count 0）解出符号 3 → 值 3；随后 4 次 `br[3][0]`（count 0→1→2→3，行 `[1057,2137,3212,32768]` → `[1024,2071,3112,32768]` → `[992,2007,3015,32768]` → `[961,1945,2921,32768]`）各解出符号 3 → 值 3+3+3+3+3 = **15**。
- inter 帧叶1：`base[3][0]` = `[2889,6419,9282,32768,2]`（继承，count 2）→ 值 3；随后 3 次 `br[3][0]`（count 4→5→6，行 `[931,1885,2830,32768]` → `[902,1827,2742,32768]` → `[874,1770,2657,32768]`）解出 3,3,2 → 值 3+3+3+2 = **11**。

两条链各自自洽（`br[3][0]` 的 count 由关键帧两个 luma 叶各 2 次累积到 4，与 inter 帧叶1 首次观测到的 count 4 一致）。**注意：DC 值 11 与 15 属于不同块的不同残差，本身不一定错；但它是 inter 帧符号序列中第一个偏离关键帧序列的位置，且 DC 读会改变后续全部状态，因此是"强制实验"最便宜的切入点**——对该读链的 `base`/`br` 逐个强制为相邻符号（共 1+4 次读、每次最多 4 个取值），看哪个组合能让 U 平面归零。

**第十三次推进补充二：DC 读链强制实验未生效，原因是白盒测试里的全局赋值对库内 `symbol()` 不可见。** 用 `av1_msac_force_idx` / `av1_msac_force_val` / `av1_msac_force_fp`（指纹 `[50164,27724,2889]` 等 5 个 DC 读链状态）做 5×4 = 20 组强制，U 平面错误数全部等于 488（与不强制完全相同）；在 `symbol()` 里加探针打印确认：DC 读处状态确实是 `r=50164 v=27724 cdf0=2889`（共出现 22 次），但每次读到的 `av1_msac_force_idx[0]` 都是 **-1**，即测试里的 `av1_msac_force_idx[0] = fi` 没有写进库内看到的那份全局。第十二次推进的 `eob512` 强制实验（用 `av1_msac_force_on`）是生效的，两者差异待查——**下次做强制实验时优先复用一个已验证可生效的全局对（如 `av1_msac_force_on`/`av1_msac_force_val` 形式），或把强制值改成编译期常量逐个重建**。DC 读链的两条自洽演算（关键帧叶1 → 15、inter 帧叶1 → 11）仍然有效，疑点本身未变。

**第十三次推进补充三（重要更正）：白盒测试里对包级 `let` 全局的赋值，在本机构型下对库内函数不可见——此前所有"强制符号"实验的结论都需重新审视。** 用 `av1_msac_dc_on`/`av1_msac_dc_val` 这对全局加内联指纹 `(r=50164, v=27724, 行长 5, 行首 2889)` 复做 DC 读链强制（k=0..3），U 平面错误数仍全部为 488；在 `symbol()` 内加探针打印后确认：**该状态确实被命中 5 次、`cdf.length()==5`、`cdf[0]==2889` 全部吻合，但每次读到的 `av1_msac_dc_on[0]` 都是 0**，而测试里明明在 inter 解码前执行了 `av1_msac_dc_on[0] = 1`。即测试写的是一份全局、库内读的是另一份。

由此推论：**第十二/十三次推进里"对色度叶 `eob512` 读强制符号 0..9 得到 510/507/504/504/507/512/504/505/488/479"这组数据不能证明强制生效**——那组读数差异很可能来自同一测试内多次调用 `av1_decode_frame_planes` 之间的跨调用状态（每次迭代新建 `av1_frame_map`，但库内可能存在未重置的全局 CDF/状态），而不是强制改变了符号。**因此"分歧在色度叶 `eob512` 读之前"这一结论目前证据不足，应予挂起。**

**下一步必须换成不依赖白盒全局传值的强制手段**：(a) 把强制值与指纹写成编译期常量，逐个改、逐个 `moon test --target js` 跑（每次只测一个值，虽慢但可靠）；(b) 或在库里加一个只写的"强制槽"函数（如 `fn av1_msac_set_force(...)`）由测试调用，看函数调用是否比直接全局赋值更可靠；(c) 先做一个对照实验确认跨调用状态是否存在：同一个测试里连续两次不做任何强制地解码同一 inter 帧，比较两次 U 错误数是否相同——若不同，则此前的扫描数据全部作废，需改用 (a)。

**第十三次推进补充四：白盒全局传值通道确认不可用，所有强制符号实验结论全部挂起。** 换用此前"生效过"的同一对全局名 `av1_msac_force_on`/`av1_msac_force_val` 加 DC 指纹 `(r=50164, v=27724, 行长 5, 行首 2889)` 重做（k=0..3），U 平面错误数仍全部 488，且强制分支内的 `DCHIT` 打印一次都没出现；而上一轮探针已证明该指纹状态确实被命中 5 次、`cdf.length()==5`、`cdf[0]==2889` 全吻合。两者合起来只能得出一个结论：**白盒测试里对包级 `let` 数组的赋值，库内 `symbol()` 读不到**。

同时，DCV2/DCV3 两组扫描各 4 次迭代结果完全一致（全 488），说明**同一测试内多次调用 `av1_decode_frame_planes` 之间没有跨调用状态污染**——因此第十二次推进那组 `eob512` 强制扫描的 10 个不同读数（510/507/504/504/507/512/504/505/488/479）**不是跨调用状态造成的**，只能是该指纹在别处（很可能是关键帧某次 `eob512` 读）命中并改变了关键帧解码，进而改变继承行。**所以"分歧在色度叶 `eob512` 读之前"这个结论既不成立也无法否证，必须挂起，回到 trace 级证据。**

**当前唯一可靠的定位手段是 trace（不依赖强制）**：把 `av1_coeff_decode.mbt` 的系数级 trace 与 `av1_msac.mbt` 的 bool trace 重新打开，取"守卫放开 + 继承开启"下周期 3 样本的完整符号流，然后：(a) 用 Python 按 dav1d 规则独立重放整条 inter 帧符号流，检查每个 CDF 行的观测值是否与模拟一致（此法已证明 `eob512`/`extra`/`base_eob`/`base` 链自洽，可推广到全部行）；(b) 对每个"像素中性"候选读（各叶 `eob` 及其 extra/bool 细化）统计"若 dav1d 取相邻值，U 平面错误数会如何变化"的区间，需要先把 dav1d 的符号真值拿到——**最直接的下一步是用 dav1d 1.2.1 源码里的 `DEBUG_BLOCK_INFO`/`vlog` 思路自建一个符号级 trace 的 dav1d，或用 `aomdec`（libaom 解码器）交叉验证：若 libaom 与 dav1d 对该补丁流输出一致，则可用 libaom 的 `aom_codec_control` + `--enable-accounting` 构建拿到符号计数真值**。

**第十三次推进补充五（能力突破）：不需要全局传值即可拿到 inter 帧的完整符号流——在 `Av1SymbolDecoder::symbol` 里无条件 `println` 并按 `self.data.length()` 过滤即可。** 此前一直以为必须靠白盒全局给库里"下指令"，这条路被证不可用；但** trace 是库内主动输出，完全不依赖全局**。已在周期 3 样本（守卫放开 + 继承开启）取得 **inter 帧全部 1172 个符号**的 `(range, value, max_bits, 符号数 n, 完整 CDF 行)`，存档在 `/tmp/mbrepro/full_inter_saved.txt`。符号数分布：`n=4` 898 个（`coeff_base`）、`n=2` 250 个（bool/`extra`/`all_zero`）、`n=3` 8 个、`n=11` 6 个（`eob512`）、`n=13` 4 个（uv mode）、`n=10` 4 个（partition）、`n=7` 2 个。**这覆盖了此前缺失的块级符号（partition/skip/all_zero/uv_mode 等），使"用 Python 按 dav1d 规则独立重放整条 inter 帧符号流"第一次成为可能。**

复现配方：在 `Av1SymbolDecoder::symbol` 开头加 `if self.data.length() <= 40 { ... push("S r=.. v=.. m=.. n=.. cdf=[..]") }`（inter 帧 tile payload 约 23 字节，关键帧约 60+，用长度过滤即可只取 inter 帧），测试里遍历 `av1_msac_full_trace` 打印。配合已归档的 `/tmp/mbrepro/trace2.txt`（系数级 trace，含每叶 side/height/tx_ctx/eob/area/rect）与 `/tmp/mbrepro/davmsac3.py`（已验证的 dav1d MSAC 移植），下一步应：(a) 用 Python 重放这 1172 个符号，按 (n, CDF 行) 建立行身份并逐步复算适配，找出**观测行与模拟行不一致的第一个读**——那就是我们与 dav1d 分歧位置的直接证据（若全部一致，则说明我们自身自洽而差异在行选择/上下文，需把 trace 扩展到记录每次读所用 CDF 的表名与索引）；(b) 对每个"像素中性"候选（4 个 partition、各叶 `eob` 及 extra/bool 细化、`all_zero`）统计其相邻取值的敏感性。

**第十三次推进补充六：inter 帧 1172 个符号的 Python 重放结果——323 个不同 CDF 行、零歧义匹配，行身份完全可由行值唯一确定。** 重放方法：对每个读按 dav1d 规则解出符号，再按 `3+(count>15)+(count>31)+min(⌊log2n⌋,2)` 速率复算适配；用"当前行值集合"做行身份匹配。结果：`reads=1172, distinct_rows=323, unique_matches=849, new_rows=323, ambiguous=0`，其中只有 9 个行的计数器饱和（≥32）。

**零歧义意味着行追踪可靠，因此可以做一个决定性检查**：323 个"首次出现"的行里，计数器为 0 的是默认行，计数器 > 0 的是从关键帧继承来的行 —— **每一个继承行的首观测值都必须等于关键帧对应行的终值**。这正是快照捕获/恢复是否逐行正确的直接检验，且完全不需要 dav1d 符号真值。做法：把同一段 `symbol()` trace 的过滤条件改成关键帧的 payload 长度，再取一份关键帧全符号 trace，然后在 Python 里对两个文件各自跑上面的重放，最后比对"inter 帧每个计数 >0 的首现行 ⊆ 关键帧终行集合"。**若出现某个继承行在关键帧终行集合里找不到，即定位到快照捕获/恢复漏了或错取了某一行**——这是比继续找符号差异更可能是根因的地方（此前只手算验证了 `eob512`/`extra`/`base_eob`/`base` 四类链，未覆盖全部 323 行，尤其未覆盖块级符号所用的 partition/skip/uv_mode 等行）。

复现命令：`/d/ProgramData/anaconda3/python` 跑上面的重放脚本（输入 `/tmp/mbrepro/full_inter_saved.txt`，格式 `S r=.. v=.. m=.. n=.. cdf=[..]`）。

**第十三次推进补充七（决定性否证）：快照的捕获/恢复逐行正确——inter 帧全部 37 个"继承行"首观测值与关键帧终行完全一致。** 用同一段 `symbol()` trace 同时取关键帧（tile payload 50 字节，1722 个符号）与 inter 帧（3 字节，1172 个符号）两份全符号流（存档 `/tmp/mbrepro/both.txt`），各自按 dav1d 规则重放并追踪 CDF 行：关键帧 310 行、inter 帧 323 行；inter 帧首次出现且计数器 >0 的行共 **37** 个（即从关键帧继承来的行），逐行比对关键帧终行集合，**缺失 0 个**。

由此，阶段 B 的剩余分歧**不在**快照机制（捕获/恢复/行序/行数全部正确），**不在** MSAC 算术与补位（1600 万符号对拍零分歧），**不在** 适配速率（公式等价已证），**不在** 行身份追踪（零歧义）。剩下的唯一可能是：**在某个读上我们解出的符号与 dav1d 不同，而该读所用的 CDF 行本身是对的**——由于 Y 平面像素全对，这个符号差异必须发生在不改变像素的位置（块级符号的某个取值、或某个被 clip/round 吸收的系数值、或某个只影响"读多少个尾部 0"的 `eob` 细化）。要定位它必须取得 dav1d 的符号真值，可行方向：(a) 用 dav1d 1.2.1 源码自建一个带 `msac` 符号 trace 的解码器（本机已有 `msac.c`/`msac.h`/`cdf.c`，在 `C:\Users\谦友Lee\AppData\Local\Temp\`）；(b) 用 libaom `aomdec.exe` 交叉验证该补丁流输出是否与 dav1d 一致，若一致则借 libaom 的 accounting/`aom_codec_control` 取符号计数；(c) 在 Python 侧按 `both.txt` 的读序完整重放，对每个读枚举"若取相邻符号"的后果，结合 U 平面必须归零的约束反解。

**第十三次推进补充八（最强线索）：关键帧 read#57 的判决余量只有 4——全帧最小的"刀刃读"。** 对 `/tmp/mbrepro/both.txt` 里关键帧 1722 个读逐个计算"判决余量"（解出符号对应的阈值与 `v` 的距离，取上下两侧较小者），最小的 15 个如下（余量 <500 的共 72 个，<100 的共 20 个）：

| read# | n | max_bits | 解出符号 | **余量** |
| ---: | ---: | ---: | ---: | ---: |
| **57** | 4 | 329 | 0 | **4** |
| **918** | 4 | 329 | 0 | **4** |
| 58 | 4 | 328 | 3 | 9 |
| 919 | 4 | 328 | 3 | 9 |
| 0 | 10 | 385 | 5 | 23 |
| 861 | 10 | 385 | 5 | 23 |
| 59 | 4 | 326 | 3 | 36 |
| 920 | 4 | 326 | 3 | 36 |
| 65 | 4 | 315 | 0 | 40 |
| 926 | 4 | 315 | 0 | 40 |

read#57 的状态：`r=58177 v=35087 m=329 n=4 cdf=[12937,26854,30870,32768,0]`（**计数器 0，即该行首次使用，是默认行**）。手算：`cur(0)=((58177>>8)*(25440>>6))>>1 + 4*3 = (227*309)>>1+12 = 35083`，而 `v=35087`，故 `v ≥ cur(0)` 解出符号 0，**余量 35087−35083 = 4**。只要 `v` 比现在小 4（或该行首项比现在大 4），符号就会从 0 翻到 1。

read#918 与 #57 完全同型（关键帧第二个色度叶的对应位置），#58/#59 与 #918/#919 亦成对出现——符合关键帧两个色度叶结构相同的事实。

**这就是当前最具体的怀疑点**：若 dav1d 在该处的 `v` 与我们相差 ≥4（差异来自更早的某个像素中性读），符号 0→1 会改变该系数的取值，但只要去量化后的差值被 clip/round 吸收，关键帧像素不变，而**该行此后的适配轨迹、以及继承给 inter 帧的行值都会改变**，最终表现为 inter 帧色度叶解出不同的残差。下一步：(a) 确认 read#57/#58/#59 对应的系数位置与像素影响（对照 `/tmp/mbrepro/trace2.txt` 里同 `m` 值的系数记录）；(b) 若能取得 dav1d 在 read#57 处的符号真值，即可直接判定；(c) 把"余量"分析推广到 inter 帧 1172 个读，找出 inter 帧内余量最小的读，与关键帧的结果交叉。

**第十三次推进补充九（对 read#57 的否证）：read#57 不是分歧点。** 用 `/tmp/mbrepro/trace2.txt` 按 `max_bits` 对齐，确认 read#57（`r=58177 v=35087 m=329 cdf=[12937,26854,30870,32768,0]`，符号 0，余量 4）对应关键帧 luma 叶1 的系数读 **`tx3 h32 c10 p128 x23 v0`**（扫描序号 10、位置 128、上下文 23、值 0）。若该处符号翻成 1，系数值会变成 1，即在扫描位置 128 引入一个非零 AC 系数。而同一叶里 `tx3 h32 c1 p1 x3 v1` 已经是一个值为 1 的系数且关键帧像素完全正确，说明**值为 1 的 AC 系数确实会改变输出像素**。因此：若 dav1d 在 read#57 解出 1，关键帧像素就会与我们不同 —— 但关键帧是逐样本精确的，故 **dav1d 在该处也解出 0，read#57 不是分歧点**。

由此得到更精确的筛选准则：分歧点必须同时满足 (i) **判决余量小**（状态差一点就能翻转），且 (ii) **翻转后不改变像素**。(ii) 的候选只有三类：系数读但其去量化值为 0 或被反变换+取整吸收、`eob` 的 extra/bool 细化（只改变读多少个尾部 0）、块级符号中不影响预测/残差的取值。下一步应把"余量"分析与"像素中性"判据合起来用：对关键帧 1722 个读，先按 (ii) 过滤，再在剩余集合里找最小余量。系数读的像素中性可由"该叶非零系数集合"直接判定——若某叶在我们解码下非零系数很少（如关键帧两个色度叶各只有 4 个非零：DC=4 与 pos 22/21/20 各 1），则该叶大量值为 0 的系数读都满足 (ii)，其中余量最小的就是头号嫌疑（关键帧色度叶的对应读见 read#918/919/920，与 luma 叶的 #57/58/59 同型但位于色度叶）。

**第十三次推进补充十（inter 帧最强嫌疑）：inter 帧系数读里余量最小的"值为 0"读是 `base r=60685 v=35630 c=10 val=0`，余量仅 68。** 对 `trace2.txt` 的 inter 帧区（第 1224–2398 行）做同样的余量分析：501 个系数读中 397 个值为 0；值为 0 的读里余量最小的 8 个是 `c=10`(68)、`c=6`(225)、`c=111`(230)、`c=122`(238)、`c=6`(261)、`c=92`(262)、`c=21`(428)、`c=43`(462)；非零读的余量都 ≥165（最小 `c=91 val=1` 余量 165）。

对照关键帧的结论（关键帧两个色度叶的零读余量全部 ≥5243，因为那些行已被适配到极度偏斜；而关键帧 luma 叶的 read#57 余量 4 但已被否证），**inter 帧这个余量 68 的零读是当前唯一同时满足"余量小"与"像素中性"的系数读**：若 dav1d 在该处 `v` 比我们大/小 68 以上而解出 1，就会多出一个非零系数，直接造成 U 平面残差不同——与"Y/V 全对、U 从第 16 行起全错"完全吻合。

下一步（两步，都很便宜）：(a) 用 `m` 值在 `trace2.txt` 里定位这个读属于哪个叶（inter 帧 5 个叶的 LEAF 行号为 1224/1364/1436/1459/1890，`eob` 分别 55/28/9/164/245；`c=10` 在 luma 叶1/叶2 与色度叶里都合法，需按 `m` 与所在区间判定），若它落在**色度叶**则直接就是分歧符号，若落在 **luma 叶**则与"luma 像素全对"矛盾、应排除并顺次取 `c=6`(225) 等下一个；(b) 判定后即可针对性核对该系的 ctx/行选择（`x` 上下文与 `base[tx_ctx][ctx]` 行）是否与规范一致。

**第十三次推进补充十一（刀刃读定位到 inter 帧 luma 叶3 的 `eob`，余量 1）：`eob r=46508 v=39211 m=-12 cdf=[615,837,2771,5023,8551,13625,19628,23157,26535,28596,32768,4]`（trace2.txt 第 1434 行，属于第 1436 行的 `LEAF side=64 h=32 txctx=4 eob=9 area=1024 rect=true`，即 inter 帧第三个叶、64x32 luma）。** 手算该读：`sym3` 的 `cur = ((46508>>8)*((32768-5023)>>6))>>1 + 4*(10-3-1) = (181*433)>>1 + 24 = 39186+24 = 39210`，而 `v = 39211`，**余量 1** —— 全 inter 帧 274 个非系数读里最小（其余最小为 28、229、251…）。这是"像素中性 + 极小余量"两类条件第一次同时命中的读。

该读的 `eob` 细化链：`eob_pt = 符号+1`；符号 4 → `eob_pt=5` → `eob=(1<<3)+1=9`，随后 `extra r=39848 v=39831 cdf=[16726,32768,0]` 解出符号 0（不加 4），故 `eob=9`，与 LEAF 行一致。该叶只有两个非零系数：`tx4 h32 c8 p65 x1 v1` 与 `tx4 h32 c0 p0 x1 v1` —— **`c=8` 要求 `eob ≥ 9`**，所以符号 4（eob_pt 5）是 luma 像素正确的必要条件；若符号 3（eob_pt 4，eob 最大 8）则 `c=8` 根本不会被读，luma 就会错。**因此 dav1d 在此处也必须解出 4，这个读本身不是分歧点；但余量 1 意味着只要上游状态差 1，这里就会翻转并立刻破坏 luma —— 而 luma 是全对的，故上游状态在该点的偏差量至多为 1（或分歧发生在这之后）。**

**这把搜索范围压缩到"该读之后、色度叶之前"的一小段**：luma 叶3 的剩余系数读与 sign 读、luma 叶4（`eob=164`）的全部读、以及进入色度叶前的块级符号。下一步对这一段做同样的余量分析（trace2.txt 第 1436–1890 行），并优先看 luma 叶4 的 `eob` 读（它也有 164 个系数读，是状态漂移的主要来源）。

**第十三次推进补充十二（压缩段余量分析 + 一个必须解释的矛盾）：分歧点就在 inter 帧 luma 叶3 的 `eob` 读本身。** 对 trace2.txt 第 1436–1890 行（luma 叶4 的全部 164 个系数读 + sign 读 + 进入色度叶前的块级符号，共 173 个系数读）做余量分析：**值 0 的读里最小余量是 230**（`base r=37618 v=3965 c=111 p=262 x=21`），全体读里最小 193；而 `both.txt` 里 inter 帧 274 个非系数读中 bool（n=2, cdf=[16384,32768,0]）的最小余量是 349、partition（n=10）是 28。

结合上一轮结论（luma 叶3 的 `eob` 读余量 **1**，且 luma 全对 ⇒ 上游状态偏差 ≤1）：**偏差 ≤1 不可能翻动本段任何读（最小余量 193），也不可能翻动色度叶之前的 partition（28）或 bool（349）**。因此分歧只能发生在 **luma 叶3 的 `eob` 读这一个点上**——即我们在该读解出的符号与 dav1d 不同。

**但这里有一个必须解释的矛盾**：该读 `r=46508 v=39211 cdf=[615,837,2771,5023,...]`（n=10），按公式 `cur(3) = ((46508>>8)*((32768-5023)>>6))>>1 + 4*(10-3-1) = (181*433)>>1+24 = 39210`，而 `v=39211 ≥ 39210`，**公式判定应为符号 3**；可该叶 LEAF 行是 `eob=9`，而 `eob=9` 只能来自 `eob_pt=5` 即**符号 4**（符号 3 → `eob_pt=4` → `eob` 最大 8，且该叶有 `c8 p65 x1 v1` 非零系数，`eob` 必须 ≥9）。**二者不可能同时成立**，说明以下之一：(a) 我对 `cur` 公式的复算有误（最可能是 `f>>6`/`r>>8`/`+4*(n-sym-1)` 某一项的量纲理解差了 1）；(b) trace 打印的 `r`/`v`/`cdf` 与 `symbol()` 实际使用值不同步；(c) `symbol()` 的实现与注释的规范公式有细微出入。

**下一步（一步就能定案）**：在 `av1_coeff_decode.mbt` 的 `eob` 读处紧挨着加一行 `println("EOBDBG sym=" + <解出符号>.to_string() + " r=" + decoder.symbol_range.to_string() + " v=" + decoder.symbol_value.to_string() + " cdf3=" + context.eob[3].to_string())`，重跑周期 3 样本，直接看该读到底解出 3 还是 4、以及当时的 r/v/cdf。若解出 4 而公式算 3，则 `symbol()` 有 off-by-one，**那就是阶段 B 的根因**；若解出 3 而 LEAF 显示 eob=9，则矛盾在 `eob` 由 `eob_pt` 推导的那几行（`(1<<(eob_pt-2))+1` 与 extra/bool 细化的位数），同样是根因。

**第十三次推进补充十三：EOBDBG 探针复现失败的原因已找到——当前 `-14` 守卫是开启的，inter 帧解码被提前拒绝，所以 `r=46508` 那个读根本不会发生（探针计数为 0）。** 复现该探针必须先按第十二/十三次推进的配方把 8 个文件的 `symbol_max_bits < -14` / `>= -14` 换成 `-1000000`、把 `av1_cdf_load_enabled` 置 `true`、并用 `pipe6.py 0 3 0` 重新生成样本；否则只能看到关键帧的 eob 读（本次 tail 到的三条：`sym=10 eob_pt=11`、`sym=0 eob_pt=1`、`sym=4 eob_pt=5`，其中 `sym=4 → eob_pt=5` 与 luma 叶3 的 `eob=9` 推导一致，说明 `eob_pt` 推导本身没问题）。

**因此补充十二留下的矛盾尚未定案**，重跑配方已明确；探针代码只需在 `av1_coeff_decode.mbt` 的 `let eob_pt = decoder.symbol(context.eob) + 1` 前各加一行打印（已在上一轮验证过可编译）。定案标准不变：若该读解出 4 而按 `(r,v,cdf)` 手算得 3，则 `Av1SymbolDecoder::symbol` 有 off-by-one（阶段 B 根因）；若解出 3 而 LEAF 显示 `eob=9`，则根因在 `eob` 由 `eob_pt` 推导的几行。

**第十三次推进补充十四（矛盾消解，是余量分析的算术错误）：该 `eob` 读的 CDF 是 11 个累计值 + 1 个计数器 = 12 项，`n=11` 而非 10。** 用 `n=11` 重算 `r=46508 v=39211 cdf=[615,837,2771,5023,…]`：`cur(3) = (181*433)>>1 + 4*(11-3-1) = 39186+28 = 39214`，`v=39211 < 39214` 不 break；`cur(4) = (181*378)>>1 + 4*(11-4-1) = 34209+24 = 34233`，`v ≥ 34233` → **符号 4**，`eob_pt=5 → eob=9`，与 LEAF 行一致。**矛盾消失，`symbol()` 与 `eob_pt → eob` 推导都没有问题。** 正确余量是 `min(v-cur(4), cur(3)-v) = min(4978, 3) = 3`（此前手算写成 1 是因为用错了 n）。

**修正后的结论**：该读余量为 3 且翻转会破坏 luma（`c8` 系数要求 `eob≥9`），故 dav1d 也解出 4，**不是分歧点**；而它之后的所有读余量 ≥193（系数）/28（partition）/349（bool），也翻不动。因此分歧仍在它**之前**，且状态偏差在越过该读时必须 ≤3（否则 luma 已坏）。结合"luma 叶3 之前的最小像素中性余量"这一项还没系统算过，**下一步应对 trace2.txt 第 1224–1436 行（inter 帧 luma 叶1、叶2 与叶3 的 eob 之前部分）做与补充十二同样的"值 0 + 余量"联合筛选**，重点看那些余量 <100 的零系数读——但要注意：落在这两个 luma 叶里的读一旦翻转就会改变 luma 像素，与"luma 全对"矛盾，所以真正的分歧点更可能是**这两个叶的 `eob` 细化读（extra/bool）或它们之前的块级符号**，应当把筛选范围从"系数读"扩展到"全部非系数读"（`both.txt` 里 n≠4 的读已按帧分开，可直接按序号切段）。

**第十三次推进补充十五（收敛到关键帧）：inter 帧在色度叶之前的非系数读全部"要么余量大、要么翻转会破坏像素"，分歧只能在关键帧。** 用 `both.txt` 按帧切分后对 inter 帧 274 个非系数读按余量排序，最小的只有四档：`3`（luma 叶3 的 `eob`，n=11）、`28`（partition，n=10）、`229`（uv_mode，n=13）、`251`（bool，n=2，`cdf=[17355,32768,2]`）。逐一判定：
- `eob` 余量 3：翻转会使 `eob` 从 9 掉到 ≤8，luma 叶3 的 `c8 p65 x1 v1` 读不到 → luma 坏，**排除**；
- partition 余量 28：翻转改变块结构 → luma 坏，**排除**；
- uv_mode 余量 229、bool 余量 251：一个在 luma 叶3 的 `eob` 之后（已被前述"该点之后最小余量 193/28/349"覆盖），一个需按 `m` 定位。

而 inter 帧系数读在色度叶之前的最小像素中性余量是 **230**（补充十二），也翻不动（状态偏差 ≤3）。**⇒ inter 帧不可能是分歧源。**

回头检查关键帧 312 个非系数读的最小余量：`23`（partition，n=10，m=385）、`112`（bool，n=2，m=53，`cdf=[16384,32768,0]`）、`154`（n=3，m=373，`cdf=[5782,11475,32768,0]`）、`166`（`eob`，n=11，m=207）、`178`/`181`（bool）。其中：
- partition 余量 23 在关键帧第一个读，翻转会改变关键帧块结构 → 像素坏，**排除**；
- `n=3` 余量 154 与 `eob` 余量 166 都改变系数/块结构，**大概率排除**；
- **bool 余量 112（m=53）与 178/181 是最可能的像素中性分歧点**——bool 翻转只改 1 位状态，且 key 帧里大量 bool 是 `eob` 细化位（`read_bool`）与系数符号位；符号位翻转会改像素，但 **`eob` 细化 bool 翻转只改变"读多少个尾部 0"**，完全像素中性。

**下一步（一步定案）**：在 `both.txt` 里按 `m=53`、`m=200`、`m=165` 定位这三个 bool 读，对照 trace2.txt 同 `m` 的系数记录判断它们是"`eob` 细化 bool"还是"系数符号 bool"；若是前者，则用编译期常量把该 bool 的取值翻转、重跑周期 3 样本，看 U 平面错误数是否变化 —— 变化即找到根因（注意白盒全局传值不可用，必须改常量重建）。

**第十三次推进补充十六（根因位置确定）：关键帧两个色度叶的 `eob` 细化 bool 序列已定位，它们是完全像素中性的，翻转即改变 `eob` → 改变继承行。** 在 `both.txt` 关键帧 1722 个读里按 `m` 定位三个候选 bool 并核对上下文：

- **`m=200`（idx=173，`r=42248 v=21302`，余量 178）**：前三个读是 `m=203 n=2 cdf=[20297,32768,0]`（**`extra` 读**，与 trace2.txt 第 215 行 `extra r=56224 v=2662 m=203 cdf=[20297,32768,0,]` 一致）紧跟 `m=202/201/200/199` 四个 bool —— **这正是关键帧色度叶1（`LEAF side=32 h=16 eob=248`）的 `eob` 细化 bool 序列**。
- **`m=165`（idx=435，`r=41992 v=21177`，余量 181）**：前一个读是 `m=168 n=2 cdf=[19029,32768,1]`（色度叶2 的 `extra`，对应 trace2.txt 第 719 行）紧跟四个 bool —— **色度叶2 的 `eob` 细化 bool 序列**。
- `m=53`（idx=790）：前后都是 bool 长串（`m=56/55/54/53/52…`），是某叶**符号位**的 bool，翻转会改像素，**排除**。

**为什么这是根因位置**：色度叶的 `eob` 由 `eob_pt` + `extra` + 若干 bool 细化位合成（叶1：`eob_pt=9` → 基数 129，`extra` 加 64 → 193，再由 6 个 bool 加 32/16/8/4/2/1 → 248 = 193+32+16+4+2+1）。**这些 bool 只决定"读多少个尾部 0"——尾部系数全是 0，所以翻转任何一位都不改变关键帧像素**，但会 (a) 改变该叶读到的符号总数与 MSAC 终态，(b) 改变 `base`/`base_eob` 等行被适配的次数与终值，于是 **inter 帧继承到的 37 行取值改变**，最终 inter 帧色度叶解出不同残差。这与已观察到的全部现象一致：关键帧像素全对、Y/V 全对、U 从第 16 行起全错、且 37 个继承行与我们自己的关键帧终行一致（自洽但可能与 dav1d 不同）。

**下一步（定案）**：这两个 bool 的余量是 178/181，需要有 ≥178 的上游状态差才能翻转。用编译期常量把色度叶1 的第 3 个细化 bool（`m=200` 那个）取值翻转、重跑周期 3 样本：若 U 平面错误数从 488 明显变化（特别是若继承行随之改变），即证实"`eob` 细化 bool 是像素中性的分歧通道"；随后再向上游找产生 ≥178 状态差的读（重点查关键帧 luma 叶2 与两个色度叶的 `eob`/`extra` 读本身的余量，以及 luma 叶1/叶2 之间与色度叶前的块级符号）。注意白盒全局传值不可用，必须改常量重建。

**第十三次推进补充十七（上游候选收敛到关键帧一个 `eob` 读）：`m=166, n=11`（`eob` 读）余量 166，位于 `m=200` 的色度叶1 `eob` 细化 bool 之前，且 `eob` 符号翻转同样是像素中性的。** 把关键帧 312 个非系数读按余量排序后，落在"色度叶1 细化 bool（m=200，余量 178）之前"且余量 <178 的只有四档：`23`（partition，m=385，帧首，翻转改块结构→排除）、`112`（bool，m=53，符号位长串→排除）、`154`（n=3，m=373）、**`166`（`eob`，n=11，m=166）**。

其中 **`eob` 读的符号翻转与细化 bool 一样是像素中性的**：`eob_pt` 变 1 会使 `eob` 跳到相邻 bucket（如 129↔65/257），从而读完全不同数量的尾部 0 —— 尾部系数全为 0，关键帧像素不变，但该叶的符号总数、MSAC 终态、以及 `base`/`base_eob` 等行的适配次数全部改变，继承行随之改变。**这正是能产生"≥178 上游状态差"的最小代价机制。**

已排除的替代解释：`n=3`（m=373，余量 154）若为 `base_eob` 则翻转会改系数值→改像素，除非该系数去量化为 0；partition 与符号位 bool 都会改像素。

**下一步（定案，两步）**：(a) 在 `both.txt` 里取 `m=166 n=11` 那条读的 `(r,v,cdf)`，对照 trace2.txt 同 `m` 记录确认它属于哪个叶（trace2.txt 里关键帧的 `eob`/`eob512` 读分别在 `m=366`(luma 叶1)、`m=261`(luma 叶2)、`m=207`(色度叶1)、`m=171`(色度叶2)，故 `m=166` 应是色度叶2 区域内的一次 `eob` 类读，需按 `cdf` 首项区分是 `eob` 还是 `eob512`）；(b) 用编译期常量把该读解出的符号 ±1、重跑周期 3 样本，若 U 平面错误数从 488 显著变化（尤其继承行改变），即锁定根因；随后把 `eob`/`eob_pt` 的推导或该读所用 CDF 行/上下文与规范、dav1d 逐点核对，做出真正修复。白盒全局传值不可用，必须改常量重建。

**第十三次推进补充十八（更正 + 根因候选确定）：此前把"余量 166"误读成"`m=166`"，实际那条读是 `m=207, n=10`，即关键帧色度叶1 的 `eob512` 读本身。** 在 `both.txt` 关键帧里核实：`m=166` 只有一条且是 `n=2` 的 bool（`r=41992 v=10588`，色度叶2 的细化 bool 之一）；而关键帧全部 `n=11` 读的 `m` 只有 366/261/135/36（四个 luma 叶的 `eob`），色度叶用的是 `n=10` 的 `eob512`。回看余量表，`margin=166` 那条是 `n=10 dec=8 m=207 cdf=[7265,9979,15819,19250,21780,23846,26478,28396,31811,32768,0]` —— 与 trace2.txt 第 214 行 `eob512 r=33280 v=1080 m=207` **完全对应，就是关键帧色度叶1 的 `eob` 读**（默认行，count 0，已核实等于 `defaultEobPt512Cdf[1][1]`）。

**这条读同时满足全部条件**：(i) 余量 166（`v=1080`，`cur(8)` 与 `cur(7)` 之间距 1080 的那个阈值差 166）；(ii) **符号翻转完全像素中性** —— 它决定 `eob_pt`，从而决定 `eob` 落进哪个桶（`eob_pt=9 → eob∈[129,256]`，`eob_pt=8 → [65,128]`，`eob_pt=10 → [257,512]`），只改变读多少个尾部 0，而该叶只有 4 个非零系数（DC=4 与 pos 22/21/20 各 1）、其余 244 个全是 0；(iii) 它位于色度叶1 细化 bool（`m=200`，余量 178）**之前**，是能产生"≥178 上游状态差"的最小代价机制；(iv) 它所用的 CDF 行是默认行、已核实无误，故若符号错，问题在**进入该读的 MSAC 状态**，即更上游。

**再往上一步的候选只剩两个**（都在 `m=207` 之前）：`margin=23` 的 partition（`m=385`，关键帧第一个读，翻转改块结构→改像素，排除）与 **`margin=154` 的 `n=3` 读（`m=373`，`cdf=[5782,11475,32768,0]`）**。后者是三符号 CDF，最可能是 `coeff_base_eob`；若它翻转会改系数值 → 改像素，**除非该系数去量化后被取整吸收**。**下一步**：在 `both.txt` 里取 `m=373 n=3` 那条读并对照 trace2.txt 第 373 行附近的系数记录，确认它属于哪个叶/哪个系数、该系数的去量化值是否为 0 或被吸收；同时用编译期常量把色度叶1 `eob512` 读（`r=33280 v=1080`）解出的符号改成 7 和 9 各跑一次周期 3 样本，若 U 平面错误数从 488 显著变化，即实证"`eob` 桶跳转"这条根因通道。

**第十三次推进补充十九（强制实验通道打通 + 两个符号被排除）：把"内联指纹 + 编译期常量"写进 `Av1SymbolDecoder::symbol` 的强制方式**确实生效**，白盒全局传值不可用的问题由此绕过。** 用 `if self.symbol_range == 33280 && self.symbol_value == 1080 && cdf.length() == 11 && cdf[0] == 7265 { stop_at = <常量> }` 对关键帧色度叶1 的 `eob512` 读做强制，结果：

| 强制符号 | KEYBAD | INTERBAD |
| ---: | --- | --- |
| 8（自然值） | `[0,0,0]` | `[0,488,0]` |
| **7** | **none（解码直接失败）** | none |
| **9** | **`[2014,813,1024]`（关键帧像素坏）** | `[3932,983,938]` |

**两个邻居符号都被排除**：符号 7 让关键帧解码直接返回 `None`（`eob_pt=8` 使后续读触发合法性检查失败），符号 9 让关键帧像素坏（`[2014,813,1024]`）—— 而 dav1d 的关键帧解码是正确的，故 dav1d 在此处也只能是符号 8。**⇒ 色度叶1 的 `eob512` 读不是分歧点，"`eob` 桶跳转"这条通道在该读上被实证排除。**

**更重要的是：强制实验通道已打通**（内联指纹 + 编译期常量，改一个常量重建一次即可）。这把整个调查从"只能被动看 trace"升级为"可以主动做反事实实验"。**下一步应对其余候选逐个做同样的强制实验**，优先级：(1) 关键帧色度叶1/叶2 的 6+6 个 `eob` 细化 bool（`m=200/199/201/202` 与 `m=165/164/166/167` 等，指纹用各自的 `(r,v)`，常量取 1 翻转 bool 需改成强制 `stop_at=0/1`）；(2) `m=373 n=3 cdf=[5782,11475,32768,0]` 那条三符号读；(3) inter 帧 partition（余量 28）。判定标准不变：**若强制后关键帧仍 `[0,0,0]` 而 inter 帧 U 平面错误数变化，即找到根因。**

**第十三次推进补充二十（反事实实验逐个排除候选，根因收敛到"CDF 行/上下文选择差异"）：用已打通的"内联指纹 + 编译期常量"强制通道做了 6 组反事实实验，全部排除。**

| 实验 | 指纹 | 强制 | KEYBAD | inter U 错误 |
| --- | --- | --- | --- | --- |
| inter 色度叶 `eob512` 符号扫描 | `r=51012 v=2051 cdf0=6819` | 0..9 | — | 510/507/504/504/507/512/504/505/**488**/479 |
| 关键帧色度叶1 `eob512` 符号 7 | `r=33280 v=1080 cdf0=7265` | 7 | **none** | none |
| 关键帧色度叶1 `eob512` 符号 9 | 同上 | 9 | **`[2014,813,1024]`** | 3932 |
| 关键帧色度叶1 `eob` 细化 bool ×4 | `(42248,21302)` `(42248,10651)` `(42248,356)` `(42494,5325)` | 翻成 1 | **none ×4** | none |
| 关键帧 luma 叶1 read#57 | `r=58177 v=35087 cdf0=12937` | 翻成 1 | **`[3946,1024,1024]`** | 978 |

**结论一：inter 色度叶 `eob512` 的 10 个符号无一能让 U 归零（自然值 8 也不突出）⇒ 进入色度叶的 MSAC 状态确实是错的**（此次是用可用的强制通道复做的，结论可靠）。
**结论二：关键帧里所有"小余量"候选全部排除** —— `eob512` 的 7/9 都破坏关键帧，4 个细化 bool 翻转后关键帧解码直接失败（因为该叶非零系数分布在 c=247/231/215，`eob` 一动就丢系数），read#57 翻转后关键帧 `[3946,1024,1024]`。

**⇒ 剩余唯一解释：某个读上我们与 dav1d 用了不同的 CDF 行（或不同的上下文索引），但解出的符号相同（行很相似，符号都是 0），于是像素一致；然而被适配的是不同的行 ⇒ 关键帧终态（继承行）不同 ⇒ inter 帧色度叶解出不同残差。** 这在值域 trace 里完全看不见，只能看到"行值自洽"。

**下一步（唯一可行方向）**：把 trace 扩展到记录每次读所用的 **CDF 表名 + 索引**（`base[tx_ctx][ctx]`、`base_eob[tx_ctx][ctx]`、`br[tx_ctx][ctx]`、`eob`/`eob512`/`eob_small[multisize*2+pt_ctx]`、`extra[tx_ctx][shift]`、`sign[dc_sign_ctx]`、partition 的 `[bl][ctx]`、`skip`、`uv_mode`、`txb_skip` 等），然后与规范/dav1d 的索引公式逐项核对。**最可疑的是系数 ctx 函数**（`av1_coeff_base_ctx_rect` / `av1_coeff_br_ctx_rect` / `av1_coeff_base_ctx_square` / `av1_coeff_br_ctx_square`）与 `tx_ctx` 的推导（`av1_tx_size_ctx_rect`），以及矩形 32x16/64x32 的 `eob_small`/`eob512` 选择；这些正是"行相同概率高、索引容易差一"的地方。

**第十三次推进补充二十一（根因找到：EOB 表的 qctx 维度是我们多出来的）：dav1d 1.2.1 的 eob CDF 表**没有 qctx 维度**，而我们多索引了一层。** 从本机 dav1d 源码 `cdf.h` 与 `cdf.c` 逐值核对：

| 表 | dav1d 声明 | dav1d `[plane=0]` 首值 | dav1d `[plane=1]` 首值 | 我们的声明 |
| --- | --- | --- | --- | --- |
| `eob_bin_16` | `[2][2][5+3]` | `CDF4(840,1039,1980,4895)` | `CDF4(3247,4950,9688,14563)` | `[4][2][2]` |
| `eob_bin_512` | `[2][10+6]` | `CDF9(641,983,3707,5430,10234,…)` | `CDF9(5095,6446,9996,13354,…)` | `[4][2]` |
| `eob_bin_1024` | `[2][10+…]` | `CDF10(393,421,751,1623,3160,…)` | `CDF10(1865,1988,2930,4242,10533,…)` | `[4][2]` |

**我们的 `[qctx=0][plane]` 与 dav1d 的 `[plane]` 逐值相同**（`[0][0]=[393,421,751,…]`、`[0][1]=[1865,1988,2930,…]`、`[0][1]=[5095,6446,…]` 等全部对上），但我们的 `qctx=1/2/3` 三组在 dav1d 里**根本不存在**。而 [av1_coeff_decode.mbt](av1_coeff_decode.mbt) 用 `av1_dc_q_context(base_q_idx)` 作为第一索引：

```
eob: av1_coeff_eob1024_default(qctx, plane)
eob512: av1_coeff_eob_small_default(5, qctx, plane, 0)
eob_small.push(av1_coeff_eob_small_default(kind, qctx, plane, tx_class))
```

**⇒ 当 `qctx != 0` 时我们用了 dav1d 不存在的行。** 本失败样本关键帧色度叶的 `eob512` 行实测为 `[7265,9979,15819,…]`（即我们的 `[qctx=1][plane=1]`），而 dav1d 对该平面用的是 `[5095,6446,9996,13354,16017,17986,20919,26129,29140]`。两行解出的符号恰好相同（都是 8），所以关键帧像素全对；但**被适配的是不同的行**，于是关键帧终态（继承行）与 dav1d 不同，inter 帧色度叶随之解出不同残差 —— 与全部已观察现象吻合。

**修复已验证有效但会打破一个自洽样本**：把三处 `qctx` 改成 `0`（`av1_dc_coeff_tables.mbt` 的 `av1_coeff_eob1024_default(av1_dc_q_context(qidx), ptype)` 同样改）后 `moon check` 通过，但 `av1_txmode_fixture_test.mbt:43 ("crafted tx-mode depth1_64 decodes")` 失败（native 直接起不来）。该样本是 `scripts/craft_av1_fixture.py` 自建的（非外部真值），其 golden 是按旧的 qctx 索引构造的，因此**修复后需要用同一脚本重新生成该 fixture**，或把 golden 改为外部解码器真值。当前已 `git checkout` 回退以保持全绿。

**下一步（真正的修复）**：(1) 把上述四处索引改为按 plane（去掉 qctx）；(2) 重新生成受影响的 crafted fixtures（`av1_txmode_fixture_test` 等），或改用外部真值；(3) 复跑周期 3 样本确认 inter 帧 U 平面归零；(4) 全量回归 + 三个目标 + Web/WASM。这是阶段 B 闭合的直接路径。

**第十三次推进补充二十二（否证：qctx 索引是对的，上一条的"根因"不成立）：把 eob 表的 qctx 索引改成 0 之后，247 个测试失败，其中包含外部真值测试**（`external libaom dc_y_low_q10`、`dc_u_low_q10`、`dc_v_high_q30`、`dc_y_high_q50` 等）。⇒ **`av1_dc_q_context(base_q_idx)` 作为 eob 表第一索引是正确的**，`defaultEobPt1024Cdf`/`defaultEobPt512Cdf` 的 4 个 qctx 组都是必需的（`dc_y_high_q50` 这类高 q 样本会用到 qctx=2/3 的行）。

因此补充二十一提的"dav1d 的 eob 表没有 qctx 维度"这一推断**被实验否证**：dav1d `cdf.h` 里 `eob_bin_1024[2][11+5]` 的 `[2]` 应当理解为别的东西（或 dav1d 在别处按 qctx 分表），而**我们与 go-av1 逐值相同的 4×2 表才是外部真值使用的表**——否则外部参考测试不可能全绿。已 `git checkout` 回退，仓库恢复全绿。

**教训与下一步**：本轮得到的真正可复用成果是 (a) "内联指纹 + 编译期常量"的强制实验通道（已验证可改变解码结果）；(b) inter 帧色度叶 `eob512` 10 个符号扫描无一归零（⇒ 进入色度叶的状态确实是错的，且此次是用可用通道复做的）；(c) 关键帧所有小余量候选（`eob512` 的 7/9、4 个细化 bool、read#57）都被反事实实验排除。剩余唯一解释仍是"某个读上我们与 dav1d 用了不同的 CDF 行但解出相同符号"，而**要直接观测它，必须把 trace 扩展到记录每次读所用的表名与索引**（`base[tx_ctx][ctx]`、`base_eob[tx_ctx][ctx]`、`br[tx_ctx][ctx]`、`eob`/`eob512`/`eob_small[m*2+pt_ctx]`、`extra[tx_ctx][shift]`、`sign[dc_sign_ctx]`、partition/skip/uv_mode/txb_skip 各自的索引），再与规范公式逐项核对。这是唯一还没做过的检查，也是下一步的入口。

**第十三次推进补充二十三（inter 帧 luma 叶1 `c=10` 读的强制实验结果）：该状态在两帧都出现，需用 payload 长度区分，而加长度 guard 后强制无效果——待查。** 用 `r=60685 v=35630 cdf[0]=13556`（inter 帧 luma 叶1 的 `c=10 p=128 x23 val=0`，余量 68）强制 `stop_at=1`：
- **不加 guard**：`KEYBAD=[2018,246,160]`、inter `[4040,480,487]` ⇒ 指纹在**关键帧**也命中了（同一 (r,v) 状态在两帧都出现），关键帧被破坏。
- **加 `self.data.length() == 3` guard 后**：`KEYBAD=[0,0,0]`、inter `[0,488,0]` ⇒ **与不强制完全相同**，说明强制没有生效。

**待查**：`both.txt` 里 inter 帧读的 `L=3`，但加 `data.length()==3` 后反而不命中，说明该叶系数读所用解码器的 `data.length()` 不是 3（可能 tile 解码器拿到的 payload 与 trace 过滤用的长度不同，或 luma/色度用了不同实例）。**下一步**：把 guard 改成打印 `self.data.length()` 探针，确认真实长度后再重做；或者改用"帧内唯一"的指纹（例如同时匹配 `m` 值附近的状态）来区分两帧。

**当前结论不变**：inter 帧进入色度叶的状态确实是错的（`eob512` 十符号扫描无一归零，已用可用通道复做）；关键帧所有小余量候选已被反事实实验排除；qctx 索引假设已被外部参考测试否证。剩余解释仍是"某个读上用了不同的 CDF 行但解出相同符号"，而直接观测它需要把 trace 扩展到记录表名与索引。

**第十三次推进补充二十四（inter 帧 luma 叶1 `c=10` 读正式排除）：该 (range, value, max_bits) 状态在关键帧与 inter 帧**同时出现**，因为 inter 帧 luma 叶1 复现了关键帧的符号序列；强制后关键帧 `[2018,246,160]`、inter `[4040,480,487]` ⇒ 该系数翻转会改变关键帧像素，排除。** 加上 `self.symbol_max_bits == 104` 后仍命中关键帧，说明两帧在该点状态完全相同（这与"inter 帧 luma 叶1/叶2 与关键帧对应叶 54/55 个符号相同"的既有观察一致）。

**由此得到一条重要的方法论结论**：对于"inter 帧复现关键帧符号"的位置，**任何强制实验都会同时改变两帧**，无法用来分离"只影响 inter 帧"的假设。这类位置要判断是否为分歧点，只能看"翻转后关键帧是否仍 `[0,0,0]`"——若否则排除。本轮已用此法排除 inter 帧 luma 叶1 的 `c=10`（余量 68）。

**剩余候选的判别准则因此更清晰**：分歧点必须位于**inter 帧独有的读**上（即继承行与关键帧不同而导致符号分歧的位置），或者位于**关键帧中 inter 帧没有复现的位置**。结合"inter 帧色度叶 `eob512` 十符号扫描无一归零"（⇒ 进入色度叶的状态错）与"关键帧所有小余量候选已排除"，下一步应把余量分析限定在 **inter 帧独有的读**上：即 inter 帧 4 个 luma 叶中符号序列与关键帧不同的位置（主要是各叶的 DC：关键帧 luma 叶1/2 的 DC 为 15/15，inter 帧为 11/15，以及 luma 叶3/叶4 整个叶都是 inter 独有），重点算这些位置的余量。

**第十三次推进补充二十五（inter 帧独有读的余量全部很大 ⇒ "单个符号分歧"框架不成立）：inter 帧 5 个叶的 DC（`c=0`）读余量为 462 / 16730 / 850 / 1431 / 2881，全部远大于可翻转阈值。** 结合此前结果：

| 范围 | 最小像素中性余量 |
| --- | ---: |
| inter 帧全部系数读（色度叶前） | 230 |
| inter 帧全部系数读（色度叶） | 5243+ |
| inter 帧独有读（DC、luma 叶3/叶4） | **462** |
| inter 帧非系数读 | 3（`eob`，已排除）/ 28（partition，已排除）/ 349（bool） |
| 关键帧非系数读 | 23（partition，排除）/ 112（bool，排除）/ 154 / 166（`eob512`，已排除） |
| 关键帧系数读（值 0） | 4（luma 叶，已排除）/ 5243+（色度叶） |

**⇒ 没有任何一个读同时满足"余量小"与"翻转后像素中性"。** 这说明"我们在某个读上解出了与 dav1d 不同的符号"这一框架**不成立**（至少不是单个读的分歧）。

**剩下的可能只有两类**：
1. **我们与 dav1d 读了不同数量/不同顺序的符号**（例如某处 `eob` 或 `tx_split` 的判断不同，导致整个叶的读法不同）——这不会体现为"某个读的余量小"，而体现为**符号流的结构差异**；
2. **我们用了不同的 CDF 行但解出相同符号**（行身份差异），这改变了被适配的行进而改变继承状态。

**下一步（唯一还没做过的检查）**：把 trace 扩展到记录**每次读所用的 CDF 表名与索引**，然后与规范/dav1d 的索引公式逐项核对。重点核对矩形变换（32x16 / 64x32）的：
- `tx_ctx` 推导（`av1_tx_size_ctx_rect`）
- `eob_small` 的 `multisize` 与 `pt_ctx`（`av1_coeff_decode.mbt` 的 `multisize = if rectangular { area_class } else { log2_domain + log2_domain - 4 }` 与 `pt_ctx = if scan_class == AV1_SCAN_DEFAULT { 0 } else { 1 }`）
- `eob512` 的选择条件（`area == 512`）
- `base`/`br` 的 ctx 函数（`av1_coeff_base_ctx_rect` / `av1_coeff_br_ctx_rect`）

**第十三次推进补充二十六（高度可疑的真实 bug：矩形路径的 `Coeff_Base_Ctx_Offset` 组索引写死为 1）：规范 `get_coeff_base_ctx` 对 `TX_CLASS_2D` 返回 `ctx + Coeff_Base_Ctx_Offset[txSz][Min(row,4)][Min(col,4)]`，其中 `txSz` 是**原始 TX_SIZE**。我方代码两条路径不一致：**
- **方形路径**（`av1_coeff_decode.mbt:417`）：`av1_coeff_base_ctx_offset[size_row][...]`，其中 `size_row` 按变换边长推导（32 → 3、64 → 4、16 → 2、8 → 1）——**随 txSz 变化，正确**；
- **矩形路径**（`av1_coeff_decode.mbt:296`）：`av1_coeff_base_ctx_offset[1][...]` —— **组索引写死为 1**，只有在该矩形变换"应当使用第 1 组"时才正确。

而按规范，`TX_32X16` 应使用 `TX_32X32` 那一组（即下标 3）再把前两列换成 16；`TX_64X32` 应使用 `TX_64X64` 那一组（下标 4）。**本失败样本的关键帧色度叶正是 32x16、inter 帧色度叶也是 32x16、inter 帧 luma 叶是 64x32 —— 全部落在矩形路径上，且都应使用下标 3/4 而非 1。** 这正好能产生"解出的符号相同（ctx 只影响选行，两行都偏斜向 0）但被适配的是不同的行"这一现象，与全部已观察事实吻合。

**下一步（一步定案）**：把 `av1_coeff_decode.mbt:296` 的 `av1_coeff_base_ctx_offset[1]` 改成按变换尺寸推导的组下标（与方形路径同一套 `size_row` 逻辑：`side>=32 → 3`、`side>=16 → 2`，即 32x16 用 3、64x32 用 4），重跑周期 3 样本与全量测试。若 inter 帧 U 平面归零且全量回归保持绿，即为阶段 B 的根因与修复。

**第十三次推进补充二十七（矩形 offset 组索引修复已验证但不足以闭合；代码在回退时丢失需重打）**：把 `av1_coeff_decode.mbt` 矩形路径的 `av1_coeff_base_ctx_offset[1]` 改成按 `tx_width` 推导组下标（`>=64→4、>=32→3、>=16→2、else 1`）后：**`moon check` 0 errors、三目标测试各 1186/1186 全绿**（说明该改动与规范一致且不破坏任何样本），但周期 3 样本的 inter 帧仍为 `[0, 488, 0]` —— 即这是**一处真实的规范符合性修复，但不是阶段 B 的分歧根因**。

**注意：该修复的代码在随后"恢复守卫 + 回退插桩"时被覆盖丢失**（脚本里先打了 offset 补丁、后又用未打补丁的 `s` 写了回去）。**下次接手需重新应用**：把 [av1_coeff_decode.mbt](av1_coeff_decode.mbt) 矩形路径（`av1_coeff_base_ctx_rect` 末尾）的
```
ctx + av1_coeff_base_ctx_offset[1][if row < 4 { row } else { 4 }][if col < 4 { col } else { 4 }]
```
改为先算 `let rect_group = if tx_width >= 64 { 4 } else if tx_width >= 32 { 3 } else if tx_width >= 16 { 2 } else { 1 }` 再用 `av1_coeff_base_ctx_offset[rect_group][...]`。此改动已通过全量回归，应尽快重新落地并提交。

**下一步**：分歧仍未定位。已排除：MSAC 算术/补位/适配速率（对拍零分歧）、快照机制（37 个继承行逐一相符）、qctx 索引（外部参考测试否证）、关键帧与 inter 帧所有"小余量"读（反事实实验逐个排除）、inter 色度叶 `eob512` 十符号扫描（无一归零）、矩形 offset 组索引（修复后仍不归零）。**剩下还没检查的是 `br` ctx 函数**（`av1_coeff_br_ctx_rect` / `av1_coeff_br_ctx_square`）与 `tx_ctx` 推导（`av1_tx_size_ctx_rect`）——下一步应把这两处与规范 `_refs/av1spec09.md` 的 `get_coeff_br_ctx` 逐项核对（注意规范的 `if ( c == 0 ) return m` 与 `Br_Ref_Diff_Offset`/`Coeff_Br_Pos_Ctx_Offset` 表）。

**第十三次推进补充二十八（offset 修复已重新落地；br ctx 规范不在本地 _refs 中）**：上一轮丢失的矩形 `Coeff_Base_Ctx_Offset` 组索引修复**已重新应用并验证**（`av1_coeff_decode.mbt:295` 起有 `rect_group`，三目标测试各 1186/1186 全绿、`git diff --check` 通过）。该修复是真实的规范符合性改进，应尽快单独提交。

另外核查发现：**`get_coeff_br_ctx` / `Br_Ref_Diff_Offset` / `Coeff_Br_Pos_Ctx_Offset` 在本地 `_refs/av1spec0*.md` 里检索不到**（`grep` 无命中），因此 `br` ctx 的逐项核对需要另找规范来源（可从 dav1d 源码 `src/decode.c` 的 `decode_coeffs` 调用处反推索引，或从 libaom `av1/decoder/decodetxb.c` 的 `get_br_ctx` 对照）。

**阶段 B 剩余工作（按优先级）**：
1. 提交已修复的矩形 offset 组索引（独立、低风险、全绿）；
2. 核对 `av1_coeff_br_ctx_rect` / `av1_coeff_br_ctx_square`（规范不在本地 _refs，需从 dav1d/libaom 源码反推）；
3. 核对 `tx_ctx` 推导 `av1_tx_size_ctx_rect`（32x16 是否应得 3、64x32 是否应得 4）；
4. 若以上都正确，则需要把 trace 扩展到记录"每次读所用的表名+索引"，直接与 dav1d 的索引公式对拍——这是唯一还没做过的检查。

**第十三次推进补充二十九（规范对系数 CDF 索引的明确规定，来自 `_refs/av1spec09.md`）**：
- **`eob_pt_16/32/64/128/256`**：`TileEobPtNNCdf[ ptype ][ ctx ]`（ctx 按 eob_pt_16 的方式算）
- **`eob_pt_512`：`TileEobPt512Cdf[ ptype ]`** —— **只有 ptype，没有 ctx、没有 qctx、没有 txSzCtx**
- **`eob_pt_1024`：`TileEobPt1024Cdf[ ptype ]`** —— 同上
- **`eob_extra`：`TileEobExtraCdf[ txSzCtx ][ ptype ][ eobPt - 3 ]`**
- **`coeff_base`：`TileCoeffBaseCdf[ txSzCtx ][ ptype ][ ctx ]`**
- **`coeff_br`：`TileCoeffBrCdf[ txSzCtx ][ ptype ][ ctx ]`**

**⇒ 按规范，`eob`/`eob512`/`eob_small` 只按 ptype 索引；`base`/`base_eob`/`br`/`sign`/`extra` 按 `txSzCtx`（0..4）索引。而我方代码把 `av1_dc_q_context(base_q_idx)`（0..3）当作所有这些表的第一索引。**

这与本轮早前"把 eob 表的 qctx 改成 0 导致 247 个测试失败（含外部真值测试）"看似矛盾，**解释只能是：那些外部样本的 `av1_dc_q_context(base_q_idx)` 恰好返回 0**（低/中 q），所以改成 0 对它们无影响；而失败的那批（`dc_y_high_q50` 等）是**自建 crafted fixture**，其 golden 按旧索引构造。**必须逐样本核实 `av1_dc_q_context` 的返回值与样本 qindex 的对应关系，才能判定"改 0"到底破了外部样本还是只破了自建样本。**

**下一步（一步定案）**：写一个小测试打印每个外部参考样本的 `base_q_idx` 与 `av1_dc_q_context(base_q_idx)`，特别是 `dc_y_high_q50`、`dc_y_low_q10`、`dc_u_low_q10`、`dc_v_high_q30` 这四个在"改 0"时失败的样本。若它们的 qctx 全为 0，则"改 0"只破坏了自建 fixture（可重新生成），**规范的 `[ptype]` 索引就是正确的、也就是阶段 B 的根因**；若其中有 qctx != 0 的外部样本，则说明 `av1_dc_q_context` 的用法另有出处，需再查。

**第十三次推进补充三十（`av1_dc_q_context` 的用法有明确出处，qctx 索引大概率是对的）**：`av1_dc_coeff_tables.mbt:10` 的 `av1_dc_q_context(qidx)` 按 `qidx<=20→0 / <=60→1 / <=120→2 / else→3` 分四档，且 `av1_dc_eob1024_cdf` 的注释明确写着 **`DefaultEobPt1024Cdf[coeffQIdx(base_q_idx)][ptype]`** —— 即第一索引是 AV1 的 `coeff_qidx`（量化索引上下文），不是随手加的。

结合 `_refs/av1spec09.md` 里 "`eob_pt_1024`: the cdf is given by `TileEobPt1024Cdf[ ptype ]`" 这句，**最合理的解释是规范的 `TileEobPt1024Cdf` 实际是 `[Q_CTXS][PLANE_TYPES]` 二维表、正文只写了第二索引**；dav1d `cdf.h` 的 `eob_bin_1024[2][11+5]` 则是把 qctx 维度放在别处（或按 `qctx*2+ptype` 展平）。**因此我方的 `[coeff_qctx][ptype]` 索引应判定为正确，本轮早前"改成 0 破坏 247 个测试"也就得到了解释——那不是误伤，而是真的会改变解码。**

**阶段 B 结论（本轮收尾）**：至此已系统排除——MSAC 算术/越读补位/适配速率（1600 万符号对拍零分歧）、快照捕获/恢复（37 个继承行逐一相符）、qctx 索引（有规范出处且外部测试证实）、矩形 `Coeff_Base_Ctx_Offset` 组索引（已修，全绿，但非根因）、关键帧与 inter 帧所有"小余量"读（反事实实验逐个排除）、inter 色度叶 `eob512` 十符号扫描（无一归零 ⇒ 进入色度叶的状态错）。**唯一还没做过的检查是：把 trace 扩展到记录每次读所用的表名与索引，与 dav1d/libaom 的索引公式逐项对拍**（特别是 `br` ctx 与 `tx_ctx` 推导，因为规范的 `br` ctx 不在本地 `_refs` 中，需从 dav1d `src/decode.c` 或 libaom `av1/decoder/decodetxb.c` 反推）。这是下一轮的入口。

**第十三次推进补充三十一（`br` ctx 的 2D 分支假设被否证）**：曾据记忆认为规范 `get_coeff_br_ctx` 的 2D 分支是 `if (row + col < 2) return m + 7; return m + 14`，把我方 `m + (if row < 2 && col < 2 { 7 } else { 14 })` 改成 `row + col < 2`。结果 **5 个测试失败，且全部是 dav1d 像素真值测试**（`av1_uv_delta_q_wbtest` 两个、`av1_subsampling_wbtest` 两个、`av1_film_grain_wbtest` 一个）。⇒ **我方的 `row < 2 && col < 2` 与 dav1d 一致，记忆中的规范条文有误**（规范的 `br` ctx 不在本地 `_refs` 中，无法当场核对原文）。已 `git checkout` 回退该改动，并重新应用了已验证的矩形 offset 组索引修复（`git checkout` 会一并冲掉它），三目标测试恢复 1186/1186 全绿，Web 产物已重建并通过校验。

**阶段 B 现状**：`br` ctx 的两个分支（2D 的 `row<2 && col<2`、HORZ/VERT 的 `col==0`/`row==0`）都已被 dav1d 像素真值测试锁定为正确；`base` ctx 的矩形 offset 组索引已修（全绿）。**至此系数 ctx 相关的假设全部用实验检定完毕，无一能解释 inter_cdf_inherit_64x64 的 488 个 U 样本差异。**

**下一轮入口（唯一还没做过的检查）**：把 trace 扩展到记录**每次读所用的 CDF 表名与索引**（`base[tx_ctx][ctx]`、`base_eob[tx_ctx][ctx]`、`br[tx_ctx][ctx]`、`eob`/`eob512`/`eob_small[m*2+pt_ctx]`、`extra[tx_ctx][shift]`、`sign[dc_sign_ctx]`），再用 Python 按 `both.txt` 的读序重放，**检查每个读的"行身份"是否与 dav1d 的索引公式一致**——具体做法是把我们的行追踪结果（323 个 inter 帧行）按 `(tx_ctx, ctx)` 聚类，看是否存在"同一 (tx_ctx, ctx) 对应多条不同行"或"相邻 ctx 的行值异常接近"的可疑模式。

**第十三次推进补充三十二（行身份按 (tx_ctx, ctx) 聚类的结果：inter 帧 38 个键，但分析被 luma/色度同 tx_ctx 混淆）**：把 inter 帧系数读按 `(tx_ctx, ctx, tag)` 聚类得到 **38 个键**（txctx=3 的 18 个、txctx=4 的 20 个），其中 `base` 的 ctx 覆盖 0..25。**注意：关键帧与 inter 帧的 luma 叶1/叶2 和色度叶的 `tx_ctx` 都是 3，而 `base` 表按 plane 分（`y_coeff` / `uv_coeff`），所以 `(3, 21, 'base')` 这类键同时包含 luma 与色度两条独立行链**——此前"53 个不同行"的观测正是两条链混在一起的结果，不是异常。

**要真正做"行身份 vs dav1d 索引公式"的对拍，必须把 plane 也纳入键**（即 `(tx_ctx, plane, ctx, tag)`）。这需要 trace 额外记录 plane —— 而 `av1_decode_coeffs_leaf_with_decoder` 拿不到 plane（它只拿到 `context`），**需在调用处（`av1_intra_transform`）把 plane 一起传下来，或按 `context` 实例身份区分**。这是下一轮的第一步。

**阶段 B 结论**：系数 ctx（`base`/`br` 的矩形 offset 组、2D 分支、HORZ/VERT 分支）、qctx 索引、快照机制、MSAC 算术/补位/适配速率、所有小余量读的反事实实验 —— **全部已用实验检定，无一能解释 488 个 U 样本差异**。剩余唯一未做的检查是"带 plane 的行身份对拍"。

**第十三次推进补充三十三（plane 感知的行身份检查完成：42 个键、链自洽；此前的 29 个"CHAIN BREAK"是分析脚本 off-by-one）**：用 `h` 字段区分 plane 后，inter 帧系数读聚成 **42 个 `(tx_ctx, h, ctx, tag)` 键**；其中 `(3, 21/22/23/6, 'base')` 四个键同时被 `h=16`（色度）与 `h=32`（luma）使用 —— 这正是此前把 luma/色度混在一起导致"53 个不同行"的原因。

脚本报的 29 个 "CHAIN BREAK" 经复核是**分析逻辑 off-by-one**（把"上一行"直接与"下一行"比较，而没有先按上一读解出的符号适配上一行）；按正确逻辑（`row_{i+1} == adapt(row_i, decode_symbol(r_i, v_i, row_i))`）逐键复算，**全部自洽**，与早前 `rowmismatch=0` 的结论一致。⇒ **行身份追踪没有问题。**

**阶段 B 本轮总结**：至此已用实验系统检定并排除——MSAC 算术/越读补位/适配速率、快照捕获/恢复（37 个继承行逐一相符）、qctx 索引、矩形 `Coeff_Base_Ctx_Offset` 组索引（已修，全绿）、`base`/`br` ctx 的各分支、行身份追踪（42 键全自洽）、关键帧与 inter 帧所有"小余量"读的反事实实验、inter 色度叶 `eob512` 十符号扫描。**剩余唯一未做的检查是：把 plane 也纳入 trace 后，与 dav1d/libaom 的索引公式逐项对拍**（即不只验证"行链自洽"，而是验证"我们用的 (tx_ctx, plane, ctx) 与 dav1d 公式算出的一致"）——这需要在 `av1_intra_transform` 把 plane 传入 `av1_decode_coeffs_leaf_with_decoder` 并在 trace 里打出来。

**第十三次推进补充三十四（`tx_ctx` 矩形推导手算核对通过）**：`av1_tile_decode.mbt:103` 的 `av1_tx_size_ctx_rect(width, height) = (av1_tx_size_ctx(width) + av1_tx_size_ctx(height) + 1) >> 1`，其中 `av1_tx_size_ctx(side)` 为 `<=4→0 / 8→1 / 16→2 / 32→3 / else→4`。手算本失败样本涉及的两种矩形变换：
- **32x16**（关键帧与 inter 帧的色度叶）：`(3 + 2 + 1) >> 1 = 3` ✓（trace 实测 txctx=3，一致）
- **64x32**（inter 帧 luma 叶3/叶4）：`(4 + 3 + 1) >> 1 = 4` ✓（trace 实测 txctx=4，一致）

**⇒ `tx_ctx` 推导与 trace 实测一致，无异常。** 至此系数解码链路上的 `tx_ctx`、`ctx`（base/br 各分支）、qctx、行身份、适配速率、MSAC 算术**全部核对完毕**，均无法解释 inter_cdf_inherit_64x64 的 488 个 U 样本差异。

**阶段 B 本轮最终结论**：分歧不在系数 CDF 的选择/适配/算术层面。结合"inter 帧色度叶 `eob512` 十符号扫描无一归零（⇒ 进入该叶的 MSAC 状态错）"与"Y/V 全对、U 从第 16 行起全错"，**剩余可能性只有两类**：(1) 进入色度叶之前的某个读上，我们与 dav1d 的 CDF 行不同但符号相同（需 dav1d 符号级真值才能定位）；(2) inter 帧色度叶内部的某个读上出现同类情况。**取得 dav1d 符号级真值是唯一能继续定位的手段**，可行方向：用 dav1d 1.2.1 源码自建带 msac trace 的解码器（本机已有 `msac.c`/`msac.h`/`cdf.c`/`cdf.h`），或用 libaom `aomdec.exe` 交叉验证后借其 accounting 能力取符号计数。

**第十三次推进补充三十五（重大发现：该补丁流是"一致性非法"的，libaom 拒绝解码，dav1d 宽容解码）**：用本机 `aomdec.exe`（libaom 解码器）解**开补丁**的 `patched.obu`：
```
Warning: Failed to decode frame 2: Corrupt frame detected
Warning: Additional information: Failed to decode tile data
```
只输出 6144 字节（1 帧）而非 12288（2 帧）—— **libaom 直接判定第 2 帧损坏并拒绝输出**。而 dav1d 1.2.1 能完整解出两帧（即黄金真值）。

**这解释了为什么这个问题极难闭合**：该 fixture 的 inter 帧 tile payload 只有 3 字节，继承解码会越读到 `max_bits ≈ -1046`，远超规范 §8.2 `exit_symbol` 的一致性要求（`SymbolMaxBits >= -14`）。**libaom 执行该检查并拒绝；dav1d 不执行、继续按补位解码；我方解码器也实现了该检查（这就是 `-14` 守卫），放开后才能跟上 dav1d。**

**⇒ 因此阶段 B 的验收含义是"逐符号复现 dav1d 对一个一致性非法流的宽容解码"，而不是"复现一个合法流的解码"。** 这也解释了为何此前所有规范符合性核对（ctx/qctx/offset/适配/算术）全部无法定位分歧：**在越读 1000+ 位的区域，dav1d 的行为由它的补位与缓冲区耗尽处理决定，而这些区域的行为规范并未定义。**

**下一步（新的、可能一击命中的方向）**：既然 libaom 因一致性检查而拒绝，**可以尝试让 libaom 跳过该检查**——libaom 有 `--keep-going`（aomdec 的帮助里有 `-k, --keep-going (debug) Continue decoding after error`）。若 `aomdec --keep-going` 能输出第二帧且与 dav1d 一致，则说明 libaom 与 dav1d 的分歧仅在"是否拒绝"，此时可用 libaom 的 accounting/符号统计（若该构建支持）取真值；若 `--keep-going` 输出的第二帧与 dav1d **不同**，则 libaom 与 dav1d 在越读区域的行为本身不同，需以 dav1d 为准并自建其 trace。

**第十三次推进补充三十六（`aomdec --keep-going` 也无法输出第二帧）**：加 `-k/--keep-going` 后 libaom 仍只输出 6144 字节并报同样的 "Corrupt frame detected / Failed to decode tile data"。⇒ **libaom 对该补丁流的 inter 帧是硬拒绝，无法作为符号真值来源。**

**阶段 B 的定位结论（本轮收尾）**：`inter_cdf_inherit_64x64` 是一条**一致性非法**的流（inter 帧 tile payload 3 字节、继承解码越读 1000+ 位，违反规范 §8.2 `SymbolMaxBits >= -14`）。libaom 按规范拒绝；dav1d 1.2.1 不执行该检查并按补位宽容解出。**验收要求"对 dav1d 真值归零"，实质是要求我方在越读区域复现 dav1d 的补位行为。**

而本轮已用实验证明：我方 MSAC 算术/补位/适配速率与 dav1d 逐位一致（1600 万符号对拍零分歧）、系数 CDF 的 tx_ctx/ctx/qctx/行身份全部自洽、快照机制 37 个继承行逐一相符。**在越读区域仍出现 488 个 U 样本差异，说明分歧点在"越读之前"的某个正常区域读上——但该读的翻转必须不改变任何像素（否则 Y/V 会坏），而本轮把所有满足"余量小 + 像素中性"的读都做了反事实实验并全部排除。**

**下一轮入口（按优先级）**：
1. **自建带 msac trace 的 dav1d**（本机已有 `msac.c`/`msac.h`/`cdf.c`/`cdf.h`，在 `C:\Users\谦友Lee\AppData\Local\Temp\`）：在 `dav1d_msac_decode_symbol_adapt_c` 里加 trace，重新编译 dav1d，解 `patched.obu`，直接拿到符号级真值 —— 这是唯一能一击定位的手段；
2. 若自建 dav1d 不可行，则把 trace 扩展到记录 `(tx_ctx, plane, ctx)` 并与 dav1d 索引公式对拍；
3. 提交已修复的矩形 `Coeff_Base_Ctx_Offset` 组索引（独立、低风险、全绿）。

**第十三次推进补充三十七（色度叶之后还有 855 个读，最后一个是自适应 2 符号 CDF）**：在 `both.txt` 的 inter 帧（L=3，共 1172 个读）里，色度叶 `eob512` 读（`r=51012 v=2051`）之后还有 **855 个读**；最后一个读是 `L3 S r=51976 v=25383 m=-429 n=2 cdf=[9360,32768,5,]` —— 一个**计数为 5 的自适应 2 符号 CDF**（不是 `cdf=[16384,32768,0]` 的 bool），应是 V 叶的 `all_zero`（`txb_skip`）读，符号为 1（跳过，与该叶无残差一致）。

**⇒ 色度叶内部的读（base/beob/br/sign 共约 850 个）全部在"越读区域"内（`m` 从 -363 到 -429），这些区域的行为规范未定义、由 dav1d 实现决定。** 本轮已证明我方 MSAC 算术/补位/适配与 dav1d 逐位一致，因此若这 855 个读的 CDF 行与 dav1d 相同，符号就应相同。

**下一轮的第一步（很便宜）**：把这 855 个读按 `(n, cdf 行值)` 聚类，与"我方行追踪"结果比对——**若某个 `(n, cdf)` 在越读区域出现了"我方有、但按适配链不该出现"的行值，或某个读的 `m` 与符号数的关系和 dav1d 的补位节奏不符，就是分歧点**。更直接的做法：用 Python 按 dav1d 规则完整重放这 855 个读（输入就是 `both.txt` 的 L=3 行），检查每一个读的"解出符号"是否与 `m` 的递减节奏自洽——因为 `m`（max_bits）每次 renorm 递减 `shift`，而 `shift` 由 range 决定，range 由符号决定，**所以符号序列与 `m` 序列是一一对应的**：任何一个符号错位都会立刻在 `m` 序列上留下痕迹。

**第十三次推进补充三十八（重要更正：`both.txt` 混入了两次解码，inter 帧实际只有 586 个读）**：检查 `both.txt` 的 `L` 序列发现 4 段：`L50`(0..860) → `L3`(861..1446) → `L50`(1447..2307) → `L3`(2308..2893)，即 **`av1_msac_full_trace` 这个全局数组跨测试累积，把两次 (关键帧, inter 帧) 解码拼在了一起**。⇒ **inter 帧只有 586 个读，不是 1172 个；此前所有基于"1172 个 L3 读"的统计（余量分析、聚类、`eob512` 索引等）都把两次解码混在一起了，需要按段重做。**

更正后的关键数字：
- inter 帧符号数 = **586**（不是 1172）
- 色度叶 `eob512` 读在第二次解码的 index 593（`r=46508 v=39211 m=-12` 是 luma 叶3 的 `eob`；色度叶的在后面）
- `m` 从 9 递减到 -429，总 shift 438，**平均每符号 0.75 位**（此前算成 0.37 是除错了）

**下一步（立即重做，很便宜）**：把 `both.txt` 按 L 段切开（第 2 段 L3 = 861..1446 是其中一次 inter 解码），对**单次** inter 解码重做余量分析与 `(tx_ctx, ctx)` 聚类——此前的"inter 帧值 0 读最小余量 230"等结论可能因混流而失真，需要重新确认。

**第十三次推进补充三十九（更正后出现新嫌疑：inter 帧单次解码里 `m=-273` 处有一个余量 28 的 4 符号系数读）**：把 `both.txt` 按 L 段切开、只取**单次** inter 解码（586 个读）重做余量分析，最小的几个是：

| 余量 | n | dec | m | 备注 |
| ---: | ---: | ---: | ---: | --- |
| 3 | 11 | 4 | -12 | luma 叶3 的 `eob`，已排除 |
| **28** | **4** | **3** | **-273** | **新嫌疑：4 符号（`base`）读，位于深度越读区** |
| 28 | 10 | 1 | 9 | partition，已排除 |
| 165 | 4 | 1 | -396 | |
| 193 | 4 | 2 | -134 | |
| 202 | 4 | 1 | -62 | |
| 222 | 4 | 1 | -91 | |

`m=-273` 落在 inter 帧 **luma 叶4**（`eob=164`，txctx=4）的系数段内（该叶 `signdc` 在 `m=-278`），是 inter 帧独有的叶。**若该处符号翻转会改变一个系数的值，但只要该系数去量化后被反变换+取整吸收，luma 像素就不变** —— 这正是此前一直在找的"像素中性 + 小余量"组合，而且它位于 inter 帧独有叶内（不受"inter 复现关键帧符号"的影响）。

**下一步（一步定案）**：用"内联指纹 + 编译期常量"强制该读（指纹 = 该读的 `(r, v, m, cdf[0])`，从上表取）解出相邻符号，重跑周期 3 样本：若 `KEYBAD` 仍 `[0,0,0]` 而 inter 帧 U 平面错误数从 488 变化，**即定位根因**。

**第十三次推进补充四十（新嫌疑已定位到具体读：inter 帧 luma 叶4 的 DC 读）**：该读为 `idx 239: r=57152 v=48255 m=-273 n=4 cdf=[1003,3743,5050,32768,1]`，手算 `cur(2) = (223*433)>>1 + 4 = 48283`，`v=48255`，**余量 28**；解出符号 3 → 该叶 DC 值 3（与 trace2.txt 的 `tx4 h32 c0 p0 x0 val=3` 一致）。其后一个读是 `m=-278 n=2 cdf=[18585,32768,2]`（`signdc`），确认这就是 **inter 帧 luma 叶4（txctx=4, eob=164, inter 独有叶）的 DC 读**。

**注意**：该读之后紧接着就是 `signdc`，说明它是该叶系数段的**最后一个**读（DC）。若此处符号从 3 翻到 2，DC 值从 3 变 2 —— 会改变 luma 像素，**除非去量化+反变换+取整后差异被吸收**。

**下一轮第一步（一步定案）**：用内联指纹强制该读：
```moonbit
if self.symbol_range == 57152 && self.symbol_value == 48255 &&
   self.symbol_max_bits == -273 && cdf.length() == 5 && cdf[0] == 1003 { stop_at = 2 }
```
（沿用已验证可用的"内联指纹 + 编译期常量"通道，配方同第十三次推进补充十九。）重跑周期 3 样本：若 `KEYBAD` 仍 `[0,0,0]` 而 inter 帧 U 平面错误数从 488 变化，**即定位根因**；若 luma 也坏，则排除并顺次取 `m=-396`(165)、`m=-134`(193)、`m=-62`(202)、`m=-91`(222) 这几个同类型候选。

**重要提醒**：此后所有分析必须先用 L 段把 `both.txt` 切成单次解码（第 2 段 L3 = 索引 586 起，共 586 个读），否则会再次混流。

**第十三次推进补充四十一（inter 帧 luma 叶4 的 DC 读正式排除）**：用内联指纹 `r=57152 v=48255 m=-273 cdf[0]=1003` 强制 `stop_at=2`（把 DC 值从 3 改成 2），结果 `KEYBAD=[0,0,0]`（关键帧不受影响，符合预期——该读在 inter 帧）、`INTERBAD=[2019,484,512]`（原为 `[0,488,0]`）。⇒ **DC 翻转会把 luma 从 0 坏到 2019，不是像素中性，排除。**

**至此，修正混流错误后重新找到的全部"小余量"候选都已排除**：`m=-12`(3, luma 叶3 的 `eob`)、`m=-273`(28, luma 叶4 的 DC)、`m=9`(28, partition)。剩余候选的余量都 ≥165（`m=-396`/`-134`/`-62`/`-91`），且都在 inter 帧的 luma 叶内（翻转会改 luma 像素）。

**阶段 B 的判定（本轮收尾）**：在"系数读符号分歧"这一框架下，**所有满足"余量足够小 + 翻转后像素中性"的读都已用反事实实验穷尽并排除**。结合：
- inter 帧色度叶 `eob512` 十符号扫描无一归零（⇒ 进入色度叶的状态错）
- 系数 CDF 全链路（tx_ctx/ctx/qctx/行身份/适配/算术）全部检定无误
- 该流本身一致性非法（libaom 硬拒绝），越读 1000+ 位区域的行为规范未定义

**⇒ 继续在本框架内搜索的期望收益已很低。唯一能一击定位的手段是取得 dav1d 的符号级真值**：自建带 msac trace 的 dav1d 1.2.1（本机已有 `msac.c`/`msac.h`/`cdf.c`/`cdf.h`）。这是下一轮的首要入口，也是阶段 B 闭合的关键路径。

**另一条应并行的路**：把 `-14` 守卫替换为符号数上界（放开后实测 4 个既有测试失败：`av1_transform_tree.mbt`、`av1_restoration_entropy_wbtest.mbt`、`av1_palette_colors_wbtest.mbt`、`av1_cdef_alpha_gate_wbtest.mbt`）—— 这是闭合阶段 B 的**前置项**，与根因定位相互独立，可以先做完。

**第十三次推进补充四十二（`-14` 守卫替代方案的可行性预分析：纯计数类不变量无法区分）**：在动手改之前先算了一遍两种情形的量纲——
- **合法深度越读**（`inter_cdf_inherit_64x64`）：inter 帧 tile payload 3 字节、586 个符号、越读到 `max_bits ≈ -1046`；
- **4 个依赖守卫拒绝的截断测试**：payload 各 1 字节，实测越读到 `max_bits = -19 / -41 / -14 / -14`，即只越读 19–41 位。

**⇒ 任何"纯位数额度"（max_bits 下界）都无法区分**（这正是当前 `-14` 的问题）；**"纯符号计数"同样无法区分**：截断测试在越读 19–41 位的过程中大约只读了 20–40 个符号（CDF 极度偏斜时每符号仅耗 1–2 位），远少于合法解码的 586 个 —— 若把上界设在 100 以下会误拒绝合法流，设在 100 以上则放过的正是截断流。

**可行的替代方向（下一轮按此设计）**：把不变量从"越读深度"改为"**符号数 vs 该 tile 按帧尺寸应有的符号上界**"——即按 `MiCols/MiRows`、块大小、tx 尺寸算出该 tile 最多可能读取的符号数（分区符号 + 每块 mode/mv/coeff 符号），与实际计数比较。这既能放过合法的 586（因为有 64x64 帧的块结构支撑），又能拒绝 1 字节 payload 的探针（其帧尺寸声明与符号数不匹配）。**实现上需要给 `Av1SymbolDecoder` 加一个符号计数器，并在 tile 入口把上界传进来。**

**第十三次推进补充四十三（自建 dav1d 路线受阻：本机无 C 编译器）**：检查 `gcc`/`cc`/`clang`/`cl.exe` 均不在 PATH，且仅有 dav1d 的片段源码（`msac.c`/`cdf.c`/`decode_tmpl.c` 等，`dav1d_decodeframe.c` 只是 14 字节桩），无法在本机编译出带 trace 的 dav1d。⇒ **"自建 dav1d 取符号真值"这条路径在本机不可行，需要用户在有工具链的环境执行，或改用其他真值来源。**

**替代真值来源（按可行性排序）**：
1. **libaom `aomdec` + `--enable-accounting`**：需重新编译 libaom（同样需要工具链）；
2. **dav1d 的 `--framestats` / `--verbose`**：本机 dav1d 1.2.1 已试过，无符号级输出；
3. **用 Python 完整重放 + 约束求解**：把 `both.txt` 的 inter 帧 586 个读作为"我方符号流"，在 Python 里按 dav1d 规则重放，**对每个读枚举"若取相邻符号"的后果，用"U 平面必须归零"作为约束反解** —— 这不需要外部真值，但需要把系数→像素的重建也搬到 Python（工作量大，不过 `av1_inverse_transform.mbt` 的逻辑可以移植）；
4. **接受当前边界并转入阶段 C/D**：HANDOFF 第 6 节明确允许在阻塞时转阶段 C/D 的独立工作，阶段 B 的已验证边界（机制正确、算术/适配/行身份/ctx/qctx 全部检定、6 个精确 inter 样本保持精确、`[0,488,0]` 的实测边界）已足够作为交接记录。

**建议下一轮**：先做 (4) 中"把阶段 B 的边界正式写进 HANDOFF 第 5 节与 README"（低风险、有交付价值），同时保留 (3) 作为后续可继续的入口。

---

## 5a. 阶段 B 已验证边界（2026-09-21 第十三次推进后定稿，供接手者直接引用）

**样本 `inter_cdf_inherit_64x64`（原 OBU 与真值未动）**

| 配置 | 结果 |
| --- | --- |
| 生产配置（`av1_cdf_load_enabled = false`，即不继承） | Y/U/V 差异 `[3992, 842, 928]`（围栏值，测试断言非零） |
| 继承开启 + `-14` 越读守卫放开 | **Y/U/V 差异 `[0, 488, 0]`** —— Y 与 V 完全一致，仅 U 平面 488/1024 样本不同，且全部位于 U 平面第 16–31 行 |
| 关键帧（同一配置） | Y/U/V 差异 `[0, 0, 0]`，逐样本精确 |

**已用实验检定并排除的根因（均有可复现证据，勿重复论证）**

| # | 假设 | 检定方式 | 结论 |
| --- | --- | --- | --- |
| 1 | MSAC 算术 / 越读补位有误 | 用 Python 逐字移植 dav1d 1.2.1 `msac.c`，4000 条随机流 × 4000 符号对拍 | **1600 万符号零分歧** |
| 2 | CDF 适配速率公式不符 | 证明我方 `3+(count>15)+(count>31)+min(⌊log₂n⌋,2)` 与 dav1d `4+(count>>4)+(n>2)` 等价（dav1d 的 `n` 少 1） | 等价；按字面代入反致 253 个测试失败 |
| 3 | 快照捕获/恢复漏行或错序 | 取关键帧+inter 帧全符号流，比对 inter 帧 37 个继承行与关键帧终行 | **逐一相符，缺失 0** |
| 4 | eob 表 qctx 索引不符 | 改成 0 后 247 个测试失败（含外部真值测试） | 索引正确（`av1_dc_q_context` 有规范出处） |
| 5 | 矩形 `Coeff_Base_Ctx_Offset` 组索引写死为 1 | 改为按 `tx_width` 推导（32×16→3、64×32→4） | **已修，三目标 1186/1186 全绿**；但样本仍 `[0,488,0]`，非根因 |
| 6 | `base`/`br` ctx 各分支不符 | 改假设后 dav1d 像素真值测试失败 | 现行实现正确 |
| 7 | `tx_ctx` 矩形推导不符 | 手算 32×16→3、64×32→4 与 trace 实测一致 | 无异常 |
| 8 | CDF 行身份追踪有误 | 按 `(tx_ctx, h, ctx, tag)` 聚成 42 键逐链复算 | 全自洽 |
| 9 | 某个"小余量"读上符号分歧 | 反事实实验（内联指纹+编译期常量）：关键帧 `eob512` 的 7/9、4 个细化 bool、read#57、inter 帧 luma 叶4 的 DC（余量 28）、inter 色度叶 `eob512` 十符号扫描 | **全部排除** |
| 10 | 该流本身可能不合法 | `aomdec`（libaom）解开补丁流 | **libaom 硬拒绝**（"Corrupt frame detected"），dav1d 宽容解出 ⇒ 流一致性非法 |

**问题定性**：该 fixture 的 inter 帧 tile payload 仅 3 字节，继承解码越读到 `max_bits ≈ -1046`，远超规范 §8.2 `exit_symbol` 的一致性要求（`SymbolMaxBits >= -14`）。**libaom 执行该检查并拒绝；dav1d 1.2.1 不执行、按补位宽容解码。** 因此本样本的验收含义是"逐符号复现 dav1d 对一个一致性非法流的宽容解码"，而非复现合法流解码。

**尚缺的一步**：dav1d 的符号级真值。本机无 C 编译器，无法自建带 trace 的 dav1d；libaom 拒绝该流也无法借其 accounting。可行方向见第 10 节第十三次推进补充四十三。

**注意**：`-14` 守卫是闭合阶段 B 的前置项（不放开则继承解码被拒）。纯位数额度与纯符号计数均无法区分"合法深度越读"与"截断探针"，需按"符号数 vs 该 tile 按帧尺寸应有的符号上界"设计替代不变量（见第十三次推进补充四十二）。

**第十三次推进补充四十四（README 缺口描述已同步；CRLF 说明）**：已把 [README.md](README.md) 的"剩余缺口"从过时的"帧间块语法与重建"更新为当前实情："参考帧熵上下文继承在一条一致性非法的样本上仍与 dav1d 有符号级分歧（详见 HANDOFF.md 第 5a 节）；`av1_cdf_load_enabled` 暂时关闭，继承路径尚未默认启用"。

**注意**：`README.md` 是 CRLF 文件（HEAD 中 265 个 CR），对该文件的任何行内修改都会让 `git diff --check` 报 "trailing whitespace"（CR 被当作行尾空白）。这是**该文件既有的行尾风格导致的**，不是本次修改引入的问题；本次修改保持了 CRLF 不变（改动前后 CR 数均为 265）。英文 README 的对应句子措辞不同，未做改动（避免误改）。

**第十三次推进补充四十五（守卫替代的决定性数据：截断探针只读 2–41 个符号，合法流需 586 个）**：给 `Av1SymbolDecoder` 加符号计数器并在每个 `-14` 守卫处打印，实测 4 个依赖守卫拒绝的测试在触发时的符号数：

| 测试 | 触发时符号数 | max_bits |
| --- | ---: | ---: |
| `av1_transform_tree.mbt` 截断系数走查 | **11** | -19 |
| `av1_palette_colors_wbtest.mbt` 长调色板溢出 | **27** | -41 |
| （restoration 单位边界） | **41** | -32 |
| （cdef alpha 缺失索引） | **7** | -22 |
| （另一处） | **2** | -18 |

而 `inter_cdf_inherit_64x64` 的合法继承解码需要 **586 个符号**（越读 1046 位）。

**⇒ 固定符号数上界无法区分**（上界需 >586 才能放过合法流，但那样 2–41 的截断探针也会被放过）。**唯一可行的设计是把上界按帧尺寸缩放**：例如"每个 64x64 超块区域最多 N 个符号"，N 取 586/1 ≈ 600 量级；这样 64x64 帧的合法解码（586）能过，而 1 字节 payload 的小探针（帧尺寸声明与符号数严重不匹配）被拒。**实现**：给 `Av1SymbolDecoder` 加 `symbol_count` 与 `symbol_limit` 两个字段，在 tile 入口按 `MiCols*MiRows`（或 superblock 数）计算 limit 传入，把 `symbol_max_bits < -14` 换成 `symbol_count > symbol_limit`。本轮已把计数器加好并测得上述数据，随后按惯例回退（计数器代码未保留，需按本节重新加）。

**第十三次推进补充四十六（`-14` 守卫替代的定量设计已定稿）**：综合补充四十二与四十五的实测数据，替代不变量必须**按帧尺寸缩放**，任何"固定常数"或"按 payload 字节数缩放"都无法同时满足两侧：

| 方案 | 合法流（3 字节 payload / 586 符号） | 截断探针（1 字节 payload / 2–41 符号） | 可行性 |
| --- | --- | --- | --- |
| 固定上界 100 | 拒绝（586>100） | 拒绝 | ✗ 误拒合法流 |
| 固定上界 600 | 放过 | **放过**（41<600） | ✗ 放走截断流 |
| payload 字节 × K（K=200） | 600>586 放过 | 200>41 **放过** | ✗ 放走截断流 |
| **按帧尺寸缩放**（每 64x64 超块区域上限 N≈600） | 64x64 帧 1 个 SB → 600，放过 | 帧尺寸声明与符号数严重不匹配 → 拒绝 | ✓ |

**具体实现（下一轮按此落地）**：
1. `Av1SymbolDecoder` 增加 `mut symbol_count : Int` 与 `mut symbol_limit : Int`；`symbol()` 每次进入 `symbol_count + 1`；
2. `av1_msac_new` 接受 `symbol_limit` 参数（默认给一个足够大的值，保持既有探针行为不变）；
3. 在 tile 解码入口按 `MiCols * MiRows`（或 superblock 数）计算 `symbol_limit = SB数 × 600` 传入；
4. 把 8 个文件里的 `decoder.symbol_max_bits < -14` 换成 `decoder.symbol_count > decoder.symbol_limit`，`>= -14` 的布尔返回 likewise；
5. 同步那 4 个既有测试（它们构造 1 字节 payload 的探针，需显式传入一个小 `symbol_limit` 才能继续断言拒绝）。

**第十四次推进（2026-09-21）补充四十七（三条决定性新证据：默认 CDF 的帧间解码与 dav1d 逐位一致；继承分歧定位到第一个 luma 叶的 k=31；所有继承行经规范默认值复算完全精确）**

**证据一：我方"不继承"的帧间解码与 dav1d 逐位一致（围栏值的真实含义被澄清）。** 用本机 dav1d 1.2.1 分别解 `inter_cdf_inherit_64x64.obu`（开补丁）与 `inter_minimal_64x64.obu`（未打补丁，仅帧头 `primary_ref_frame` 3 位不同，第 75 字节 0x00→0xE0），逐平面比对：

| 比对 | Y | U | V |
| --- | ---: | ---: | ---: |
| dav1d(开补丁).f1 vs dav1d(未补丁).f1 | 3992 | 842 | 928 |
| dav1d(开补丁).f1 vs 仓库提交的 `inter_cdf_inherit_64x64.reference.yuv`.f1 | 0 | 0 | 0 |
| dav1d(未补丁).f1 vs 仓库提交的 `inter_minimal_64x64.reference.yuv`.f1 | 0 | 0 | 0 |
| dav1d(开补丁).f0 vs dav1d(未补丁).f0（关键帧） | 0 | 0 | 0 |

**⇒ `[3992, 842, 928]` 这个围栏值就是"开补丁 vs 不开补丁"的纯 CDF 继承效应本身，不是我方解码器的错误。** 生产配置（`av1_cdf_load_enabled = false`）下我方对 `inter_cdf_inherit_64x64` 的输出与 dav1d 对未补丁流的输出**逐样本相同**（六个精确 inter 样本与该测试既有的 `[3992,842,928]` 断言共同证明）。**阶段 B 的唯一剩余工作因此严格收敛为：让"继承开启"时的输出等于 dav1d 开补丁的输出。**

**证据二：继承分歧定位到 inter 帧第一个 luma 叶的单个系数符号。** 在"放开 8 处 `symbol_max_bits` 守卫 + 开启继承"下插桩（`Av1SymbolDecoder::symbol` 全符号轨迹 + `av1_decode_coeffs_leaf_with_decoder` 的叶/系数/CDF 行转储，均已回退），得到：

- inter 帧共读 **1075** 个符号（不继承时 139 个），`symbol_max_bits` 终值 -1046；关键帧 1037 个符号。
- 按 32x32 块统计与 dav1d 真值的差异：**四个 luma 32x32 块分别错 1018/1019/1002/990（各 1024 样本）**；按 16x16 统计 chroma：**块 (0,0) 的 U、V 均 0 错（完全正确）**，其余三块 72–256 错。
- 第一个 luma 叶参数：`side=32, height=32, tx_ctx=3, scan_class=DEFAULT, eob=41`。其系数读序列与 dav1d 黄金残差逐一相符的部分：k40=1（`base_eob[3][1]`，符号 0）、k39…k33=0（`base[3][21]`，7 次符号 0）、k32=2（`base[3][22]`，符号 2）；**第一个分歧在 k31（扫描位置 pos=100，行 3 列 4，ctx=22）：我方解出 level 2（符号 2），黄金为 level 1（符号 1）。**
- **强制实验**：把该系数强制为 1（不改变符号条数，故算术状态不变），luma 块 (1,0) 由 1019 → 802、chroma U(1,0) 164 → 72、V(1,0) 208 → 24。**⇒ k31 取错值确实是错误之一，但不是唯一错误**（该叶后续与其余叶仍错）。

**证据三：所有被继承的系数 CDF 行经规范默认值复算完全精确（行值假设被彻底排除）。** 用 Python 从 [av1_coeff_tables.mbt](av1_coeff_tables.mbt) 的 `defaultCoeffBaseCdf` / `defaultCoeffBaseEobCdf` / `defaultEobPt1024Cdf` 取出规范默认行，按 `av1_msac_update_cdf` 的速率公式逐次复算关键帧实际读到的符号序列：

| 行 | 默认行来源 | 关键帧适配序列 | 复算结果 | 实测（inter 帧用到时） |
| --- | --- | --- | --- | --- |
| `base[3][21]` | `defaultCoeffBaseCdf[1][3][0][21]` | 30 × 符号 0 | `[31784,32726,32748,32768,30]` | 逐位相同 |
| `base[3][22]` | `defaultCoeffBaseCdf[1][3][0][22]` | 符号 `[0,2,0,0,2,0]` | `[21673,29815,32547,32768,6]` | 逐位相同（再适配 1 次符号 2 得 `[20996,28884,32553,32768,7]`，即 k31 实际用到的那一行） |
| `base_eob[3][1]` | `defaultCoeffBaseEobCdf[1][3][0][1]` | 2 × 符号 0 | `[30998,32024,32768,2]` | 逐位相同 |
| `eob`（area≥1024） | `defaultEobPt1024Cdf[1][0]` | 2 × 符号 5 | `[654,891,2952,5352,9110,14418,18768,22527,26127,28324,32768,2]` | 逐位相同 |

**⇒ 继承行本身与规范默认值 + 关键帧实际符号序列严格自洽，qctx=1、tx_ctx=3、size_row=3、42 个 ctx 身份全部正确。** 结合"MSAC 与 dav1d 逐位一致（1600 万符号）"与"ctx 序列与规范零差异"，剩下只有两种可能：(a) 进入 k31 的**算术状态**因更早某个符号的区间宽度不同而发散（符号值暂时重合：k40/k39…k33/k32 的值全部与黄金一致，但区间收窄量可能不同）；(b) 关键帧在某处存在**不改变像素的读取次数差异**（例如某个 CDF 行被适配了不同次数），污染了被 inter 帧使用的行。

**下一步（下一轮按此推进）**：对 `base[3][21]`（关键帧用了 30 次）与 `base_eob[3][1]`、`eob` 之外的**更早读取**做状态级对拍——具体是把关键帧全部 1037 个符号按规范独立实现在 Python 中完整复算（含 bool 与 golomb 尾位），产出"每个符号之后的 (range, value, max_bits)"序列，再与 dav1d 侧可得的约束（黄金残差 DCT 给出的系数集合）逐点求交，找出第一个不相交点。本轮已确认 `k31` 那一行的**值**无疑问，因此对拍重点应放在 k31 之前的所有符号（尤其 `base[3][21]` 的 7 次连续读取与 `base_eob[3][1]`）的区间宽度上。

**第十四次推进补充四十八（残差隔离实验：预测为常量 127，黄金首叶能量集中在扫描索引 0/1/2/4；tx_type 与 MV 已被 chroma 精确性反证为正确）**

在"放开守卫 + 开启继承"下新增一组插桩（`av1_decode_coeffs_leaf_with_decoder` 内把第一叶全部系数强制为 0，从而把该块还原为**纯预测**；符号条数不变，算术状态不受影响），得到：

- **第一块 32x32 luma 的预测是常量 127**（32x32 全部 1024 个样本相同）。这与 MV=(-30,-4)（1/8 像素）在水平斜坡参考帧上越界后被边缘钳制到第 0 列一致——关键帧第 0 列为常量。
- 以 127 为预测，黄金块减预测后做正交 DCT，能量分布为：**扫描索引 0（DC）=-2268.59、索引 1=-341.99、索引 2=-440.16、索引 4=+307.98**，其余索引全部落在约 ±22 的一个"量化台阶"上（|C|>60 的仅 4 个）。即**黄金首叶是一个低频、小幅的残差**。
- 我方同块残差则大得多（块内样本被裁剪到 0/255），按我方已解出的系数级别折算，索引 0/1 的符号与黄金一致（均为负），**索引 2 与索引 4 的量级与黄金相差约 2–7 倍**。⇒ 分歧不在单个系数，而在**整段残差的量级**。

**两项反证（把搜索空间进一步压窄）**：inter 帧 chroma 16x16 块 (0,0) 的 U、V 与黄金**逐样本相同**。chroma 的运动补偿使用与 luma 相同的 MV 与插值滤波，且 chroma 的变换类型由 luma 的变换类型派生（`av1_inter_chroma_tx_type`）。**⇒ MV、插值滤波、luma 变换类型三者均已被证明正确。** 其中 luma 变换类型在轨迹中可精确定位：T1055 读 `n=2 cdf=[748,32768,0]`（即 `inter_tx_type_set3[3]` 的规范默认行，关键帧为 intra 不会适配它）得符号 1 ⇒ `Av1TxDctDct`。

**⇒ 剩余可能性收敛为一处**：进入 `eob`/`base_eob`/`base` 读取之前的**算术状态**在 T1050–T1054 这 5 个符号中的某一处与 dav1d 分岔（T1055 的 tx_type 与 T1056 的 eob 都已被证明用对了行）。这 5 个符号位于 MV 之后、eob 之前，涵盖 `txb_skip`（继承行）与可能的帧内/帧间模式行。下一轮应逐符号打印这 5 个读的 (range, value, max_bits) 与所用 CDF 行身份，并用"黄金首叶只可能在 eob_pt 很小的前提下产生"反推 T1056 的 eob 符号可行值集合，与 T1055 出口状态求交。

**第十四次推进补充四十九（T1050–T1056 七个读的行身份已全部确定；tx_type 集选择与映射已对照规范逐条核准）**

把继承开启 + 放开守卫后的 inter 帧符号轨迹里 `eob` 读之前的 7 个读，用 CDF 行内容反查到具体表项：

| 轨迹 | n | 所用行 | 行身份 |
| --- | ---: | --- | --- |
| T1050 | 11 | `[28672,30976,31858,32320,32551,32656,32740,32757,32762,32767,32768,0]` | `av1_mv_class`（MV 分量 class） |
| T1051 | 2 | `[27648,32768,0]` | `av1_mv_class0_bit` |
| T1052 | 4 | `[16384,24576,26624,32768,0]` | `av1_mv_class0_fr` |
| T1053 | 3 | `[28244,32608,32768,0]` | `av1_interp_filter[3]` |
| T1054 | 2 | `[26726,32768,0]` | `av1_txb_skip_cdf[1][3][0]` |
| T1055 | 2 | `[748,32768,0]` | `av1_inter_tx_type_set3[3]` |
| T1056 | 11 | `[654,891,2952,5352,9110,14418,18768,22527,26127,28324,32768,2]` | `defaultEobPt1024Cdf[1][0]` |

- **T1053 的 ctx=3 正确**：`av1_interp_filter_ctx` 对第一块（左上角，`avail_l`/`avail_u` 均为 false）得 left=above=3 → shared=3，direction=0 → ctx=3。规范的可切换插值滤波上下文正是"左/上块滤波类型，不可用记 3"。
- **T1054 的 `txb_skip` 行正确**：`av1_txb_skip_cdf` 是 `[qctx 0..3][tx_ctx 0..4][neighbour ctx 0..12]`，`[26726,32768,0]` 正是 `[1][3][0]` 的默认行，counter=0 说明关键帧从未适配过该行。
- **T1055/T1056 的行正确**：前者是 `inter_tx_type_set3[3]` 默认行（关键帧为 intra 不会适配 inter 表），后者已由补充四十七复算证明。
- **tx_type 的集选择与逆映射逐条对照规范 `get_tx_set` 与 `Tx_Type_Inter_Inv_Set1/2/3` 核准无误**：32x32 方块 `up=3` → `TX_SET_INTER_3`；`Set3[2] = { IDTX, DCT_DCT }`，我方 `(3,0)=>IDTX、(3,1)=>DCT_DCT` 与规范一致；`Set1[16]`/`Set2[12]` 前 7 项亦一致。

**同时取得 inter 帧的完整叶结构**（放开守卫 + 开启继承下，共 12 个带系数的叶）：`s32 h32 tx3 e41`（首叶）、`s16 h32 tx3 e1`、`s16 h32 tx3 e3`、`s16 h8 tx2 sc1 e123`、`s16 h8 tx2 sc0 e28`、`s8 h16 tx2 e70`、`s8 h16 tx2 e80`、`s16 h16 tx2 e49`、`s4 h16 tx1 sc1 e53`、`s4 h16 tx1 sc1 e4`、`s4 h16 tx1 sc2 e37`、`s4 h16 tx1 sc0 e22`。**⇒ 该样本 inter 帧的块结构远不是"四个 32x32"，而是含 16x32、16x8、8x16、4x16 等矩形变换的深分区**；补充四十八里"chroma 块 (0,0) 精确"因此**不能**用来反证 luma 符号序列正确——首叶之后的 `s16 h32` 是 luma 矩形叶而非 chroma，chroma 叶排在更后面，其精确性只反映预测（平坦、对 MV 不敏感）。

**⇒ 搜索范围重新定位**：首叶 `s32 h32 tx3 e41` 的 41 个 base 读全部使用已证明正确的行（`base[3][21]`/`base[3][22]`/`base_eob[3][1]`），MSAC 亦与 dav1d 逐位一致，但残差量级与黄金差 2–7 倍。剩下两种可能：(a) 首叶的**逆变换**（32x32 DCT_DCT）或**反量化**在 qindex=128 下有误——注意不继承时首叶 skip=1、该路径完全不被执行，故既有位精确样本无法暴露它；(b) `eob` 读之前的状态在 T1050–T1054 某处发散。下一轮应先测 (a)：用 Python 按规范实现 32x32 逆变换 + 反量化，对我方已 dump 的首叶 41 个系数复算像素，与 `B`（我方块）和 `G`（黄金块）三方对拍——若复算值与 `B` 不符即坐实 (a)。

**第十四次推进补充五十（黄金首叶系数结构已测出：DC 主导；我方 AC 幅度约为黄金 2.4 倍且 (1,1) 反号）**

在"放开守卫 + 开启继承"下把第一叶的**带符号系数**与**我方块 B**、**黄金块 G** 三方对拍（预测已由补充四十八隔离为常量 127；32×32 正交 DCT/IDCT 在 Python 中独立实现；DC 与 AC 反量化分开拟合）：

- **黄金首叶残差（G−127）是 DC 主导的**：正交 DCT 后 `(0,0)=-2268.59`、`(1,0)=-440.16`、`(0,1)=-341.99`、`(1,1)=+307.98`，其余位置全部落在约 ±43.5 的一个台阶上。换算成级别（用我方 AC 反量化标尺）为 `(0,0)≈-32.5`、`(1,0)≈-6.3`、`(0,1)≈-4.9`、`(1,1)≈+4.4`，其余约 20 个位置 ≈ ±0.6。**⇒ 黄金首叶只有 4 个量级较大的系数，且全在最低频。**
- **我方首叶有 25 个非零系数**：`(0,0)=-13、(0,1)=-4、(0,2)=+1、(0,3)=-3、(0,4)=-1、(1,0)=-15、(1,1)=-4、(1,2)=-2、(1,3)=-1、(1,4)=+1、(2,0)=+6、(2,1)=-4、(2,2)=+1、(2,3)=+15、(2,4)=+4、(3,0)=+3、(3,1)=+1、(3,2)=+1、(3,3)=+6、(3,4)=-2、(4,0)=-5、(4,1)=-3、(4,2)=-1、(4,3)=-2、(4,4)=+1`。
- **两处硬差异**：(a) `(1,1)` 我方 **-4**、黄金 **+4.4**（**反号**）；(b) `(1,0)` 我方 **-15**、黄金 **-6.3**，且我方 `(2,3)=+15`、`(3,3)=+6` 这类中频大幅系数在黄金里完全不存在（黄金该处 ≈0）。
- **我方残差均值 -40.32，黄金 -70.89**；我方块被裁剪到 0/255（1015/524 个未裁剪像素无法用单一标尺解释），黄金块 31–51 无裁剪。
- **IDTX 假设被排除**：若 dav1d 用 IDTX，残差应近似等于系数的栅格排布，而黄金残差是常量 -71 上下的平滑波（DCT_DCT 特征），且 IDTX + eob=41 只会在 41/1024 个位置产生非零，与"黄金残差处处 ≈ -71"矛盾。
- **32×32 默认扫描顺序已核对无误**：`0,1,32,64,33,2,3,34,65,96,128,97,66,35,4,5,36,67,98,129,160,192,…` 与 AV1 32×32 zigzag 一致。
- **反量化表结构无误**：`dcQlookup_highbd[0][49]=48 / ac=56`，`[0][128]=140 / ac=176`，dc/ac 比在 q=49 为 0.857、q=128 为 0.796；tx_ctx=3 时分母 2。**注意 q=49 时 dc≠ac，故"关键帧位精确"并不能证明 DC/AC 反量化都对**——但本样本差异同时涉及符号与反号，不是单纯标尺问题。

**⇒ 结论**：黄金首叶是一个 DC 主导的小残差，我方却解出一串大幅中频系数并出现 `(1,1)` 反号。这只能是**符号序列本身分歧**（而非反量化/变换），且分歧点在 `eob` 读（T1056）或其入口状态。T1056 所用行已证明正确，故入口状态必在 T1050–T1055 某处不同。其中 **T1050–T1052 是 MV 分量读（`mv_class`/`mv_class0_bit`/`mv_class0_fr`）**：MV 值不同会同时改变预测与算术状态，而我方预测为常量 127（MV 越界钳制）对 MV 的具体值不敏感——**这正好构成"MV 读错却看不出来"的盲区**。下一轮应先核 `mv_class`/`mv_bit`/`mv_fr` 等 MV CDF 的**上下文索引**（邻块参考帧/MV 派生），这是唯一能同时解释"预测看不出 + 状态发散 + 系数大幅反号"的位置。

**第十四次推进补充五十一（MV CDF 全部索引核准无误——MV 盲区假设被排除）**

逐一核对该样本 inter 帧用到的全部 MV 相关 CDF 与其索引方式，对照 go-av1 `decode/cdf.go` 与 `decode/intermode.go`（go-av1 的 `readMvComponent(mvCtx, comp)` 与本解码器同构）：

- `mv_sign` `[mv_ctx][comp]`：默认行 `[16384,32768,0]`，go-av1 `DefaultMvSignCdf` 同值。
- `mv_class` `[mv_ctx][comp]`：默认 2 行（comp 0/1）**逐位相同**，go-av1 `DefaultMvClassCdf` 亦是 2 行同值；`mvCtx` 恒为 0（仅 intrabc 用 1，而本样本 `allow_intrabc=0` 且帧门拒绝）。
- `mv_class0_bit` `[mv_ctx][comp]`：`[27648,32768,0]`，go-av1 同值。
- `mv_class0_fr` `[mv_ctx][comp][bit]`：2×2×2，go-av1 `DefaultMvClass0FrCdf` 同形同值。
- `mv_class0_hp` / `mv_hp` `[mv_ctx][comp]`：`[20480,…]` / `[16384,…]`，go-av1 同值。
- `mv_bit` `[mv_ctx][comp][bit_index]`：10 行按**位下标**索引（`bits_cdf[index]`，`index` 从 0 到 `class-1`），go-av1 `mvBit[mvCtx][comp][i]` 完全一致；曾疑心此处把 `[context][component]` 当成 CDF 行，实际代码 `let bits_cdf = cdfs.mv_bit[context][component]` 取到的是 10 行数组，再 `bits_cdf[index]` 取行，**索引正确**。
- `mv_fr` `[mv_ctx][comp]`：2 行同值，go-av1 同值。
- `mv_joint` `[mv_ctx]`：单行 `[4096,11264,19328,32768,0]` 复制成 2 份，go-av1 `DefaultMvJointCdf` 同值。

**⇒ "MV 读错但预测看不出来"这一唯一盲区假设被排除。** 至此，`eob` 读之前的所有读（T1050–T1056）所用 CDF 行与索引**全部**经规范/go-av1 核准无误，且 MSAC 与 dav1d 1600 万符号零分歧。

**⇒ 阶段 B 剩余分歧的确定性结论**：在“行与索引全部正确 + 算术内核与 dav1d 逐位一致”的前提下，我方 inter 帧仍解出与黄金不同的符号序列（首叶 DC 主导 vs 我方大幅中频、`(1,1)` 反号）。这只剩一种解释——**dav1d 1.2.1 在这条一致性非法的流上，其 `load_cdfs` 之后的某个行为与本解码器实现的规范路径存在无法从外部观测的差异**（例如 dav1d 对 `primary_ref_frame` 指向的 slot 与实际 `ref_frame_idx` 的解析方式、或其 CDF 复制的维度/边界处理）。由于本机无 C 编译器无法插桩 dav1d 取得符号级真值，而 libaom 又按规范拒绝该流，**符号级根因在本机已不可达**。

**处置建议（下一轮）**：把该样本的验收口径从“逐样本等于 dav1d 宽容解码”调整为“**拒绝该一致性非法的流**”（libaom 的立场：`Corrupt frame detected`），即让 `inter_cdf_inherit_64x64` 的 inter 帧在越读超过规范 §8.2 阈值时返回 `None`，测试断言改为“支持继承路径且被位流一致性守卫拒绝”。这符合完成标准第 (4) 条“合法未实现工具不被无声解码为错误画面”的精神——该流本身非法，无声解出错误画面正是要避免的。六个精确 inter 样本与位精确性不受影响。

**第十四次推进补充五十二（single_ref 树与 go-av1 逐分支一致；默认/继承轨迹的唯一结构差异是合法分支数不同）**

把默认 CDF 与继承两种解码的 inter 帧轨迹前 8 个读并排比对，并核对 `single_ref` 树：

- 两条轨迹在索引 5、6 处行值不同（默认 `[19647]`/`[24773]`，继承 `[16751]`/`[24035]`）。经查这**不是 bug**：`single_ref` 是 `[ref-count ctx 0..2][决策位 p 0..5]` 的二叉树，`[16973]/[16751]/[19647]/[24773]` 是同一 ctx 下 p=0/1/2/3 的不同行；索引 4 的符号值两种解码不同（默认 0、继承 1），因此走入不同分支、读不同个数的符号（默认 3 个 single_ref 符号后接 `new_mv[0]`，继承 2 个后接 `new_mv[0]`），随后都在 `mv_joint` 汇合。**分支数不同是符号值不同的合法后果。**
- `single_ref` 树结构与 go-av1 `readRefFrames` 逐分支一致：`single_ref[ctx][0]`；为 1 时 `[ctxP2][1]`，为 0 时再 `[ctxP6][5]`（ALTREF2/BWD），否则 ALTREF；为 0 时 `[ctxP3][2]`，为 1 时再 `[ctxP5][4]`（LAST3/GOLDEN），否则 `[ctx][3]`（LAST2/LAST）。`refCountCtx` 的前/后向计数口径亦一致。
- `is_inter[0]`（索引 3）、`skip`（索引 2，继承行 `[31739,32768,1]` = 默认 `[31671,32768,0]` 适配一次）身份确认。

**阶段 B 结论（定稿，不再重新论证）**：`eob` 读之前 inter 块的**全部**语法读——分区、`skip`、`is_inter`、`single_ref` 树、`new_mv`、MV 分量（`mv_sign`/`mv_class`/`mv_class0_*`/`mv_bit`/`mv_fr`/`mv_hp`）、`mv_joint`、`interp_filter[ctx]`、`txb_skip[1][3][0]`、`inter_tx_type_set3[3]`、`eob`——其 CDF 行值、索引方式、符号顺序均已对照规范与 go-av1 核准无误；`base`/`base_eob`/`eob` 三组继承行已由规范默认值 + 关键帧实际符号序列**逐位复算精确**；MSAC 与 dav1d 1.2.1 1600 万符号零分歧。在此前提下我方仍解出与黄金不同的符号序列（黄金首叶 DC 主导、约 4 个显著系数；我方 25 个非零、含大幅中频与 `(1,1)` 反号）。

**⇒ 唯一未逐位复算的继承行是 `br`（bit-precision）组**（`Coeff_Br_Cdf[qctx][tx][plane][brCtx]`，21 行/组），它在 `value > 2` 时被读并直接加到系数值上——若该组行值有误，会精确产生"系数值偏大但不改变符号条数"的现象，与观察完全吻合。下一轮应先复算 `br` 组（默认值 + 关键帧 `br` 读序列），这是阶段 B 最后一个可在本机验证的假设。

**明确不做的事**：不把该样本的断言改成"拒绝该非法流"来充当阶段 B 闭合——完成标准第 (3) 条要求 `[3992,842,928] → [0,0,0]` 且原 OBU/真值不动，且明令不得以改变验收口径的方式收尾。该样本的围栏值 `[3992,842,928]` 与 `av1_cdf_load_enabled = false` 维持原状。

**第十四次推进补充五十三（矩形 base-ctx 偏移表已按规范逐位置穷尽验证；br 组钳制常量核准）**

**1. `Coeff_Base_Ctx_Offset` 矩形路径逐位置穷尽验证（假设排除）。** 从规范 `_refs/av1spec09.md:1090` 与 go-av1 `_refs/go-av1/decode/scan_gen.go` 提取完整 19×5×5 表，并按 go-av1 `_refs/go-av1/decode/tables.go:12` 的 TX_SIZE 枚举确定行序（0..4 方形；5..18 矩形：`TX4x8, TX8x4, TX8x16, TX16x8, TX16x32, TX32x16, TX32x64, TX64x32, TX4x16, TX16x4, TX8x32, TX32x8, TX16x64, TX64x16`）。结论：

- 方形行 1..4（8x8..64x64）**逐位相同**，我方 `av1_coeff_base_ctx_offset[1..4]` 与之逐位一致；行 0（4x4）亦一致。
- **高矩形**（Tx_Width < Tx_Height）共 7 行分两形：`Tx_Width == 4` 时（TX4x8/TX4x16）第 4 列为不可达占位 0；`Tx_Width >= 8` 时第 4 列为 **11**。两形在**可达位置**上完全一致：前两行（除 (0,0)）一律 11，第 2..4 行与方形表相同。
- **宽矩形**（Tx_Width > Tx_Height）共 7 行同样分两形：`Tx_Height == 4` 时第 4 行为不可达占位 0；`Tx_Height >= 8` 时第 4 行为 **16**。两形在可达位置上完全一致：前两列（除 (0,0)）一律 16，第 2..4 列与方形表相同。
- **⇒ 我方 `av1_coeff_base_ctx_rect` 的 `tx_width < tx_height && row < 2 → ctx+11`、`tx_width > tx_height && col < 2 → ctx+16`、其余走方形表，在全部可达 (row, col) 上与规范逐位一致。** 曾据误读（把高矩形第 4 列记成 21）提出"修改"，实测打破 4 个既有测试（`av1_subsampling_wbtest` 4:2:2 像素真值、`inter_still_64x64` 三个测试），已完整回退并复绿。该次误读本身即证明：**这 4 个测试对矩形 base-ctx 偏移敏感，构成有效回归网。**

**2. `br` 组钳制常量核准。** 规范 `get_coeff_br_ctx` 的邻级钳制是 `Min(Quant[...], COEFF_BASE_RANGE + NUM_BASE_LEVELS + 1)`；go-av1 `decode/coeff.go` 定义 `numBaseLevels = 2`、`coeffBaseRange = 12`，故钳制值为 **15**。我方 `av1_coeff_br_ctx_square` 用 `if v < 15 { v } else { 15 }`，**正确**。同时核准：`br` 循环次数 `COEFF_BASE_RANGE / (BR_CDF_SIZE - 1) = 12/3 = 4`（我方 `for _ in 0..<4` ✓）；golomb 阈值 `NUM_BASE_LEVELS + COEFF_BASE_RANGE = 14`（我方 `quant[pos] > 14` ✓）；`br_ctx` 的 `txClass` 分支（2D 看 row/col<2、HORZ 看 col==0、VERT 看 row==0）与我方按 `scan_class` 的分支一致；`Mag_Ref_Offset_With_Tx_Class` 三个偏移组与我方 `refs` 表逐项一致。

**⇒ 至此，系数段全部上下文（`base` 方形/矩形偏移、`base_eob` 四分支、`br` 的 txClass 分支与邻级钳制、循环次数、golomb 阈值）均已按规范逐位核准；所有被继承的系数 CDF 行（`base`/`base_eob`/`eob`）已由规范默认值 + 关键帧实际符号序列复算精确。`br` 组行值本身的复算仍待做（需关键帧 `br` 读序列），但 `br` 的**上下文与钳制**已排除。**

**第十四次推进补充五十四（决定性发现：`br` 组部分行未被正确继承）**

在"放开守卫 + 开启继承"下插桩 `av1_decode_coeffs_leaf_with_decoder`，把每个系数读**实际使用的 `br` 行**（`context.br[clamp(tx_ctx)][br_ctx]`，含适配计数器）连同叶参数一并 dump，得到关键帧 872 行 + inter 帧 511 行。按平面分离（关键帧 `e29` 叶 = luma/plane 0，`e379`/`e435` 叶 = chroma/plane 1；inter 首叶 `s32 h32 tx3 e41` = luma/plane 0）后逐 brctx 比对：

| brctx | 关键帧 luma 末行 | 关键帧 chroma 末行 | inter 首叶首行 | 继承正确？ |
| ---: | --- | --- | --- | --- |
| 0 | `[11720,18852,23292,32768,0]` | `[9788,16044,20276,32768,0]` | `[17648,24596,27817,32768,0]` | **否** |
| 1 | `[18171,24151,27930,32768,1]` | `[22092,28281,30333,32768,1]` | `[17097,24851,27971,32768,1]` | **否** |
| 2 | `[17604,23397,28081,32768,2]` | `[21402,27398,30409,32768,2]` | `[17604,23397,28081,32768,2]` | **是** |
| 4 | `[8825,15034,18930,32768,4]` | — | `[3418,6459,9099,32768,4]` | **否** |

**⇒ brctx=2 的行被正确继承，而 brctx=0/1/4 没有。** inter 帧这三个行既不等于关键帧 luma 末行、也不等于关键帧 chroma 末行，且**不等于任何规范默认行**（`defaultCoeffBrCdf[q][3][0][bc]` 四个 qctx 的默认值已逐一列出比对，均不匹配），而计数器为 0/1/4 说明它们在关键帧里确实被读过。这是**可复现行级证据**：`br` 在 `value > 2` 时被读并**直接加到系数级别上**，行值错误会精确产生"系数值偏大但不改变符号条数"的现象——与补充五十测得的"黄金首叶约 4 个显著系数、我方 25 个非零且 (1,1) 反号"完全吻合。

**下一步（下一轮）**：查 `av1_frame_cdfs.mbt` 中 `y_coeff.br` 的捕获/恢复路径。捕获用 `av1_cdf_rows_of3(state.y_coeff.br)`（4 个 tx 组 × 21 行 = 84 行），恢复用 `av1_cdf_rows_into3(state.y_coeff.br, tables[index])`；两者扁平化顺序一致、形状相同，理论完整。重点核查两点：(a) `state.y_coeff` 与传进 `av1_decode_coeffs_leaf_with_decoder` 的 `context` 是否是同一对象（若 `context` 在每叶由 `av1_coeff_context` 重建，恢复会被随后的重建覆盖）；(b) `Av1CoeffContext.br` 只建 4 个 tx 组（0..3）而 `base` 建 5 个（0..4），`av1_coeff_context` 的调用点传的 `tx_ctx` 是否与恢复时机匹配。

**第十四次推进补充五十五（重要更正：补充五十四的"br 未继承"结论系插桩 bug 所致）**

补充五十四的插桩把 `usedbr[usedbr.length()-1]`（即行的**适配计数器**）当作 `brctx` 打印，导致按"计数器"而非"按 br 上下文索引"分组比对，得出的"brctx=0/1/4 未继承"是**错误的**。已重写插桩打印真正的 br 上下文索引 `B{n}` 并重新比对，结论修正如下：

- inter 帧首叶（`s32 h32 tx3 sc0 e41`，32×32 luma）共用到 10 个不同的 br 上下文：`B6, B11, B13, B14, B15, B16, B17, B18, B19, B20`。
- 与关键帧 luma 末态逐行比对：**B14、B15 完全一致**（`B14=[17604,23397,28081,32768,2]`、`B15=[17648,24596,27817,32768,0]`），且 `B15` 正是 `defaultCoeffBrCdf[1][3][0][15]` 的 qctx=1 默认值（0 次适配），`B14` 可由该默认值经 2 次 symbol=2 适配复算得到——**说明 qctx=1 的关键帧行确实被继承到了 inter 帧**。
- 差异仅两处：`B6`（关键帧末态计数器 8 → inter 首用 12）与 `B17`（关键帧末态计数器 0 → inter 首用 2）。二者计数器分别多 4 和 2。
- 首叶内 br 上下文的演进自洽：`B15` 从 ctr=0 开始，在 c=25（v=4>2，首次真正读 br）后变 1，c=19 后变 2；`B14` 全程 ctr=2 不变（该行对应系数的 v 均 ≤2，不触发 br 读）。**⇒ br 的适配推进本身符合规范。**

**⇒ 补充五十四的 bug 结论作废。** 剩余待解释的只有 `B6`/`B17` 两行计数器偏大的现象，且完全可能是**关键帧侧计量口径问题**（补充五十四用"关键帧 luma 叶（eob=29）的最后一帧"作为末态，但关键帧有 2 个 luma 叶；若 `B6`/`B17` 只在第 1 个 luma 叶被读、第 2 个叶不再读，则"最后一帧"恰为第 2 叶的值而非全局末态——此口径已在补充五十四引入）。下一轮应按"关键帧全部 luma 叶的全局末态"重新取一行比对，预期两处差异随之消失。

**教训（已记入）**：插桩打印派生量时必须打印**索引本身**而非从行内容反推；本例中计数器与 brctx 数值偶合（0/1/2/4/8/12）造成了完全错误的结论，并差点导致一次错误的代码修改。

**第十四次推进补充五十六（`br` 继承完全验证通过——系数 CDF 全链路闭合）**

按补充五十五的方案，用打印真正 br 上下文索引的插桩重新取证，并**按叶切分**（共 15 个叶：关键帧 leaf0 = luma `e29`、leaf1/2 = chroma `e379`/`e435`；inter 帧 leaf3 = 首叶 `s32 h32 tx3 e41`，leaf4–14 为后续矩形叶）。关键帧 luma 只有一个带系数的叶（另一 luma 叶 txb_skip=1，不产系数），故其末态即全局末态。

关键帧 luma 叶用到 5 个 br 行：`B6, B7, B14, B15, B17`。与 inter 首叶首次使用逐行比对：

| brctx | 关键帧 luma 末行 | inter 首叶首用 | 结果 |
| ---: | --- | --- | --- |
| B14 | `[17604,23397,28081,32768,2]` | `[17604,23397,28081,32768,2]` | **逐位相同** |
| B15 | `[17648,24596,27817,32768,0]` | `[17648,24596,27817,32768,0]` | **逐位相同** |
| B17 | `[11720,18852,23292,32768,0]` | `[12023,18716,22883,32768,2]` | 差 2 次适配 |
| B6 | `[821,1662,2494,32768,8]` | `[725,2489,3222,32768,12]` | 差 4 次适配 |

**两处差异已精确定性为帧内多次读所致，而非继承失败**：规范 `coeffs()` 的 br 循环在每个系数上最多读 4 次（`for idx < COEFF_BASE_RANGE/(BR_CDF_SIZE-1)` = 4，读到 `coeff_br < 3` 才停），每次读都适配该行。用 Python 按 `av1_msac_update_cdf` 复算：

- **B17**：关键帧末行经 **2 次**适配（符号序列 `(3,0)`）精确得到 inter 首用行 `[12023,18716,22883,32768,2]`。对应 inter 首叶 c=24（v=6>2）的 br 循环：首读 br=3 继续、次读 br=0<3 停止，恰 2 次。✓
- **B6**：关键帧末行经 **4 次**适配（符号序列 `(3,3,3,1)`）精确得到 inter 首用行 `[725,2489,3222,32768,12]`。对应 inter 首叶 c=0（v=13>2）的 br 循环跑满 4 次。✓

**⇒ `br` 组继承完全正确。** 结合此前各轮，系数段 CDF 全链路现已逐位闭合：

| 组件 | 验证方式 | 结论 |
| --- | --- | --- |
| `base` 方形偏移表 | 规范/go-av1 19×5×5 表逐位置比对我方实现 | 全部可达位置一致 |
| `base` 矩形偏移 | 规范高/宽矩形两形表 + 可达性分析 | 一致（误读修改已回退，4 个既有测试为回归网） |
| `base_eob` 四分支 | 规范 `get_coeff_base_ctx` isEob 分支 | 一致 |
| `eob`/`eob512`/`eob_small`/`extra` | 规范默认值 + 关键帧符号序列复算 | 逐位精确 |
| `br` 行继承 | 关键帧末态 → inter 首用，含帧内多次读复算 | **逐位精确** |
| `br` 钳制/循环/golomb/txClass | 规范常量与 go-av1 实现 | 一致 |
| MSAC 算术 | dav1d 1.2.1 `msac.c` 逐字移植对拍 1600 万符号 | 零分歧 |
| 全部 CDF 索引（MV/interp/txb_skip/tx_type/single_ref 树） | 规范 + go-av1 逐项 | 一致 |

**⇒ 阶段 B 的剩余分歧不在任何可在本机验证的 CDF 行、索引或算术内核上。** 在"行与索引全部正确 + 算术与 dav1d 逐位一致"的前提下，我方继承解码仍与 dav1d 宽容解码不同；该流本身一致性非法（libaom 按规范 §8.2 拒绝），符号级根因需插桩 dav1d 方能取得，而本机无 C 编译器。围栏值 `[3992,842,928]` 与 `av1_cdf_load_enabled = false` 维持原状，不改样本、不改真值、不以改变验收口径收尾。

**第十四次推进补充五十七（CI 冒烟与公开入口全链路本地复核；`-14` 守卫替代方案决定不实施）**

**1. CI 全部冒烟步骤本地复核通过**（`.github/workflows/ci.yml` 的 5 个非测试步骤逐一实跑）：

| CI 步骤 | 命令 | 结果 |
| --- | --- | --- |
| Type check | `moon check` | 64 warnings / **0 errors** |
| Test (wasm-gc) | `moon test` | **1186/1186** |
| Test (JavaScript) | `moon test --target js` | **1186/1186** |
| Test (native) | `moon test --target native` | **1186/1186** |
| Web 产物可复现 | `node scripts/build-web.mjs --check` | `OK web/dist/web.js`、`OK web/dist/wasmcore.wasm` |
| WASM 线性内存集成 | `node verify-wasm.mjs` | **WASM verification passed** |
| CLI demo (ppm) | `moon run cmd/ppm` | exit 0 |
| CLI demo (showcase) | `moon run cmd/showcase` | exit 0 |
| CLI `--help` | `moon run --target native cmd/cli -- --help` | exit 0，用法/格式/管线清单完整输出 |

**2. AVIF 公开入口全链路复核**（完成标准第 (1) 条"能力表各项接入真实解码路径并有公开入口与可观察结果"）：对 `tests/fixtures` 下全部 140 个 `.avif` 逐一跑 `moon run --target native cmd/cli -- info --input <file>`：

- **133 个成功解析**并输出 `format=avif / width / height / channels / bytes`，覆盖 `av1`（8/10/12-bit、DC/AC、单色）、`av1-cdef-frame`（128x64 2tile 10bit）、`av1-highbd-ac`、`av1-multitile`、`av1-palette`、`av1-restoration`、`av1-film-grain`、`av1-large-block` 等各族。
- **7 个被拒**，全部是 `avif-grid/` 下的**故意畸形负样本**：`dimg_missing_target`、`truncated_grid_extent`、`unsupported_grid_version`、`tile_extent_beyond_file`、`primary_ispe_width_mismatch``odd_420_output_width`、`tile_av1c_depth_mismatch`。它们在 `avif_grid_reference_wbtest.mbt` 中均有对应的 "AVIF grid rejects …" 拒绝断言，**CLI 拒绝它们正是预期行为**。
- 端到端转换复核：`convert --from avif --to png` 于 `tests/fixtures/av1/ac_y_cosine_q30.avif` 产出合法 PNG（签名正确、64×64、bit depth 8 / color type 6 即 RGBA、458 字节）。

**3. `-14` 守卫替代方案：决定不实施（理由记录在案，避免后续重复论证）**

补充四十六曾设计"用符号数上界替代 `symbol_max_bits >= -14`"。经本轮权衡，**决定不实施**：

- **不充分**：补充五十已实测——即便把 8 处守卫全部放开（改 `-1000000`）并开启继承，`inter_cdf_inherit_64x64` 的 inter 帧仍为 `[4029, 464, 708]`，达不到 `[0,0,0]`。该改动对完成标准第 (3) 条没有路径。
- **回退合规性**：该守卫实现的是规范 §8.2 `exit_symbol` 的位流一致性要求（"It is a requirement of bitstream conformance that SymbolMaxBits is greater than or equal to -14"）。以符号数上界取代它等于放宽一致性检查，与完成标准第 (4) 条"合法未实现工具不被无声解码为错误画面"方向相反。
- **削弱既有测试**：补充四十五的实测表明，依赖该守卫拒绝截断输入的 4 个既有测试在触发时只读 2/7/11/27/41 个符号，而合法继承解码需 586 个；按"SB 数 × 600"的标尺化上界会同时放过这些截断探针，必须为它们显式传入小上限——即这 4 个测试的截断拒绝断言被削弱。
- **代价/收益不成立**：改动涉及 16 处守卫点 + 构造函数 + tile 入口 + 4 个测试，风险面大，而收益仅是"更像 dav1d 那样宽容"；且 libaom 同样按规范拒绝该流，我方拒绝它是可辩护的。

**⇒ 阶段 B 的工程项至此全部收敛。** 剩余唯一未闭合的是 `inter_cdf_inherit_64x64` 的 `[0,0,0]`，其根因不在任何本机可验证的 CDF 行、索引、上下文或算术内核上（补充四十七至五十六已逐位闭合系数 CDF 全链路、MV CDF、single_ref 树、tx_type 集与映射、扫描顺序、反量化表），需插桩 dav1d 取得符号级真值方能定位，而本机无 C 编译器。围栏值 `[3992,842,928]` 与 `av1_cdf_load_enabled = false` 维持原状：不改样本、不改真值、不以改变验收口径收尾。

**第十五次推进（阶段 C 首项解除：`coded_lossless` 帧间帧已样本精确并通过外部核验）**

**1. 门禁现状盘点（`av1_inter_frame_supported`，[av1_inter_tile.mbt:1003](av1_inter_tile.mbt#L1003)）**。用 `scripts/generate-av1-inter-reference.py` 的 `MINIMAL_FLAGS` 逐项加回一个工具，生成了 5 条隔离码流并以 dav1d 1.2.1 取真值，用我方解析器读帧头：

| 码流 | 追加参数 | inter 帧帧头 | 门禁 |
| --- | --- | --- | --- |
| `c_base` | （无） | 全 false | **true** |
| `c_lossless` | `--lossless=1` | `lossless=true` | false |
| `c_refmvs` | `--enable-ref-frame-mvs=1` | 全 false（未生效） | true |
| `c_obmc` | `--enable-obmc=1` | `mmode=true` | false |
| `c_warped` | `--enable-warped-motion=1` | `mmode=true, warped=true` | false |

**另确认**：aomenc 默认参数会在**序列头**里置 `enable_interintra_compound` / `enable_masked_compound`，因此任何非 `MINIMAL_FLAGS` 编码的帧间流都会被门禁整体拒绝——这解释了为什么仓库的六个精确 inter 样本全部需要专门的最小参数集。

**2. `coded_lossless` 已解除并样本精确。** 临时把门禁里的 `header.coded_lossless` 分支短路后实测：lossless 关键帧解码成功，lossless inter 帧对 dav1d 真值 **`bad=[0,0,0]`**（Y/U/V 全 0 差异）。据此把该分支从 `av1_inter_frame_supported` 中正式移除（不是短路），并补：

- 样本 [tests/fixtures/av1-inter/inter_lossless_64x64.obu](tests/fixtures/av1-inter/inter_lossless_64x64.obu)（169 字节，aomenc `MINIMAL_FLAGS` + `--lossless=1`，输入为共享的 `ramp` y4m）与 `.reference.yuv`（dav1d 1.2.1 原生平面）。
- `manifest.json` 追加 `inter_lossless_64x64` 条目（含 aomenc 完整命令与两个 sha256）。
- `av1_inter_reference_wbtest.mbt` 追加两个测试：帧头/门禁事实断言（`coded_lossless=true`、`av1_inter_frame_supported` 为 true、关键帧八槽全部存入）与 inter 帧逐样本 `[0,0,0]` 断言。
- `tests/fixtures/av1-inter/README.md` 追加该样本的说明段。

**⇒ 阶段 C 第一项（无损帧间）闭合。** native/js/wasm-gc 各 **1188/1188**（新增 2 个测试）；`moon check` 64 warnings / 0 errors；`build-web.mjs --check` 两文件 OK；`verify-wasm.mjs` PASS。

**3. 阶段 C 剩余门禁（按隔离度排序）**：
- `is_motion_mode_switchable` → OBMC（`c_obmc`，头部位 `mmode=true`）
- `allow_warped_motion` → 局部 warp（`c_warped`，与 `mmode` 同时置位）
- `reference_select` / `skip_mode_present` / `allow_intrabc` / `allow_screen_content_tools`（本批输入未触发，需专门构造内容）
- `sequence.enable_interintra_compound` / `enable_masked_compound`（默认即置位，影响面最大）
- 非 identity 全局运动（`gm_type`）

下一轮按 `c_obmc` 推进：先确认 `is_motion_mode_switchable` 单独置位时块内究竟读哪些符号（`motion_mode` 的 OBMC/局部 warp 二选一），再决定实现顺序。

**第十五次推进补充一（`read_motion_mode` 已按规范落地；OBMC 流在门禁旁路下 luma 精确、chroma 余 16/48）**

**1. `read_motion_mode`（AV1 §5.11.27）已实现并接线。** 新增 `av1_read_motion_mode`（[av1_inter_mode.mbt](av1_inter_mode.mbt)）与 `av1_has_overlappable_candidates`（§7.10.3），严格对照 go-av1 `decode/intermode.go:280-300` 与规范 `av1spec06.md:2822-2855` 的分支顺序：`skip_mode` → `!is_motion_mode_switchable` → `min(BlockW,BlockH) < 8` → `GLOBALMV` 且 `GmType > TRANSLATION` → `!has_overlappable_candidates` → 读 `use_obmc`（二分支）或 `motion_mode`（三分支，仅 `allow_warped_motion` 时可达）。为支撑它给 `Av1MvFrame` 增加 `is_motion_mode_switchable` 与 `allow_warped_motion` 两个字段（由 `av1_mv_frame_of` 从帧头投影），并同步 `av1_mv_oracle_wbtest.mbt` 的测试构造器。调用点插在 `av1_assign_mv` 之后、`av1_read_interp_filter` 之前，与规范 `inter_block_mode_info` 的顺序一致。

**2. 决定性实测：该符号读是必需的，且 OBMC 在本样本中未被选中。** 用 `c_obmc`（`MINIMAL_FLAGS` + `--enable-obmc=1`）做对照实验——同一份门禁旁路，仅切换 `av1_read_motion_mode` 调用：

| 配置 | 结果 |
| --- | --- |
| 不调用 `av1_read_motion_mode` | inter 帧**被拒**（符号流少读，后续错位） |
| 调用 `av1_read_motion_mode` | inter 帧解码成功，`bad=[0, 16, 48]` |

**⇒ 该符号确实被 bitstream 编码（块 (1,0)/(0,1)/(1,1) 有可重叠邻块），我方此前不读它导致符号流错位而被拒；现在读满后 luma 逐样本精确（0/4096），且读出的都是 0（SIMPLE），没有任何块选择 OBMC。** 余下 16 个 U、48 个 V 样本差异是**独立的色度缺陷**，与 OBMC 无关（luma 已精确证明符号流正确）。

**3. 门禁决定：`is_motion_mode_switchable` 暂不解除。** 理由：(a) 本样本虽未选 OBMC，但只要有一条流选中，`av1_read_motion_mode` 会返回 false 使整帧被拒——行为诚实但等于没有解除能力；(b) 余留 16/48 色度差异未定位，此时解除门禁会让"合法但未正确实现的工具"产出错误画面，违反完成标准第 (4) 条。**OBMC 预测核（邻块预测加权混合）本身尚未实现**，是下一轮的具体工作项。

**4. 踩坑记录**：包级 `let` 计数器在库内写、白盒测试读**不可见**（与既有的"白盒测试写、库内读不可见"同向），导致 `use_obmc` 读取计数误报为 0；本轮一度据此外推"符号未被读取"，与对照实验矛盾后才定位到该坑。后续插桩一律改用**编译期常量**或返回值传递。

**验证**：`moon check` 63 warnings / 0 errors；native/js/wasm-gc 各 **1188/1188**；`verify-wasm.mjs` PASS；Web 产物已重建（`build-web.mjs --check` 两文件 OK）。门禁保持 `is_motion_mode_switchable` 拒绝，`coded_lossless` 解除状态不受影响。

**第十五次推进补充二（`c_obmc` 流 16/48 色度差异已定位到单一列：色度第 16 列恒 -1）**

按 16×16 色度块切分比对，差异**全部集中在右上块**（色度列 16–31、行 0–15），左下/右下/上行块全部为 0。逐行打印该块差值：**每一行第 16 列（该块最左列）恒为 -1，其余 15 列全部为 0**。

| 观测 | 值 |
| --- | --- |
| 差异位置 | 色度 (行 0–15, 列 16)，即右上 16×16 块的最左列 |
| U 差异 | 16 个样本，全部 -1 |
| V 差异 | 48 个样本（3 列 × 16 行，需下一轮取逐列值确认） |
| luma | 0/4096 精确 |
| 帧滤波 | 该流 loop_filter_level 全 0、cdef 强度全 0、lr_type 全 0，**排除环路滤波/CDEF/LR 边界处理** |

**⇒ 定性**：整列恒 -1 是**水平频率 1 的基函数**形态，且只出现在右上块的最左列。结合 luma 全精确（说明符号流、MV、残差读取均正确），最可能是**色度亚像素预测在该块左沿的取相/舍入**或**残差在列方向的放置偏移**，而非熵或滤波问题。下一轮应先取 V 的逐列差值确认是否同为"最左若干列"，再对照规范 `inter_predictors` 的色度 MV 取相规则（`subsampling_x` 下 `mv & 7` 的折半）与逆变换的列寻址。

**注意**：该差异与 OBMC 无关（本流无块选中 OBMC），是独立的色度缺陷；在它归零前 `is_motion_mode_switchable` 门禁保持拒绝。

**第十五次推进补充三（色度差异精确定位：U 仅第 16 列 -1；V 为第 17 列 -1、第 19/20 列 +1）**

逐列统计 32×32 色度平面的差异列（每列 32 个样本）：

| 列 | U 差异样本数 | V 差异样本数 |
| ---: | ---: | ---: |
| 16 | **16**（全列，恒 -1） | 0 |
| 17 | 0 | **16**（全列，恒 -1） |
| 19 | 0 | **16**（全列，恒 +1） |
| 20 | 0 | **16**（全列，恒 +1） |
| 其余 28 列 | 0 | 0 |

逐行确认：U 的第 16 列每行都是 -1；V 的第 17 列每行 -1、第 19 与 20 列每行 +1，且同一模式在全部 32 行重复。

**⇒ 关键推论**：U 与 V 的差异**列位置不同**（U 在 16，V 在 17/19/20），说明不是统一的**列放置偏移**（那会让 U/V 模式相同），而是**残差系数值本身在个别列上差 ±1**。结合 luma 0/4096 精确、且该流 loop_filter/cdef/lr 全 0，最可能是**色度逆变换或反量化在个别系数上的舍入**，或**色度变换尺寸/扫描选择**导致的少数系数值偏差。下一轮应先确认该 inter 帧的 `tx_mode` 与色度块实际变换尺寸（`av1_chroma_tx_size` 的入参），再核对 16×16（或矩形）逆变换的列寻址与舍入。

**第十五次推进补充四（决定性归因：色度差异 100% 在预测侧，且为水平亚像素舍入）**

用"把全部系数强制为 0"的插桩做归因实验（符号条数不变，仅丢掉残差）：

| 配置 | Y/U/V 差异 |
| --- | --- |
| 正常解码（残差在场） | `[0, 16, 48]` |
| **残差全部置 0（纯预测）** | **`[0, 16, 48]`（完全相同的数）** |

**⇒ 差异 100% 来自色度预测，与残差/逆变换/反量化无关。** 结合 luma 0/4096 精确（luma 预测与残差均正确），问题被压到**右上 16×16 色度块的运动补偿**。

进一步由误差形态定性：V 的第 17 列恒 -1、第 19/20 列恒 +1，且**同一模式在全部 16 行重复（不随行变化）**。垂直方向无变化 ⇒ 该块 **`subpel_y == 0`（垂直为整像素）**，误差只出现在水平方向 ⇒ **水平 8-tap 亚像素滤波在该 `subpel_x` 相位下舍入差 1**。其余三个色度块精确，说明它们的 `subpel_x` 相位（或 MV 不同）未触发该舍入路径。

**下一轮（已定向）**：核对 `av1_mc.mbt` 中色度水平 8-tap 滤波的中间舍入（`round0`/`round1` 与 `FILTER_BITS`/移位序列）对 4 个非零 `subpel_x` 相位是否逐位对齐 dav1d；重点比对"整像素垂直 + 非零水平"这一组合。由于四个块的 MV 不同，只需对触发块的那个相位定点修复。

---

# 第十六次推进补充（2026-09-21，接续"色度水平亚像素舍入差 1"调查）

## 一、结论先行：上一轮归因是错的，真正根因是 OBMC 被静默忽略

上一轮把差异归到"色度水平 8-tap 亚像素滤波舍入差 1"，并列出滤波表、舍入常数、
起止公式均已排除。本轮完整重查后确认：**那些排除全部正确，但根因不在那里。**

`c_obmc.obu`（`--enable-obmc=1` 隔离码流）的 inter 帧右上 32×32 块（MI row 0,
col 8）选中了 **OBMC**（`use_obmc == 1`）。而 `av1_read_motion_mode`
（`av1_inter_mode.mbt`）读到该符号后：

```moonbit
if decoder.symbol(info.cdfs.use_obmc[size_index]) == 1 {
  block.motion_mode = 1
  return true        // ← 错误：应当是拒绝整帧
}
```

它把 `motion_mode` 置 1 却报告成功，于是**整帧被无声解码成错误画面**——这正是
完成标准第 4 条明令禁止的行为。因为 OBMC 混合只发生在块边缘的共享条带上，且
luma 参考在该处恰好平坦到让混合结果四舍五入回同样本，所以 luma 0/4096 精确、
只有色度混合列出错（U 1 列 16 个样本、V 3 列 48 个样本）。这种"大部分正确"的
假象比直接拒绝危险得多。

**验证方式（决定性实验）**：把 `return true` 改成 `return false` 后该 inter 帧
立即被拒绝 ⇒ 证明 OBMC 确实被选中。同时在 `av1_read_motion_mode` 里打印
`motion_mode == 1` 的块，得到唯一一行 `OBMC block at 0,8 32x32`，与差异位置
（色度列 16–23 的左混合条带）完全吻合。

本轮同时用 Python 按规范独立复算排除了其余假设：参考平面内容与我方存储逐字节
相同（`REFU`/`REFV` == dav1d 关键帧 U/V），滤波表、`Round2` 常数、
`origX/baseX/startX/stepX` 公式、`Clip3` 边缘钳制均与 `av1spec08.md`
（§7.11.3.3、§7.11.3.4，行 2930–3140）逐字一致；把 6 种滤波 × 16 相位 × MV
偏移全部枚举后，没有任何单一参考水平滤波能复现黄金值——因为黄金值根本不是
单一参考滤波的结果，而是 OBMC 混合的结果。

## 二、已实现：OBMC 预测核（AV1 §7.11.3.9）

`av1_inter_tile.mbt` 新增三块：

- `av1_obmc_masks` / `av1_obmc_mask(length)`：五条混合斜坡
  （`Obmc_Mask_2/4/8/16/32`），按条带长度选取。
- `av1_obmc_overlap(...)`：单个候选的 `predict_overlap`——用**候选块自己的**
  MV 与**候选块自己的**插值滤波器（规范 §7.11.3.4 的 `candRow/candCol`）插值
  一条参考带，`Clip1` 后按
  `Round2(m * curr + (64 - m) * obmc, 6)` 混合回平面。
- `av1_obmc_blend(...)`：`overlapped_motion_compensation` 主流程。above pass
  （`AvailU` 且残余尺寸 ≥ 8×8）按 `step4 = Clip3(2, 16, Num_4x4_Blocks_Wide[candSz])`
  步进，最多 `Min(4, Mi_Width_Log2)` 个候选，混合上半；left pass 对称混合左半。
  两个 pass 顺序执行、都读平面当前内容。

调用点挂在 `av1_inter_predict` 每个平面预测写回之后
（`if block.motion_mode == 1 && !av1_obmc_blend(...)`）。

`av1_read_motion_mode` 的 OBMC 分支改回"接受"（现在有实现），并更新注释说明
LOCALWARP 分支在本配置下不可达（`allow_warped_motion` 仍被门禁挡住）。

## 三、门禁解除与样本

`av1_inter_frame_supported`（`av1_inter_tile.mbt`）移除
`header.is_motion_mode_switchable`。保留的门：`reference_select`、
`allow_warped_motion`、`use_ref_frame_mvs`、`skip_mode_present`、
`allow_intrabc`、`allow_screen_content_tools`，以及序列级
`enable_interintra_compound` / `enable_masked_compound`。
`allow_warped_motion` 必须继续挡着，否则规范 §5.11.27 的第三分支
（三符号 `motion_mode`，会读 LOCALWARP）可达，而我方只读 `use_obmc` 单符号。

新样本（与既有 inter 样本同源的 `MINIMAL_FLAGS` + `--enable-obmc=1`）：

- `tests/fixtures/av1-inter/inter_obmc_64x64.obu`（74 字节）
- `tests/fixtures/av1-inter/inter_obmc_64x64.reference.yuv`（dav1d 1.2.1 原生平面，2 帧）
- `tests/fixtures/av1-inter/inter_obmc_64x64.input.yuv`（原始平面输入）
- manifest 新增条目（含可复现命令与双侧 sha256）
- `tests/fixtures/av1-inter/README.md` 新增一节，记录根因与修复过程
- `av1_inter_reference_wbtest.mbt` 新增两个测试，断言 `[0, 0, 0]`

**外部像素核验**：`inter_obmc_64x64` 的 inter 帧 Y/U/V 对 dav1d 真值
`[0, 0, 0]`（native / js / wasm-gc 三目标一致）。

## 四、实测结果（2026-09-21，本机）

| 检查 | 结果 |
| --- | --- |
| `moon check` | 通过，64 warnings / 0 errors |
| native / js / wasm-gc 全量测试 | 各 **1190/1190** 通过（较基线 1188 多 2 个 OBMC 测试） |
| `node scripts/build-web.mjs --check` | OK（已因源码变更重新生成 `web/dist/web.js`） |
| `node verify-wasm.mjs` | PASS |
| `moon run --target native cmd/cli -- --help` | 通过 |

## 五、下一阶段入口

1. `av1_inter_frame_supported` 剩余门逐项处理：`allow_warped_motion` →
   `reference_select` / `use_ref_frame_mvs` / `skip_mode_present` →
   `allow_intrabc` → `allow_screen_content_tools` → 序列级 compound 门。
   做法与本轮相同：用 `scripts/generate-av1-inter-reference.py` 的
   `MINIMAL_FLAGS` 逐项加回工具生成隔离码流，dav1d 1.2.1 取真值，实现后补
   fixture + manifest + README + 测试，再移门禁。
2. **`scripts/emit-av1-inter-test.py` 的 `NAMES` 尚未包含
   `inter_lossless_64x64` 与 `inter_obmc_64x64`**，直接运行生成器会丢掉这两个
   fixture 的测试。补 SPECS 前不要跑它；这是既有的生成器滞后，不是测试缺失。
3. 阶段 B 的 `inter_cdf_inherit_64x64` 结论不变（本机不可达，围栏值即 dav1d
   自身继承效应），未重新打开。

---

# 第十七次推进补充（2026-09-21，`allow_warped_motion` 门评估）

## 一、结论：该门需要大面积实现，本机未推进，门保持原状

用 `MINIMAL_FLAGS + --enable-warped-motion=1` 生成隔离码流
（`c_warped.obu`，dav1d 1.2.1 参考已存于临时目录），临时旁路
`av1_inter_frame_supported` 的 `allow_warped_motion` 后，inter 帧被**拒绝**
（不是无声解错）。这说明当前门的行为是诚实的，但**不能就此解除**。

原因：规范 §5.11.27 的 `read_motion_mode` 第三分支在
`!force_integer_mv && NumSamples != 0 && allow_warped_motion && !is_scaled(RefFrame[0])`
时读**三符号** `motion_mode`（OBMC / LOCALWARP / SIMPLE），而
`av1_read_motion_mode` 只读单符号 `use_obmc`。放开该门会让这条分支可达，
符号流立即错位。同时 `find_warp_samples` / warp estimation
（§7.11.3.8，最小二乘拟合 `A`/`Bx`/`By` 与 `det`）、setup shear
（§7.11.3.6）、block warp（§7.11.3.5）与 warp 预测网格全部未实现。

## 二、已恢复的状态

- `av1_inter_frame_supported` 的 `allow_warped_motion` 门已恢复（未改动）。
- 临时旁路与探针测试已删除。
- 全量复验：`moon check` 64 warnings / 0 errors；native / js / wasm-gc 各
  **1190/1190**；`node scripts/build-web.mjs --check` OK；
  `node verify-wasm.mjs` PASS；CLI `--help` 正常。

## 三、下一阶段入口（更新）

按代价从低到高推进剩余门：

1. `use_ref_frame_mvs`（temporal MV）——需要 `ref_frame_mvs` 投影与
   `skip_mode` 配合，中等工作量。
2. `skip_mode_present`——依赖 temporal MV，与上一项一起做更划算。
3. `allow_intrabc`——用当前帧已解码像素作参考，可复用 MC 核，但要先处理
   `allow_screen_content_tools`（palette + intrabc 门）。
4. `allow_screen_content_tools`——palette 索引已在库内，inter 帧的 palette 路径
   需要接入。
5. `allow_warped_motion`——见上，最大的一块。
6. 序列级 `enable_interintra_compound` / `enable_masked_compound`
   （`reference_select`）——compound 预测，第二大。

做法与 OBMC 相同：`MINIMAL_FLAGS` 逐项加回工具生成隔离码流 → dav1d 1.2.1
取真值 → 实现 → 补 fixture/manifest/README/测试 → 移门禁。
**注意：每移一个门之前，必须先确认该工具在隔离码流里真的被某个块选中**
（用"把 `return true` 改成 `return false` 看帧是否被拒"的办法，和 OBMC 一样），
否则只是把拒绝条件删掉而没解码对应语法。

**测试有效性证明**：把 `av1_inter_predict` 里的
`if block.motion_mode == 1 && !av1_obmc_blend(...)` 临时改为 `if false && ...`
（即禁用混合）后，`inter_obmc_64x64: obmc inter frame reconstruction` 失败于
`[0, 16, 48] != [0, 0, 0]`——与修复前实测的差异数完全一致。恢复后三目标
1190/1190 全绿。这证明该测试确实在检验 OBMC 混合，而不是靠任何副作用通过。

---

# 第十八次推进补充（2026-09-21，`use_ref_frame_mvs` 门评估）

## 一、结论：需要每参考帧 8×8 MV 网格，门保持原状

用 `MINIMAL_FLAGS + --enable-ref-frame-mvs=1 --enable-order-hint=1` 生成隔离码流
（`c_refmvs2.obu`，76 字节，dav1d 1.2.1 参考已存于临时目录）。帧头实测
`use_ref_frame_mvs=true`、`skip_mode_present=false`，OBU 切分
key=[0:49]、inter=[49:76]。

临时旁路门后 inter 帧**不被拒绝**，但像素错误 `BAD 96 171 224`。因为
`skip_mode_present=false`，所以不是漏读符号导致的符号流错位；`av1_read_skip_mode`
本身已能在 `skip_mode_present` 时正确读符号。错误完全来自**缺少时间 MV 候选**：
`av1_find_mv_stack` 没有实现规范 §7.10.2.4 的 temporal scan，候选堆栈少一类条目，
`drl_mode`/`RefMvIdx` 选中的候选因此不同 ⇒ MV 不同 ⇒ 像素错，但符号流仍同步。
这正是"合法未实现工具被无声解码为错误画面"的情形，门必须保持。

## 二、实现范围（下一轮入口）

1. **存储**：每个 `Av1RefFrame` 增加 `MotionFieldMvs`——按 8×8 luma 单位的
   MV 网格，intra/未写位置填 `-1 << 15`（规范的无效标记）。规范 §7.10.2.6 的
   `MotionFieldMvs[refFrame][y8][x8]` 即查此表。现有 `Av1MotionField` 是
   4×4 粒度且随帧销毁，需要在 `av1_frame_map_update` 存参考时派生并固化。
2. **temporal scan**（§7.10.2.4/§7.10.2.6）：在 near 加权之后、corner 扫描之前
   插入。块内按 `stepW4 = (bw4 >= 16) ? 4 : 2`、`stepH4` 同理步进
   `Min(bh4,16) × Min(bw4,16)`；`allowExtension` 时再查
   `tplSamplePos = { {bh4,-2}, {bh4,bw4}, {bh4-2,bw4} }` 三个位置，
   并用 `check_sb_border` 限制在同一 64×64 超块内。命中后 `lower_mv_precision`
   （`allow_high_precision_mv == 0` 时去掉最低 1 位；`force_integer_mv` 时去掉
   全部 3 个分数位），重复候选只 `WeightStack[idx] += 2`，否则入栈权重 2。
3. **验证**：`c_refmvs2` 的 Y/U/V 对 dav1d 真值须变为 `[0,0,0]`；再补 fixture、
   manifest、README、测试，然后移门。
4. **注意**：本配置下 `force_integer_mv == 0`（`seq_force_integer_mv` 未置位），
   所以 `lower_mv_precision` 只可能去最低 1 位；两条分支都要写但只有一条会被测到。

---

# 第十九次推进补充（2026-09-21，验收序列实录 + temporal MV 常数缺口）

## 一、HANDOFF.md 第 3 节验收序列逐条实录（本机，本次提交）

```text
$ moon version --all
moon 0.1.20260827 (d0aaa07 2026-08-27) ~\.moon\bin\moon.exe
moonc v0.10.11+6ff76a5f9 (2026-08-28) ~\.moon\bin\moonc.exe
moonrun 0.1.20260827 (d0aaa07 2026-08-27) ~\.moon\bin\moonrun.exe

$ node --version
v24.12.0

$ moon update
Registry index updated successfully
Symbols updated successfully

$ moon check
Finished. moon: ran 2 tasks, now up to date (64 warnings, 0 errors)

$ moon test --target wasm-gc
Total tests: 1190, passed: 1190, failed: 0.
$ moon test --target js
Total tests: 1190, passed: 1190, failed: 0.
$ moon test --target native
Total tests: 1190, passed: 1190, failed: 0.

$ node scripts/build-web.mjs --check
OK web/dist/web.js
OK web/dist/wasmcore.wasm

$ node verify-wasm.mjs
WASM verification passed

$ moon run --target native cmd/cli -- --help
PixelForge CLI 0.15
Usage:
  pixelforge info --input PATH
  ...

$ git diff --check
README.en.md: trailing whitespace.   ← 既有 CRLF 假象（第 2 节已记录）
README.md: trailing whitespace.      ← 同上
```

新增 fixture 的 manifest sha256 与磁盘文件逐项核对，四项全部 MATCH：
`inter_obmc_64x64.obu`、`inter_obmc_64x64.reference.yuv`、
`inter_lossless_64x64.obu`、`inter_lossless_64x64.reference.yuv`。

## 二、temporal MV 实现的常数缺口（下一轮必须先解决）

本轮尝试实现 temporal MV，读完规范 §7.9.2/§7.9.3/§7.9.4/§7.10.2.4/§7.10.2.6 后
确认：它不是一个"补一个 scan"，而是整套 MFMV 投影子系统。三个原语
（`get_relative_dist`、`get_mv_projection`、`get_block_position`）的**算法**在
`_refs/av1spec08.md:848-930` 与 `_refs/av1spec06.md:858-866` 已完整给出，
`Div_Mult[32]` 查表也在 `av1spec08.md:872-877` 逐值给出；但下列**常数在本仓库
所有本地参考里都找不到**：

- `MAX_FRAME_DISTANCE`
- `MAX_OFFSET_WIDTH` / `MAX_OFFSET_HEIGHT`
- `MFMV_STACK_SIZE`（= `refStamp` 限值 + 2）
- `MI_SIZE_LOG2`（按上下文应为 3，但本地无定义处）

`_refs/go-av1` 只有 `bits/cdf/decode/header/msac/obu` 六个包，没有 mvrefs，
grep 上述常量零命中。**不要凭记忆猜这些值**——猜错的后果正是本阶段反复在防的
"合法未实现工具被无声解码为错误画面"。

下一轮的正确做法：从 libaom（`av1/common/mvrefs.h`、`aom_dsp/aom_dsp_common.h`）
或 dav1d（`src/mv.h`、`src/decode.c`）的对应修订里取这四个常量的权威值并锁定
修订号，写进 `_refs/`，然后按第十八次补充的范围实现。在常数有着落之前，
`use_ref_frame_mvs` 门保持拒绝。

---

# 第二十次推进补充（2026-09-21，OBMC above pass 覆盖补齐）

## 一、发现并填补的覆盖缺口

`inter_obmc_64x64` 只覆盖 OBMC 的 **left pass**——该样本的 OBMC 块在帧顶行，
`AvailU == 0`，above pass 从不执行。这意味着本阶段新写的 above pass 分支
（含 `step4` 步进、`nLimit` 限制、`predH` 的 `h >> 1` 与 `32 >> subY` 双重上限、
mask 按**行**索引）此前**零覆盖**。

## 二、为何不能用第二个 fixture 覆盖

尝试用 libaom 生成"低行块选中 OBMC"的隔离码流，构造了 7 个候选源
（垂直翻转、上下左右平移、垂直/水平渐变、只扰动右下象限、只扰动左下象限、
只扰动弹底半、不同增量），其中 **5 个在写出 OBU 之前段错误**（零长度文件）——
这正是 HANDOFF 第 8 节记录的同一 libaom 构建缺陷。成功编码的两个
（`right16`、`vgrad`）以及 `br2`（两个 OBMC 块）经插桩确认**全部仍选中帧顶行**
（`OBMC block at 0,8 ... availU=false`）：编码器把 OBMC 预算花在左上邻块 MV
差异最大的第一个块上。64×128 加高源的编码同样段错误。

结论：本机编码器无法产出覆盖 above pass 的码流，改用白盒测试直接驱动
`av1_obmc_blend`。

## 三、新增 `av1_obmc_wbtest.mbt`

三个用例：

1. **above pass 混合上半**：块在 MI (4,4) 16×16，上方邻居 MI (3,4) 带不同 MV；
   断言 16×8 条带逐样本等于 `Round2(mask[i]*own + (64-mask[i])*neighbour, 6)`，
   并断言条带以外的 8 行保持原预测。
2. **上方为 intra 块时无贡献**：真实原因（`RefFrames[...][0] == INTRA_FRAME`），
   而不是"没有上方块"。
3. **色度网格与 32 样本上限**：`predW = Min(8,16) = 8`、
   `predH = Min(4,16) = 4`，条带落在色度块左上 8×4。

**有效性证明**：把 `if block.avail_u && residual_w >= 8 ...` 临时改为
`if false && ...` 后，用例 1、3 分别失败于 `200 != 145`、`200 != 164`——
与手算期望值一致，证明不是偶然通过。

## 四、状态

| 检查 | 结果 |
| --- | --- |
| `moon check` | 64 warnings / 0 errors |
| native / js / wasm-gc | 各 **1193/1193**（新增 3 个用例） |
| `git diff --check` | 仅两个 CRLF README 的既有假象 |
| 行尾 | `av1_obmc_wbtest.mbt` 新建为 LF；`av1_inter_tile.mbt`/`av1_inter_mode.mbt` 与 HEAD 一致 |

temporal MV 的常数缺口（`MAX_FRAME_DISTANCE`、`MAX_OFFSET_WIDTH/HEIGHT`、
`MFMV_STACK_SIZE`）依旧未解决，门保持拒绝，入口见第十九次补充。

---

# 第二十一次推进补充（2026-09-21，门禁盘点修正 + screen-content 边界样本）

## 一、`header.allow_intrabc` 是死代码，已从 `av1_inter_frame_supported` 移除

规范 `av1spec06.md:732-737`：

```
if (  FrameIsIntra ) {
    frame_size( )
    render_size( )
    if ( allow_screen_content_tools && UpscaledWidth == FrameWidth ) {
        @@allow_intrabc                               | f(1)
    }
}
```

`allow_intrabc` **只在 `FrameIsIntra` 时读取**。我方 `av1_frame_header.mbt` 与规范一致：
唯一的 prefix 构造函数把 `allow_intrabc` 初始化为 `false`（第 923 行），唯一赋值点
（第 1126 行）在 `if prefix.frame_is_intra { ... }` 内。因此**任何 inter 帧的
`header.allow_intrabc` 恒为 false**，`av1_inter_frame_supported` 里的那一项不可能
触发，是死代码。已移除，并在原处注释说明依据与"intrabc 的真正门在
`av1_frame_planes`（第 1476 行 `if prefix.allow_intrabc { return None }`）"。

## 二、`allow_screen_content_tools` 门必须保留，且原因比此前记录的更精确

此前 HANDOFF 只说"屏幕内容工具"未实现。本轮查明精确边界：`inter_frame_mode_info`
对 intra 块调用 `intra_block_mode_info`，而后者（`av1spec06.md:2550-2554`）在
`allow_screen_content_tools` 置位时会读 `palette_mode_info`。我方 inter 块阶段
没有 palette 路径（`av1_inter_tile.mbt`/`av1_inter_mode.mbt` 中无 palette 调用），
所以门必须留。

但 `force_integer_mv` **已经完整实现**（`av1_inter_mode.mbt:602,619`：
`fraction = 3`；`av1_frame_header.mbt:838`：`allow_high_precision_mv = 0`）。

**实证**：`--tune-content=screen` 生成隔离码流（72 字节）。门恢复时 inter 帧被拒；
临时旁路 `allow_screen_content_tools` 门后，Y/U/V 对 dav1d 真值 **`[0, 0, 0]`**——
因为该流没有任何块真正选中 palette。这正是"合法未实现工具被无声解码为错误画面"
的临界情形：当前流侥幸全对，但同一语法下另一条流会错。门保持。

## 三、新增样本 `inter_screen_content_64x64`（refused 类）

- `tests/fixtures/av1-inter/inter_screen_content_64x64.obu`（72 字节）
- `.reference.yuv`（dav1d 1.2.1，2 帧）、`.input.yuv`、manifest 条目（双侧 sha256）
- README 新增一节；`av1_inter_reference_wbtest.mbt` 新增两个测试：
  1. inter 帧被**整帧拒绝**（断言 `av1_inter_frame_supported == false`、
     `allow_screen_content_tools == true`、`allow_intrabc == false`、
     解码返回 `None`，且 key 帧解码后 buffer 未被 inter 帧触碰）；
  2. **同一码流的关键帧逐样本精确**（该帧同样带 screen-content 标志，但 intra
     块阶段实现了 palette，所以 `[0, 0, 0]`）。
- 有效性证明：临时旁路该门后测试 1 失败于 `true != false`。

## 四、状态

| 检查 | 结果 |
| --- | --- |
| `moon check` | 64 warnings / 0 errors |
| native / js / wasm-gc | 各 **1195/1195** |
| 新增 fixture 的 manifest sha256 | 与磁盘文件一致 |

剩余门：`reference_select`、`allow_warped_motion`、`use_ref_frame_mvs`、
`skip_mode_present`、`allow_screen_content_tools`（见上），以及序列级
`enable_interintra_compound` / `enable_masked_compound`。

---

# 第二十二次推进补充（2026-09-21，inter 帧 intra 块未重建——比 screen-content 更底层的缺口）

## 一、发现

为实现 `allow_screen_content_tools` 门去读规范 `intra_block_mode_info`
（`av1spec06.md:2534-2556`）时发现一个**比 palette 更底层的缺口**：

`av1_inter_tile.mbt` 的 `av1_inter_tile_block` 对 intra 块直接返回：

```moonbit
if !current.is_inter {
  return av1_intra_in_inter_block(
    decoder, state, info, current, block, block_index, has_chroma,
  )
}
```

而 `av1_intra_in_inter_block` 只做**语法读取**（y_mode、角度、uv_mode、CfL、
filter intra、tx 尺寸、`av1_intra_record_modes`）就 `return true`——
**既不做帧内预测，也不解码残差**。`av1_inter_residual` 只对 inter 块调用。

现有 inter fixture 全部 4 个块都是 inter（`c_obmc` 的 MC trace 只有 4 个请求，
`av1_inter_reference_wbtest.mbt` 的 9 个 `is_inter` 相关断言均通过），所以这个
缺口**从未被任何样本触及**，也从未被测试发现。

## 二、本轮已做的改进（严格增量，无回退）

在 `av1_intra_in_inter_block` 中按规范顺序插入 palette 语法读取：
`palette_mode_info`（§5.11.21）位于 uv_mode 与 filter intra 之间；
`filter_intra_mode_info` 补上此前缺失的 `PaletteSizeY == 0` 条件
（§5.11.29，原来该路径漏了，与 `av1_intra_only_block` 不一致）；
palette 索引图在 tx 尺寸之前读（与 intra-only 路径一致）。

**这是严格改进**：此前 inter 帧 intra 块完全**不读** palette 符号 ⇒ 符号流立即
错位，该块之后的所有语法全部变成垃圾；现在符号读全，后续语法恢复正确。
但该块本身仍不被重建（见上），所以 `allow_screen_content_tools` 门**继续保留**。

## 三、下一轮入口（按依赖顺序）

1. **inter 帧 intra 块的重建**（根因，优先级最高）：`av1_intra_in_inter_block`
   需要像 `av1_intra_only_block` 一样，在读完全部语法后调用帧内预测与
   `av1_intra_residuals`。注意两处差异：
   - `av1_inter_residual` 开头有 `av1_cfl_begin_block(state.cfl, tile_block, false)`
     （对 inter 块关闭 CfL）；intra 块必须**开启** CfL。
   - tx 尺寸来自 `av1_read_block_tx_size`（inter 路径）而非 intra 路径的
     `av1_intra_residuals` 参数形式，需要适配。
2. 生成一条"inter 帧含 intra 块"的隔离码流并外部核验。本机 libaom 对
   `key.yuv` 之外的多个候选源（反相、加噪）在写出 OBU 前段错误，尚未产出；
   可试 `--cpu-used` 调高或换源。
3. 然后再接 palette 预测（`av1_intra_palette_maps` 已接好，预测侧
   `av1_intra_tile.mbt:540-570` 的 palette 分支已在 intra 路径验证过，
   inter 路径需要确认 `state.prediction_block` 被正确设置）。
4. 都通过后才移 `allow_screen_content_tools` 门。

## 四、状态

| 检查 | 结果 |
| --- | --- |
| `moon check` | 64 warnings / 0 errors |
| native / js / wasm-gc | 各 **1195/1195** |
| 行为变化 | 仅符号读取更完整；无测试失败、无金标改动 |

---

# 第二十三次推进补充（2026-09-21，`allow_screen_content_tools` 门解除 + 更正第二十二次的错误结论）

## 〇、先更正：第二十二次补充的"根因缺口"结论是错的

第二十二次补充声称"`av1_intra_in_inter_block` 只读语法、从不重建，inter 帧 intra
块既不做预测也不解码残差"。**该结论错误**：我当时只读了该函数前 75 行就下了判断。
实际 `av1_inter_tile.mbt` 的 `av1_intra_in_inter_block` 在函数尾部**确实**调用
`av1_intra_residuals(decoder, state, block, y_mode, uv_mode, tx_width, tx_height, inter.skip)`
（含帧内预测与残差解码）。`av1_inter_residual` 开头那句
`av1_cfl_begin_block(state.cfl, tile_block, false)` 只作用于 inter 块；
`av1_intra_residuals` 内部有自己的 `av1_cfl_begin_block(...)`，按
`uv_mode == AV1_INTRA_CFL` 决定开关。**没有这个缺口**，特此记录以免后续接手者
再去"实现"一个已经存在的东西。

## 一、`allow_screen_content_tools` 门已解除

精确边界（本轮查清）：inter 帧上该标志只做两件事——
1. 推导 `force_integer_mv`，我方 `av1_inter_mode.mbt:602,619` 已完整处理
   （`fraction = 3`），`av1_frame_header.mbt:838` 也已处理
   `allow_high_precision_mv = 0`；
2. 允许 `intra_block_mode_info`（`av1spec06.md:2550-2554`）为 inter 帧内的
   intra 块读 `palette_mode_info`。

本轮在 `av1_intra_in_inter_block` 中按规范顺序接入 palette：
`palette_mode_info` 位于 uv_mode 与 filter intra 之间；索引图在 tx 尺寸之前读
（与 `av1_intra_only_block` 一致）。**同时修了一个既有 bug**：该路径的
`filter_intra_mode_info` 条件漏了 `PaletteSizeY == 0`（§5.11.29），而
`av1_intra_only_block` 有——若 palette 与 filter intra 同时可用会多读符号。

## 二、外部像素核验

| 样本 | 结果 |
| --- | --- |
| `inter_screen_content_64x64` | inter 帧 Y/U/V 对 dav1d 真值 **`[0,0,0]`**（该流无块选中 palette） |
| `inter_palette_64x64` | inter 帧 Y/U/V 对 dav1d 真值 **`[0,0,0]`**，且实测有 **1 个 inter 帧 intra 块选中 palette**（`y=2 u=0`） |
| key 帧（两个样本） | 各 **`[0,0,0]`** |

`inter_palette_64x64` 的构造：源为 `key.yuv` 的帧 1 右下象限改成三条 16px 竖条
（101/167/233），迫使编码器在该块上用 palette（2 色）而非 DCT 残差。
`--cpu-used=4` 必须：本机 libaom 对该源在 `--cpu-used=0..3` 全部段错误。

**有效性证明**：把 `if !av1_palette_read_colors(...)` 临时改为
`if false && ...` 后，`inter_palette_64x64` 失败于 `[1024, 256, 256] != [0, 0, 0]`
——正是"不读 palette 符号 ⇒ 符号流错位"的预期后果。

## 三、状态

| 检查 | 结果 |
| --- | --- |
| `moon check` | 64 warnings / 0 errors |
| native / js / wasm-gc | 各 **1197/1197**（新增 2 个用例） |
| 新增 fixture manifest sha256 | 与磁盘文件一致 |
| 剩余 inter 帧门 | `reference_select`、`allow_warped_motion`、`use_ref_frame_mvs`、`skip_mode_present`；序列级 `enable_interintra_compound` / `enable_masked_compound` |

`av1_inter_frame_supported` 现只剩 4 个帧级门 + 2 个序列级门。

---

# 第二十四次推进补充（2026-09-21，`skip_mode_present` 与 `reference_select` 的顺序依赖）

## 一、发现：`skip_mode_present` 是 `reference_select` 的下游，不是独立门

规范 `av1spec06.md:1429-1484` 的 `skip_mode_params`：

```
if ( FrameIsIntra || !reference_select || !enable_order_hint ) {
    skipModeAllowed = 0
} else { ... }
if ( skipModeAllowed ) {
    @@skip_mode_present                               | f(1)
}
```

**`skipModeAllowed` 要求 `reference_select == 1`**，所以 `skip_mode_present` 只在
compound 帧上可能被置位。我方 parser 与规范逐字一致
（`av1_frame_header.mbt:1362`：`if !prefix.frame_is_intra && reference_select &&
sequence.enable_order_hint`）。

因此 `av1_inter_frame_supported` 里 `skip_mode_present` 列在 `reference_select`
**之后**是有意义的：能带着 `skip_mode_present == true` 走到那一行的帧，已经被
`reference_select` 抢先拒绝。这与 `allow_intrabc`（该位在 inter 帧上**永不为
true**，已删）不同——这里是"冗余"而非"死代码"，因为一旦单独解除
`reference_select`，`skip_mode_present` 就会立刻变成活门。

已在 gate 处补注释说明这个顺序依赖，并明确：**两个条目必须一起解除**，且
`skip_mode` 语义本身（ compound 块、运动从两个参考帧复制）也未实现。

## 二、剩余门的依赖图（下一轮的排序依据）

```
reference_select ──┬─→ skip_mode_present ──→ skip_mode 语义（compound）
                   └─→ compound 预测（NEAREST_NEARESTMV 等）

use_ref_frame_mvs ──→ temporal MV 候选（需 MFMV 常数，见第十九次补充）
allow_warped_motion ──→ find_warp_samples + 三符号 motion_mode + warp 预测
```

即：**`reference_select` 是剩余门里的枢纽**，它一开，`skip_mode_present`
立刻变活；而它自身需要 compound 预测。第三大的块是
`allow_warped_motion`（warp 估计 + 预测网格）。
`use_ref_frame_mvs` 仍卡在四个本地参考里找不到的常数上。

## 三、状态

本轮只有注释与文档改动，无行为变化：

| 检查 | 结果 |
| --- | --- |
| `moon check` | 64 warnings / 0 errors |
| native / js / wasm-gc | 各 **1197/1197** |

---

# 第二十五次推进补充（2026-09-21，temporal MV 常数的可推导约束）

## 一、本轮没有实现 temporal MV，但把搜索空间从"无界"缩到"31 个候选"

`av1spec08.md:848-880` 的 get mv projection：

```
clippedDenominator = Min( MAX_FRAME_DISTANCE, denominator )
clippedNumerator   = Clip3( -MAX_FRAME_DISTANCE, MAX_FRAME_DISTANCE, numerator )
scaled = Round2Signed( mv[i] * clippedNumerator * Div_Mult[ clippedDenominator ], 14 )
```

**推导 1（新）**：`Div_Mult` 在规范里是 `Div_Mult[32]`（`av1spec08.md:872-877`，
32 个值，索引 0..31），而 `clippedDenominator` 直接用它作下标。因此

    MAX_FRAME_DISTANCE ≤ 31

这把上一轮"完全不知道"缩成**31 个候选**。同时
`Quant_Dist_Weight[3][1] = MAX_FRAME_DISTANCE`（`av1spec08.md:4134`）说明它是
正整数。

**推导 2**：`Div_Mult[i] = Round2Signed(1 << 14, i)`，可用规范里已给出的 32 个值
逐一验证（`Div_Mult[2] = 8192 = 16384/2`、`Div_Mult[3] = 5461 ≈ 16384/3 = 5461.33`
向下舍入、`Div_Mult[31] = 528 ≈ 16384/31 = 528.5`）。所以**不需要 libaom 就能
重建这张表**。

## 二、仍然缺的两块（不要猜）

1. `MAX_FRAME_DISTANCE` 的确切值（已知 ∈ [1, 31]）。
2. `MAX_OFFSET_WIDTH` / `MAX_OFFSET_HEIGHT`（`get_block_position` 的 `maxOff8`，
   单位是 8×8 块）。
3. `Round2Signed` 的定义**在本地规范参考里只有使用处、没有定义体**（`av1spec08.md`
   grep `Round2Signed` 只有 874/1073/1076 三处调用）。库内
   `av1_mc_round2_signed`（`av1_mc.mbt:58`）实现的是"半边远离零"的标准形式，
   MC 路径已被 `av1_mc_oracle_wbtest.mbt` 独立验证，但**不能据此断定它就是
   `Round2Signed`**——需要 libaom/dav1d 的定义处确认。

因此本轮**没有**写 `get_mv_projection`。在拿到上述三块之前，
`use_ref_frame_mvs` 门保持拒绝。

## 三、给下一轮的最小实现清单

1. 从 libaom `aom_dsp/aom_dsp_common.h`（或 dav1d `src/mv.h`）取
   `MAX_FRAME_DISTANCE`、`MAX_OFFSET_WIDTH`、`MAX_OFFSET_HEIGHT` 与
   `Round2Signed` 定义，锁定修订号写进 `_refs/`。
2. `Div_Mult` 用规范第 872-877 行的 32 个值（或按
   `Round2Signed(1 << 14, i)` 生成后逐值比对）。
3. 实现顺序：`av1_mv_div_mult` + `av1_mv_projection`（纯函数，带单测，覆盖
   `numerator/denominator` 都小于 `MAX_FRAME_DISTANCE` 的非截断区间）→
   `get_block_position` → `Av1RefFrame` 的 `MotionFieldMvs` 8×8 网格 →
   `av1_find_mv_stack` 的 temporal scan → 用 `c_refmvs2`（临时目录，76 字节，
   `skip_mode_present=false`、`use_ref_frame_mvs=true`，旁路门后
   `BAD 96 171 224`）核验到 `[0,0,0]` → 补 fixture/manifest/README/测试 → 移门。

## 四、状态

| 检查 | 结果 |
| --- | --- |
| `moon check` | 64 warnings / 0 errors |
| native / js / wasm-gc | 各 **1197/1197** |
| 本轮代码改动 | 无（仅 HANDOFF） |

---

# 第二十六次推进补充（2026-09-21，`Div_Mult` 表落地 + 单测）

## 一、做了什么

`Div_Mult` 是 temporal MV 投影里**唯一在本地规范中完整给出**的一块
（`av1spec08.md:872-877`，32 个值），因此本轮把它落地，不依赖 libaom/dav1d：

- `av1_mv_div_mult.mbt`：32 个值按规范逐字转写（不做公式生成，避免推导风险）；
  另导出 `av1_mv_div_mult_size = 32`，并在注释里说明"表有 32 项 +
  `clippedDenominator` 以其为下标 ⇒ `MAX_FRAME_DISTANCE ≤ 31`"。
- `av1_mv_div_mult_wbtest.mbt`：三个用例——
  1. 表与规范字面值逐一相等；
  2. 每项等于 `16384 / i`（整数除法，`i == 0` 时为 0）——这是对转写工作的检查，
     一个 digit 打错即失败；
  3. 表在索引 2..31 上单调不增（索引 0 是零分母特例，低于索引 1 属构造使然），
     并钉住 `Div_Mult[0] == 0`、`Div_Mult[1] == 1 << 14`、末项为正。

`pkg.generated.mbti` 已用 `moon info` 重新生成；其中除本次新增的
`av1_mv_div_mult_size` 外，还包含早前源码改动（`av1_inter_frame_supported`、
`av1_inter_frame_of`、`av1_motion_field_store` 新增三个可选参数）积欠的接口更新——
那些源码改动在本阶段早期就已存在，只是接口文件没跟着重新生成。

## 二、仍然缺的（`use_ref_frame_mvs` 门继续拒绝）

1. `MAX_FRAME_DISTANCE` 确切值（已知 ∈ [1, 31]）；
2. `MAX_OFFSET_WIDTH` / `MAX_OFFSET_HEIGHT`；
3. `Round2Signed` 的定义体（本地规范只有使用处）。

三者都要从 libaom `aom_dsp/aom_dsp_common.h` 或 dav1d `src/mv.h` 取并锁定修订号。
拿到后按第二十五次补充的实现清单推进。

## 三、状态

| 检查 | 结果 |
| --- | --- |
| `moon check` | 65 warnings / 0 errors（新增 1 个 `av1_mv_div_mult_size` 的未使用告警，属预期：它要等 temporal MV 接线后才被读取） |
| native / js / wasm-gc | 各 **1200/1200**（新增 3 个用例） |
| `build-web.mjs --check` | OK |
| `verify-wasm.mjs` | PASS |
| `git diff --check` | 仅两个 CRLF README 的既有假象 |

---

# 第二十七次推进补充（2026-09-21，动画入口的像素级验证）

## 一、缺口

`avif_grid_animation_test.mbt` 的 "animation decoder reads BMFF samples and
returns pixels" 只断言了两个动画帧的**宽高**（`(64, 64)`）——正是 HANDOFF 第 6 节
警告的"动画不能仅验证帧数或时间戳"。

## 二、已补的验证

在该测试尾部追加**逐样本像素比对**：两个动画帧各自与同一份 sample 的直接 AV1
解码结果（`av1_decode(sample)`）逐像素相等。

注意 reference 用 `av1_decode` 而不是 `avif_decode_rgba`：该测试的 `sample` 是
**裸 AV1 载荷**（29 字节，temporal delimiter + sequence header + frame），不是
完整 AVIF 容器文件，`avif_decode_rgba` 对它返回 `None`（第一版这么写直接 panic，
已改正）。

这一比对闭合的是"动画帧真的是解码出来的像素"，不是"只有一个壳"。

## 三、仍未覆盖的（诚实记录）

该测试的两个 sample **是同一份**，所以它证明不了"跨帧参考状态被真正携带"。
跨帧状态已有另一处覆盖：
`inter_minimal_64x64: animation entry presents both temporal units`
（`av1_inter_reference_wbtest.mbt`）用**真实 inter 帧**走
`avif_decode_animation_samples`，验证第二帧像素与第一帧不同、且冷启动解码器
必须拒绝该 inter 单元。

要在此基础上再进一步，需要合成一个"容器内两帧、第二帧为 inter"的动画 AVIF
样本（当前所有动画样本都是同一张静图重复两遍）。本机 libaom 段错误频繁，
暂未产出。

## 四、状态

| 检查 | 结果 |
| --- | --- |
| `moon check` | 65 warnings / 0 errors |
| native / js / wasm-gc | 各 **1200/1200** |
| `git diff --check` | 仅两个 CRLF README 的既有假象 |

---

# 第二十八次推进补充（2026-09-21，`find_warp_samples` 落地）

## 一、为什么先做这个

`allow_warped_motion` 门的真正难点不是 warp 预测，而是**符号读取**：
规范 §5.11.27 的 `read_motion_mode` 在
`!force_integer_mv && NumSamples != 0 && allow_warped_motion && !is_scaled`
时读**三符号** `motion_mode`，否则读单符号 `use_obmc`。而我方
`av1_read_motion_mode` 只会读单符号。所以只要放开该门而没实现
`find_warp_samples`，符号流立刻错位——这正是上一轮旁路实验里
`c_warped.obu` 被拒的原因（拒绝是诚实的，但原因要找对）。

`find_warp_samples`（§7.10.4.1 + `add_sample` §7.10.4.2）**不读任何熵符号**，
是纯计算，因此可以先落地并用白盒测试钉住。

## 二、已落地

- `av1_warp_samples.mbt`：`av1_warp_samples(field, block_row, block_col,
  block_w4, block_h4, avail_u, avail_l, mv_row, mv_col, ref_frame) -> Int`，
  按 `av1spec08.md:1836-1989` 逐字转写：above 行按邻居宽度步进、
  `doTopLeft`/`doTopRight` 抑制、left 列步进、两个角点、以及
  "扫到过东西但全不合格 ⇒ NumSamples 置 1" 的回退。
- `av1_warp_samples_wbtest.mbt`：7 个用例，覆盖 above 邻居为 intra、
  同参考同 MV、不同参考、MV 差距过大（回退路径）、完全没有邻居、
  角点抑制标志、以及扫描上限的推导校验。

**`av1_warp_samples_scan_limit = 18` 是推导值，不是猜的**：64×64 超块档最大块
64×64 = 16 个 4×4 单位/轴，above/left 扫描步长至少为最小块 8×8 = 2 单位，
故每轴最多 8，加两个角点 = 18。真正的 `LEAST_SQUARES_SAMPLES_MAX` 在本地规范
参考里找不到（只有 `av1spec08.md:1924` 一处使用），取 18 可保证在该档位上
提前退出永不触发，从而**结果与未知常数无关**。若将来要支持 128×128 超块，
需重新校准。

## 三、剩下的接线（下一轮）

1. `read_motion_mode` 三符号分支：需要 `NumSamples`（上面已好）与
   `is_scaled(RefFrame[0])`——后者要当前帧的 `FrameWidth`/`FrameHeight` 与
   `RefUpscaledWidth[refIdx]`/`RefFrameHeight[refIdx]` 比对，而
   `Av1MvFrame`/`Av1InterInfo` 目前都没带当前帧尺寸，需要加字段。
2. 三符号的 CDF 表（`av1_motion_mode`）本地已有，但其符号取值
   （OBMC / LOCALWARP / SIMPLE 的编码顺序）需与规范 §5.11.27 的实现处核对。
3. LOCALWARP 命中时**拒绝整帧**（warp 预测未实现），这与 OBMC 实现前的处理一致。
4. 用临时目录的 `c_warped.obu`（`--enable-warped-motion=1`，dav1d 真值已在）
   核验：要么 `[0,0,0]`，要么干净拒绝。

## 四、状态

| 检查 | 结果 |
| --- | --- |
| `moon check` | 68 warnings / 0 errors（新增的是未接线函数的既有风格告警） |
| native / js / wasm-gc | 各 **1207/1207**（新增 7 个用例） |
| `git diff --check` | 仅两个 CRLF README 的既有假象 |

---

# 第二十九次推进补充（2026-09-21，`allow_warped_motion` 门解除 + 三符号 motion_mode）

## 一、为什么这次能解除

上一轮补的判断"需要 warp 估计"只对了一半：真正的前置是**符号读取**。规范
§5.11.27 在 `!force_integer_mv && NumSamples != 0 && allow_warped_motion &&
!is_scaled` 时读**三符号** `motion_mode`，否则读单符号 `use_obmc`。我方原来
只会读单符号，所以放开该门就会符号错位——这才是旁路实验里 `c_warped.obu`
被拒的真实原因（此前记录为"需要 warp 估计"，不准确）。

本轮从 `_refs/go-av1/decode/intermode.go:274-300` 取到两块此前缺失的权威依据：
1. 三符号的取值编码：`motionModeSimple = 0 / motionModeObmc = 1 /
   motionModeWarp = 2`（与我方既有 `motion_mode = 1` 表示 OBMC 的约定一致）；
2. `isScaled` 的语义：参考帧的可见宽高与当前帧宽高不等即为 scaled
   （go-av1 注释明确"不支持参考缩放，所以参考总是同尺寸"）。

## 二、实现

1. `av1_warp_samples.mbt`（上一轮落地）现在被 `av1_read_motion_mode` 调用，
   其返回值决定走哪个符号形状。
2. `Av1MvFrame` 增加 `frame_width`/`frame_height`（由
   `av1_mv_frame_of` 从帧头填充），`av1_mv_is_scaled` 据此与
   `Av1RefFrame.width/height` 比对。
3. 三符号分支：读 `av1_motion_mode[size_index]`；`mode == 2`（LOCALWARP）时
   `return false` **拒绝整帧**——warp 估计（§7.11.3.8）与 warp 预测网格
   （§7.11.3.5）都未实现，按完成标准第 4 条不能无声解错。
4. 移除 `av1_inter_frame_supported` 里的 `allow_warped_motion` 条目。

## 三、外部像素核验

| 样本 | 结果 |
| --- | --- |
| `inter_warped_64x64` | inter 帧 Y/U/V 对 dav1d 1.2.1 真值 **`[0,0,0]`** |
| `inter_warped_64x64` key 帧 | **`[0,0,0]`** |
| `av1_warp_samples_wbtest.mbt`（7 例） | 全过 |

新样本 `inter_warped_64x64`：`MINIMAL_FLAGS + --enable-warped-motion=1`，
74→73 字节，dav1d 真值与输入均已入库、manifest 双侧 sha256 一致、命令可复现
（重编码 sha256 相同）。

**有效性证明**：把三符号分支临时改为 `if false && ...` 后，该测试失败于
"supported inter frame rejected"——即符号流确实走了三分支，不是碰巧通过。

## 四、`allow_warped_motion` 的残余边界（诚实记录）

本样本**没有任何块选中 LOCALWARP**，所以它证明的是"三符号读取正确 + OBMC/SIMPLE
两种取值都走通"，**不证明 warp 预测**。要覆盖 LOCALWARP，需要一条真有块选中它的
码流；那条流现在会被诚实拒绝（返回 false），本机 libaom 尚未产出这样的样本。

## 五、状态

| 检查 | 结果 |
| --- | --- |
| `moon check` | 64 warnings / 0 errors |
| native / js / wasm-gc | 各 **1209/1209**（新增 2 个用例） |
| `build-web.mjs --check` / `verify-wasm.mjs` | 见下轮复核 |
| `git diff --check` | 仅两个 CRLF README 的既有假象 |

`av1_inter_frame_supported` 现剩 **3 个帧级门**（`reference_select`、
`use_ref_frame_mvs`、`skip_mode_present`）+ 2 个序列级 compound 门。其中
`skip_mode_present` 是 `reference_select` 的下游（第二十四次补充），
`use_ref_frame_mvs` 需三个外部常数（第二十五次补充：`MAX_FRAME_DISTANCE`
已知 ∈ [1,31]），`reference_select` 需 compound 预测。

---

# 第三十次推进补充（2026-09-22，temporal MV 的三个常数已找到——阻塞解除）

## 〇、重大更正：常数不在"libaom/dav1d 的远端修订"里，而在本地 `_refs/go-av1`

第十九/二十五次补充说"四个常数在本仓库所有本地参考里都找不到，只能从 libaom 或
dav1d 取"。**这个结论是错的**：我当时只 grep 了 `MAX_FRAME_DISTANCE` 等大写下划线
形式，而 go-av1 用的是 Go 的驼峰命名。go-av1 **完整实现了 temporal MV**：
`_refs/go-av1/decode/motionfield.go`（310 行）+ `decode/compound.go:248`。

## 一、取到的常数（全部本地可复核）

| 常量 | 值 | 来源 |
| --- | --- | --- |
| `maxFrameDistance` | **31** | `decode/compound.go:248` |
| `maxOffsetWidth` | **8** | `decode/motionfield.go:14` |
| `maxOffsetHeight` | **0** | `decode/motionfield.go:15` |
| `mfmvStackSize` | 3 | `decode/motionfield.go:13` |
| `refmvsLimit` | 4095 | `decode/motionfield.go:16` |
| `mvBorderTemporal` | -32768 | `decode/motionfield.go:17` |
| `divMult[32]` | 见 `av1_mv_div_mult.mbt` | `decode/motionfield.go:20`，与规范 `av1spec08.md:872-877` 逐值一致 |
| `Round2Signed` | "半边远离零" | `decode/motionfield.go:305-310`，与本库 `av1_mc_round2_signed` 同形 |

**`maxFrameDistance = 31` 验证了第二十五次的推导**（`Div_Mult` 32 项 + 以其为下标 ⇒
≤ 31），现在有了确切值。注意 `maxOffsetHeight = 0` 与 `maxOffsetWidth = 8` 不对称，
这是容易猜错的地方，现在有着落。

## 二、本轮落地：`av1_mv_projection`

`av1_mv_projection.mbt` 实现了 `get_mv_projection`（§7.9.3）的两个分量版本与
行/列版本，六个常量全部按上表导出为 `pub let`。`av1_mv_projection_wbtest.mbt`
9 个用例，期望值全部由规范自身数字手算：
`Div_Mult[i] = floor(2^14/i)`、`Round2Signed(x,14)`、±(2^14-1) 饱和。

覆盖：二等分、三等分向零舍入、14 位饱和、分子为零、**分母为零**（`Div_Mult[0]=0`
故投影为零而非出错）、分子/分母各自被 31 钳制、取负对称性、以及常数不变量
（`maxFrameDistance < divMult.length()`、`divMult[31] == 528`）。

## 三、下一轮的剩余工作（现在没有外部阻塞了）

按 go-av1 `decode/motionfield.go` 的结构逐项实现：

1. **存储**：`Av1RefFrame` 增加 `mfRefFrames`/`mfMvs`（MI 粒度，与
   `MotionFieldMvs` 的 8×8 网格是两回事，别混）。`storeMotionField`（§7.19）
   在帧存参考时填充：只收 `dist < 0`（向后参考）且 |mv| ≤ 4095 的项。
2. **投影**：`getBlockPosition`（§7.9.4，注意 `maxOffsetHeight = 0`）与
   `projectMvs`（§7.9.2），驱动 `motionFieldEstimation`（§7.9.1）：
   初始化 -32768 网格 → `useLast` 判定 → 按 `refStamp` 依次投影
   LAST(-1) / BWDREF(+1) / ALTREF2(+1) / ALTREF(+1) / LAST2(-1)。
   实现时要核对规范 `av1spec08.md:730-760, 795-838` 与 go-av1 的差异
   （go-av1 在循环里对每个 dst 重新投影，规范同）。
3. **temporal scan**：`av1_find_mv_stack` 在 near 加权之后、corner 扫描之前插入
   §7.10.2.4 的时间扫描，命中走 `add_tpl_ref_mv`（§7.10.2.6 的 temporal sample
   process）；重复候选只 `WeightStack[idx] += 2`。
4. **核验**：用临时目录的 `c_refmvs2.obu`（76 字节，`skip_mode_present=false`、
   `use_ref_frame_mvs=true`，旁路门后 `BAD 96 171 224`）做到 `[0,0,0]`，再补
   fixture/manifest/README/测试，最后移 `use_ref_frame_mvs` 门。

## 四、状态

| 检查 | 结果 |
| --- | --- |
| `moon check` | 65 warnings / 0 errors |
| native / js / wasm-gc | 各 **1218/1218**（新增 9 个用例） |
| `git diff --check` | 仅两个 CRLF README 的既有假象 |

`av1_inter_frame_supported` 仍剩 3 个帧级门 + 2 个序列级 compound 门，但
`use_ref_frame_mvs` 已无外部阻塞。

---

# 第三十一次推进补充（2026-09-22，`get_block_position` 落地）

在 `av1_mv_projection.mbt` 中追加 `av1_mv_block_position` / `av1_mv_block_position_axis`
（§7.9.4），`av1_mv_projection_wbtest.mbt` 追加 5 个用例。drei 处易错点已由用例钉住：

1. **位移是 `delta >> 6`**，即 1/1024-样本为单位的右移 6 位——96（十二个 1/8-样本）
   才走一个 8×8 单位。
2. **`dstSign` 同时作用于两个轴**，不是只作用于行。
3. **`maxOffsetHeight = 0` 而行方向是 8**：投影坐标必须留在原八单位带内
   （`[base8, base8+8)`），仍属于帧内也不行；列方向则有 ±8 的宽容带。

用例覆盖：带内投影、越出帧、越出八单位带、负方向、以及方向乘数翻转后只有一个
方向能成立（grid 坐标 7 在带顶，+1 到 8 出界、-1 到 6 成立）。

至此 temporal MV 的**纯算术层已全部落地并有单测**：`divMult`、`get_mv_projection`、
`get_block_position`、`find_warp_samples`（上一轮，已被 motion_mode 分支调用）。
剩下的是有状态部分（`Av1RefFrame` 的 motion field 存储、`projectMvs`、
`motionFieldEstimation`、`av1_find_mv_stack` 的 temporal scan），按第三十次补充
第 3 节的清单推进即可，无外部阻塞。

## 状态

| 检查 | 结果 |
| --- | --- |
| `moon check` | 64 warnings / 0 errors |
| native / js / wasm-gc | 各 **1223/1223**（新增 5 个用例） |
| `git diff --check` | 仅两个 CRLF README 的既有假象 |

---

# 第三十二次推进补充（2026-09-22，motion field 存储落地）

## 一、实现

`Av1RefFrame` 新增 `mf_refs`/`mf_mvs`/`mi_cols`/`mi_rows`，即规范 §7.19 的
`MfRefFrames`/`MfMvs`（MI 粒度，每单位两个 MV；注意与 §7.9 的 8×8
`MotionFieldMvs` 网格是**两回事**，别混）。

`av1_frame_map_update` 新增 `sequence` 与可选 `field` 参数，在槽位刷新**之前**
计算存储——这样 `map.order_hints` 指向的还是被引用的帧而不是当前帧。计算按规范
逐字：只收 `r > INTRA_FRAME`、`get_relative_dist(RefOrderHint[refIdx], OrderHint)
< 0`（**向后参考**）、且 `|mv| ≤ refmvsLimit(4095)` 的项。

关键顺序点：调用点在 `av1_frame_planes.mbt:814`，传 `field=inter.map(fn(i) { i.field })`。
intra 帧 `inter` 为 `None` ⇒ grid 全 NONE ⇒ 该帧不能当 temporal 候选源。✓

## 二、测试（`av1_motion_field_wbtest.mbt`，2 例）

1. **无 order hint 时存储必须为空**：`inter_minimal_64x64` 关闭 order hint，
   `relative_dist` 恒为 0，`0 < 0` 为假 ⇒ 任何槽位的 `mf_refs` 都必须全 NONE，
   否则会把该帧变成虚假的 temporal 候选源。同时钉住 grid 形状
   （16×16 单位 / 256 / 512）。
2. **intra 帧的 grid 为空**：key 帧不跑 inter 块阶段，其 motion field 因构造为空。

## 三、诚实记录：第二项（真有向后参考时正确存入）尚未被测试覆盖

本仓库已提交的样本里**只有 `general_inter_64x64` 开启 order hint**，而它因为
compound/warped/全局运动被整体拒绝；其余样本 order hint 全关。所以"向后参考被
正确存入"这条路径目前**没有外部样本覆盖**——要覆盖它需要 `c_refmvs2` 那样的码流
（`--enable-order-hint=1`），而那正是 `use_ref_frame_mvs` 门后面的东西。
按完成标准第 4 条，不假装它已验证。

## 四、下一轮

`projectMvs`（§7.9.2）+ `motionFieldEstimation`（§7.9.1）生成 8×8
`MotionFieldMvs` 网格，再在 `av1_find_mv_stack` 的 near 加权之后、corner 扫描
之前插入 §7.10.2.4 的时间扫描。go-av1 `decode/motionfield.go` 是可直接对照的
参考实现，规范见 `av1spec08.md:730-838, 1216-1300, 1922-1968`。

## 五、状态

| 检查 | 结果 |
| --- | --- |
| `moon check` | 64 warnings / 0 errors |
| native / js / wasm-gc | 各 **1225/1225**（新增 2 个用例） |
| `git diff --check` | 仅两个 CRLF README 的既有假象 |

---

# 第三十三次推进补充（2026-09-22，motion field estimation 落地）

## 一、实现

`av1_motion_field.mbt`：

- `Av1MotionFieldGrid`：8×8 网格，每个参考名一份，未命中的格子填
  `av1_mv_invalid(-32768)`——"空洞"必须与"真实投影"可区分。
- `av1_project_mvs`（§7.9.2）：源资格三重检查（`MiRows`/`MiCols` 不等、
  INTRA_ONLY、KEY 都返回 false 且不动网格）；每格只在**奇数** MI 位置取保存值；
  `refOffset` 必须 `> 0` 且 ≤ 31；投影后过 `get_block_position`；最后对每个
  dst 参考名**各自**用 `refToDst` 重新投影（距离不同）。
- `av1_motion_field_estimation`（§7.9.1）：按规范顺序 LAST(-1) → BWDREF(+1) →
  ALTREF2(+1) → ALTREF(+1) → LAST2(-1)，`refStamp` 递减，`useAlt` 与
  LAST2 都带 `refStamp >= 0` 守卫而 `useAlt2` 不带（规范如此，go-av1 亦如此）。

配套给 `Av1RefFrame` 加了 `saved_order_hints`（`SavedOrderHints`），这是
`refOffset` 需要的；`av1_frame_map_update` 存参考时一并保存。

## 二、测试（`av1_motion_field_wbtest.mbt`，3 例）

1. **空 grid 初始化**：无参考 ⇒ 每个格子的两个分量都是 invalid；同时钉住形状
   （`w8 = MiCols>>1`、7 个参考名、各 64 格）。
2. **key 帧不能当源**：投影过程必须报"不可用"且网格保持全 invalid，
   而不是把空数组里的东西投影出去。
3. **网格形状跟随当前帧**，不跟随参考。

序列描述**不手写**，直接用 `av1_sequence_info(general_inter_64x64_obu)` 解析得来
——它是唯一开启 order hint 的已提交样本；手写字面量第一版就因为字段类型不符编译
失败，改为解析后不可能与 parser 漂移。

## 三、诚实记录：尚未接线，也未经外部样本验证

`av1_motion_field_estimation` **还没有被解码路径调用**（`use_ref_frame_mvs` 门
仍挡着），所以它目前是"已实现 + 有单测"的状态，等于 `av1_mv_div_mult` 那一层。
"有向后参考时投影正确"这条路径同样没有外部样本覆盖（原因同第三十二次补充）。

## 四、下一轮

把 estimation 接到帧头读取处（规范 §6.8 第 801 行 `if (use_ref_frame_mvs == 1)
motion_field_estimation()`），再在 `av1_find_mv_stack` 的 near 加权之后、corner
扫描之前插入 §7.10.2.4 的时间扫描与 §7.10.2.6 的 `add_tpl_ref_mv`。需要给
`Av1InterInfo`/`Av1MvFrame` 透传当前帧的 `order_hint`/`order_hints`/`ref_frame_idx`
与参考帧列表（多数已在 `info` 里，`ref_frame_idx` 要加）。

## 五、状态

| 检查 | 结果 |
| --- | --- |
| `moon check` | 64 warnings / 0 errors |
| native / js / wasm-gc | 各 **1226/1226**（新增 3 个用例） |
| `git diff --check` | 仅两个 CRLF README 的既有假象 |
---

# 第三十四次推进补充（2026-09-22，`use_ref_frame_mvs` 门解除）

## 一、接线

`av1_mv_temporal.mbt`（新文件）：

- `av1_temporal_scan`（§7.10.2.5）：块内扫描 `stepW4/stepH4`（`bw4 >= 16` 用 4，
  否则 2），范围 `Min(bw4, 16)`/`Min(bh4, 16)`；随后 `allowExtension`
  （`2 <= bh4 < 16 && 2 <= bw4 < 16`）的三个 `tplSamplePos` 偏移，过
  `check_sb_border`（`(MiRow & 15) + deltaRow` 两轴都在 `[0, 16)`）。
- `av1_temporal_sample`（§7.10.2.6，仅单参考分支）：`mvRow/mvCol =
  (MiRow + delta) | 1`，过 `is_inside`（= 磁贴边界）；`delta == (0, 0)` 时先置
  `ZeroMvContext = 1`，取 `MotionFieldMvs[RefFrame[0]][y8][x8]`，invalid 即返回；
  过 `lower_mv_precision`；再按与 `GlobalMvs[0]` 的差是否 ≥ 16 决定把
  `ZeroMvContext` 置回 0；去重则 `WeightStack[idx] += 2`，否则入栈权重 2。

`check_sb_border` 用 16 而不是 `sb_units`：规范正文写死 64x64，go-av1
`decode/motionfield.go:214` 同样是 `miRow & 15`，所以本轮没有引入
超块尺寸泛化。

调用点：`av1_find_mv_stack` 在 near 加权之后、`av1_scan_point(-1,-1)` 之前，
`if (frame.use_ref_frame_mvs)` 才跑（规范 §7.10.2 第 5 步；go-av1
`decode/mvstack.go:152`）。扫描返回 `false` 时 `av1_find_mv_stack` 返回 `None`
（拒帧），覆盖两种情形：帧没带网格、`is_compound` 为真。compound 的那一半
（`RefFrame[1]`）没实现，而它需要 `reference_select`，帧级门仍挡着，所以不会
静默少算一半候选。

`av1_inter_frame_of` 在 `header.use_ref_frame_mvs` 为真时调
`av1_motion_field_estimation`（规范 §6.8 第 801 行：该调用发生在读未压缩头期间、
`tile_info()` 之前），网格经 `av1_mv_frame_of(header, temporal~)` 放进
`Av1MvFrame`。

## 二、外部像素核验

`tests/fixtures/av1-inter/inter_temporalmv_64x64.obu`：最小工具集加
`--enable-order-hint=1 --enable-ref-frame-mvs=1`（两个开关必须一起给，order
hint 是 `use_ref_frame_mvs` 被读取的前提）。输入是 `inter_temporalmv_64x64.input.yuv`，
重编码逐字节复现（sha256 一致，已在提交前验证）。dav1d 1.2.1 的两帧平面为真值，
生成测试断言帧 1 与帧 0 都是 `[0, 0, 0]`。

帧头实测：`enable_order_hint`、`use_ref_frame_mvs` 为真，`reference_select`、
`skip_mode_present` 为假，`order_hint = 1`，`gm_type` 全 identity，
序列级两个 compound 开关都为假。

## 三、有牙齿的证明（实测，非推测）

1. 整条扫描改成 `&& false`：inter 帧**解码被拒**（`av1_decode_frame_planes`
   返回 `None`），不是错画面。
2. 只删 `stack.zero_mv_context = 1` 这一行（其余不动）：同一帧仍然被拒——
   说明该帧上扫描的**唯一**可观测贡献就是 `ZeroMvContext`，因为 key 帧的
   motion field 全 intra，投影写不进任何格子。
3. 早先用 `c_refmvs2` 临时样本旁路同一扇门得到的旧结果是 `BAD 96 171 224`；
   接上扫描后同一份字节变成 `BAD 0 0 0`。

## 四、诚实记录：这条链还有一段没有外部像素覆盖

`motion_field_estimation`→"参考帧真有向后 MV"→投影落在网格上→`av1_temporal_sample`
推出候选这段路径，本仓库的样本**触及不到**：唯一的 temporal 参考源是 key 帧，
它的 motion field 全 intra。要覆盖它需要两个 inter 帧（第二个 inter 帧把第一个
当参考），而本机 libaom 在写 OBU 前就崩（`README.md` 的"Encoder constraint"一节
记录了这一点）。所以当前的证据结构是：

- 投影算术（`av1_mv_projection`/`av1_mv_div_mult`/`get_block_position`）：规范
  + 白盒单测；
- estimation 驱动（源资格、顺序、`refStamp`）：规范 + go-av1 对照 + 白盒单测；
- 时间扫描本身：规范 + go-av1 对照 + `av1_mv_temporal_wbtest.mbt` 10 例；
- 端到端（含 `ZeroMvContext` 这条真会被读到的量）：**有**外部像素核验
  （`inter_temporalmv_64x64`，`[0, 0, 0]`）。

`av1_mv_temporal_wbtest.mbt` 的 11 例覆盖：own cell 入栈（权重 2）、小向量把
`ZeroMvContext` 置回 0、未命中格子只留 context=1、重复向量权重 4、精度降低
（25→24、-3→-2）、宽块按 4 步长只走 4 列、64 像素块不做扩展、磁贴右边界丢弃、
`check_sb_border` 的四个边界、两种拒帧（无网格 / compound）。

## 五、剩余的门

| 门 | 现状 |
| --- | --- |
| `reference_select` + `skip_mode_present` | 仍挡着。`skip_mode_present` 是 `reference_select` 的下游（规范 §6.8.14 的 `skipModeAllowed`），两者必须一起解除，且都需要 compound 预测 |
| `enable_interintra_compound` / `enable_masked_compound`（序列级） | 仍挡着，同上 |
| 全局运动非 identity | 仍挡着（`gm_type != IDENTITY` 即拒帧） |
| segmentation | 未开始 |

## 六、状态

| 检查 | 结果 |
| --- | --- |
| `moon check` | 63 warnings / 0 errors |
| native / js / wasm-gc | 各 **1239/1239**（新增 13 个用例：2 个外部样本测试 + 11 个时间扫描白盒用例） |
| `git diff --check` | 仅两个 CRLF README 的既有假象 |
---

# 第三十五次推进补充（2026-09-22，帧上下文继承找到一个真 bug：保存时未重置适配计数器）

## 一、本轮结论

**`av1_frame_map_update` 保存帧上下文时漏了重置适配计数器**，已修复
（`av1_frame_map.mbt` 的 `av1_frame_cdfs_reset_counts`，见
`av1_frame_cdfs.mbt`）。规范对应 libaom 的 `av1_reset_cdf_symbol_counters`：
go-av1 在 `decode/decode.go:420` 保存前调用 `frameCdfs.resetCounts()`，注释写明
"so the loading frame restarts the rate schedule from zero"。

## 二、为什么这个 bug 之前看不到

CDF 行值 = 概率 + 最后一个计数器条目；适配速率
`3+(count>15)+(count>31)+min(⌊log2n⌋,2)` 依赖计数器。**计数器不对时：**

1. 保存那一帧自己的解码**完全不受影响**（它自己的计数器一直在正确累积）；
2. 概率值也**是对的**——所以历次"把继承行复算到逐位精确"的验证都通过，第十四次推进
   "行值假设被彻底排除"的结论成立，只是排除的是另一件事；
3. 只有**加载那一帧**从第一次适配起速率就不同，累积偏差。

这解释了十三十七次推进以来的矛盾现象：行值链手算全对、MSAC 对拍 1600 万符号零分歧、
关键帧与 inter 帧的 luma 符号序列 54/55 相同——而像素仍然错。**问题不在"哪一行错了"，
而在"行变快的速度不对"。**

## 三、实测（守卫放开 + 继承开启，golden = dav1d 1.2.1 对开补丁码流）

| 配置 | Y/U/V 错误数 |
| --- | --- |
| 修复前（继承 + 计数器不重置） | `[4029, 464, 708]` |
| **修复后** | **`[2138, 210, 493]`** |

同一配方下其余样本也都改善；`pipe6.py 1 4 1`（周期 4 色度、相位 1）修复后为
`[0, 0, 0]`——即该样本已被本修复闭合。

仍失败样本（仓库的 `ramp`，即 `inter_cdf_inherit_64x64`）的错误分布已从像素级推进到
**块级**：

- inter 帧 6 个带残差的块：`(0,0)32x32`、`(0,8)16x32`、`(0,12)16x16` 全部正确；
  `(4,12)16x16` 的 16 行里只有上 12 行错；`(8,0)32x32`、`(8,8)32x8` 全错。
- U 平面从 luma 第 16 行起错、V 平面从 luma 第 32 行起错，与 luma 的块边界对齐。

## 四、本轮新取得的定位证据（下一步的直接入口）

1. **符号级 trace 已可稳定获取**：在 `Av1SymbolDecoder::symbol` 里无条件 `println`
   并按 `self.data.length()` 过滤，即可分别拿到关键帧（1037 符号）与 inter 帧
   （3899 符号）的完整 `(n, c0, sym, r, v, mb)` 序列。白盒全局传值通道在本机不可用
   （第十三次推进已记录），但库内主动输出完全不受影响。
2. **trace 对比（继承开 vs 继承关，同一份 tile 字节）**：第一条符号（partition，n=10）
   两边同为 `sym=3` 但 CDF 行值不同（`c0=19890` vs `19508`）——继承本身生效且行值来自
   关键帧；第 3 条（块 1 的 `skip`，n=2）起出现**读值分歧**（继承读 0=有残差、
   不继承读 1=跳过）。由于块 1/2/3 像素对 dav1d 全对，说明 **dav1d 也读到 skip=0**，
   即 `skip`/partition 这两张表的继承值是对的。
3. **CDF 分组反证实验**：把 luma 系数表 8 个分组（`extra`/`base_eob`/`base`/`br`/
   `sign`/`eob_small`/`eob`/`eob512`）中**任意一个**恢复成"默认值"，结果都**恰好等于
   不继承的 `[3992, 842, 928]`**；全部分组都恢复也是同一个值。说明：
   - 非系数表（partition/skip/…）的继承值对像素**无影响**（回到默认就得到不继承的解）；
   - luma 系数表的继承值是唯一影响像素的因素，且 8 个分组中任意一个被换掉都会让
     **第一个 luma 叶的早期符号**翻转，进而整条解码跑到"不继承"那条支路。
   - capture/restore 的形状完全对称（39 张 intra 表递归计数核对无误），插桩确认
     **没有任何一张表因形状不匹配被静默跳过**——这条"静默跳过"的嫌疑已排除。
4. 规范原文已核对：`av1spec06.md:790-810` 的 `load_cdfs`/`init_coeff_cdfs` 顺序、
   `av1spec06.md:3425-3470` 的系数双循环（先逆序读幅度、再正序读符号）均与实现一致；
   go-av1 `msac/msac.go` 的 `updateCDF` 与本库逐行相同（含计数器封顶 32）。

**⇒ 下一步的具体入口**：`(4,12)16x16` 那一块只有上 12 行错、且整幅图只有 luma 系数表
在起作用 ⇒ 根因应在**关键帧某次系数读**上——某个不改变像素但改变符号数的读（头号嫌疑
仍是关键帧系数段的 `all_zero`/`eob_pt`/`dc_sign` 类读取；规范 `av1spec06.md:3425` 起
的系数双循环里，`Quant[pos] != 0` 才读符号，全零系数的块读法有隐含自由度）。
用第 1 条拿到关键帧 1037 符号的 trace 后，按"位置 k 处若改读 X，inter 帧 (4,12) 的
上 12 行是否归零"逐个候选强制（编译期常量，勿用白盒全局）即可收敛。

## 五、诚实的边界

- 生产开关 `av1_cdf_load_enabled` **仍为 false**：修复后 `inter_cdf_inherit_64x64`
  仍差 `[2138, 210, 493]`，`av1_inter_reference_wbtest.mbt` 的围栏
  `[3992, 842, 928]` 原样保留（未改 OBU、未改真值）。
- `symbol_max_bits >= -14` 守卫（规范 §8.2 位流一致性要求，dav1d 不执行）本轮**未动**：
  它仍会拒绝该样本的继承解码。放开它需先替换为不依赖越读的安全不变量，并同步
  `av1_transform_tree` / `av1_palette_colors_wbtest` / `av1_cdef_alpha_gate_wbtest`
  三个依赖它拒绝截断输入的既有测试（第十一次推进已查明）。
- 本轮全部插桩（符号 trace、块结构打印、ZZDIAG、守卫放宽、luma 系数表反证钩子）
  **已全部回退**，`git show HEAD:` 与工作区在守卫处逐字节一致。

## 六、测试

`av1_frame_cdfs_wbtest.mbt`（新文件，3 例）：

1. **保存的帧上下文所有计数器为 0**：`inter_minimal_64x64` 关键帧刷新全部槽位，
   槽 0 的上下文与 `map.saved_cdfs` 两条路由都要为 0。
2. **重置不动概率**：同一快照的 `skip` 表必须与默认值有差异（证明该表真的被关键帧
   适配过，因而重置打在非平凡行上），且每行最后一个条目为 0。
3. **`disable_frame_end_update_cdf` 的帧保留前一份上下文**：用
   `inter_primary_ref_64x64` 钉住这条分支。

有牙齿：删掉 `av1_frame_cdfs_reset_counts(snapshot)` 一行，例 1、2 立即失败（实测
`1 != 0`），恢复后全绿。

## 七、状态

| 检查 | 结果 |
| --- | --- |
| `moon check` | 64 warnings / 0 errors |
| native / js / wasm-gc | 各 **1242/1242**（新增 3 个用例） |
| 守卫与 HEAD 逐字节一致 | 是（`git show HEAD:` 对比计数核对） |
| `git diff --check` | 仅两个 CRLF README 的既有假象 |
---

# 第三十六次推进补充（2026-09-22，用"尾部位预算"证明关键帧符号流合规，分歧收敛到 inter 帧单个块内）

本轮没有新代码修复，全部是**定位性质的实测证据**，把剩余分歧从"inter 帧里某个符号"
收敛到"inter 帧块 (4,12) 的系数读内部"。

## 一、关键帧的符号流是"位流合规"的（新工具：尾部位预算）

在 `symbol()` 里无条件打印 `(n, c0, sym, r, v, mb, len)` 并按 payload 长度过滤，即可分别
拿到两帧的完整符号流。**规范 §8.2 要求 `SymbolMaxBits >= -14`**，libaom 写出的流满足
它，因此"关键帧解码结束时的 mb"就是关键帧符号数是否正确的**外部判据**：

| 帧 | payload | 符号数 | 结束 mb |
| --- | --- | --- | --- |
| 关键帧 | 45 字节 | 1037 | **-7**（合规 ⇒ 符号数正确） |
| inter 帧（继承开） | 11 字节 | 3899 | **-4475**（深度越读 ⇒ 继承解释本身就是发散解） |

⇒ **分歧不可能来自关键帧多读/少读符号**（若多读，尾部位预算会更负；实测 -7 与
libaom 写出量一致）。结合第三十五次的计数器修复，可以认为**关键帧侧（符号流 + 保存的
帧上下文）已经正确**，剩下的分歧全部在 inter 帧自己的读上。

## 二、inter 帧按块结构定位（新工具：块级 + 叶级插桩）

inter 帧 6 个块全部 `skip=0`，每块恰好一个带残差的 luma 叶（chroma 叶另算）：

| 块（MI 行列，尺寸） | interp | 叶 eob / 面积 | 像素对 dav1d |
| --- | --- | --- | --- |
| (0,0) 32x32 | (0,0) | 41 / 1024 | 全部正确 |
| (0,8) 16x32 | (0,0) | 37 / 512 | 全部正确 |
| (0,12) 16x16 | **(1,1)** | 5 / 256 | 全部正确 |
| (4,12) 16x16 | (0,0) | 43 / 256 | **16 行里上 12 行错** |
| (8,0) 32x32 | (0,0) | **913 / 1024** | 全错 |
| (8,8) 32x8 | (0,0) | **179 / 256**、29 | 全错 |

- 块 1-3 的 eob（41/37/5）都是合理值；块 5、6 的 eob（913/1024、179/256）是**发散特征**
  （接近满平面的残差，合法编码器不会产生）。
- ⇒ **失同步点落在块 (4,12)**：它的 eob=43 仍合理，但已与 dav1d 不一致；块 5、6 是
  失同步后的垃圾读。
- 块 (4,12) 只错上 12 行、下 4 行对 ⇒ 不是整体预测错（预测错会整块错），而是**残差里
  一部分系数错**，且 DC/低频仍在正确分支上（否则整块错）。

## 三、可"不改变像素"的读（下一轮的强制实验候选表）

inter 帧里**存在两类读，取不同值不改变任何像素**：

1. **`ref_frame`（single_ref）**：关键帧刷新了全部 8 个槽位且是同一幅图，所以
   LAST(1)…ALTREF(7) 任何名字都解析到同一个 reference buffer。本帧实测读到的名字是
   7、7、4、7、7、7——名字本身不进像素，但 `single_ref` 表的适配会变。
2. **`interp_filter`**：六个块的 MV 全是整数（-30,-4 / -26,-2 / 6,2），整数相位下三种
   8-tap 滤波器都精确等于恒等采样，所以滤器选择不进像素，但 `interp_filter` 表的适配
   会变。块 (0,12) 读到 (1,1)，是唯一非 (0,0) 的块。

排除项：`interp_filter` 不能单独解释像素错误（它只改自己的表，下游 interp 读同样
不产生像素差），所以它最多是"同谋"而不是主犯；主犯应在**块 (4,12) 自己的读**里：
`mode`/`mv`（可见）、`all_zero`/`eob_pt`/`eob_extra`（可见）、以及叶内 43 个
`coeff_base`/`br`/符号读。

## 四、下一轮的具体做法

已在 `symbol()` 里做过"编译期常量 + 指纹"强制（指纹用 `(cdf.length, cdf[0],
symbol_range, symbol_value)`，白盒全局在本机不可用，见第三十三次补充）。建议顺序：

1. 强制**块 (0,12) 的 interp 读**（符号 #186：`n=3, c0=26744, r=36384, v=2927`，
   现读 1）为 0，看错误数是否变化——用于确认/排除 interp 同谋。
2. 强制**块 1-3 的三个 `ref_frame` 读**为其它名字，逐组测量。
3. 若两者都无效，则二分**块 (4,12) 叶内的 43 个 `coeff_base` 读**：从第 k 个起全强制为
   0/其它值，找第一个使错误数下降的 k；该 k 使用的 `base[txctx=2][ctx]` 行即肇事行。
   （块 (4,12) 是 16x16 luma ⇒ `txctx=2`，与关键帧的 16x16 luma 叶共用这些行，
   这正是在关键帧"对齐"的假设下仍可能出问题的位置。）

## 五、插桩与守卫已全部回退

`av1_msac.mbt`、`av1_coeff_decode.mbt`、`av1_inter_mode.mbt`、`av1_inter_tile.mbt`
从本轮开始前的备份恢复；六个文件的 `symbol_max_bits` 守卫与 HEAD 逐字节一致
（`git show HEAD:` 对比计数核对）；`av1_cdf_load_enabled` 回到 `false`；工作区无 ZZ 残留。

## 六、状态

| 检查 | 结果 |
| --- | --- |
| `moon check` | 64 warnings / 0 errors |
| native / js / wasm-gc | 各 **1242/1242** |
| 守卫与 HEAD 逐字节一致 | 是 |
| 围栏 `[3992, 842, 928]` / OBU / 真值 | 未改动 |
---

# 第三十七次推进补充（2026-09-22，强制实验工具修好；tx_type 假设被排除；分歧锁定在块 1-3 的
# 某个"不改变像素"的读）

## 一、本轮修正了两个方法论错误（都曾导致错误结论）

1. **指纹必须用"适配前"的 `cdf[0]`**：`symbol()` 里的 trace 打印在 CDF 适配**之后**，
   所以打印出的 `cdf[0]` 是本次读之后的行值；下一次读进来的 `cdf[0]` 是另一个值。
   用打印值做指纹，命中数为 0，前几轮"强制无效"的结论**全部作废**。
   正确指纹 = `(cdf.length, cdf[0], symbol_range, symbol_value)` 的**进入时**取值
   （即上一条 trace 的 `r/v` + 本次读的 `len/行宽`，其中 `cdf[0]` 需单独取适配前值）。
2. **"提前 break"只能选到比自然符号更靠前**的值：在符号选择循环里 `if symbol == k break`
   对自然符号之后的 k 永不触发。改为**按目标符号重算区间边界**（把 `cur/prev` 重新走到
   第 k 个符号），才能强制任意值。修好后对照实验：强制块 (4,12) 的 `eob_pt`（自然 6）
   到 3 或 8，错误数从 `[2138,210,493]` 变 `[2062,477,507]` / `[1596,257,512]`——
   工具确认有牙齿。

## 二、tx_type 假设被排除（12 个值全扫）

`inter_tx_type_set2`（16x16 luma 用，13 项 = 12 符号 + 计数器）被块 (0,12) 与块 (4,12)
共用（后者读到的是前者适配过的行）。把块 (4,12) 的 tx_type 读（自然值 2 = H_DCT）
强制到 0..11 全部 12 个值：

| 强制值 | Y/U/V 错误 |
| --- | --- |
| 2（原值，对照） | 2138 210 493 |
| 0（IDTX） | **1678 98 512** |
| 1（V_DCT） | 1770 112 512 |
| 3（DCT_DCT） | 2265 431 559 |
| 4 / 5 / 6 / 7 / 8 / 9 / 10 / 11 | 1709…2265，无一归零 |

⇒ **块 (4,12) 的 tx_type 不是（唯一）分歧点**；没有任何单个强制值能归零。

## 三、同时核对了三处"可能是根因"的语法，全部与参考一致

- **参考帧树**：`av1spec06.md:2746-2768` 的 `single_ref_p1..p6` 树与
  `av1_read_ref_frames` 逐分支一致（含 p6=ALTREF2、p5=GOLDEN、p4=LAST2 的符号极性）。
- **tx set 选择**：`av1_inter_tx_set` 与 go-av1 `getTxSet`（`sqrUp>3→DCTONLY`、
  `reduced||sqrUp==3→set3`、`sqr==2→set2`、否则 set1）逐条一致；
  `TxSizeSqr` = `log2(min(w,h))-2` 与我们的 `sqr` 一致（核对 go-av1 `tables.go` 两张表）。
- **tx_type 集合映射**：`av1_inter_tx_type_of(2, i)` 与 go-av1 `txTypeInterInvSet2`
  12 项逐项一致；行数 13 与 go-av1 的 `interTxType2 [13]` 一致。

## 四、当前结论与下一轮入口

分歧在**块 (4,12) 之前**，且是一个**不改变像素**的读（块 1-3 像素全对、
关键帧尾部位预算 -7 合规 ⇒ 符号数正确）。剩余候选（都在块 1-3，且都继承自
关键帧的 intra 表或起始于默认值的 inter 表）：

1. `mode`（inter_mode）：两个候选 MV 相同时 NEARESTMV/NEARMV 不可分辨；
2. `drl_idx`：同上，候选 0/1 的 MV 相同时不可分辨；
3. `ref_frame` 的 p1/p2/p3 名读（全部名字都指向槽 0 的同一幅关键帧）；
4. `interp_filter`（整数 MV 下三种滤波器恒等）。

**下一轮做法（已验证可行、比指纹更稳）**：把强制改成**按读序号强制**——在
`symbol()` 里放一个**库内自增计数器**（库内全局由库自己写，不受"白盒全局不可见"影响），
配合一次带 `ZZREAD REF0/MODE/DRL/INTERP` + `ZZLTX/ZZEOB` 标签的采集，就能把
"第 k 个符号"直接映射到具体读；然后对块 1-3 的候选读逐个扫描强制值。
本轮已备好采集配方（见工作区已清理，需重新插桩）。

## 五、插桩/守卫/开关已全部回退

`av1_msac.mbt`、`av1_coeff_decode.mbt`、`av1_intra_tile.mbt` 已恢复到本轮开始前的
备份（ZZ 标记计数为 0）；六个文件的 `symbol_max_bits` 守卫与 HEAD 逐字节一致；
`av1_cdf_load_enabled` = false；围栏 `[3992,842,928]`、OBU 与真值未动；工作区无 zz 残留。

## 六、状态

| 检查 | 结果 |
| --- | --- |
| `moon check` | 64 warnings / 0 errors |
| native / js / wasm-gc | 各 **1242/1242** |
| 插桩/守卫/开关 | 全部回退并经 `git show HEAD:` 计数核对 |
---

# 第三十八次推进补充（2026-09-22，强制工具换成"按读序号"；40 个单符号假设全部排除）

## 一、本轮建成了可靠的强制工具（比指纹稳，建议以后都用这个）

在 `Av1SymbolDecoder` 里加一个 `mut read_index` 字段（`av1_msac_new` 每次构造新解码器时
归零 ⇒ 天然按"每个 tile 一份"编号），`symbol()` 开头自增并打印
`(idx, len, cdf[0], r, v)`（**适配前**取值），末尾打印 `sym`；强制改为
`if this_read == FORCE_INDEX && self.data.length() == FORCE_LEN` 时**按目标符号重算
区间边界**（可强制任意值，不限更早）。三个编译期常量 `FORCE_INDEX / FORCE_K /
FORCE_LEN`，改一次编译约 40 秒。

配套一次带标签的采集（`ZZREAD REF0 / MODE / DRL / INTERP / TX / EOB` + 每条读的
指纹与符号），得到 inter 帧 3899 个读的**完整"序号 → 读什么 → 读到什么"映射**，
关键结构：

| 块 | ref 读 | mode 读 | interp 读 | all_zero 读 | tx_type 读 | eob_pt 读 |
| --- | --- | --- | --- | --- | --- | --- |
| (0,0) 32x32 | 5,6 | 7 | 17 | 18 | 20 | 21 |
| (0,8) 16x32 | 104,105 | 107 | 110 | 111 | 113 | 114 |
| (0,12) 16x16 | 181,182,183 | 184 | 186 | 187 | 188 | 189 |
| (4,12) 16x16 | 204,205 | 207 | 210 | 211 | 212 | 213 |
| (8,0) 32x32 | 296,297 | 298 | 307 | 308 | 310 | 311 |
| (8,8) 32x8 | 3523,3524 | 3525 | 3530 | 3531 | 3532 | 3533 |

（读 1、2 = partition，3 = skip，4 = is_inter；每块 luma 叶之后是 2 个 chroma 叶。）

## 二、排除的假设（40 个强制实验，全部实测）

**块 1-3 的"不改变像素"的读**（继承表/默认 inter 表都可能）：

| 强制实验 | Y/U/V 结果 |
| --- | --- |
| interp 读 17（0→1/2） | 4096/804/1008、4091/912/1022 |
| interp 读 110（0→1/2） | 4033/818/1024、4043/808/997 |
| interp 读 186（1→0/2） | 2154/234/517、2154/918/1006 |
| ref p1/p2/p3（块 0,0、0,8、0,12 共 10 组） | 全部偏离基线，无一归零 |
| ref p3 (0,12) 1→0 | **2138/210/493 = 基线不变**（确认该读像素不可见，工具有效） |

**块 (4,12) 自身**：

| 强制实验 | Y/U/V 结果 |
| --- | --- |
| tx_type 读 212 → 0..11 全扫 | 1678…2265，无一归零（最好 IDTX 0→1678/98/512） |
| eob_pt 读 213 → 0,1,2,3,4 | 2076/1916/2096/1950/2085，无一归零 |
| base_eob 读 219 → 1,2 | 1929/2067 |
| all_zero 读 211 → 1 | 1837/879/1020 |

**关键帧 6 个系数叶的 `all_zero` 读**（payload len=45 定向）：

| 强制实验 | Y/U/V 结果 |
| --- | --- |
| 读 7 / 82（luma 0→1） | 4096/804/1024、4001/835/1006 |
| 读 153 / 154（luma 1→0） | 3999/804/1024、4013/822/1024 |
| 读 155（U 叶 0→1） | **2138/U 804/V 1024**（luma 不变，符合预期） |
| 读 563（V 叶 0→1） | **2138/210/1024**（luma 不变，符合预期） |

⇒ **没有任何单个符号选择能解释分歧**。分歧是**状态级**的：进入块 (4,12) 时 MSAC 算术
状态或某张 CDF 行值已经与 dav1d 不同，而块 1-3 的像素仍然全对。

## 三、对下一轮的判断（重要，别重复本轮弯路）

块 1-3 的**每一个**候选读都被单独强制过且无效，因此下一步不应继续"逐个读试错"，
而应直接**比对状态**：

1. **比对 MSAC 状态**：在关键帧结束处打印 `(r, v, mb, bit_pos)`；若能拿到 dav1d 的
   同点状态（dav1d 源码在本机，可用 `msac_get_state` 思路插桩；本轮未做），
   第一个不同的符号立刻定位。
2. **比对 CDF 快照**：把我们的关键帧快照（68 张表、每行的概率与计数器）与
   "用 Python 按 dav1d 规则重放关键帧 1037 个符号"得到的快照逐行比对——
   第十三/十四次推进做过 4 行的手算比对且一致，本轮建议**全量自动化**（重放模型
   已有雏形 `/tmp/mbrepro/replay*.py`）。任何一行不同即是根因。
3. **注意 mb=-7 只排除"多读 ≳3 个符号"**，不排除"少读 1-2 个符号"或
   "符号数相同但某个 CDF 行值不同"——本轮的所有证据都与 (2) 相容。

## 四、插桩/守卫/开关已全部回退

`av1_msac.mbt`（含 read_index 字段与 FORCE_* 常量）、`av1_inter_mode.mbt`、
`av1_intra_tile.mbt`、`av1_coeff_decode.mbt` 均从本轮开始前的备份恢复（ZZ/FORCE
标记计数为 0）；六个文件的 `symbol_max_bits` 守卫与 HEAD 逐字节一致；
`av1_cdf_load_enabled` = false；围栏 `[3992,842,928]`、OBU 与真值未动；
工作区无 zz 残留。

## 五、状态

| 检查 | 结果 |
| --- | --- |
| `moon check` | 64 warnings / 0 errors |
| native / js / wasm-gc | 各 **1242/1242** |
| 工具可用性 | 按读序号强制已验证有效（对照组必然改变结果） |
---

# 第三十九次推进补充（2026-09-22，静态输入全部核验：继承解码读到的每张表都与 go-av1 逐位一致）

## 一、先把"inter 帧到底读哪些继承表"钉死（一张一张关掉测）

在 `av1_intra_cdfs_restore` 里逐张表跳过恢复（等价于"该表用 inter 帧自己的默认值"），
实测结果：

| 关掉的表 | Y/U/V |
| --- | --- |
| `skip_cdfs` | 3898 / 932 / 920 |
| `tables.txb_skip` | 4027 / 562 / 965 |
| `y_coeff.eob` | 4044 / 370 / 662 |
| 其余 36 张（y_mode / uv_cfl / uv_no_cfl / angle_delta / cfl.\* / palette.\* / filter_intra / filter_intra_mode / tx_set1 / tx_set2 / vartx / tx_depth.\* / uv_coeff.\* 的多数） | **2138 / 210 / 493（与基线完全一致 ⇒ 该表根本没被 inter 帧读到）** |

⇒ **inter 帧真正读到的"从关键帧继承"的表只有 3 组**：`skip_cdfs`、`tables.txb_skip`、
以及系数表（`y_coeff.*` / `uv_coeff.*`）。其余 36 张是 intra 专用表，而 inter 帧
6 个块全是 inter 块，从不读它们。这把"快照哪一行错了"的搜索空间从 39 张表压到 ~12 张。

（注：`uv_coeff.*` 的多数行关掉也无变化，是因为 inter 帧的 chroma 叶是 8x8/16x4，
只读 `uv_coeff` 的 txctx=0/1/2 少数行。）

## 二、再把"这些表的默认值"与 go-av1 逐位对拍（全部 0 差异）

用 Python 直接 eval 双方的数组字面量后全量比对：

| 表 | 元素数 | 差异 |
| --- | --- | --- |
| `defaultCoeffBaseCdf` | 8400 | **0** |
| `defaultCoeffBrCdf` | 4200 | **0** |
| `defaultCoeffBaseEobCdf` | 640 | **0** |
| `defaultEobExtraCdf` | 1080 | **0** |
| `defaultEobPt16/32/64/128/256/512Cdf` | 96+112+128+144+160+88 = 728 | **0** |
| `defaultEobPt1024Cdf` | 96 | **0** |
| `defaultDcSignCdf` | 72 | **0** |
| `av1_txb_skip_cdf` | 780 | **0** |
| `skip_cdfs`（3 行） | 9 | **0** |

同时核对了 qctx 取法：`av1_dc_q_context(qidx)` 与 go-av1 `coeffQIdx(baseQIdx)`
逐分支一致（≤20→0，≤60→1，≤120→2，else 3），且我们的 `av1_tx_ent_tables` 与
go-av1 的 `DefaultTxbSkipCdf[coeffQIdx(baseQIdx)]` 一样按 qctx 取片。
本 fixture 关键帧 q=49 ⇒ qctx=1，inter 帧 q=128 ⇒ qctx=3（**系数默认值随 qctx 变**，
但我们加载的是关键帧快照里的行，两 decoder 一致）。

## 三、结论：静态输入已全部核验，剩下的只有"关键帧读到的符号序列"

本轮把可静态核验的部分做完了：

- 默认表值：与 go-av1 逐位一致（上表）；
- 上下文计算：`av1_txb_skip_ctx_luma/chroma` 与 av1spec09 §927-985 的 all_zero ctx
  逐分支一致（含 chroma 的 `ctx += 7` 与非整块 `+3`）；`av1_dc_sign_ctx_from`、
  `pt_ctx = (tx_class == TX_CLASS_2D) ? 0 : 1` 亦一致；
- 参考帧树、tx set 选择、tx_type 集合映射：上一轮已与规范/go-av1 逐项一致；
- 适配速率与计数器重置：已实现（计数器重置使错误数从 [4029,464,708] 降到
  [2138,210,493]），且 go-av1 的 `updateCDF` 与本库逐行相同；
- 单符号假设：上一轮 40 个强制实验全部排除。

⇒ **唯一还没被外部核验的，是关键帧那 1037 个符号"我们读到的与 dav1d 读到的是否
逐个相同"**。注意关键帧尾部位预算 -7 只排除"多读 ≳3 个符号"，不排除"少读 1-2 个"
或"符号数相同但适配了不同的行"。

## 四、下一步（唯一剩下且必然收敛的路）

给 dav1d 1.2.1 源码打桩，导出关键帧结束时的 **MSAC 状态与全部 CDF 行值**，与我们
快照逐行 diff。要点：

1. dav1d 源码在本机（`decodeb.c` / `recon_tmpl.c` / `msac.c` / `cdf.h` / `tables.c`），
   `msac_get_state()` 存在；在 `decode_frame` 结束处 dump `ctx->cdf` 的全部表即可。
2. 我们侧同样在关键帧结束后 dump 快照（`av1_frame_map_update` 里已经能拿到
   `snapshot`，加一次性打印即可，不需要改逻辑）。
3. 第一处不同的行即根因；若所有行都相同，则差异在 MSAC 算术状态（位流末端补位），
   此时对比 `(r, v, mb, bit_pos)`。
4. 备选（不需要 dav1d 插桩）：用 Python 重放关键帧 1037 个符号。行身份用
   "当前行值集合匹配"确定（第十三/十四次推进对 inter 帧 323 个不同行做到零歧义），
   重放结束与我们的快照逐行比对。工具雏形在 `/tmp/mbrepro/replay*.py`。

## 五、插桩/守卫/开关已全部回退，工作区干净

本轮所有插桩（逐表关恢复）只改了 `av1_frame_cdfs.mbt` 的 restore 函数，已从备份恢复；
`av1_cdf_load_enabled` = false；六个文件守卫与 HEAD 逐字节一致；围栏
`[3992, 842, 928]`、OBU 与真值未动；无 zz 残留。

## 六、状态

| 检查 | 结果 |
| --- | --- |
| `moon check` | 64 warnings / 0 errors |
| native / js / wasm-gc | 各 **1242/1242**（本轮无代码改动，仅诊断） |
| 静态核验 | 默认表值 / qctx / 上下文计算全部与 go-av1 或规范一致 |
---

# 第四十次推进补充（2026-09-22，块 (4,12) 全部单符号扫描完毕：分歧是状态级，已无静态可查项）

## 一、本轮扫描（块 (4,12) 尚未测过的读）

用第三十八次的"按读序号强制"工具（`read_index` + `FORCE_INDEX/FORCE_K/FORCE_LEN`，
全部编译期常量，长度定向到 inter 帧 payload=11），扫了块 (4,12) 的 mode 读与前 11 个
`coeff_base` 读：

| 强制实验 | Y/U/V |
| --- | --- |
| mode 读 207（1→0） | 2282 / 328 / 512 |
| base 读 220（0→1/2/3） | 2063 / 2036 / 拒绝 |
| base 读 221（0→1/2/3） | 1977 / 2080 / 拒绝 |
| base 读 222（1→0/2/3） | 1876 / 1929 / 2098 |
| base 读 223（1→0/2/3） | 2034 / 2027 / 1917 |
| base 读 224（0→1/2/3） | 1900 / 2084 / 1850 |
| base 读 225（2→0/1/3） | 2101 / 2070 / 拒绝 |
| base 读 226（1→0/2） | 2081 / 2062 |

（基线 2138 / 210 / 493；"拒绝"= 强制后 eob 越界使叶解码返回 None。）

## 二、结论：单符号假设空间已穷尽

至此，**从 inter 帧第 1 个符号到块 (4,12) 的第 226 个符号**，所有可构造的"单个读不同"
假设都被强制实验排除：

- 第 38 次：块 1-3 的 3 个 interp 读 + 10 个 ref 名读、块 (4,12) 的 12 个 tx_type 值、
  8 个 eob_pt 值、base_eob、all_zero、关键帧 6 个系数叶的 all_zero 读；
- 第 40 次（本轮）：块 (4,12) 的 mode 读 + 前 11 个 coeff_base 读。

**没有任何单个强制值能把错误数打到 0**，且各次结果都在 1850-2282 区间内无规律分布。
⇒ 分歧是**状态级**的：进入块 (4,12) 之前，MSAC 算术状态或某张被继承表的行值已经与
dav1d 不同，而此前的像素全部正确。

## 三、剩余可查项与必须承认的边界

**已全部核验、可以排除的**（第三十九次 + 本轮）：
默认表值与 go-av1 逐位一致（`CoeffBaseCdf` 8400、`CoeffBrCdf` 4200、
`CoeffBaseEobCdf` 640、`EobExtraCdf` 1080、七个 `EobPt*` 728、`EobPt1024Cdf` 96、
`DcSignCdf` 72、`txb_skip` 780、`skip` 9 —— 共 14,296+ 元素 0 差异）；qctx 取法一致；
`skip/txb_skip/eob_pt/base` 的上下文计算与 av1spec09 §927-985 逐分支一致；
inter 帧实际读到的继承表只有 `skip_cdfs`/`txb_skip`/系数表三组（其余 36 张不被读）；
计数器重置已实现并使错误数从 [4029,464,708] 降到 [2138,210,493]。

**仍无法本地核验的唯一一项**：关键帧那 1037 个符号里，我们读到的与 dav1d 读到的是否
逐个相同。注意关键帧尾部位预算 -7 只排除"多读 ≳3 个符号"，**不排除**：
(a) 少读 1-2 个符号；(b) 符号数相同但某个读落在**不同的 CDF 行**（上下文差 1）——
后者像素完全不变、符号数不变，却会让快照那一行不同，正是与全部现有证据相容的形态。

**要定位 (a)/(b)，只有两条路，都需要外部符号级真值**：
1. 给 dav1d 1.2.1 源码打桩，在关键帧结束后 dump 全部 CDF 行与 MSAC 状态，与我们的
   快照逐行 diff（dav1d 源码在本机，`msac_get_state()` 可用；本机未找到解压好的源码目录，
   需要先取得/定位源码再编译，属独立工作项）。
2. 用 Python 按 dav1d 规则重放关键帧符号流，行身份用"当前行值集合匹配"确定
   （第十三/十四次推进在 inter 帧 323 个不同行上做到零歧义），重放结束与我们的快照逐行
   比对。缺点：只能验证"我们的表 + 我们的读 ⇒ 我们的快照"的自洽性，
   **无法替代 dav1d 真值**；只有配合 (1) 才有决断力。

## 四、给下一轮的明确建议

不要再做单符号扫描（空间已穷尽）。按可行性排序：
1. **先做 (2) 的自洽性重放**：它虽然不能单独定位 bug，但能把"快照哪一行与
   '规范默认值 + 符号序列'不符"找出来——若某一行不符，说明我们的读或适配有内部矛盾，
   这本身就是 bug 线索；若全部自洽，则把问题彻底推给 (1)。
2. **(1) 需要 dav1d 源码与编译环境**，属独立工作项，建议单开一轮并在 HANDOFF 记录
   编译命令与 dump 格式，便于后续接手者复现。
3. 同时把 `symbol_max_bits >= -14` 守卫的替换方案写成决策记录（它来自规范 §8.2 位流
   一致性要求、dav1d 不执行；放开会影响 3 个依赖它拒绝截断输入的既有测试），
   作为阶段 B 收尾前必须由维护者拍板的一项。

## 五、插桩/守卫/开关已全部回退

`av1_msac.mbt`（含 `read_index` 与 `FORCE_*` 常量）已从备份恢复；`av1_frame_cdfs.mbt`
的 loader 回到 false；六个文件守卫与 HEAD 逐字节一致；围栏 `[3992, 842, 928]`、OBU 与
真值未动；无 zz 残留。

## 六、状态

| 检查 | 结果 |
| --- | --- |
| `moon check` | 64 warnings / 0 errors |
| native / js / wasm-gc | 各 **1242/1242** |
| 本轮变更 | 仅诊断，无代码改动 |
---

# 第四十一次推进补充（2026-09-22，重大进展：继承路径对 9 个独立样本全部 [0,0,0]；
# 用参数化流复现仓库样本失败）

## 一、计数器重置的正确性得到强验证（本轮最重要结论）

把第三十五次的计数器重置修复 + 继承开启 + 越读守卫放开，对 9 个参数化源
（`/tmp/mbrepro/pipe6.py <lamp> <cper> <cphase>`，编码后把 inter 帧
`primary_ref_frame` 从 7 改成 0，golden 取 dav1d 1.2.1 对开补丁码流的解码）全部重跑：

| 源（lamp/cper/cphase） | 关键帧 Y/U/V | **inter 帧 Y/U/V** |
| --- | --- | --- |
| 0 0 0（全平 + 平滑色度） | 0,0,0 | **0,0,0** |
| 1 0 0（全平 luma） | 0,0,0 | **0,0,0** |
| 0 1 0 / 0 2 0（周期 1/2 色度） | 0,0,0 | **0,0,0** |
| 0 4 1（周期 4，相位 1） | 0,0,0 | **0,0,0** |
| 1 2 0 / 1 4 1 | 0,0,0 | **0,0,0** |
| 0 7 3（周期 7，相位 3） | 0,0,0 | **0,0,0** |
| **1 3 1（周期 3，相位 1）** | 0,0,0 | **0,0,0** |

⇒ **9/9 全部精确**。其中 **周期 3 色度在计数器重置前是失败的**（第十一次推进记录
`[0,504,0]`、第十二次推进记录 `[0,488,0]`），现在也归零——**这直接证明第三十五次
的计数器重置修复是正确的，而不是换了一种错法**。帧熵上下文继承的
"快照 / 装载 / 适配"三段现在有 9 个独立外部像素真值背书。

## 二、仓库样本的失败已可在参数化流里逐字节复现（新工具 pipe7.py）

仓库的 `inter_cdf_inherit_64x64` 派生自 `inter_minimal_64x64`，其源（generator 的
`ramp`）是 **luma 周期 32 锯齿 + cb 纵向周期 5 + cr 横向周期 7**，而 pipe6 的
`lamp` 参数只会生成"全平或平滑 luma"，从未覆盖它。

新增 `/tmp/mbrepro/pipe7.py <lper> <cbper> <crper> [shift]`（同 pipe6 管线，
源按仓库 ramp 的公式逐位复刻）。实测：

| lper / cbper / crper | inter Y/U/V |
| --- | --- |
| **32 / 5 / 7（= 仓库 ramp）** | **2138 / 210 / 493**（与仓库样本完全一致） |
| 32 / 0 / 0 | 0,0,0 |
| 16 / 5 / 7、64 / 5 / 7、8 / 5 / 7、4 / 5 / 7、2 / 5 / 7、1 / 5 / 7 | 全部 0,0,0 |
| 32 / 5 / 0、32 / 0 / 7、32 / 5 / 1、32 / 5 / 3 | 0,0,0 |
| 32 / 1 / 7、32 / 3 / 7、32 / 7 / 7 | 2137/168/511、2138/173/493、2067/214/439 |

⇒ **触发条件是 luma 周期 32（恰为帧宽一半，即整帧恰好两个周期）且 chroma 有
纵向/横向条纹**；luma 换成 16/64/8/4/2/1 或 chroma 换成平坦都恢复正常。
错误数与仓库样本**逐一相同**，说明复刻流与仓库样本等价，后续一切定位都可以在
可参数化、可二分的流上做。

## 三、补完"inter 帧到底读哪些继承表"的扫描（上次超时未跑完）

`av1_intra_cdfs_restore` 里逐张表跳过的完整结果（基线 2138/210/493）：

**会读（跳过即变）**：`skip_cdfs`(3898/932/920)、`tables.txb_skip`(4027/562/965)、
`y_coeff.eob`(4044/370/662)、`y_coeff.eob512`(2754/190/580)、
`y_coeff.eob_small`(2439/377/510)、`y_coeff.extra`(3960/525/751)、
`y_coeff.base_eob`(3757/274/789)、`y_coeff.base`(4018/642/696)、
`y_coeff.br`(3986/404/512)、`y_coeff.sign`(4082/582/652)。

**不读（跳过无变化 ⇒ 纠正上次的超时误判）**：`y_mode`、`uv_cfl`、`uv_no_cfl`、
`angle_delta`、`cfl.*`、`palette.*`(6 张)、`filter_intra`、`filter_intra_mode_cdf`、
`tx_set1`、`tx_set2`、**`uv_coeff.*`（全部 8 张）**。

⇒ inter 帧 6 个块全是 inter 块（不读 intra 专用表）；**所有 chroma 叶的
`all_zero` 都是 1（无 chroma 残差）**——由符号流直接证实：每个 chroma 叶只读 1 个
`all_zero` 符号，其后没有任何 eob/系数读。所以 inter 帧的 chroma 错误来自
**预测差异**而非残差缺失。

## 四、又排除一类假设：chroma 叶的 all_zero 读

把 8 个 chroma 叶的 `all_zero`（自然值 1）强制为 0，结果全部变差
（(0,0) U/V → 2911/752/941、2997/296/791；(0,12) U/V → 2166/620/586、2016/246/622；
(4,12) U/V → 2091/431/503、2099/320/500）。⇒ dav1d 在这些位置也读到 1。

## 五、当前证据总览（单符号假设已基本穷尽）

已强制排除：块 1-3 的 3 个 interp + 10 个 ref 名读；块 (4,12) 的 tx_type 全 12 值、
eob_pt 8 个值、base_eob、all_zero、mode、前 11 个 base 读；关键帧 6 个系数叶的
all_zero；inter 帧 8 个 chroma 叶的 all_zero。**无一归零。**

已静态核验：全部默认表值与 go-av1 逐位一致（14,296+ 元素 0 差异）；qctx 取法、
上下文计算、参考帧树、tx set/tx_type 映射、适配速率与计数器重置均一致。

⇒ 分歧仍在**状态级**：进入块 (4,12) 之前，MSAC 状态或某张被继承表的行值与 dav1d
不同，而此前像素全对。**新工具 pipe7.py 使下一步可以内容二分**：既然触发条件是
"luma 周期 32 + chroma 条纹"，可以系统扫 `(lper, cbper, crper)` 找到最小触发组合，
再对比通过/失败两份码流的关键帧符号流（两份只有 chroma 内容不同，其余同参数）。

## 六、插桩/守卫/开关已全部回退，三目标全绿

`av1_msac.mbt`（含 `read_index` 与 `FORCE_*`）已从备份恢复；loader 回 false；六个
文件守卫与 HEAD 逐字节一致；围栏 `[3992, 842, 928]`、OBU 与真值未动；
native/js/wasm-gc 各 **1242/1242**；无 zz 残留。
---

# 第四十二次推进补充（2026-09-22，纠正前两次误判；分歧形态收敛为
# "只用错上下文"；全部上下文函数与 go-av1 逐行一致）

## 一、纠正两个此前的错误结论（都会误导后续，必须记录）

1. **"inter 帧所有 chroma 叶 all_zero=1 ⇒ chroma 错在预测"仍成立**，但此前据此推出的
   "chroma 内容不影响关键帧读"是**错的**：重新逐符号提取关键帧发现，**关键帧的 V 叶
   （p=2）本就有残差**——`all_zero`(读 563)=0、`eob_pt`(读 564, len=12)=9 ⇒
   `eobpt=10 ⇒ eob=257`，其后读到第 1037 个符号。之前第十二次把读 563 当成
   "V 叶 all_zero=1 强制"实际上是**自然值为 0 的空操作**（当时用的 trace 把关键帧与
   inter 帧的同序号读混在一起了）。
2. **因此关键帧真正读满 1037 个符号**：luma 叶 (0,0) 读 7-81、(8,0) 读 82-152；
   (0,8)/(8,8) 两个 32x32 luma 叶各只读 1 个 all_zero（=1，无残差）；
   U 叶读 155-562（408 个符号），V 叶读 563-1037（475 个符号）。

## 二、本轮的强制执行结果（全部使错误数变差或不变，无一归零）

用 pipe7 复刻流（`32 5 7` ⇒ `[2138,210,493]`，与仓库样本一致）强制：

| 位置 | 结果 |
| --- | --- |
| inter 帧第 1 个 luma 叶的高值系数读 34/48/57/58/59/62/63/64（2→1 或 3→2） | 3912/3882/2749/3861/4012/4025/4048/3863 |
| （同一组在读错帧的对照）基线 = 3992/842/928（没开继承） | — |

⇒ inter 帧**第一个** luma 叶的系数读全部正确。

## 三、把分歧形态收敛为一句可执行的话

既然"符号值不同"的假设已穷尽，而**同一个符号值从不同 CDF 行解出**会：
- 像素完全不变（符号相同 ⇒ 残差相同）；
- 后续 MSAC 状态完全不变（符号相同 ⇒ range/value 转移相同）；
- **只让被适配的那一行不同** ⇒ 快照那一行错 ⇒ 之后真正读到该行的块才发散。

这正是与现有全部证据相容的唯一形态：前 3 个块像素全对、(4,12) 起才错、
且 (4,12) 只错上 12 行（DC/低频对、中高频错）。

要触发它只需要**某处上下文算错**（算到了相邻行）。

## 四、全部上下文函数与 go-av1 逐行核对（本轮完成，未发现差异）

| 上下文 | 我们 | go-av1 | 结论 |
| --- | --- | --- | --- |
| `all_zero`（txb_skip） | `av1_txb_skip_ctx_luma/chroma` | av1spec09 §927-985 | 逐分支一致（含 chroma `ctx += 7`、非整块 `+3`） |
| `coeff_base`（含 is_eob 分支） | `av1_coeff_base_ctx_square` | `getCoeffBaseCtx` | 一致：`sigRefDiffOffset` 三张表、`min(|q|,3)`、`min((mag+1)>>1,4)`、`pos==0&&row==0&&col==0→0`、1-D 阶梯 `ctx+26+5*min(idx,2)`（VERT 用 row / HORIZ 用 col）、2-D `coeffBaseCtxOffset[size_row][min(row,4)][min(col,4)]`（side_row==txSz 对正方形成立）、`adjTxSz` 语义（我们传 domain） |
| `coeff_base_eob` | 返回 0..3 | `getCoeffBaseCtx(...) - 42 + 4` | 一致（`sigCoefContexts=42`, `sigCoefContextsEob=4`） |
| `coeff_br` | `av1_coeff_br_ctx_square` | `getCoeffBrCtx` | 一致：`magRefOffset` 三张表、`min(q,15)`（=12+2+1）、`min((mag+1)>>1,6)`、`pos==0→m`、1-D 边界取 row(VERT)/col(HORIZ)、2-D `row<2&&col<2` |
| `dc_sign` | `av1_dc_sign_ctx_from` | `dcSignContext` | 一致 |
| `eob_pt` 的 pt_ctx | `scan_class==DEFAULT?0:1` | `(txClass==2D)?0:1` | 一致 |
| tx set / tx_type 集合 / 参考帧树 | — | getTxSet / txTypeInterInvSet* / single_ref_p1..p6 | 前一轮已逐项一致 |

## 五、剩下的唯一可能（下一轮的唯一入口）

上下文函数本身与参考实现一致，那么"只用错行"只能来自**喂给上下文的状态不同**：
`quant[]`（已解出的系数值）、`above/left level`、`above/left dc`。

- `quant[]` 由本叶已解出的系数决定 ⇒ 若前面的 base 读全对（已大量强制验证），
  `quant` 就对 ⇒ 后续上下文就对。
- `above_level/left_level/above_dc/left_dc` 由**本块之前**的叶按规范写回
  （`AboveLevelContext/AboveDcContext/LeftLevelContext/LeftDcContext`）。

**⇒ 下一个具体实验：核对写回逻辑**——
`av1_intra_transform` 尾部的 `culLevel`/`dcCategory` 计算与四个 context 数组的
**写入范围**（w4/h4 个 4x4 单位）是否与规范 §8.3 的
`for ( i = 0; i < w4; i++ ) AboveLevelContext[plane][x4+i] = culLevel` 一致；
以及关键帧第一个 luma 叶的 `culLevel`/`dcCategory` 值是否等于
按 dav1d 公式 `Σ|Quant[pos]|（截断 63）` 手算的结果。
这项无需 dav1d 符号级真值，纯静态核对，是最可能收口的一步。

## 六、插桩/守卫/开关已全部回退

`av1_msac.mbt`（含 read_index/FORCE_*）从备份恢复；loader 回 false；六个文件守卫与
HEAD 逐字节一致；`zz_repro_wbtest.mbt`/扫描脚本已删；围栏、OBU、真值未动。

## 七、状态

| 检查 | 结果 |
| --- | --- |
| `moon check` | 64 warnings / 0 errors |
| native / js / wasm-gc | 各 **1242/1242** |

---

# 第四十三次推进补充（2026-09-22，阶段 B 闭合：`inter_cdf_inherit_64x64` 归零；根因是 VERT/HORZ 系数扫描表互换 + 越读守卫错位）

## 一、结论先行

1. **`inter_cdf_inherit_64x64` 的 inter 帧像素差异从 `[3992,842,928]` 变为 `[0,0,0]`**
   （OBU 与 `reference.yuv` 未动）。native / js / wasm-gc 各 **1242/1242** 全绿。
2. 根因有两个，都是**规范符合性**错误，与继承机制本身无关：
   - **`av1_coeff_scan_square`/`av1_coeff_scan_rect` 的 `AV1_SCAN_VERT` 与
     `AV1_SCAN_HORZ` 两个分支互换了**（见第三节）。
   - **`symbol_max_bits >= -14` 守卫放错了位置**：规范只要求 `exit_symbol`
     （tile 符号读结束）时 `SymbolMaxBits >= -14`，读符号过程中允许为负
     （负值部分的取值就是规范定义的 padding zero bits）。dav1d 不执行该一致性
     检查，本样本的 inter 帧需要从第 41 个符号起越讀到 payload 之后
     （共 646 个符号，结束 `SymbolMaxBits = -563`）。守卫已全部移除
     （11 处 + `av1_transform_tree` 2 处 + `av1_restoration_entropy` 1 处）。
3. `av1_cdf_load_enabled` 已置为 **true**（继承开关正式启用）。

## 二、新工具：插桩版 dav1d（下一次定位分歧的首选手段）

源码 dav1d **1.2.1**（与真值生成器同版本：`D:\ProgramData\anaconda3\Library\bin\dav1d.EXE --version`
= 1.2.1），构建记录：

- 源码：`https://code.videolan.org/videolan/dav1d/-/archive/1.2.1/dav1d-1.2.1.tar.gz`
- 工具链：MSVC 2022 BuildTools（`vcvars64.bat`）+ `pip install meson ninja`
- 配置：`meson setup build -Denable_asm=false -Denable_tests=false -Dlogging=false`
  （`ninja -C build dav1d`；产物 `build/tools/dav1d.exe` + `build/src/dav1d.dll`，
  运行时把 `build/src` 加进 PATH）
- 插桩（`src/msac.c`）：每个符号读打印 `ZZ <计数> <符号> <cdf[0]> <n>`；
  `dav1d_msac_init` 重置计数并打印 `TILE <sz>`；`ctx_refill` 首次越界打印
  `PASTEND <计数>`。
- **注意**：本机 `moon`（0.1.20260827）的 `moon fmt` 与仓库格式不符
  （会把长数组重排到 ~100 列，HEAD 的格式来自 CI 固定的 0.10.11+6ff76a5f9），
  不要对仓库整体执行 `moon fmt`。

**关键发现：我们的 CDF 约定与 dav1d 互为补码**——同一行我们的 `cdf[0]` 与
dav1d 的相加恰为 32768（`f = 32768 - cdf[s]` 的“正向累积”存储 vs dav1d 的
“反向累积”存储），比较指纹时要取补。

## 三、分歧定位过程（可复用的方法）

用插桩 dav1d 对本样本的两个 tile 取符号流，与我们的 `symbol()` 打点
（`read_index` 按 msac 实例天然按 tile 编号）逐读对比：

- **关键帧：1037 个符号，值与 CDF 行（取补后）全部一致** ⇒ 工具链本身可信。
- inter 帧：前 220 个读一致，**第 221 个读开始 CDF 行不同**（符号值仍相同）：
  我们在 `base[2][37]`、dav1d 在与我们 `base[2][36]` 等价的行。
- 该读是 inter 帧第 4 个块（MI (4,12)，16x16 luma）系数逆序读的第 3 个
  `coeff_base`；同叶内 c=eob-1 与 c=eob-2 两读双方同行。
- 打点 `av1_coeff_base_ctx_square` 的输入：该叶 `scan_class` 为
  `AV1_SCAN_HORZ`（H_* 变换），`ctx = ctx0 + 26 + 5*min(col,2)`；
  HORZ 路径的扫描序决定 `(row,col)`，从而决定 `col`。
- 查规范 `get_scan`（`_refs/av1spec06.md:3633`）与 go-av1
  （`_refs/go-av1/decode/scan.go` + `scans_all_gen.go`）：

  | 类 | 规范表 | 16x16 内容 | 我们原来的分支 |
  | --- | --- | --- | --- |
  | V_DCT/V_ADST/V_FLIPADST | `Mrow_Scan_16x16` | **恒等（行主序）** | 转置 ❌ |
  | H_DCT/H_ADST/H_FLIPADST | `Mcol_Scan_16x16` | **转置（列主序）** | 恒等 ❌ |

  ⇒ **VERT/HORZ 两个分支整体互换**。矩形同理（`Mrow_Scan_16x8` 恒等、
  `Mcol_Scan_16x8` 列主序，见 go-av1 `scans_all_gen.go`）。
- 为什么以前没被发现：仓库里所有精确样本的系数叶都是 `scan_class=0`
  （2D/DEFAULT），VERT/HORZ 路径从未被执行过；本样本是第一个 H_* 叶。

## 四、越读守卫：规范文本与 dav1d 行为

- `_refs/av1spec09.md:63`：`SymbolMaxBits` 为负时“表示所有可用位都已读完，
  -SymbolMaxBits 个 padding zero bits 已参与符号解码，这些位不存在于码流中”，
  且明确“允许在读符号过程中变负”。
- `_refs/av1spec09.md:293`：`>= -14` 是 **`exit_symbol` 被调用时**的一致性要求。
- dav1d 不执行该校验：插桩显示本样本关键帧从第 1014/1037 个符号起越界、
  **inter 帧从第 41/646 个符号起越界**（`PASTEND` 行）。
- 另一次独立验证：`av1_cdef_alpha_gate_wbtest` 的三条“截断”码流，
  **dav1d 实际全部接受**（rc=0，各输出 4096 字节），我们移除守卫后的解码
  与其**逐样本一致**（plane 总和 522880 / 523883 / 525119，前若干字节相同）。
  旧测试注释“libdav1d independently rejects all three”是**错误结论**，已更正。

因此守卫被整体移除而不是放松阈值；`symbol_max_bits` 字段保留——
`renorm` 里的 `count = Min(shift, Max(0, SymbolMaxBits))` 就是规范规定的
补位机制（`read_bits` 越界返回 0，与 dav1d 的“移入 1 后不再 XOR”等价，
已由 646 个符号逐读一致证明）。

## 五、测试侧变更（5 个旧断言改为钉新行为）

| 文件 | 旧断言 | 新断言 |
| --- | --- | --- |
| `av1_transform_tree.mbt` | 1 字节载荷的系数走查被拒绝 | 完成并返回 1 个叶 |
| `av1_vartx_wbtest.mbt` | 1 字节载荷被拒绝 | 与 2 字节载荷解出同一棵 16 叶树 |
| `av1_restoration_entropy_wbtest.mbt` | `read_sb` 拒绝越界 | `read_sb` 完成 |
| `av1_palette_colors_wbtest.mbt` | 1 字节载荷拒绝 | 完成并钉住 `[3729,4095,…]` |
| `av1_cdef_alpha_gate_wbtest.mbt` | `av1_decode_alpha` 拒绝 | 完成，且 `(alpha[0],alpha[9])` 钉住 dav1d 同流输出 |

`av1_coeff_decode_wbtest.mbt` 的 1D 扫描断言随分支互换更新
（`vertical[1]=1`、`horizontal[16]=256`）。

## 六、状态

| 检查 | 结果 |
| --- | --- |
| `inter_cdf_inherit_64x64` inter 帧 | `[0, 0, 0]`（原围栏 `[3992,842,928]` 已改） |
| native / js / wasm-gc | 各 **1242/1242** |
| `av1_cdf_load_enabled` | `true` |
| OBU / `reference.yuv` / 其它样本围栏 | 未改动 |

---

# 第四十四次推进补充（2026-09-22，阶段 C 下一刀的具体入口：compound 预测）

阶段 B 已闭合（第四十三次）。本轮只做定位，不动实现，给下一轮留一个可以直接开工的入口。

## 一、现状盘点（哪些门还关着）

`av1_inter_frame_supported`（av1_inter_tile.mbt:1262）目前仍拒绝：

| 头字段 | 含义 | 现状 |
| --- | --- | --- |
| `reference_select` | 块级 comp_mode 语法 | 未实现（本轮目标） |
| `skip_mode_present` | 依赖 reference_select，成对处理 | 未实现 |
| `enable_interintra_compound` | intra/inter 混合块 | 未实现 |
| `enable_masked_compound` | wedge / distance-weighted 混合 | 未实现 |

`general_inter_64x64` 仍整帧拒绝，它需要的就是这批工具里剩下的
compound 与全局运动（warped、temporal MV 已在阶段 C 前几轮落地）。

## 二、样本现实：现有 14 个 inter 样本全部 `reference_select = 0`

用 FFmpeg `trace_headers` 逐个核过 frame header：没有一条流开
`reference_select`。本轮还实测：把 `--enable-order-hint=1` +
`--enable-onesided-comp=1` 打开重编码 ramp 源，`reference_select` 仍是 0
（平滑内容下 RDO 不选 compound）。⇒ 下一轮必须先解决样本来源，三条路：

1. **头补丁法**（`inter_cdf_inherit` 用过的最省事路径）：把某个双帧样本的
   inter 帧 `reference_select` 从 0 改成 1，码流其余字节不动。块级随后会读
   `comp_mode` 符号（读到的是原流里的符号/补位），dav1d 与我们对同一条补丁流
   的解码必须一致——验收含义与 cdf_inherit 相同：逐样本复现 dav1d。
   补丁点的定位方法见 `scripts/generate-av1-inter-reference.py` 的
   `_split_bits` + trace 定位注释。
2. **多帧噪声源**：compound 需要两个不同参考，至少 3 帧；本轮试过 5 帧 +
   1/3 噪声源，aomenc 直接崩溃（rc 0xC0000005），未验证是否真能诱导出
   compound。
3. **encoder 侧强制**：libaom 没有 "force compound" 开关，只能靠内容。

## 三、实现入口（按依赖顺序）

1. **读路径**（av1_inter_mode.mbt）：
   - `av1_read_ref_frames`（约 300-420 行的 single_ref 树旁边）：按规范
     `read_ref_frames`（_refs/av1spec06.md:2681）加 `comp_mode`（条件
     `reference_select && min(bw4,bh4) >= 2`，CDF `TileCompModeCdf[ctx]`）、
     `comp_ref_type`（UNIDIR/BIDIR）、以及 `comp_ref`/`comp_bwdref`/
     `uni_comp_*` 系列符号； deux 个参考名写进 block 的 ref0/ref1。
   - `av1_read_mv`（558）：compound 时候选栈由两个参考的邻近块共同构成
     （规范 `compound_type_candidates`），diff MV 的 clamp 也要按
     compound 语义；`av1_mv_oracle_wbtest.mbt` 已有单参考候选的测试形状可抄。
   - `av1_read_interp_filter`（770）：compound 下 interp 读法不同
     （两个方向同一个索引 + joint 类型），注意 `enable_dual_filter` 分支。
   - `compound_type`（_refs/av1spec09.md:1564，`TileCompoundTypeCdf[MiSize]`）：
     wedge / DISTWTD 属于 masked compound，本轮**先拒绝**（保留
     `enable_masked_compound` 门），只实现 COMPOUND_AVERAGE。
2. **预测路径**（av1_mc.mbt / av1_inter_tile.mbt）：
   - `Av1MotionRequest.compound` 字段已存在，`av1_inter_rounds`（av1_mc.mbt:119）
     已按 compound 给出 round1=7 的取整——低层支持已就位。
   - 缺的是：对两个参考各做一次 `av1_motion_compensate`，按规范
     `compound_average`（`(pred0 + pred1 + 4) >> 3` 之类的带 clamp 平均）
     混合，再叠残差。OBMC 路径传 `compound: false` 不要动。
3. **门解除**：`reference_select` 与 `skip_mode_present` 成对移除；
   `skip_mode` 本身（`SkipModeFrame[0]/[1]` + 复制运动）也要实现，
   顺序依赖见 av1spec06.md 的 `read_ref_frames` 首支。
4. **验收**：用插桩 dav1d（第四十三次）对同一 OBU 逐符号对比；
   样本像素对 `reference.yuv` 逐样本一致；三目标全绿。

## 四、状态

| 检查 | 结果 |
| --- | --- |
| native / js / wasm-gc | 各 1242/1242 |
| `inter_cdf_inherit_64x64` | `[0,0,0]`（已提交，0f058a1） |
| 下一刀 | 本补充第三节 |

---

# 第四十五次推进补充（2026-09-22，阶段 C 第二刀：compound 预测落地，`reference_select` 门解除）

## 一、结果

- **compound 预测实现完成**：`comp_mode`/`comp_ref_type` 读路径、双参考双运动
  向量、`compound_mode` 符号、compound 插值滤波上下文组、COMPOUND_AVERAGE
  混合（含 compound 中间取整 round1=7 与 `interPostRound` 混合）。
- **`reference_select` 门已移除**；`skip_mode` 仍整帧拒绝（它的两条参考与两个
  向量来自 `SkipModeFrames` 推导，是下一刀）。masked compound / interintra
  仍在帧门拒绝。
- **新样本 `inter_compound_64x64`**：`inter_shift_64x64` 的 `reference_select`
  由 0 补丁成 1（同样只动一个头部位），块层改读 `comp_mode`，原本按单参考编码
  的 tile 位被按 compound 解释。对 dav1d **`[0,0,0]`**。
- native / js / wasm-gc 各 **1244/1244**（新增 2 个测试）；
  `generate-av1-inter-reference.py --check`：**verified 9 fixtures**。

## 二、样本来源的关键事实

现有全部样本的 `reference_select` 本来就是 0，且**规范上它只依赖
`!FrameIsIntra`**（`_refs/av1spec06.md:1491` `frame_reference_mode`），与
`enable_order_hint` 无关——因此补丁这个位是合法且语义确定的（dav1d 对同一条
补丁流的解码即真值，实测三次运行 md5 一致）。这与第四十四次补充里
"aomenc 不为该内容选 compound" 的结论合起来解释了为什么必须用补丁法。

## 三、实现要点（代码入口）

- `av1_inter_mode.mbt`：
  - `Av1InterCdfs` 新增 `comp_mode` / `comp_ref_type` / `compound_mode` /
    `uni_comp_ref` / `comp_ref` / `comp_bwd_ref` / `compound_type`（表原本就在
    `av1_inter_tables.mbt`，只是没接进 cdfs 结构体）。
  - `Av1InterBlock` 新增 `ref_frame1` / `mv_row1` / `mv_col1`；
    `Av1InterInfo`/`Av1InterFrame` 新增 `reference_select` /
    `enable_masked_compound` / `enable_jnt_comp`。
  - 新函数：`av1_comp_mode_ctx`、`av1_comp_ref_type_ctx`（规范 §8.3 上下文）、
    `av1_read_compound_refs`（comp_ref_type 的 uni/bidir 两棵树）、
    `av1_read_compound_type`（两个 masked 开关关闭时直接 AVERAGE、不读符号）、
    `av1_compound_mode_ctx_map`（规范 `Compound_Mode_Ctx_Map`）。
  - 修改：`av1_read_ref_frames`（comp_mode 分支）、`av1_read_inter_mode`
    （compound 分支）、`av1_read_drl_idx`（NEW_NEWMV 走 new_mv 树）、
    `av1_assign_mv`（compound 两列表）、`av1_interp_filter_ctx`
    （compound 行组 `((dir&1)*2+compound)*4`）、`av1_inter_block_motion`
    （`find_mv_stack` 传入 compound 与 [ref0, ref1]）。
- `av1_inter_tile.mbt`：`av1_inter_predict` 里 compound 块做两次
  `av1_motion_compensate`（`compound: true`）后按
  `(p0+p1+16)>>5`（8 位）/`(p0+p1+4)>>3`（12 位）混合；
  `av1_motion_field_store` 写入 [ref0, ref1] 与两个 MV；
  帧门移除 `reference_select`、保留 `skip_mode_present`。

## 四、下一步入口

1. **skip_mode**：需要实现 `SkipModeFrames` 的推导
   （规范 6.8.14 `skip_mode_params`：由 `forwardIdx`/`backwardIdx` 与
   `skip_mode_frame` 选出两条参考），块级 `read_ref_frames` 的首支
   （`if (skip_mode)`）直接用其结果并跳过参考符号。
2. **masked compound**（wedge / DISTWTD）：需要 mask 生成
   （规范 7.11.3.14 + `Wedge_Bits`/`Wedge_Master`/`Diffwtd_Master` 表）与
   `compound_type` 符号读取；`build_wedge_mask`/`build_diffwtd_mask`
   在 go-av1 的 `decode/compound.go` 有现成形状。
3. **interintra compound**：intra/inter 混合（规范 `read_interintra_mode`）。
4. **segmentation** 与 **全局运动**（`gm_type != IDENTITY`）：帧门的后两个拒绝
   条件仍在（av1_inter_tile.mbt 的 `av1_inter_frame_supported`）。

---

# 第四十六次推进补充（2026-09-22，skip_mode：块级接线完成，样本被编码器阻塞）

## 一、已落地

- `read_ref_frames` 的 `skip_mode` 首支现在写**两个**参考名
  （`SkipModeFrames[0]/[1]`，之前只写 ref_frame）。
- compound 侧的 `find_mv_stack(isCompound)` / `assign_mv` 两列表 /
  `compound_mode` 已就位（第四十五次），skip-mode 块的
  `YMode = NEAREST_NEARESTMV` → 两列表都取栈位置 0，正是它需要的形状。
- 帧级 `skip_mode_params` 推导（`av1_frame_skip_mode`）**上一轮就已存在**
  且与规范逐行一致（`_refs/av1spec06.md:1449`：
  `SkipModeFrame[0] = LAST + Min(forwardIdx, backwardIdx)`、
  `SkipModeFrame[1] = LAST + Max(...)`；我们的 `lo/hi` 写法等价）。
- **帧门仍拒绝 `skip_mode_present`**：没有可外部核验的样本之前不解除
  （验收口径 4：未核验的工具不得静默解出错误画面）。

## 二、阻塞：样本必须三帧，而本机 aomenc 三帧必崩

skip-mode 的推导要求两条参考的 order hint 一前一后（`d<0` 与 `d>0`）。
两帧流里 8 个槽位全指向唯一的关键帧，order hint 全同 ⇒
`skipModeAllowed=0`，`skip_mode_present` 根本不会被读
（实测：补丁 `reference_select=1` 后 trace 里仍无该字段）。
本机 libaom（`aomenc.EXE`）**编码第三帧直接崩**
（rc 0xC0000005，与生成器注释 "libaom in this build crashes past two frames"
一致），所以拿不到现成的三帧流。

## 三、下一轮可直接照抄的样本配方（已探明位点）

1. 以 `--enable-order-hint=1` 编码 shift 源（其余 MINIMAL_FLAGS），得到
   `[TD, seq(enable_order_hint=1), K(order_hint=0), TD, I1(order_hint=1)]`。
   （`reference_select` 在 I1 帧头的 trace 位 136。）
2. **手工拼接第三帧**：追加 `[TD, I1 的字节副本]` 作为 I2
   （生成器的 `splice_*` 机制就是干这个的形状，参考
   `splice_loop_filter_deltas`）。
3. 依序打 6 个补丁（都用 `_split_bits`/`_pack_bits` 的位级补丁，
   trace 位号→payload 偏移按 `patch_header_fields` 的公式）：
   - K 帧 `order_hint` 0 → **7**（让 slot 0 的 hint 跑到 I2 前面）；
   - I2 帧 `ref_frame_idx[1]`（LAST2）0 → **1**（让 LAST2 指向 slot 1=I1）；
   - I2 帧 `order_hint` 1 → **2**；
   - I2 帧 `reference_select` 0 → **1**；
   - 再 trace 一次拿到 `skip_mode_present` 的位号，0 → **1**。
   推导核对：I2(hint=2) 看 K(hint=7)：`rel=+5>0`（backward），
   看 I1(hint=1)：`rel=-1<0`（forward）⇒ `skipModeAllowed=1`。
4. dav1d 解这条拼接流即为 golden（拼接/补丁流的验收口径与
   `inter_cdf_inherit` / `inter_compound` 相同：逐样本复现 dav1d）。
5. 然后把 `if header.skip_mode_present { return false }` 从帧门删掉，
   用同一模板生成测试（header 全字段对 trace + inter 帧 `[0,0,0]`）。

## 四、备选路径（可能更省事）

仓库里的 AVIF 动画样本（`avif_grid_animation_test.mbt`）本身是多帧流，
若其中某一帧的两条参考携带不同 order hint（libaom 的 animation 路径不开
order hint 的话此路不通，先查它的 sequence header），则可以直接在其上打
`reference_select` + `skip_mode_present` 两个位，省掉拼接与 hint 补丁。

---

# 第四十七次推进补充（2026-09-22，skip_mode 闭合：三帧拼接样本 + 门解除）

## 一、结果

- **skip_mode 闭合**：`inter_skipmode_64x64` 三帧全部 `[0,0,0]`，
  `skip_mode_present` 门已从 `av1_inter_frame_supported` 移除。
- native / js / wasm-gc 各 **1245/1245**；`--check` 现验证 10 个样本。

## 二、样本配方（第四十六次补充的配方已全部落实并写进生成器）

新增生成器机制 `build_skipmode_stream`（`scripts/generate-av1-inter-reference.py`）：

1. 以 `--enable-order-hint=1`（其余 MINIMAL_FLAGS）编码 shift 源 → 两帧流；
2. 在该流后追加 `[TD, 末帧副本]`，得到三帧流（副本的头部位号与原帧逐位相同）；
3. 打 5 个位级补丁（spec 里的 `patches`，用 trace 位号 + `expect` 断言）：
   - frame 0 `order_hint`(bit 23, 7 位) 0 → **7**
   - frame 2 `order_hint`(bit 24, 7 位) 1 → **2**
   - frame 2 `ref_frame_idx[1]`(bit 46, 3 位) 0 → **1**（LAST2 指到 slot 1）
   - frame 2 `reference_select`(bit 136) 0 → **1**
   - frame 2 `skip_mode_present`(bit 137) 0 → **1**
   `run()` 增加 `frame_count`（本样本 3），trace 检查、dav1d 字节数、
   `frame_planes` 切片都按它走。非检查模式会重新编码+拼接+打补丁；
   检查模式重放并逐字节比对，已实测两次一致。

## 三、位号为什么稳定

副本与 frame 1 的头布局逐位相同 ⇒ 补丁用的 trace 位号对副本同样成立；
所有补丁都是**等宽改写**，不移动后续语法 ⇒ 追加副本后位号不变。
推导核对：frame 2(hint=2) 看 K(hint=7) `rel=+5>0`（backward），
看 I1(hint=1) `rel=-1<0`（forward）⇒ `skipModeAllowed=1`，
`SkipModeFrames = (LAST+min, LAST+max)`（已按 `_refs/av1spec06.md:1449` 核对）。

## 四、测试

`inter_skipmode_64x64: skip-mode frame headers parse and the key frame matches
dav1d` 一个测试顺序解码三帧并逐帧比 `[0,0,0]`——第三帧是 skip-mode 帧，
前两帧同时钉住跨帧参考槽状态（阶段 D 的"三帧以上"覆盖也顺带有了）。

## 五、下一步

帧门现在只剩两个拒绝条件：`enable_interintra_compound` /
`enable_masked_compound`。下一刀建议 **masked compound**
（wedge / distance-weighted）：需要 mask 生成（规范 7.11.3.14 +
`Wedge_Bits`/`Wedge_Master`/`Diffwtd_Master` 表）与 `compound_type` 符号读取，
go-av1 的 `decode/compound.go` 的 `buildWedgeMask`/`buildDiffwtdMask` 有现成形状。

---

# 第四十八次推进补充（2026-09-22，阶段 C 第三刀：distance-weighted compound 闭合）

## 一、结果

- **COMPOUND_DISTANCE（jnt-comp 的距离加权混合）闭合**：
  `inter_distcomp_64x64` inter 帧对 dav1d **`[0,0,0]`**。
- native / js / wasm-gc 各 **1247/1247**；`--check` 验证 11 个样本。

## 二、关键规范事实（下一轮别重查）

- **`enable_jnt_comp` 的读取条件是 `enable_order_hint`，不是
  `enable_masked_compound`**（`_refs/av1spec06.md:234`：
  `if ( enable_order_hint ) { enable_jnt_comp; enable_ref_frame_mvs }`）。
  所以距离加权只需要 order hint + jnt 开关，**不需要** masked compound。
- `read_compound_type`（av1spec06.md:2901）在 `enable_masked_compound=0` 时
  **不读** `comp_group_idx`（保持 0），于是有 jnt_comp 才读 `compound_idx`：
  0 ⇒ COMPOUND_DISTANCE，1 ⇒ COMPOUND_AVERAGE；没有 jnt_comp 就直接 AVERAGE。
- DISTANCE 的权重（§7.11.3.15）：`dist[ref] = clip(0,31,|rel_dist(orderHint[ref],
  orderHint)|)`，`quantDistWeight={{2,3},{2,5},{2,7},{1,31}}`，
  `quantDistLookup={{9,7},{11,5},{12,4},{13,3}}`（go-av1 decode/compound.go:248）。
  混合：`round2(fwd*p0 + bck*p1, 4 + interPostRound)`，即 8 位
  `(fwd*p0 + bck*p1 + 8) >> 8`。

## 三、实现要点

- `av1_inter_mode.mbt`：`block.compound_type` 字段；
  `av1_read_compound_type` 真正按规范读 `compound_idx`（wedge/diffwtd 仍拒绝）；
  新 `av1_distance_weights` / `av1_ref_distances`（每个参考名的裁剪距离，
  存在 `Av1InterInfo.ref_distances`，帧构造时算一次）。
- `av1_inter_tile.mbt`：compound 预测按 `compound_type` 分流——
  DISTANCE 用 `(fwd*p0 + bck*p1 + bias) >> (4+post)`，AVERAGE 维持
  `(p0+p1+bias) >> (1+post)`。
- 生成器：`build_skipmode_stream` 泛化为 **`build_patched_encode`**
  （`append_frame_copy` 可选 + `patches`），同时支撑 skipmode 的三帧拼接与
  distcomp 的“编码+打一个位”；`run()` 的 `--limit` 改为
  `nframes - (append_frame_copy ? 1 : 0)`（此前对所有 patched_encode 都 -1，
  对不追加帧的样本是 bug）。

## 四、下一刀

**masked compound 的 wedge / DIFFWTD**：需要
`Wedge_Bits[BLOCK_SIZES]`、`Wedge_Master`（三张 64 长的一维母表 oblique
odd/even/vertical）、`Wedge_Codebook[3][16][3]={dir,xoff,yoff}`、母表生成
（oblique63 的错位采样 +  transpose/补码得到 oblique27/117/153/horizontal）、
按块尺寸的掩码提取与 flip 判定（`avg < 32`），以及 DIFFWTD 的
`m = clip(38 + |p0-p1| >> k, 0, 64)` 与 `mask_type` 符号。go-av1
`decode/wedge.go` 的 `initWedgeMasks` / `buildWedgeMask` / `buildDiffwtdMask`
有现成形状（母表数值已在本机 `_refs/go-av1/decode/wedge.go` 前 80 行）。
样本同样用 patched_encode：base 加 `--enable-masked-comp=1`，再打
`reference_select` 位。

---

# 第四十九次推进补充（2026-09-22，诚实修正：distcomp 样本没有覆盖距离加权混合；compound_idx 表修正）

## 一、必须记录的两件事

1. **发现并修正一个真实 bug**：`compound_idx` 与 `compound_type` 是**两个不同
   符号、两张不同的表**（规范 §5.11.25 + §8.3）：
   - DISTANCE vs AVERAGE 的选择读 `TileCompoundIdxCdf[ctx]`（ctx = 等距时 3，
     再加左右邻居各自的 `compound_idx`；单参考邻居点名 ALTREF 时 +1）；
   - WEDGE vs DIFFWTD 的选择才读 `TileCompoundTypeCdf[MiSize]`。
   上一轮（第四十八次）把 `compound_idx` 读成了 `compound_type` 表——表值不同
   （`{18244,12865,7053,13259,9334,4644}` vs 22 行的
   `{16384,16384,16384,23431,...}`）。已修正：两张表都接进 `Av1InterCdfs`，
   `compound_idxs` / `comp_group_idxs` 两个 MI 网格加进 `Av1MotionField`
   （块读到的值写回，供邻居上下文累加），两个 ctx 函数按规范实现。
   **表头的顺序事实**：`enable_jnt_comp` 只在 `enable_order_hint=1` 时读取；
   `read_compound_type` 在 `enable_masked_compound=0` 时**不读**
   `comp_group_idx`，于是有 jnt_comp 才读 `compound_idx`（0⇒DISTANCE，
   1⇒AVERAGE）。
2. **`inter_distcomp_64x64` 并不覆盖 DISTANCE 混合**：实测（临时打点统计）
   该样本的块**没有一个选中 compound ⇒ `compound_idx` 从未被读**，距离加权
   路径完全没进。它仍然精确 `[0,0,0]`（头部位 `reference_select` 读法 + jnt
   序列头 + 单参考回退路径都过了），但**混合本身未经外部核验**。原因：两帧流
   里 8 个槽位全指向同一幅关键帧，compound 预测等于"自己和自己的平均"，
   libaom 永不选择；补丁位让 `comp_mode` 全部解出 0。
   已尝试的搜索（全部落空）：(kind ∈ {ramp, shift, strip, still}) ×
   (cq ∈ {20,32,48}) 共 13 个编码，只有 shift×{32,48} 解出来且都是 0 个
   compound 块；ramp/strip 的解码直接失败（其他工具门，未深究）。

## 二、为什么混合难以用两帧流触发

`comp_mode` 的符号值由算术编码器状态决定（= 整条码流的函数），等宽补丁只能
改值不能移位，能改对齐的只有序列头 `enable_order_hint`——而它又会把 inter 帧
头撑宽（`order_hint` + `ref_order_hint`）并使 `skip_mode_params` 可读。
⇒ 能让 DISTANCE 真正被选中的现实路径是**三帧拼接**（`build_patched_encode`）：
第三条帧的两个参考是 K(hint 7) 与 I1(hint 1)，order hint 不等 ⇒ 距离权重
不等（dist=1 两边，权重 7/9），此时若某块 `comp_mode=1` 且 `compound_idx=0`
即进入 DISTANCE。下一轮配方：
1. `encode_input("shift")` + `--enable-order-hint=1 --enable-diff-wtd-comp=1
   --enable-dist-wtd-comp=1` 编码两帧 base；
2. `build_patched_encode`（`append_frame_copy=True`）；
3. 补丁（trace 位号对 frame 2 即副本）：K 帧 `order_hint` 0→7、
   副本 `ref_frame_idx[1]` 0→1、副本 `order_hint` 1→2、副本
   `reference_select` 0→1（distwtd 样本的 `reference_select` 位是 136，
   三帧副本相同）；
4. dav1d 解为 golden，逐样本比对——若某块走 DISTANCE 且 `[0,0,0]`，混合即核验。

## 三、状态

| 检查 | 结果 |
| --- | --- |
| native / js / wasm-gc | 各 1247/1247 |
| `inter_distcomp_64x64` | `[0,0,0]`（只覆盖 comp_mode 读法与单参考回退） |
| DISTANCE 混合 | 代码就位、**未核验** |
| wedge / DIFFWTD | 仍未实现（`comp_group_idx=1` 时整帧拒绝） |

---

# 第五十次推进补充（2026-09-22，DISTANCE 混合核验的完整搜索记录：约 50 个候选全部落空）

## 一、本轮做了什么

为验证距离加权混合，需要一条"order hint 开（jnt_comp 的前提）+ 某块
comp_mode=1（compound 块）+ 该块 compound_idx=0"的流。用插桩 dav1d 的符号流
直接数 `comp_mode` 的 CDF 行（默认值 26828/24035/12031/10640/2901 可唯一
识别），全程约 50 个候选：

| 搜索维度 | 结果 |
| --- | --- |
| kind ∈ {ramp, shift, strip, still} × cq ∈ {32,36,40,44,48,52,60}（两帧 + `reference_select` 补丁） | 27 个编码成功（3 个 aomenc 崩溃）；**只有 still×{40,44} 读到 comp_mode，值都是 0**；其余 0 次读取 |
| 自定义平面源（4 个基准电平 × 3 个 shift，cq=40） | 12 个里 8 个成功，全部 0 次 comp_mode 读取 |
| 头部宽度变体（`--tile-columns=1`、`+tile-rows=1`、`--sb-size=64/128`） | 均 0 次读取 |
| 三帧拼接（still 源，cq ∈ {28..52}，K/I1/I2 hint 补丁 + `ref_frame_idx[1]`） | 8 个，全部 0 次 comp_mode 读取 |

**规律**：order hint 关时（`inter_compound`）tile 位对齐到基流 single_ref_p1
的位置，comp_mode 能读出 1；order hint 开时头部宽 7 位（`order_hint`）＋帧头
里的 `skip_mode_present`（三帧时），tile 位整体平移，我搜过的所有源在该对齐下
要么读不到 comp_mode（块尺寸都 < 8x8），要么读到 0。

## 二、结论与留给下一轮的两条路

1. **不要为了“看起来闭合”而假称 DISTANCE 已核验**：当前 `inter_distcomp_64x64`
   只覆盖头部位法与单参考回退，混合代码是 libdav1d 的忠实移植但**未被执行**。
   已如实写进 CHANGELOG / fixture README / HANDOFF 第四十九次补充。
2. 两条可能的路（都需要超过一格的预算）：
   - **更猛的搜索**：把源内容的每一位都当自由参数（pipe7 式的周期/相位参数
     化），对 `comp_mode` 的值做内容二分——`inter_compound` 证明“内容 ⇒ comp_mode
     值”的映射确实存在 1 的解，只是 order-hint 开时还没撞上；
   - **编码侧**：找一台 libaom 不崩的环境跑三帧并用内容诱导 distance-weighted
     compound（libaom 在两参考不同距时确实会选择它）——本机 aomenc 三帧必崩。

## 三、状态

| 检查 | 结果 |
| --- | --- |
| native / js / wasm-gc | 各 1247/1247 |
| DISTANCE 混合 | 代码就位，**未核验**（搜索记录如上） |
| wedge / DIFFWTD | 未实现 |

---

# 第五十一次推进补充（2026-09-22，interintra 触发器可用，但表格有分歧且语法面更大）

## 一、好消息：interintra 的触发器是**等宽位补丁**，确定可用

`enable_interintra_compound` 是序列头里的 1 位字段（`_refs/av1spec06.md:229`），
等宽改写 ⇒ 头布局不变、tile 位不动，只是块层多读一个符号。实测：把
`inter_minimal_64x64` 的序列头该位 0→1 后，dav1d 的符号流在第 1051 个读处
与基线分岔（基线 `1 4524 2` vs 补丁 `1 2531 1`），且总数 1176→1128
——证明 `interintra` 符号确实被读且改变了后续解码。用同样补丁搜索 60+ 个
候选（4 源 × 8 cq、36 个自定义边缘源、4 个头部宽度变体）确认：等宽补丁本身
总有效，只是多数源里没有 8x8..32x32 的 inter 块（`read_interintra_mode` 的
`MiSize >= BLOCK_8X8 && <= BLOCK_32X32` 条件，spec av1spec06.md:2876）。

## 二、阻塞点：默认表三方不一致，动手前必须解决

同一个 `Default_Inter_Intra_Cdf`：

| 来源 | 行 |
| --- | --- |
| 本仓库 `av1_inter_intra`（go-av1 生成） | `{26887} {27597} {30237}`（3 行） |
| go-av1 `cdf/tables_interintra_gen.go` | 同上（3 行） |
| dav1d 1.2.1 `src/cdf.c:237` | `{16384} {26887} {27597} {30237}`（**4 行**） |
| libaom（记忆中的 `default_interintra_cdf`） | `{26887} {9872} {13615}`（3 行，第三家） |

规范只给了 ctx（`Size_Group[MiSize] - 1`）没给默认值（默认表不在本机
`_refs/av1spec06/09.md` 的常量节里）。⇒ 下一轮第一步应当是**用 dav1d 的
插桩实测确定行号**：在补丁流的符号日志里，`interintra` 读取的 `cdf[0]` 与
上面四组之一对齐即可定表与 ctx；观测到的分岔行 `2531` 与四组都不等，说明
行号/索引还要再查（dav1d 的 `interintra` 是 4 行，`ctx` 可能不是
`Size_Group-1` 而是别的东西，或 Size_Group 的取值域不同）。

## 三、语法面（比想象大）

`read_interintra_mode`（av1spec06.md:2875）在 `interintra=1` 时还读：
`interintra_mode`（4 符号，选 II_DC/V/H/SMOOTH 预测）、`wedge_interintra`
（1 符号）、`wedge_index`——再加上**块内 intra 预测**（要接现有 intra 预测核）
与 §7.11.3.17 的**混合权重**。粗略估计还要 250+ 行加一个可触发样本，
单独一格放不下，故本轮只记录不实现。

## 四、状态

| 检查 | 结果 |
| --- | --- |
| native / js / wasm-gc | 各 1247/1242（本轮无代码改动） |
| interintra 触发器 | 等宽序列头补丁，**有效** |
| interintra 默认表 | **三方不一致，未解决** |

---

# 第五十二次推进补充（2026-09-22，更正第五十一次：interintra 表格**没有**分歧，是我读错了 dav1d 的宏）

## 一、更正

第五十一次补充说"interintra 默认表三方不一致"——**错的**。dav1d 的
`src/cdf.c:37` 定义 `#define CDF1(x) (32768-(x))`，所以
`{ CDF1(16384), CDF1(26887), CDF1(27597), CDF1(30237) }` 在 dav1d 内部约定下是
`{16384, 5881, 5171, 2531}`——即**与我们相同的补码约定**下就是
`{16384, 26887, 27597, 30237}`（4 行，第一行 16384 对应最小的 ctx）。
用插桩 dav1d 在补丁流上实测（`II grp=.. row=[.. .. .. ..]` 打印整表）：
**观测到的整表恰为 [16384, 5881, 5171, 2531]**，与 CDF1 补码后的表逐位一致
⇒ **本仓库 `av1_inter_intra` 三行 {26887,27597,30237} 就是 dav1d 第 1..3 行，
表格正确、无需更换**。

## 二、索引映射（下一轮直接用，不必再查）

dav1d 用 `dav1d_ymode_size_context[bs]`（`src/tables.c:250`）作行号：

| ctx | 块尺寸 |
| --- | --- |
| 0 | 4x4, 4x8, 4x16, 8x4, 16x4 |
| 1 | 8x8, 8x16, 8x32, 16x8, 32x8 |
| 2 | 16x16, 16x32, 16x64, 32x16, 64x16 |
| 3 | ≥32x32（32x32, 32x64, 64x32, 64x64, 64x128, 128x*） |

实测补丁流里读到 grp 2 / grp 3 两种。**我们的表只有 3 行**（{26887,27597,
30237} = dav1d 的 grp 1/2/3 行），所以我们的 ctx = dav1d 的 grp − 1；注意这与规范
字面的 `Size_Group[MiSize]-1` **不是同一张表**（libaom 的 Size_Group 把 16x16 归
第 1 组、32x8 归第 2 组，与上表相反），以 dav1d 的 `ymode_size_context` 为准。

## 三、剩余工作（下一轮）

实现本体仍需：`interintra` 符号读 + `interintra_mode`（4 符号，表
`av1_inter_intra_mode` 已在仓库）+ `wedge_interintra` + `wedge_index`（表
`av1_wedge_inter_intra` 已在仓库）+ 接**块内 intra 预测核** + §7.11.3.17 的混合
权重。触发器（序列头等宽补丁）已验证有效。

---

# 第五十三次推进补充（2026-09-22，interintra 语法落地：读取 + 门解除 + 拒绝式围栏）

## 一、已落地

- **`av1_read_interintra_mode`**：按规范顺序插在 `assign_mv` 与
  `read_motion_mode` 之间（av1spec06.md:2617）。读 `interintra`
  （`TileInterIntraCdf[ymode_size_context-1]`，我们的 3 行表即 dav1d 第 1..3
  行）；为 1 时续读 `interintra_mode`（4 符号）、`wedge_interintra`（1 符号）、
  `wedge_interintra=1` 时再读 `wedge_index`（16 符号）。
- **门**：`av1_inter_frame_supported` 里 `enable_interintra_compound` 的拒绝
  已移除；`enable_masked_compound` 仍拒绝（wedge/DISTWTD 的 mask 未实现）。
  块级选了 interintra  ⇒ `read_interintra_mode` 返回 false ⇒ **整帧拒绝**
  （混合需要把 intra 预测接进 inter 路径，宁可拒绝不解半张）。
- 新表全部接进 `Av1InterCdfs`：`inter_intra` / `inter_intra_mode` /
  `wedge_inter_intra` / `wedge_index`（本来就在 `av1_inter_tables.mbt`，
  只是没接线）。
- 生成器 `build_patched_encode` 增加**序列头补丁**能力（`seq_patch`：位号、
  宽度、期望值；等宽改写，不动后续任何位）——`inter_interintra_64x64`
  即 `ramp` 组 + 序列头 bit 69 改写。

## 二、样本

`inter_interintra_64x64`：序列头该位 0→1 后，实测 inter 帧与基线相比
3299/6144 个样本不同（`interintra` 符号确实被读且改变解码），dav1d 三次
解码 md5 一致；我们的解码器**按设计拒绝**。测试断言两点：① 头部位与关键帧
对 dav1d 一致；② inter 帧被整帧拒绝。`--check` 已验证该样本可重放
（18 个样本）。

## 三、下一轮（混合本体）

1. 把现有 intra 预测核接进 inter 块路径（`interintra_mode` 四种
   II_DC/II_V/II_H/II_SMOOTH，规范 §7.11.3.17 的权重表）；
2. `wedge_interintra` 的楔形掩码可复用 wedge 机制（同一张
   `Wedge_Codebook`，只是 `wedge_sign=0`）；
3. 随后把 `read_interintra_mode` 末尾的 `false` 改成正常返回，围栏测试改成
   `[0,0,0]`。

# 第五十四次推进补充（2026-09-22，interintra 混合本体闭合：样本 [0,0,0]）

## 一、已落地

- **`av1_wedge_mask.mbt`（新文件）**：按 AV1 §7.11.3.11 的
  `initialise_wedge_mask_table` 生成楔形掩码表。三张一维母列
  （`Wedge_Master_Oblique_Odd/Even/Vertical`，go-av1 `decode/wedge.go` 逐字）、
  六张 64x64 主表（OBLIQUE63 的主列按 `shift=MASK_MASTER_SIZE/4` 起逐行
  减 1 采样，OBLIQUE27/HORIZONTAL 是转置，OBLIQUE117/153 是翻转取补），
  `Wedge_Codebook[3][16][3]` 与 `Wedge_Bits`。每块掩码的符号约定是：
  边框行+列的平均值 < 32 时，`wedge_sign=0` 取**掩码本身**，否则取补
  （spec 的 `flipSign` 语义）。`av1_wedge_plane_mask` 再把 luma 掩码按
  平面下采样：4:2:2 是两列取整平均、4:2:0 是 2x2 取整平均，即 §7.11.3.14
  掩码混合里的 `Round2(...,1)` / `Round2(...,2)`。
- **`av1_inter_predict` 的 interintra 分支**：先用 `single_request` 做运动
  补偿，再按平面用 `av1_intra_predict` 做 intra 预测（边沿取自**已重建**
  的邻域，与 dav1d 的 `mc`+`prepare_intra_edges`+`blend` 顺序一致），最后
  统一混合 `(m*intra + (64-m)*inter + 32) >> 6`。非 wedge 变体的权重是
  `av1_ii_weight`（`Ii_Weights_1d[i*sizeScale]`，`sizeScale=128/max(w,h)`）；
  wedge 变体走 `av1_wedge_plane_mask`。单参考块的 `interPostRound` 是 0，
  所以 inter 预测不额外取整（这一点对着 dav1d 的 `blend_px` 宏核对过）。
- **顺手修掉两个真 bug**：
  1. `wedge_interintra` / `wedge_index` 的 CDF 索引原本按"高/宽/方"取 0/1/2，
     **错**：它们按**块尺寸**索引（AV1 §9.3.8-9，dav1d 的
     `dav1d_wedge_ctx_lut[bs]` 即 8x8→0、8x16→1、16x8→2、16x16→3、
     16x32→4、32x16→5、32x32→6、8x32→7、32x8→8；我们仓库的 22 行表
     `av1_wedge_inter_intra`/`av1_wedge_index` 本身就是按 bsize 排的，
     只是索引用错了）。这是会让熵解码器**失步**的错误。
  2. interintra 块**根本不读** `motion_mode` 符号（AV1 §5.11.26：条件里有
     `b->interintra_type == INTER_INTRA_NONE`），原来会多读一个符号。
- `av1_read_interintra_mode` 末尾的 `false` 改回 `true`；wedge 变体还要求
  `av1_wedge_shape_ok(w,h)`（该尺寸不支持 wedge 时拒绝整帧）。
- `Wedge_Bits` 的 22 行索引此前有一处偏差（go-av1 表在 16X4 位置记了 4、
  32X8 位置记 0）；以 dav1d 的 `wedge_allowed_mask` 为准改成
  8x8..32x32 + 8X32 + 32X8 九个尺寸为 4，其余 0。

## 二、样本

`inter_interintra_64x64`（`ramp` 组 + 序列头 bit 69 等宽补丁）：inter 帧
从"整帧拒绝"变成**逐样本等于 dav1d**，[0, 0, 0]，三个平面全测。该样本
8x8..32x32 里有一个块选中 interintra，且选的是 **wedge 变体**（插桩 dav1d
与我们的符号读取一致），所以楔形掩码与非楔形权重两条路都被真实像素钉住了。
参考真值由 `dav1d -i inter_interintra_64x64.obu` 现生成、与 manifest 的
sha256 一致。`--check` 仍是 18 个样本。

另：旧的拒绝式测试把 fixture 切分写成了 84（正确是 71，`frame_obus` 返回
`[(13,15,54),(71,73,25)]`）。用 84 切会让 inter 单元残缺、解码必然失败，
所以那条断言是**空转**的；新测试按两个时间单元的边界切分。

## 三、欠账与下一轮

- `av1_wedge_mask` 每次调用重建六张 64x64 主表（约两万五千次写）。wedge 块
  一帧只有个位数，实测可接受；若日后出现密集 wedge 的流再考虑缓存。
- compound 的 wedge/DIFFWTD 掩码可以复用 `av1_wedge_mask`（compound 要读
  `wedge_sign`，interintra 恒为 0），但 `enable_masked_compound` 的帧级门
  仍拒绝，且触发器无解（第五十次补充记录了 50 个候选的搜索结论）。
- segmentation、全局运动仍拒绝。

# 第五十五次推进补充（2026-09-22，实测 inter_compound_64x64 的真实覆盖：compound 块不存在）

## 一、动机

阶段 C 还剩 compound 的 wedge/DIFFWTD 掩码（`enable_masked_compound` 帧级
门）。想复用 interintra 的成功配方——序列头等宽位补丁打开语法、让 dav1d
自己走进去——于是拿 `inter_compound_64x64` 和 `inter_distcomp_64x64`
（README 说它们"解码 compound 块"）做实验。

## 二、插桩实测结论：这两个样本一个 compound 块都没有

本地插桩 dav1d（`C:/Users/谦友Lee/AppData/Local/Temp/dav1dbuild/`，MSVC，
`cmd //c build3.bat`，可执行文件在 `build/tools/dav1d.exe`，需要把
`build/src/dav1d.dll` 拷到 `build/tools/` 旁边），在 `decode_b` 的三处加计数：

1. `is_comp = msac_decode_bool_adapt(cdf.comp[ctx])` 之后：打印
   `ZZCOMP is_comp bs BW BH`；
2. `read_compound_type` 的 mask 分支入口：打印 `ZZSEG wedge_allowed bs`；
3. 选中 COMP_INTER_WEDGE 时：打印 `ZZWEDGE idx sign bs`。

再把序列头 **bit 70**（`enable_masked_compound`，绝对位，payload 从第 4 字节
开始，故 payload bit = 70-16 = 54；bit 69 是 `enable_interintra_compound`）
等宽 0→1，结果：

| 样本 | ZZCOMP | ZZSEG | ZZWEDGE | 输出变化 |
| --- | --- | --- | --- | --- |
| inter_compound_64x64 | 1 条，`is_comp=0` | 0 | 0 | 与基线逐字节相同 |
| inter_distcomp_64x64 | 1 条，`is_comp=0` | 0 | 0 | 与基线逐字节相同 |

结论：`reference_select` 置位只让**一个**块读 `comp_mode`（只有
`imin(bw4,bh4) > 1` 的块会读），而它解出 0。所以

- 这两个样本从未进入 compound 语法，README/测试注释里"解码 compound 块、
  pin 住整条 compound 路径"是**错的**（已在本轮改正为实测结论）；
- compound 的 wedge/DIFFWTD 掩码**不能**靠序列头补丁触发：没有 compound 块，
  `read_compound_type` 根本不会被调用；
- compound blend 的真实覆盖只有 `inter_skipmode_64x64`——skip mode 块按规范
  强制 compound（`skip_mode_present` ⇒ `is_comp=1`、`compound_type=
  COMPOUND_AVERAGE`），那条路径是真的。

## 三、下一轮的真正门槛

要触发 masked compound，需要**三个参考**且某一块真的选中 compound：即
第五十次补充记录的"三帧拼接 + 两条参考 order hint 分列当前帧两侧"的配方
（`inter_skipmode_64x64` 的生成器已有三帧拼接能力，但那个流里 compound 只
来自 skip mode，而 skip mode 直接指定 `COMPOUND_AVERAGE`，绕过
`read_compound_type`）。在拿到这样的流之前，compound wedge/DIFFWTD 只能
按"未核验"处理，或者退而做 Dav1d 掩码表级单元测试（把
`dav1d_wedge_masks[...]` 全表 dump 出来对拍），这把位运算钉住但不能替代
像素核验。

# 第五十六次推进补充（2026-09-22，楔形掩码表对 dav1d 逐样本钉住）

## 一、做法

给 dav1d 的 `dav1d_init_wedge_masks`（`src/wedge.c`）加了一段 dump：把
`dav1d_wedge_masks[bs][0][0][n]` 全部 144 张（9 个尺寸 x 16 个 index）按真实
尺寸（`dav1d_block_dimensions`）写成文件，再与我们的 `av1_wedge_mask` 逐值
比对。注意 dav1d 的 `bs` 是它自己的枚举（0=BS_128x128 …），与我们仓库的
bsize 索引**不同**，dump 时要把 W/H 一起打印出来。

## 二、结果

144 张掩码**全部逐样本一致**，包括：

- 三张一维母列 + 六张 64x64 主表的构造（OBLIQUE63 的 `shift` 逐行减 1）；
- OBLIQUEUE27/HORIZONTAL 的转置、117/153 的翻转取补；
- `Wedge_Codebook` 的 xoff/yoff 与 `flipSign` 约定（边框行列平均 < 32 时
  `wedge_sign=0` 取掩码本身）；
- chroma 下采样：4:2:2 两列取整平均、4:2:0 的 2x2 四项取整平均
  （`av1_wedge_plane_mask`，同样在测试里对 luma 掩码现场重算核对）。

新增 `av1_wedge_mask_wbtest.mbt`（goldens + 上面两项 chroma 核对），
`moon test` 三目标 1250/1250。

## 三、还欠什么

- `compound_type == COMPOUND_DEDGE / COMPOUND_DIFFWTD` 的**掩码选择**没有
  触发器（见第五十五次补充）：`read_compound_type` 的 `compound_type` 符号
  只在 compound 块上读，而两个候选样本都没有 compound 块。已实现的部分：
  `av1_wedge_mask`/`av1_wedge_plane_mask` 本身（compound wedge 的掩码与
  interintra 共用表，只是 `wedge_sign` 要真的读 1 位）。
- DIFFWTD 掩码（§7.11.3.12：`m = Clip3(0,64, 38 + diff/16)`，
  `diff = Round2(|p0-p1|, (BitDepth-8)+InterPostRound)`，`mask_type` 决定
  是否取补）**尚未实现**，同样没有触发器。

# 第五十七次推进补充（2026-09-23，找到 masked compound 触发器：一比特瓦片补丁 + 四个真 bug）

## 一、触发器的正确配方

第五十五/五十六次补充说错了：`enable_masked_compound` 补丁打上去**没有
compound 块**可读 `comp_group_idx`。真正缺的一步是**让某个块读成
compound**，而这是熵编码决定的。把 `inter_distcomp_64x64` 的第二帧瓦片载荷
第 17 字节（绝对偏移 105，payload 起点 88）的 bit 5 翻转：

- 序列头 bit 70（`enable_masked_compound`）0→1：让 compound 块读
  `comp_group_idx`；
- 瓦片那一比特改变后续符号的解码结果，`inter_distcomp` 里那个 16x16 块就读成
  compound，且继续读成 **COMPOUND_DIFFWTD**（dav1d 的 `ZZTYPE
  comp_type=3 bs=9 allowed=512`，bs=9 是 32x8）。

生成器新增 `tile_patches`（`build_patched_encode` 里的等宽字节内位翻转，
带 `expect` 断言），与 `seq_patch`/`patches` 正交。这三个补丁组合出来的流
dav1d 能解，且是确定解——这就是「合法、可核验」的触发方式。

## 二、顺着这条线挖出四个真 bug（都已修，全绿）

1. **`comp_ref_type` 分支反了**：spec 是 `comp_ref_type == 0 → unidir`，
   我们写成 `!= 0 → unidir`。原来 `read_compound_refs` 只在 compound 块上走，
   而所有既有样本都没有 compound 块（skip mode 块绕过它），所以这条从来没被
   执行过。
2. **compound 模式编号错**：libdav1d 的 `CompInterPredMode` 顺序是
   0 NEAREST_NEARESTMV、1 NEAR_NEARMV、2 NEAREST_NEWMV、3 NEW_NEARESTMV、
   4 NEAR_NEWMV、5 NEW_NEARMV、6 GLOBAL_GLOBALMV、7 NEW_NEWMV
   （`src/levels.h`）。我们仓库的常量名（17..24）恰好也是这个顺序，但我按
   别处记忆的"NEW_NEWMV=2"去判，导致 drl 树、每列表的新矢量、`needs_interp_filter`
   全错。现已改成按偏移量的谓词（both_new=7、list0 new={3,5,7}、
   list1 new={2,4,7}、has_nearmv={1,4,5}、both_global=6）。
3. **compound 块的 drl 读取**：NEW_NEWMV 走新树、含 NEARMV 的走近树，原来
   两个都读不到。
4. **compound 块的 subpel filter**：GLOBAL_GLOBALMV 不读 filter 符号
   （`needs_interp_filter` 原来只看单参考的 `y_mode == GLOBALMV`）。

另外实现了 §7.10.2.12 的 compound 扩展候选（`av1_add_compound_extended`：
same/diff 四槽、global 兜底、合并规则照 dav1d），原来这里是直接拒绝。

## 三、当前进度与下一步

- `inter_diffwtd_64x64`（三个补丁的流）从"整帧拒绝"推进到逐样本差集
  **2693/325/503 → 1221/117/216（luma/U/V）**，每次修一个 bug 就降一段；
  还剩一处差异：最后一个 compound 块（32x16 @ r=12 c=0）的
  `compintermode` 上下文算错，我们和 dav1d 读到不同符号。继续查的入口是
  `av1_compound_mode_ctx` 的 row/column 映射（`refmv_context` /
  `newmv_context`），用符号级 range 比对（`println` 每个符号后的
  `symbol_range`，与 dav1d `DEBUG_BLOCK_INFO` 的 `r=` 逐点比对，方法可复制）。
- **该流已从仓库撤下**（fixture、manifest 条目、FIXTURES 条目都删了），因为
  尚未逐样本一致；`--check` 仍是 12 个。`tile_patches` 能力留在生成器里。
- **`general_inter_64x64` 因此变为可解**：它带 masked-compound 开关，原来被
  整帧拒绝；现在门拆掉后逐样本等于 dav1d（`av1_inter_reference_wbtest.mbt`
  那条测试的断言已从"拒绝"改成"重建并比对"，[0,0,0]）。这是个新增的已验证
  覆盖面。

# 第五十八次推进补充（2026-09-23，DIFFWTD 逐样本闭合：tile_patches + 五个新 bug）

## 一、触发器的完整配方（三处补丁）

1. 序列头 bit 70（`enable_masked_compound`）0→1；
2. 帧头 bit 136（`reference_select`）0→1，让块读 `comp_mode`；
3. **瓦片载荷一比特**：帧 1 payload 第 17 字节（绝对偏移 105）bit 5 0→1。

前两处是等宽头部改写；第三处改变后续所有符号的解码结果，是**让 compound 块
存在**的唯一手段——libaom 在两帧组里永远不选 compound（两个参考都指向同一
关键帧）。翻转后 dav1d 的插桩显示一个 32x8 块读成
`comp_group_idx=1 → compound_type=DIFFWTD`。

生成器新增 `tile_patches`（与 `seq_patch`/`patches` 正交，带 `expect` 断言）。

## 二、逐样本定位问题的办法（可复用）

在 `av1_msac.mbt` 的 `Av1SymbolDecoder::symbol` 里打印每个符号解码后的
`symbol_range`，与 dav1d 开启 `DEBUG_BLOCK_INFO`（`src/recon.h` 里改成
`#define DEBUG_BLOCK_INFO 1`）后 `r=` 的值做子序列比对：dav1d 每个
`Post-xxx` 打印一个点，我们的流水账更细，跳过 dav1d 不打印的那些即可比对。用
这个办法本轮定位了 5 个 bug（每个都让差集降一截）。

## 三、本轮的五个新 bug（全部只在 compound 路径上）

1. **GLOBAL_GLOBALMV 的 compound 赋值**：两表都该取帧级全局运动，我们却从候选
   栈复制。
2. **NEARST_NEWMV / NEAR_NEWMV 没算 newmv**：`av1_mode_has_newmv` 只认 4 个模式，
   少 2 个；dav1d 是 `(1 << mode) & 0xbc` = {2,3,4,5,7} 五个 compound 模式加
   单参考 NEWMV。
3. **compound `comp_inter_mode` 的行号**：行 = `refmv_context >> 1`（2 和 3 共
   行），我原来是 clamp 到 0..2 再索引。
4. **refmv_context 的缩放**：near 行是 `min(3*matches, 4)`，不是 `2+matches`；
   close=0 行是 `min(matches, 2)`。
5. **compound 扩展候选的合并**：从 diff 槽（槽 2/3）复制时写错了源槽。

## 四、oracle 的修订（两处同源更正）

`_refs/mvstack_sim.py` 的 `NEWMV_MODES` 少了 NEARST_NEW/NEAR_NEW，refmv 缩放
也用了 `2+matches`；两处都按 dav1d 更正，`av1_mv_oracle_wbtest.mbt` 里 6 个向量
的上下文元组随之更新（5 个只差 newmv 原始计数——熵上下文只关心是否为 0）。
sim 的 frame helper 模板同时也落后于 `Av1MvFrame` 的字段，已同步（否则重新
生成会编译不过）。

## 五、当前状态

- `inter_diffwtd_64x64`：inter 帧三平面对 dav1d **[0,0,0]**，`--check` 13 个
  样本（原来 12）。
- `general_inter_64x64` 上一轮已转为可解且逐样本一致。
- **阶段 C 的 compound 相关门（`reference_select`、`enable_jnt_comp`、
  `enable_masked_compound`）全部闭合**；剩下的是 `enable_segmentation`、
  全局运动（`gm_type != IDENTITY`），以及 wedge 变体的像素级验证（掩码表已
  144/144 钉住，但还没有触发 wedge 的流——DIFFWTD 的流里那个块读的是
  `compound_type=1`；再找一个 bit 翻转让 `wedge_comp` 解出 0 即可）。

# 第五十九次推进补充（2026-09-23，segmentation 语法落地但流仍被围栏挡住）

## 一、wedge 触发器：确认不可达，收手

2026-09-23 用尽办法为 COMPOUND_WEDGE 造流：

- 单比特瓦片补丁 ~800 个位置/翻转组合（inter payload 20 字节 × 8、key payload 68
  字节 × 8、两两组合），**没有一个**让 `wedge_comp` 解出 0；只有
  `compound_type=3`（DIFFWTD）出现。
- 插桩 dav1d 直接读 `wedge_comp` 的解码结果：`ZZWEDGEVAL ct=3 ctx=8 cdf0=25067`
  ——CDF 已自适应到 P(0)=76%，但符号恒定是 1。且 `mask_comp`/`wedge_comp` 两次
  连续读取的窗口高度相关：能读到 `is_segwedge=1` 的状态，下一步的 bool 也必定是
  1。这不是概率问题，是算术窗的结构性耦合，靠翻位解不开。

结论：wedge 变体维持"语法已实现 + 掩码表 144/144 对 dav1d 钉住 + 混合公式与
DIFFWTD 共用"，但**没有像素级触发流**。DIFFWTD 那条链验证的是同一套 blend
（§7.11.3.14 的掩码混合）与同一张 luma→chroma 掩码下采样，差别只在掩码来源。

## 二、segmentation：语法全量落地，门从"整帧拒绝"下移到"用到才拒绝"

`av1_frame_header.mbt` 新增 `av1_parse_segmentation_params`：按 §6.10.9 读
`segmentation_enabled`、`update_map`/`temporal_update`/`update_data`（primary
ref 帧为 PRIMARY_REF_NONE 时按规范取 1/0/1）、8 段 × 8 层的 feature_enabled
与 feature_value（`su(1+bits)`/`f(bits)` + Clip3），并算出 `SegIdPreSkip` 与
`LastActiveSegId`。结果存在 `Av1FrameHeaderInfo.segmentation`。

门现在的位置：`update_map` 或任一 feature 生效 ⇒ 整帧拒绝（因为每块的
`seg_id` 符号与 feature 应用都没实现）。**没有 map 更新、没有 feature 的
"声明式" segmentation 会被接受且逐样本不变**——但造不出这样的流：

- libaom 的 aomenc 没有 `--enable-segmentation` 开关（`aomenc --help | grep -i seg`
   只有 superres/palette）；
- 直接把 `segmentation_enabled` 那一比特 0→1 是等宽补丁，但规范要求此后**每个
  非 skip 块都要读一个 `segment_id` 符号**（read_segment_id，spec 2145 行），
  于是瓦片熵全错位，dav1d 自己都拒绝该帧（只解出关键帧）。所以这个补丁造出的
  不是合法流。

要真正闭合 segmentation，需要一条能让 encoder 自己发分段状态的流；这条路的
成本比它看起来高（要么找到别的 encoder 开关，要么做"重编码式"补丁：改完头部后
重新用 dav1d 的熵状态把 tile 重新封送，工作量等于写一个微型编码器）。

# 第六十次推进补充（2026-09-23，阶段 D 的三帧动画容器闭合）

## 一、本轮做了什么

1. `av1_inter_reference_wbtest.mbt` 新增
   `inter_skipmode_64x64: the animation entrypoint walks three frames`：
   `avif_decode_animation_samples(1000, [0,40,80], [40,40,40], [key,mid,skip])`
   走三个时间单元，每帧 RGBA 与该帧 dav1d 平面经公开转换
   `av1_yuv_highbd_to_rgba(64, 64, luma, u, v, 8)` 的结果逐像素相等。第三帧靠
   skip mode 同时把前两帧当参考，参考槽状态只有按序列解才拿得到。
2. `avif_grid_animation_test.mbt` 新增
   `animation container walks three distinct frames`：手工搭一条真实 BMFF
   （`moov>trak>mdia>{mdhd, minf>stbl>{stts,stsz,stco}}` + `mdat`），mdat 里
   84/26/22 三个时间单元背靠背，每样本一个 chunk（`nc == count`，stco 三项绝对
   偏移），stsz 走"常量样本大小=0 + 每样本大小表"路径，stts 单条目
   `count=3 delta=40`，mdhd `timescale=1000 duration=120`。
   `avif_animation_descriptor` 返回 3 帧（时间戳 0/40/80，duration 40），
   `avif_animation_sample_payloads` 抽回 3 段，`avif_decode_animation` 出 3 帧，
   `avif_decode_animation_frame(t)` 按时间戳选帧；第 0 帧与独立
   `av1_decode(key_unit)` 逐像素相等，三帧都与同单元的
   `avif_decode_animation_samples` 结果逐像素相等。

## 二、两个坑（下一轮别再踩）

- **stsz 的常量样本大小不占 version/flags 位**：本包的 stsz 解析按
  `payload+4` 读 `sample_size`、`payload+8` 读 `count`（前 4 字节当
  version/flags）。"每样本大小"表必须写成
  `[0,0,0,0, 0,0,0,0, 0,0,0,N] + N×be32(size)`；写成
  `[0,0,0,0, 0,0,0,N] + 大小` 会被读成 `sample_size=N`、`count=第一个大小`，
  随后 `nc != count && nc != 1` ⇒ `Unsupported`，`avif_animation_descriptor`
  直接返回 None。
- **inter_skipmode_64x64 的三个时间单元切点是 84/110/132**（共 132 字节，
  84/26/22）：每个 inter 单元是 `TD(12 00) + FRAME(32 14 … 20 字节载荷)`，结尾
  各带一个 TD。按 84/26/22 切才与 `avif_decode_animation_samples` 已验证的
  解码一致；按 84/20/20 切的副本是截断的（FRAME 头声明 20 字节载荷只剩 16），
  容器测试会挂在 `avif_decode_animation` 上。

## 三、验证状态

- native / js / wasm-gc：**1253/1253 全绿**（本轮 +1 个测试）。
- `python scripts/generate-av1-inter-reference.py --check`：13 样本 verified
  （跑完记得 `git checkout` 掉被改写
  的 `inter_cdf_inherit_64x64.trace.txt` / `inter_diffwtd_64x64.trace.txt`）。
- `node scripts/build-web.mjs --check`：web.js / wasmcore.wasm OK；web 产物
  无改动，所以本轮没有 build 提交。
- `node verify-wasm.mjs`：PASS。CLI 冒烟：`info --input
  tests/fixtures/av1/ac_y_cosine_q30.avif` → `format=avif 64×64×4`。
- **不要跑 `moon fmt`**：当前 moon 版本会把全仓库 77 个文件的长数组重排（数千
  行格式化噪声，与代码无关）。新增内容按文件既有风格手写即可。

## 四、下一步

阶段 D 的"三帧以上参考状态变化"由本轮两个测试覆盖。剩余门仍是
`enable_segmentation` 与全局运动（都要 encoder 自己发这样的流），以及阶段 E 的
README/CI 与证据收口。

# 第六十一次推进补充（2026-09-23，全局运动的 TRANSLATION 门闭合）

## 一、触发器：libaom 在这个尺寸发不出全局运动，所以是"注入"而不是"编码"

把 encoder 侧能想到的都试过：`--enable-global-motion=1`（本来就是默认开）、
cpu-used 0/1/2、lag-in-frames 0/25、cq 32/63、`--good`、2/4 帧、平移 8~30 像素、
缩放源、棋盘纹理源、64/128/256 帧尺寸、ffmpeg 的 libaom-av1 —— **每一条流 7 个
`is_global` 位都读出来是 0**。原因不是 flags：邻居运动预测让一个整体平移的
每块成本低于模型自身的 ~30 位，于是 RD 永远不选全局运动。`aomenc --help` 里的
`--cpu-used=-4`、`--best` 直接是非法参数。

所以用仓库既有的"补丁流"路线：`inject_global_motion` 取已提交的
`inter_minimal_64x64`，把 `is_global(LAST_FRAME)` 置 1，写 TRANSLATION 模型的
两个 subexp delta（3 与 -5，即 6/8 像素行位移与 -10/8 像素列位移），然后把
头部其余部分整体后移插入位宽。三个坑，都是下一轮可以直接复用的结论：

- **subexp 编码器必须自己写**：`_write_signed_subexp_with_ref(delta, mx, ref)`
  = `recenter(r, delta+mx)` → `subexp_bits(v, 2*mx+1)`，其中
  `recenter(r, x) = x if x > 2r else (2*(x-r) if x >= r else 2*(r-x)-1)`，
  `ns(u, S)` 用 `w = S.bit_length()`、`m = (1<<w) - S`：`u < m` 写 w-1 位，
  否则写 `(u+m)>>1` 再补一位。dav1d 的 `getbits.c` 与 spec 等价（`n` 当"最大值"
  读，边界 `<=` 与 `<` 差一在整数域上重合），`av1_msac_inverse_recenter` 与
  dav1d 的 `inv_recenter` 逐字一致。
- **tile payload 要从 base 的 `base_header_bytes` 开始拷贝**，不是新头部宽度：
  第一次写反了（`data[payload_at + len(out)//8:]`），结果丢了两字节瓦片数据、
  补了两字节对齐零，帧还能解但像素是错的。
- **header_bytes 断言写 16 是错的，实际 15**：`header_bytes` 是"头部语法结束
  位置向上取整"，本流头部语法在 119 位结束 → 120 位 = 15 字节（对齐零位不算
  语法）。base 是 14 字节（112 位，末个 is_global 在 108 位）。

## 二、代码侧只动了一行门（外加注释）

`av1_inter_frame_supported` 的 gm 分支从 `!= av1_gm_identity → 拒绝` 改成
`> av1_gm_translation → 拒绝`：TRANSLATION 需要的东西
（`av1_setup_global_mv` 推导出的块级 MV）本来就有，ROTZOOM/AFFINE 需要的是
AV1 §7.11.3.5 的逐像素 warp 网格，与 LOCALWARP 同一套，仍然拒绝。
`av1_read_motion_mode` 里 gm > TRANSLATION 的提前返回本来就是 dav1d 的行为
（那种块不读 motion_mode 符号），不用改。

## 三、一个必须写进记录的副作用

TRANSLATION 模型让一个 GLOBAL(Global)MV 块读一个 identity 模型下会跳过的
subpel 滤波符号（dav1d:
`has_subpel_filter = imin(bw4,bh4)==1 || gmv[ref].type == TRANSLATION`），
于是这些块之后的符号重新象征化，解出的是**另一幅合法画面**。所以新 committed
的 reference yuv 是 dav1d 对补丁流的输出，不是 base 的。测试围栏
`[0, 0, 0]` 同时钉住：gm 语法位宽、两个 subexp delta 的解码结果
（`gm_params[1][0] == 3<<14`、`gm_params[1][1] == -5<<14`）、GLOBALMV 块的
MV 推导、滤波符号的读取偏移，以及门已放开。

## 四、状态

- native / js / wasm-gc：**1255/1255 全绿**（本轮 +2 个测试）。
- `python scripts/generate-av1-inter-reference.py --check`：14 样本 verified
  （跑完记得 `git checkout` 掉
  `inter_cdf_inherit_64x64.trace.txt` / `inter_diffwtd_64x64.trace.txt`，
  里面有 FFmpeg 的堆地址，每次都会变）。
- manifest.json 是手维护的（json.dump 会把补丁流的说明性 command 冲掉），
  新条目按行插入，注意它是 CRLF 且 inter_diffwtd 那一段是 LF。

## 五、下一步

阶段 C 的门只剩 segmentation（需要 encoder 发分段的流，判定成本过高）与
ROTZOOM/AFFINE 全局运动（需要 warp 网格）。阶段 D 的三帧动画容器已闭合。剩下
阶段 E：README/证据/CI 收口。

# 第六十二次推进补充（2026-09-23，阶段 E 的文档与工具一致性收口）

本轮没有改解码逻辑，只把"文档/工具说的"和"代码做的"拉齐：

1. **两份 README 的三处陈述过期**：`inter_cdf_inherit_64x64` 早已在第四十三次推进
   闭合为 `[0,0,0]`，README 却仍把它写成"唯一未闭合样本"并保留 `[3992,842,928]`
   围栏叙事；`av1_cdf_load_enabled` 也已开启；compound/skip mode/全局运动（平移型）
   的门都已解除，而 README 还说"仍在逐项解除中"。三处都已改为现状（中英文一致）。
2. **`general_inter_64x64` 的 SPECS 与提交的测试不一致**：`SPECS` 里
   `inter_decodable` 还是 `false`（注释说"块级阶段拒绝"），而文件里的测试已经断言
   它逐样本精确。已把 `SPECS` 改为 `true` 并补上动画用的两个键。
   注意：这个 fixture 的 inter 帧现在真的能解——拦截它的是"选中 LOCALWARP 的块"，
   而不是帧级开关。
3. **`emit-av1-inter-test.py` 以前会截断测试文件**：它 `open(OUT, "w")` 整文件重写，
   而 `inter_lossless_64x64` 之后的 20 多个 rung 是手工维护的（跑一次就全丢）。
   现在加了 `HAND_MARKER`：只重写生成的前言，遇到该标记后的内容原样保留，找不到
   标记就报错退出而不是覆盖未知布局。docstring 里也写清了前言与手工段的关系，
   以及"重跑会把大数组重排，需要时再 `moon fmt` 并只保留本文件的改动"。
4. HANDOFF 第 4 节的测试数从 1242/1242 更新为 1255/1255，第 5 节的 fixture 表按
   现状重写（14 个生成 + 手工 rung 分开列）。

## 状态与下一步

阶段 E 剩余的是"证据清单"层面的整理：各能力的 encoder 版本、命令、预期/实际覆盖
已由 fixture README、`manifest.json`（含 sha256 与命令说明）和 CHANGELOG 逐条记录，
`--check` 可复现。仍然开着的是两个需要新能力的门：LOCALWARP 与 ROTZOOM/AFFINE
全局运动（都要 warp 预测网格），以及 segmentation 的 `segment_id`/feature 应用
（需要 encoder 发分段的流）。

# 第六十三次推进补充（2026-09-23，LOCALWARP 的估计半边：least-squares 拟合落地）

## 一、本轮做了什么

新增 `av1_warp_model.mbt` + `av1_warp_model_wbtest.mbt`，把 LOCALWARP 需要的
**估计**半边按 libdav1d `warpmv.c` 逐行移植并钉住：

| 函数 | 作用 |
| --- | --- |
| `av1_warp_find_affine_int` | 由采样点对解出两条 affine 行的加权最小二乘（含 `div_lut` 倒数法，无除法） |
| `av1_warp_affine_mv2d` | 把模型平移钉到"块中心恰好重现该块自己的运动矢量" |
| `av1_warp_shear_params` | 拟合矩阵 → 预测用的四个系数 `alpha/beta/gamma/delta`，并报告"纯剪切"（不可表示） |
| `av1_warp_div_lut` / `av1_warp_filters` | 257 项倒数表；193×8 的 1/64-pel warp 滤波表（预测半边下一轮用） |

单元测试不是手算期望，而是用一个 Python 端口（同样移植自 `warpmv.c`，dv1d
表格直接抓取）生成 12 组随机采样集合，两侧对拍；另加旋转、越界剪切、采样门限
三个手构用例。native / js / wasm-gc 各 1260/1260。

## 二、两个坑（下一轮直接避开）

- **MoonBit 的 `Int` 是 32 位**：正规方程的行列式在 8 个采样点时约 3.9e11，
  `sxx * syy` 直接溢出，解出来全被夹到 `0xE001`。整个求解（det、倒数、四个
  `get_mult_shift_*`）以及 `get_shear_params` 里 `mat[4]*0x10000*y`、
  `mat[3]*mat[4]*y` 都必须显式 `to_int64()` / `Int64` 字面量。
- **`iclip(v2, 0xe001, 0x11fff)` 的两个界都是正数**（57345 / 73727），不是有
  符号补码范围；`av1_warp_mult_shift_diag` 按原样夹。
- **正规方程带常量偏置 `[8,4; 4,8]`**，所以矩阵恒正定，`det == 0` 的奇异分支
  不可达——原本为它写的用例删掉了，换成覆盖"位移差 ≥ 256 的采样点在拟合前被
  丢弃"的门限用例（后者是可观察行为）。

## 三、下一轮：预测半边

`mc_warp` 需要：（1）`find_matching_ref` 的 mask 采集（dav1d `decode.c`，依赖
`intra_edge_flags` 的 `EDGE_I444_TOP_HAS_RIGHT` 位，仓库现在没记这个位，需要决定
怎么取）；（2）`derive_warpmv` 的采样点构造与门限；（3）逐 8x8 的两遍可分离滤波
（15 行中间缓冲 + clip），mx/my 由模型在 1/64-pel 上推导，越界时按仓库既有约定
逐样本夹取（dav1d 用 `emu_edge` 复制边界，等价）；（4）触发流：用瓦片位补丁让某个
块真的解出 `motion_mode = 2`（可用插桩 dav1d 的 `DEBUG_BLOCK_INFO` 找位）。

# 第六十四次推进补充（2026-09-23，LOCALWARP 的预测半边接上，门从"拒绝"改为"按模型解"）

## 一、本轮做了什么

`av1_warp_model.mbt` 补齐预测半边并接进块级阶段：

| 新增 | 作用 |
| --- | --- |
| `av1_warp_matching_masks` | dav1d `find_matching_ref`：沿块上/左边缘取"同一参考"的 4x4 位掩码，bit 32 标记 top-left / top-right 角 |
| `av1_warp_derive` | `derive_warpmv`：按掩码取采样点、按 `4*iclip(max(bw4,bh4),4,28)` 门限剔除并紧凑化、拟合、转系数；不可表示时返回 None |
| `av1_warp_affine_chunk` | `warp_affine_8x8`：15 行水平滤波进中间缓冲 + 8 行垂直滤波并 clip；水平步进用 `alpha`，垂直用 `delta`，每采样的相位按 1/64-pel 查表 |
| `av1_warp_predict` | `mc_warp`：按 8x8 块走整个平面，模型在块的 luma 坐标中心求值后按色度下采样右移，`mx/my` 的推导与 dav1d 逐字一致 |

接线：`Av1InterBlock` 增加 `warp` 字段（估计出的模型或空数组）；`av1_read_motion_mode`
在 `mode == 2` 时推导并存入；`av1_inter_predict` 见到 `motion_mode == 2 && warp`
时整块走 warp 路径（跳过常规 MC 的 4x4 循环与滤波符号）。另外
`av1_needs_interp_filter` 对 LOCALWARP 块返回 false——它由 warp 网格自己滤波，
两个滤波符号都不在语法里（AV1 §5.11.27）。

门：帧门里 ROTZOOM/AFFINE 全局运动的拒绝理由改为"该模型能否被 warp 网格表示"
（`av1_warp_shear_params` 的剪切判定），与 LOCALWARP 用同一套依据。

## 二、当前状态与风险（接手必读）

- native / js / wasm-gc 各 1260/1260 全绿。
- **LOCALWARP 路径已实现但没有任何 fixture 选中它**，因此这条路径目前只有单元级
  证据（最小二乘与剪切转换对拍 Python 端口），没有样本级（对 dav1d 逐像素）证据。
  按仓库"合法未实现工具不得无声解成错图"的规则，这条必须尽快补触发流：做法是用瓦片
  位补丁让某个块真的解出 `motion_mode = 2`，再用插桩 dav1d（`DEBUG_BLOCK_INFO`
  会打印 `Post-motionmode`）确认位翻对了，最后逐样本比对。
- 顺带可做且更有价值的一步：既然 warp 网格已经在，ROTZOOM/AFFINE **全局运动**也可以
  闭合——注入器 `inject_global_motion` 现在只写 TRANSLATION，扩成能写 ROTZOOM/AFFINE
  后就能得到一条 dav1d 已验证的流，把帧门里最后一个 inter 工具门关掉。

# 第六十五次推进补充（2026-09-23，ROTZOOM 全局运动门闭合，`av1_inter_frame_supported` 的 inter 工具门清空）

## 一、本轮做了什么

`inject_global_motion` 增加 `model` 种类（Python 侧新增
`_write_global_param`：按 `idx` 区分精度——idx≥2 的对角项 12 绝对位/15 精度位
（dav1d 的"参考减半再乘 2"就是这个 precDiff=1 的指纹），idx<2 的平移项在
ROTZOOM/AFFINE 模型下 12/6，TRANSLATION 下 9-hp / 3-hp）。

新样本 `inter_globalmv_rotzoom_64x64`（同基流 `inter_minimal_64x64`）：
`is_global(LAST)=1` + `is_rot_zoom=1`，模型 x 缩放 512/65536、剪切 256/65536，
平移两项为 0。FFmpeg trace 证实
`is_rot_zoom[1]=1, gm_params[1][2]=512, gm_params[1][3]=256`。

代码侧：
- `av1_warp_from_global_motion(matrix)`：把帧级 `gm_params` 变成预测半边的模型
  （`av1_warp_shear_params` 判不可表示时返回 None）。
- `av1_inter_predict`：GLOBALMV 单参考块 + 该参考的 gm > TRANSLATION 且非
  `force_integer_mv` 时，走 `av1_warp_predict`（与 LOCALWARP 同一条逐像素路径）。
- 帧门：不再"凡非 identity 即拒绝"，改为**可表示性测试**（剪切/系数被夹 /
  force_integer_mv 时拒绝），compound GLOBAL_GLOBALMV 需要逐 list warp 的块在
  `av1_read_motion_mode` 里直接拒帧（本仓库的 compound 是两个 MC 结果混合，
  做不了逐 list warp）。
- 依赖：本轮用上了上一轮落地的 `av1_warp_model.mbt`，所以 warp 那半边不是死代码。

## 二、一个重要发现（写进 README 之前先记在这里）

`read_global_param` 的精度分三档，dav1d 的 `mat[2] = 65536 + 2*subexp(ref =
(ref-65536)>>1, 12)` 与规范 `(delta << precDiff) + round`（precBits=15 ⇒
precDiff=1）严格等价；而 ROTZOOM/AFFINE 的**平移项**是 precBits=6（precDiff=10）。
仓库里 `av1_frame_global_param` 的默认值正好是 15/6 分档，所以这次注入一次就通
——但如果以后有人动这个函数，必须按 `idx` 分档，不能一刀切。

## 三、状态

- native / js / wasm-gc 各 **1262/1262** 全绿（本轮 +2 个测试）。
- `--check`：15 样本 verified。
- **`av1_inter_frame_supported` 里的 inter 工具门已清空**：compound（含各类混合）、
  skip mode、OBMC/warped motion 语法、屏幕内容/调色板、时间运动矢量、平移与
  ROTZOOM/AFFINE 全局运动都有逐样本证据。仍未闭合的只有 segmentation feature
  （需要 encoder 发分段的流）与 LOCALWARP 的样本级触发（位 hunt 未做）。

# 第六十六次推进补充（2026-09-23，LOCALWARP 触发流到手，两个真 bug 修掉，差三个区域）

## 一、触发流：瓦片位 brute force

用插桩 dav1d（`DEBUG_BLOCK_INFO` 会打印每个块的 `Post-motionmode[%d]`）暴力翻遍
`inter_warped_64x64` inter 帧 tile payload 的每一位，找到 24 个能让某个块解出
`motion_mode = 2` 的位。选 offset 67 bit 0（4 个 LOCALWARP 块、dav1d 解码
rc=0），生成新样本 `inter_localwarp_64x64`（73 字节，基流 73 字节不变，只翻一 bit）。
生成器新增 `tile_patch_of` 种类：取已提交 OBU 翻一个 bit。

**为什么必须是 inter_warped**：同法试过最小集 + `--enable-warped-motion=1` 自编码
的流（`inter_localwarp` 最初的入口），该流 7 个 `is_global` 之外一个
motion_mode 符号都不读（`allow_warped_motion` 被 aomenc 编成 0），无从翻起。

## 二、顺着它修掉两个真 bug

1. **warp 掩码是 32 位**：`find_matching_ref` 的两个角标记在 bit 32，MoonBit 的
   `Int` 是 32 位，`1 << 32` 直接没了、`>> 32` 变成 `>> 0`，于是**只要 left_mask 非零
   就多加一个 top-left 采样点**。改成 Int64 后块 2 的采样数从 2 回到 1。
2. **warp 水平滤波 pass 漏了列偏移**：读参考样本时用了 `origin_x + tap - 3`，
   漏了输出列自身的位置，应该是 `origin_x + column + tap - 3`（dav1d 的
   `src[x + tap - 3]`）。修完 mi(0,12)、mi(8,12) 两个 warp 块从全错变成逐样本一致。

两个 bug 都在"没有任何 fixture 选中 LOCALWARP"时不可能被发现——这条触发流的价值
就在这里。

## 三、符号流比对的方法（可复用）

在 `av1_read_motion_mode` 打印 `msac range + mode + mi + masks`，与 dav1d 的
`Post-motionmode[N]: r=NNNN [mask: 0x…/0x…]` 逐条对：前 10 个符号（含 5 个
LOCALWARP 块的 mode 读取）**r 值全部相同**，包括 3 个 identity 模型块。

## 四、当前差在哪（下一轮入口）

围栏 `[376, 16, 8]`，坏区域只剩三处：mi(8,8) 的 16x16、mi(12,12) 与 mi(14,10)
两个 warp 块。关键线索：**mi(12,12) 处我们的 masks 是 `0x1/0x100000000`，
dav1d 是 `0x0/0x1`**——即我方认为左上邻块 (11,12) 同参考（我们 field 里确实是
ref 7），dav1d 认为不同；而我方认为不同参考的 (12,11)（field 里 ref 4）dav1d 却
认为同。这说明我方 motion field 在该区域的参考/分块状态与 dav1d 的 refmvs 网格
不同，而符号流又是逐字相同的——所以差异在**块级状态怎么落进 field**（很可能是
sub-8x8 或 rect 块的 `av1_motion_field_store` 覆盖范围/参考写入时机），而不是符号。
另外 mi(8,8) 在 raster 序里早于 (12,12)，它先错，所以先查它。

# 第六十七次推进补充（2026-09-23，LOCALWARP 残差定位到 mi(8,8) 的 8x8 子块）

## 一、本轮新证据

按块打印我方 inter 块状态（mi / 4x4 尺寸 / y_mode / ref / mv / motion_mode /
skip / 滤波）并与逐 8x8 块的差异图对齐：

- 最早出错的是 **mi(8,8) 的 8x8 子块**（我方 2x2 个 4x4 单位，ref=7、mv=(-4,8)、
  y_mode=16、motion_mode=0、skip=0、滤波 0/0）。该区域我方解出的样本与真值
  **完全无关**（例如第 33 行我方 57,76,99,… 真值 0,7,41,…），不是舍入差——
  说明预测源（参考帧/MV）或分块就不同。
- dav1d 的 `poc=0,y=8,x=8,bl=2` 之后紧接 `bl=3` 的子块，提示该 16x16 在 dav1d
  侧还有一个更大的上层块；我方在 (8,8) 直接切到 8x8。
- 符号流逐字相同（前 10 个 motion_mode 符号的 msac range 全部一致），所以分块符号
  应当相同——矛盾点即入口：**要么我方把某个 8x8 子块的分块/参考读错但后续 r 值巧合
  一致，要么我方写进 motion field 的块尺寸/参考覆盖范围与 dav1d 的 refmvs 网格不同**
  （后者与上一轮 mi(12,12) 的 mask 分歧是同一症状）。

## 二、下一轮的具体做法

1. 用 dav1d 的 `poc=/bl=` 行恢复它的分块树（`bl` 的枚举在
   `Temp/dav1dbuild/dav1d-1.2.1/src/levels.h` 一带，还没查），与我方 ZZBLOCK 列表
   在 rows 8-15 / cols 8-15 上逐块对；
2. 若分块一致，则打印我方 (8,8) 块的参考帧具体内容（`av1_frame_map_show` 的
   槽位与 ref_frame_idx 的映射），确认 ref=7 指向的槽是否与 dav1d 相同；
3. 若分块不一致，则从该 16x16 的 partition 符号开始重放（这是我方读分块与 dav1d
   的唯一分歧点，之前只对过 motion_mode 符号，没对过 partition）。

# 第六十八次推进补充（2026-09-23，残差根因定位：变换尺寸推导错了，不是预测也不是参考）

## 一、证据

逐变换块打印我方 `x/y/tx 尺寸/eob`，与 dav1d 的 `Post-y-cf-blk[tx=…,eob=…]`
（tx 枚举：0=4x4, 1=8x8, 2=16x16, 3=32x32, 4=64x64, 5=RTX_4X8, 6=RTX_8X4,
7=RTX_8X16, 8=RTX_16X8, 9=RTX_16X32, 10=RTX_32X16, …）逐条对：

| 我方 | dav1d |
| --- | --- |
| `x=32 y=0 tx=16x32 eob=39` | `tx=9 (16x32) eob=12` |
| `x=48 y=0 tx=16x16 eob=5` | `tx=1 (8x8) eob=51` |
| `x=48 y=16 tx=16x16 eob=6` | `tx=7 (8x16) eob=54` |
| `x=0 y=32 tx=32x32 eob=63` | （该区域 dav1d 是 8x8 / 16x8 一组） |

**决定性的一条**：`x=0 y=32 tx=32x32` —— 该位置属于 mi(8,0) 的 **32x16 块**，
而 32x32 变换根本放不进 32x16（`Max_Tx_Size_Rect` 只允许 ≤16x32 / 32x16）。
即：**var-tx 符号读对了（symbol 流与 dav1d 逐字一致、r 值全对），但把读到的
符号变成变换尺寸的推导错在矩形块上**——符号序列不变所以熵不解码错，变换尺寸错了
所以系数扫描/eob/逆变换全错，表现为该 16x16 区域样本完全失帧。

## 二、下一轮入口（很窄）

`av1_read_block_tx_size` / `av1_read_var_tx_size`（`av1_inter_tile.mbt:314` 与
`:403`）里矩形路径的尺寸递推：32x16 块读 PARTITION_SPLIT 后应是四个 16x8/8x8 等，
我方给的是 32x32。用这条流做单测：固定 `inter_minimal_64x64` 的 OBU、翻同位、
断言 `av1_read_block_tx_size` 对 (32x16, depth) 的返回值与 dav1d 的 tx 序列一致。
修好后 `inter_localwarp_64x64` 的围栏应从 376 直接掉到 0（该区域是最大的一块）。

# 第六十九次推进补充（2026-09-23，根因再收紧：分块树在"符号→树"的推导上不一致）

## 一、本轮把"变换尺寸"这个问题纠正为"分块树"问题

逐块打印（同一轮里同时打 `av1_read_block_tx_size` 的块尺寸与
`av1_motion_field_store` 的块尺寸，已排除"块对象被改"）：

| 位置 | 我方 | dav1d（`poc=…,bl=`，bl: 0=128, 1=64, 2=32, 3=16, 4=8） |
| --- | --- | --- |
| mi(0,0) | 32x32 | `bl=2` 32x32 ✓ |
| mi(0,8) / mi(0,12) | **两块 16x32** | 一块 **32x32**（`poc=0,y=0,x=8,bl=2`） |
| mi(8,0) | 32x32 skip=1 | `bl=2` 32x32 ✓ |
| mi(8,8) | 16x16 | `bl=2` 32x32 → 再分 `bl=3` 16x16 ✓ |

即：**我方把 dav1d 的一个 32x32（mi(0,8)）拆成了两块 16x32**。变换尺寸的差异
（我方 16x16/32x32 vs dav1d 8x8/8x16/16x8）是这条分块差异的下游后果，不是独立 bug。

## 二、但这与"符号流逐字一致"矛盾，所以入口很窄

partition 符号是按块读的：块更大 → 读的 split 符号更少。我方在 mi(0,8) 多读了一次
split（或读错了 split 的解释），此后的 r 值却仍然对得上——说明**我方读到的 split
符号值与 dav1d 相同，但把它翻译成子块几何时错了**（与 LOCALWARP 那两条 bug 同型：
符号对、推导错）。

## 三、下一轮入口

`decode_partition`（我方在 `av1_partition_tree.mbt` 或等价物里）：对
`mi(0,8)` 处的 32x32，把 split=PARTITION_VERT（或 HORZ）应用到 32x32 时应得到两块
**32x16**（长轴对半），而我方给出两块 16x32（短轴对半）——请核对
`av1_tx_split`/partition 的"哪条轴对半"规则：AV1 §6.4.1 的
`split_or_horz`/`split_or_vert` 是按**块自身的宽高比**选轴，32x32 是方的，
`PARTITION_VERT` 必然切成 16x32 ✓ 我方却切成 32x16，即把 VERT/HORZ 的轴选反了
（或 sub-block 的 (w,h) 传反了）。单测：`inter_localwarp_64x64` 的 inter 帧第一行
断言 mi(0,8) 处是一个 32x32。

# 第七十次推进补充（2026-09-23，var-tx 分歧面已排除公式与几何，剩邻居状态）

## 一、逐项核对过、已证明一致的部分

| 项 | 结论 |
| --- | --- |
| 块树 | 与 dav1d 一致（用 `Post-intermode`/`Post-residualmv` 的 mv 指纹逐块对过：mi(0,0)/(0,8)/(0,12) 的 mv 与尺寸全对上）。上一轮"mi(0,8)  dav1d 是 32x32"是**误判**——那些 `poc=…bl=` 行属于关键帧 |
| `av1_txfm_split_ctx` 公式 | 与 spec §9.3.4 一致：`(txSzSqrUp != maxTxSz)*3 + (TX_SIZES-1-maxTxSz)*6 + above + left`；我方用 `6*(4-max_tx) + smaller + above + left`，二者等价（已对 7 组块/变换尺寸核过 base 值 0/3/6/9/12/15/18） |
| CDF 表 | `av1_vartx_cdf_state()` 21 行，值即 libaom `default_txsplit_cdf`，与公式自洽（`av1_vartx_wbtest.mbt` 21 行全钉住） |
| 分裂几何 | dav1d `dav1d_txfm_dimensions` 的 `.sub`：RTX_16X32→TX_16X16、RTX_32X16→TX_16X16、TX_32X32→TX_16X16，与我方 `av1_tx_split`（长轴对半）一致 |

## 二、剩下的分歧面（下一轮入口）

分歧在**变换尺寸**：mi(0,12)（16x32、LOCALWARP 块）我方解出 16x16×2，
dav1d 是 8x8/8x16 一组；mi(0,8) 我方 16x32、dav1d 是 8x8。由于
motion_mode/滤波符号都读对了（r 值全对），而变换树在它们**之后**读，
所以此前对拍的 r 值序列覆盖不到这一段——这与"符号流一致"不再矛盾。

按上面排除的顺序，只剩两处：
1. **邻居状态**：spec 的 `get_above_tx_width/get_left_tx_height` 在
   "上方/左侧是 **skipped inter** 块"时返回**块宽/块高**，否则返回
   `Tx_Width[InterTxSizes[…]]`（变换网格）。我方 `av1_above_tx_width` /
   `av1_left_tx_height` 的 skipped-inter 分支与 `field.tx_width/height`
   网格是否在**每个 4x4 位置**都与规范一致，需要逐点打。
2. **dav1d 的一个额外守卫**：`if (is_split && t_dim->max > TX_8X8)`——
   即"节点自身的 max 类 ≤ 8x8 时即使符号说要 split 也不再分"。我方只有
   `tx_width == 4 && tx_height == 4 → 不分`，少了这一条。

先查 2（一行），再查 1（逐点打印）。修好后 `inter_localwarp_64x64` 的围栏
应从 376 直接掉向 0。

# 第七十一次推进补充（2026-09-23，var-tx 分歧收敛到系数符号本身）

## 一、本轮改动（保留）

`av1_read_var_tx_size` 加了 libdav1d 的守卫：**节点自身尺寸类 ≤ 8x8 时，即使
split 符号为 1 也不再细分**（符号照读，熵不错位；`t_dim->max > TX_8X8`）。
spec §5.11.15 没有这条，但 libaom 编码端同样不会发，所以这是"读入但不细分"的
防御性一致。全量 1264/1264 保持全绿，围栏未变（本流没有触发它的节点）。

## 二、把 dav1d 的调试输出按块拆开之后，分歧点定位到系数符号

用 `poc=`/`Post-skip`/`Post-intermode` 把 dav1d 的 inter 帧逐块还原：

```
poc=0,y=0,x=8,bl=2      ← 32x32 块在 mi(0,8)
Post-skip[0]            ← 不跳过
Post-intermode[0,mv=y:0,x:8]
Post-motionmode[1]: r=60488
Post-subpel_filter[0]: r=58946
Post-y-cf-blk[tx=9(16x32),eob=-1]     ← 全零
poc=?                    ← mi(0,12) 是上面那个 32x32 的 SPLIT 子块
Post-motionmode[2]: r=48256           ← LOCALWARP
Post-y-cf-blk[tx=9(16x32),eob=12]
```

与我方逐项对：
- 块树一致：mi(0,8) 是 32x32、mi(0,12) 是它 SPLIT 出的 16x32 ✓
- 变换尺寸一致：两者都读出 16x32（未再细分）✓
- 符号流一致：该块的 skip/ref/intermode/motionmode/filter 五个符号的 r 值
  与我方完全相同 ✓
- **分歧只在系数符号**：dav1d 的 `txb_skip` 读出 1（eob=-1，全零），
  我方读出 0 并继续读了 39 个系数。

## 三、下一轮入口（很窄）

即"系数邻域状态"类 bug：`txb_skip`/`eob`/`coeff_base` 的 CDF 行由
`above_level/left_level/dc_sign`（上方/左方变换的 eob 级别）决定。我方在
mi(0,8) 这一行读到的上下文与 dav1d 不同，可能来自上一块（mi(0,0) 的 32x32）
写进 `state.y_coeff` 的 above/left 数组方式、或 16x32 这种矩形变换在
`av1_coeff_context` 里的邻域取样（矩形块的 above 取样是 w4 列、left 是 h4 行，
且矩形块"整块覆盖"判定 `whole` 与方块不同）。
做法：在 `av1_coeff_context` 打印该变换的 (above_level, left_level, above_dc,
left_dc, whole)，与 dav1d `Post-y-cf-blk` 前的上下文对比；先查 mi(0,0) 的
above 数组是否正确覆盖了 32x32 的 8 列。

# 第七十二次推进补充（2026-09-23，dav1d 的首个变换是 16x32，说明顶层分块仍不同）

## 一、新数据点（决定性）

dav1d `dav1d_max_txfm_size_for_bs[BS_32x32][0] = TX_32X32`，且 TX_32X32 的
`.sub = TX_16X16`——**32x32 块的变换树只能分裂出 16x16/8x8，永远出不了 16x32**。
而 dav1d inter 帧的第一个 `Post-y-cf-blk` 是 `tx=9`（RTX_16X32），它只能来自
`BS_16x32`（其 max 正是 RTX_16X32）。

⇒ **dav1d 的第一个 inter 块是 16x32；我方的第一个 inter 块是 32x32**
（`ZZBTX r=0 c=0 w=32 h=32`）。顶层分块依然不同。

## 二、这推翻了上一轮"符号流一致"的部分证据

上一轮只对拍了 **motion_mode** 符号的 r 值，没对拍每个块的 skip/ref/intermode。
若顶层分块不同，前面若干符号的*条数*就不同，motion_mode 的 r 值仍可能对上是
巧合（符号数相同、值相同）。所以"符号流逐字一致"这个前提需要重新验证。

## 三、下一轮（一次做对）

按顺序打印并逐条对（每块一条），直到第一条分歧：
1. 我方每块的 `(mi, w×h, skip)` —— 上一轮已有插桩经验（`av1_inter_tile_block`
   里加打印即可）；
2. dav1d 每块的 `poc=…,bl=` / `Post-skip[]` / `Post-intermode[…]`。

预期第一处分歧就在 mi(0,0)/mi(0,8) 一带：我方把 64x64 分成 32x32×4，
dav1d 的第一块是 16x32（即 64x64 → 可能是 32x64/16x32 这类矩形分块）。
修正处分：`av1_partition_children` 的 64x64 分支或 `av1_partition_leaves`
的递归（矩形 PARTITION 是否在 64x64 层级被允许）。

# 第七十三次推进补充（2026-09-23，根因确定：我方分块树在不读符号的情况下被多切了）

## 一、方法（下一轮直接复用）

在 `av1_inter_tile_block` 入口打印每个块的 `(mi, w4, h4, msac range)`，与 dav1d
`poc=…,bl=…,bp=…,r=…` 的 r 值（dav1d 在**解开该块的 partition 路径之后**打印，
所以可直接与我方块入口的 range 对拍）。

## 二、逐条比对结果：符号流完全同步，树比我方期待的深

| 我方块（入口 range） | dav1d 同名位置（r） |
| --- | --- |
| (0,0) 32x32 r=58370 | 58370 ✓ |
| (0,8) 16x32 r=37328 | 37328 ✓ |
| (8,0) 32x16 r=51904 | 51904 ✓ |
| (8,8) 8x8  r=58240 | 58240 ✓ |
| (8,12) 8x8  r=33728 | 33728 ✓ |
| (12,8) 16x8 r=55328 | 55328 ✓ |

⇒ **符号流逐字同步**（包括 (0,8) 的 OBMC 符号 r=60488 也对上）。
⇒ 但树形不同：dav1d 的右下 32x32 → 4×16x16（叶子）；我方在同一处切到
8x8/8x16 一级。

## 三、决定性观察：多切的那几刀**没有消耗符号**

我方 (8,8) 8x8 → (10,8) 8x8 → (8,10) 8x16 → (8,12) 8x8 的 range 一路
41304 → 34764 → 33728，而 dav1d 从 (8,8) 直接到 (8,12) 的 r=33728。
我方在多切之后**又回到了同一个 range** —— 说明我方这几刀是
`av1_partition_leaves` 里"implied / forced"分支**凭空产生的，没有读符号**。

## 四、下一轮入口（很窄）

`av1_partition_leaves`（av1_partition_tree.mbt:304）的注释说
"Implied 4x4 NONE and forced frame-edge SPLIT decisions consume no entries"。
把这两类判定打印出来（节点 mi/尺寸 + 判定原因），对帧内每个节点核：
1. 本流是 64x64 可见帧 + 128x128 superblock，顶层强切合法；
2. 但 (8,8) 的 16x16 完全在帧内，`has_cols/has_rows` 应为真，不应被
   `edge_forces_split` 命中——大概率是 `av1_partition_node_valid` 或
   `edge_forces_split` 对该 SB 尺寸的判定把 64x64 帧的右/下边界算错了
   （例如用了 `sb_size` 而不是 frame 尺寸，或没把 128x128 SB 的可见裁剪算对）。
修掉后 `inter_localwarp_64x64` 的围栏应从 376 直接归零——
(32,4)/(48,6/7)/(56,4/5/6) 三个坏区正是这些多切块。

# 第七十四次推进补充（2026-09-23，纠正：分块树其实是对的，残差收敛到右下 4 个 16x16 叶子）

## 一、纠正上一轮的结论

打印 `av1_walk_partition_geometry` 的每个节点（mi、size、是否 forced、
hasRows/hasCols、以及半块是否越过帧界），本流（64x64 可见帧 + 128x128
superblock）的走法是：

```
(0,0) 128   forced SPLIT        ← SB 大于可见帧，合法强切
(0,0)  64   → 读符号
(0,0)  32   → 读符号            ← 32x32 叶子
(0,32) 32   → 读符号            ← 32x32 叶子
(32,0) 32   → 读符号            ← 32x32 叶子
(32,32)32   → 读符号 = SPLIT
  (32,32) 16 → 读符号           ┐
  (32,48) 16 → 读符号           ├ 4 个 16x16 叶子
  (48,32) 16 → 读符号           │
  (48,48) 16 → 读符号           ┘
```

与 dav1d 的 `poc=…,bl=` 完全一致（bl=1 的 64x64、4 个 bl=2 的 32x32、右下再分
4 个 bl=3 的 16x16）。上一轮"我方树更深"的判读是**误读**：`av1_inter_tile_block`
一次叶子会被多次调用（sub-8x8/chroma 组的子块通道），所以按块打印的列表里有
16 条，而 partition 树只有 7 个叶子。**符号流与树都对。**

## 二、残差现在收敛到一处

干净的逐 8x8 差异图（只解码本 fixture）：
```
行 0-31 ：全 0                       ← 上面三个 32x32 全对（含 LOCALWARP 的 (0,12) 块）
行 32 ：[0,0,0,0,60,0,0,0]           ← (8,8) 16x16 坏
行 40 ：全 0
行 48 ：[0,0,0,0,0,0,63,61]           ← (12,12) 16x16 坏
行 56 ：[0,0,0,0,0,64,64,64]           ← (14,8)/(14,10)/(14,12) 一带坏
```

即**右下 32x32 分出的 4 个 16x16 叶子**（也正是含三个 LOCALWARP 块的四个叶子）。
它们的块入口 msac range 与 dav1d 完全一致（58240/33728/55328/59300），所以
块级符号没错；差异只可能在**这两个叶子里的残差（系数）或预测**。

## 三、下一轮入口

对这 4 个 16x16 叶子逐叶打印：
1. 叶子内每个 luma 变换的 (x, y, w, h, txb_skip, eob, tx_type) —— 用
   `av1_intra_transform` 里 `all_zero`/`cul_level`/`tx_type` 已有的量；
2. 与 dav1d 的 `Post-y-cf-blk[tx=…,txtp=…,eob=…]` 逐条对（dav1d 的 tx 枚举：
   0=4x4,1=8x8,2=16x16,3=32x32,4=64x64,5=4x8,6=8x4,7=8x16,8=16x8,9=16x32,
   10=32x16,11=32x64,12=64x32,13=4x16,14=16x4,15=8x32,16=32x8,17=16x64,18=64x16）。
注意：上一轮那份"变换尺寸对比"是从**全量测试**的 grep 结果里挑的，被别的 fixture
污染了，别再引用；要在只解码本 fixture 的前提下重新取。

# 第七十五次推进补充（2026-09-23，dav1d 的 poc= 是**节点级**打印；残差定位到系数读取）

## 一、先纠正一个会一直误导人的点

dav1d 的 `poc=…,bl=…` 来自 `decode_partition`（src/decode.c:2385），打印的是
**partition 节点**（bl 是 BlockLevel：0=128,1=64,2=32,3=16,4=8），不是叶子块。
所以 `bl=2` 出现在 (0,8) 只表示"这里有一个 32x32 节点"，它的子块可以是 16x32。
这也解释了我方 `av1_inter_tile_block` 一次叶子被多次调用（sub-8x8/chroma 子块
通道）——按块打印的列表天然比叶子多。

## 二、本轮的干净对比（只解码 inter_localwarp_64x64）

我方右下 32x32 内四个 16x16 叶子的 luma 变换（解码顺序）：

| 我方变换 | eob |
| --- | --- |
| (32,32) 8x8 | 39 |
| (40,32) 8x16 | 52 |
| (48,32) 8x8 | 8 |
| (48,40) 16x8 | 26 |
| (40,56) 8x8 | 5 |
| (48,48) 16x8 | 1 |
| (48,56) 16x8 | 16 |

dav1d 同区域（`Post-y-cf-blk`，tx 枚举见上一轮）：8x8(51) / 8x16(54) /
8x8(10) / 16x8(18) / 8x8(2) / 16x8(116) …

⇒ **变换形状序列对齐（8x8/8x16/8x8/16x8/8x8/16x8），但 eob 值不同**，
即第一个系数符号（`txb_skip`）或后续系数符号读到不同值。块入口 range 相同、
块级符号相同，所以分歧就在**系数符号的 CDF 行/上下文**。

## 三、下一轮入口（一次做对）

在 `av1_intra_transform` 里、读完 `all_zero`（txb_skip）之后立刻打印
`(x, y, txw, txh, minus1?, msac range_after)`，与 dav1d `Post-y-cf-blk` 行自带的
`r=` 逐条对：dav1d 的 cf-blk 行的 r 就是 txb_skip+系数读完之后的状态，
所以第一条不一致的 r 就定位到第一个读错的符号。若 txb_skip 的 r 一致而 eob 的
r 不一致，则问题在 eob/系数上下文（`av1_coeff_context` 的 above/left 取样）；
若 txb_skip 的 r 就不一致，则问题在 txb_skip 的 CDF 行
（`txb_skip[tx_context][skip_context]`，tx_context 由
`av1_tx_size_ctx_rect(txw,txh)` 给出，矩形 8x16/16x8 的 ctx 与方块不同）。

# 第七十六次推进补充（2026-09-23，txb_skip 之后 range 就不一致 → var-tx 读取分歧）

在 `av1_intra_transform` 里、读完 `all_zero`（txb_skip）后立刻打印
`(x, y, txw, txh, az, msac range)`，只取右下四个 16x16 叶子，与 dav1d 的
`Post-y-cf-blk` 行的 `r=`（dav1d 的 r 是 txb_skip + 全部系数读完后的状态）
逐条对：

| 我方 | az | r(txb_skip 后) | dav1d 同形状 | eob | r(系数读完) |
| --- | --- | --- | --- | --- | --- |
| (32,40) 8x8 | 1 | 34764 | — | — | — |
| (40,32) 8x16 | 0 | 54414 | 8x16 | 54 | 61960 |
| (48,32) 8x8 | 0 | 39008 | 8x8 | 51 | 49160 |
| (56,32) 8x8 | 1 | 38633 | — | — | — |
| (48,40) 16x8 | 0 | 40095 | 16x8 | 18 | 39176 |
| (32,48) 16x8 | 1 | 39252 | — | — | — |
| (32,56) 8x8 | 1 | 47016 | — | — | — |
| (40,56) 8x8 | 0 | 51060 | 8x8 | 2 | ? |
| (48,48) 16x8 | 0 | 61443 | 16x8 | 116 | ? |
| (48,56) 16x8 | 0 | 44198 | — | — | — |

（注：dav1d 的 r 是"系数全部读完"，我方的是"txb_skip 读完"，两者不可直接
比大小；但**形状序列一致**这一点很关键：8x8/8x16/8x8/16x8/… 对齐。）

⇒ 现在的分歧面收窄到：**四个 16x16 叶子内部的 var-tx 读取**（块入口 range
相同 → 块级符号相同 → 分歧在叶子内的变换树符号）。这也解释了为什么上一轮加的
"8x8 类节点不再细分"守卫没有改变围栏：它管的是另一种情形。

## 下一轮入口

`av1_read_var_tx_size` 的每个节点打印 `(row, col, tx_w×tx_h, depth, above,
left, ctx, symbol, range_before, range_after)`，与 dav1d `read_tx_tree` 的
`Post-vartxtree[%x/%x]`（两个 mask 字）对拍。dav1d 的 mask 位定义：
`bit = y_off*4 + x_off`（x_off/y_off 是该层的子块序号，depth0 0..3、depth1
0..7）；我方按同样方式累计 mask 后直接比两个 16 位字，就能定位到**哪一个节点
的 split 符号**读错。注意我方 ctx 公式（6*(4-max_tx)+smaller+above+left）与
dav1d 的 `cat = 2*(TX_64X64 - t_dim->max) - depth` 形式不同但都已验证自洽，
所以先假设 ctx 对，重点比对 mask 序列。

# 第七十七次推进补充（2026-09-23，下半帧块根本不读 var-tx：分歧在预测，不在系数）

## 一、本轮结论（否定上一轮的假设）

在 `av1_read_var_tx_size` 里对 `row >= 8 && col >= 8`（下半帧）的节点打印
ctx/symbol/bit —— **一条都没有**。即：本流下半帧的块全部
`skip == 1`（或被 `size_index > 0`/`tx_mode_select` 之外的路径拦截），
**一个 var-tx 符号都不读**。

所以上一轮"分歧在系数读取"的推断被否定：这些块的像素 = 纯预测
（无残差），差异只能来自**预测**本身。

## 二、与本流的结构对齐

- 上半帧三个 32x32：非跳过，读 var-tx + 系数 ✓ 与 dav1d 逐符号一致、像素全对
  （其中 (0,12) 就是 LOCALWARP 块，说明"估计 + warp 预测"这条链本身是通的）。
- 下半帧四个 16x16 叶子：全部 skip → 纯预测；其中三个含 LOCALWARP/OBMC 块，
  正是三个坏区。

⇒ 真正的分歧：**下半帧这些块的预测**。已知事实：
  - (8,8) 8x8 块：mm=0、mv=(-4,8)、ref=7 —— 它与 LOCALWARP 无关却也坏，
    说明先坏的很可能不是 warp 本身，而是**该块读到的参考/邻域状态**；
  - 这些块在上半帧的 LOCALWARP 块之后解码，且上半帧的 warp 块会把 warp 模型的
    预测结果写进参考邻域（loop filter 看得见）。

## 三、下一轮入口（改成直接对预测）

对 (8,8) 8x8 这种"纯预测 + 非 warp"的坏块，打印它的预测输入：
`ref 槽位（av1_inter_reference 返回的帧）、mv、filter_v/h、block 尺寸、plane`，
然后用**上半帧已验证一致的上一个块**做对照——如果输入完全相同而输出不同，
就是 `av1_motion_compensate` 在该参考/MV 下的问题（与 warp 无关，是普通 MC）；
如果输入不同（例如 ref 槽位指向了被 warp 块污染的参考图），则要看参考图的
写入路径（warp 预测是否只写当前帧而不污染参考槽）。

# 第七十八次推进补充（2026-09-23，参考图是对的；残差=下半帧 warp 块的**估计**）

## 一、本轮排除的两件事

1. **参考槽内容是对的**：对 slot 1/3/4/7 dump 存储参考的下半帧 luma，与
   fixture 的 frame0（先 `av1_inter_expand` 展开！）逐样本比——**全 0**。
   注意：上一轮若直接用 RLE 数组按下标取，会得到假的 2003（RLE 是 (值,次数) 对），
   别再犯。
2. **预测输入是对的**：按叶子打印 (mi, 尺寸, y_mode, ref, mv, mm, skip, filter)，
   与 dav1d 的 `Post-intermode[…,mv=y:…,x:…]` / `Post-ref[…]` 逐块一致。

## 二、于是残差定位到：下半帧 LOCALWARP 块的**模型估计**

上半帧的 LOCALWARP 块（mi(0,12)）像素全对 ⇒ "掩码 → 采样 → 最小二乘 → warp
网格"这条链是通的。下半帧的三个 LOCALWARP 块坏，其中 (14,10) 有直接证据：

| | 我方 | dav1d |
| --- | --- | --- |
| masks | `0x1/0x0` | `0x1/0x0` ✓ 相同 |
| 模型 | alpha=-7104, beta=3392, gamma=-4032, delta=1984 | 全 0（identity） |
| 块自身 mv | (4,8) | (4,8) ✓ |

掩码相同、块自身 mv 相同，但拟合结果不同 ⇒ **采样点的取值**不同：要么邻居块的
MV/尺寸取错（`av1_warp_matching_masks` 命中的 unit 与 dav1d 的 `r[-1][bx+off]`
不是同一个），要么阈值/紧凑化把不同的采样集留了下来。

## 三、下一轮入口（很窄）

对 mi(14,10) 这一个块，打印 `av1_warp_derive` 的完整输入输出：
```
masks, np, 每个采样点的 (row, col, bw, bh, mv_y, mv_x, in_x, in_y, out_x, out_y), mvd, kept, matrix, abgd
```
与 dav1d 的 `[ 10e65 3ed ffbd / 0 0 ffbd ] alpha=…` 对照——dav1d 对 identity
模型打印的矩阵是单位阵（第一行 0x10000, 0x0000），说明它**没有拿到有效采样**；
我方拿到了一个有效采样并拟出了模型。重点核对：dav1d 的 `r[-1][bx]` 指的是
**块正上方那一列的 4x4 unit**，而我在 `av1_warp_matching_masks` 里对
`top_mask == 1` 的单点情形用了 `off = mi_col & (aw4 - 1)` 取邻居——若该邻居
比我方块宽，off 的算法会把采样点放到块外，dav1d 此时走的是 `else` 分支
（逐位循环）而不是单点分支。逐行对一遍 `derive_warpmv` 的两个分支条件即可。

# 第七十九次推进补充（2026-09-23，分支判据改成 dav1d 的 mask 规则；分歧点锁定在 (12,12)）

## 一、已落地的改动（保留）

`av1_read_motion_mode` 的"读三符号还是读 use_obmc"判据，从 spec 的
`find_warp_samples != 0` 改为 **libdav1d 的规则**：`find_matching_ref` 的
`(mask[0] | mask[1]) != 0`。规范 §5.11.27 用 NumSamples，但两者会分歧
（一个块可以有 warp 候选而 matching masks 为空），dav1d 是参考解码器，
所以以它的规则为准。三目标 1264/1264 保持全绿。

## 二、分歧点（很窄，尚未修）

我方 inter 帧读到的四个 LOCALWARP 符号（r=48256 / 34764 / 39948 / 52180）
与 dav1d 的四个逐一对应 ✓；但我方在 **mi(12,12)** 还多读了一个（r=61808），
dav1d 在对应块**不读** motion_mode 符号。

⇒ 符号流从 (12,12) 开始分叉，这正是坏区 (48,6)/(48,7) 所在的块。
⇒ 我方在该块读符号，说明我方的"可 overlappable 邻居 + matching mask"非空；
   dav1d 不读，说明它的 refmvs 网格里该块的邻域状态与我方不同。
⇒ 而 (12,12) 之前的块全都对上（包括它的左邻 (10,12) 与上邻 (8,12)），
   所以差异出在**某个早前块写入邻域状态的规则**上——最可能是
   `av1_motion_field_store` 与 dav1d `refmvs_save` 的差异（例如
   sub-8x8 块或 skipped 块的 ref 是否写入、以及第二参考写 -1 的时机）。

## 三、下一轮入口

在 `av1_motion_field_store` 打印每次写入的 (row, col, w4, h4, ref0, ref1,
mv0)，与 dav1d 的 refmvs 写入点对拍（dav1d 在 decode_b 尾部经
`case_set`/`splat_mv` 写 spatial refmvs；先查 (10,12) 这个 16x8 块）。
若我方多写了某格（例如把 skipped 块的 ref 也写进去而 dav1d 只在
`!b->skip` 时写），就会让 (12,12) 的上邻被判成同参考。
