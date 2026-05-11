# JPEG-XS Textbook (LaTeX · ElegantBook)

基于 **ElegantBook v4.6** 版式的 JPEG XS 编码技术教材工程。

## 版式方案

| 项目 | 说明 |
|------|------|
| 文档类 | **ElegantBook v4.6**（TeX Live 2026 自带） |
| 编译引擎 | **xelatex** |
| 中文支持 | `ctex` (scheme=chinese) + macOS 系统字体 (STSong/STHeiti) |
| 代码排版 | `listings`（自定义 C 语言风格） |
| 流程图 | `TikZ` |

### ElegantBook 来源

- 类文件：`elegantbook.cls`（TeX Live 2026 自带，路径 `tex/latex/elegantbook/`）
- 仓库：<https://github.com/ElegantLaTeX/ElegantBook>
- 许可：LPPL 1.3c
- 本工程**不**自带 ElegantBook 文件，直接使用 TeX Live 发行版中的版本
- 如需本地放置：将 `elegantbook.cls` 放入工程根目录即可覆盖系统版本

## 工程结构

```
docs/jpegxs-textbook-latex/
├── main.tex                           # 主文档（ElegantBook class）
├── preamble.tex                       # 宏包、自定义教学环境、CJK 字体
├── Makefile                           # 构建脚本
├── chapters/
│   ├── 00-notation.tex                # 符号与约定
│   ├── 01-overview.tex                # 概述与设计目标
│   ├── 02-signal-model.tex            # 信号模型、色彩采样与内部精度
│   ├── 03-configuration.tex           # 码流配置：Profile / Level / 参数
│   ├── 04-nlt.tex                     # NLT 非线性变换
│   ├── 05-mct.tex                     # MCT 多分量变换
│   ├── 06-dwt.tex                     # DWT 离散小波变换
│   ├── 07-bands-precincts.tex         # 子带、Precinct、Packet 与渐进
│   ├── 08-gcli.tex                    # GCLI、预测与显著性模型
│   ├── 09-rate-control.tex            # 预算表与码率控制
│   ├── 10-quantization.tex            # 量化、细化与 GTLI 选择
│   ├── 11-packing.tex                 # 打包、Marker 与码流语法
│   ├── 12-decoder.tex                 # 解码器逆向路径与重建
│   ├── 13-special-paths.tex           # 特殊路径：Bayer / Tetrix / Profile
│   ├── 14-end-to-end-trace.tex        # 端到端编码追踪
│   └── 15-notes.tex                   # 实现笔记与常见误解
├── examples/
│   ├── nlt-worked-examples.tex
│   ├── mct-worked-examples.tex
│   ├── dwt-worked-examples.tex
│   ├── precinct-and-band-mapping-examples.tex
│   ├── gcli-gtli-and-budget-examples.tex
│   ├── rate-control-search-examples.tex
│   └── packing-and-marker-examples.tex
├── figures/
├── tables/
└── appendices/
    └── notation-table.tex             # 符号总表
```

## 编译方法

### 前置要求

- **TeX Live 2024+**（或 MacTeX 2024+），需包含 `elegantbook` 宏包
- macOS 中文字体：STSong / STHeiti / STFangsong（系统自带）
- Linux 用户需修改 `preamble.tex` 中的 `\setCJKmainfont` 等配置

### 编译命令

```bash
cd docs/jpegxs-textbook-latex

# 方法 1：Makefile
make

# 方法 2：latexmk
latexmk -xelatex main.tex

# 方法 3：直接调用（需多次编译以解析交叉引用）
xelatex main.tex
xelatex main.tex
```

### 清理

```bash
make clean
```

## 自定义教学环境

以下环境在 ElegantBook 版式之上保留，用于教材特有的教学结构：

| 环境 | 用途 | 颜色 |
|------|------|------|
| `examplebox` | 算例（Worked Example） | 蓝色边框 |
| `engineeringnote` | 工程解释 / 实现推断 | 橙色边框 |
| `codefact` | 代码来源核验 | 绿色边框 |
| `sourcetrace` | 与代码位置对应 | 灰色边框 |
| `implmap` | 实现映射（标准→代码函数） | 紫色边框，\small 字号 |
| `misunderstanding` | 常见误解 | 红色边框 |

所有环境基于 `tcolorbox`，支持 ElegantBook 的 `breakable` 跨页。

## preamble.tex 的设计原则

`preamble.tex` 采用"最小补充"原则：
- **不重复加载** ElegantBook 已经提供的包（amsmath, booktabs, graphicx, tikz, tcolorbox, listings, enumitem, hyperref, geometry, fontspec, ctex 等）
- **补充加载** ElegantBook 未提供的包（mathtools, longtable, tabularx, cleveref, float）
- **覆盖设置** CJK 字体、listings 代码风格、自定义 tcolorbox 教学环境、TikZ 流程图样式

## 迁移历史

- **2026-05-09**：从普通 `book` 类迁移到 ElegantBook v4.6
  - 移除 `fontspec`/`xeCJK` 直接加载（改由 ctex 管理）
  - 移除 `geometry` 和 `titlesec` 的手动配置（ElegantBook 接管版式和章节样式）
  - 移除 `hyperref` 手动配置（ElegantBook 接管超链接样式）
  - 保留所有 6 个自定义 tcolorbox 教学环境
  - 保留 tabularx 列类型和 TikZ 流程图样式

## 技术笔记

### 为什么不使用 minted

minted 需要 Pygments（Python 包）和 `--shell-escape`，增加编译复杂度。ElegantBook 自带的 `listings` 配置足够，且我们在此基础上添加了 C 语言关键字高亮和 CJK 兼容。

### 关于 ElegantBook 选项

| 选项 | 值 | 说明 |
|------|-----|------|
| `lang` | `cn` | 中文界面（目录/图表/定理标题） |
| `color` | `blue` | 蓝色主题色（与教材原有蓝色风格一致） |
| `mode` | `fancy` | tcolorbox 定理盒子风格 |
| `chinesefont` | `nofont` | 不使用 ctex 预设字体，由我们手动设置 |
| `scheme` | `chinese` | "第一章" 格式的章节编号 |
| `titlestyle` | `hang` | 悬挂式章节标题 |
