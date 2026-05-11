# 仓库映射指南（ElegantBook / LaTeX 版）

本文件默认假设教材工程使用 **ElegantBook** 文档类。因此，源码映射不仅要正确，还要兼顾书籍式排版的稳定性与可读性。

## 代码根目录

`/Users/silas/Desktop/code/VideoCompress/jpegxs/libjxs/src/`

## 核心文件速查

### 编解码器入口

| 文件 | 用途 |
|------|------|
| `xs_enc.c` | 编码器主逻辑 |
| `xs_dec.c` | 解码器主逻辑 |

### 算法模块

| 文件 | 对应章节 | 核心函数 |
|------|---------|---------|
| `nlt.c` | 04 NLT | `nlt_forward_transform()`, `nlt_inverse_transform()` |
| `mct.c` | 05 MCT | `mct_forward_transform()`, `mct_inverse_transform()` |
| `dwt.c` | 06 DWT | `dwt_forward_transform()`, `dwt_inverse_transform()` |
| `precinct.c` | 07 Precinct | `precinct_from_image()`, `update_gclis()` |
| `gcli_methods.c` | 08 GCLI | `gcli_method_get_enabled()` |
| `rate_control.c` | 09 码率控制 | `rate_control_process_precinct()`, `_do_rate_allocation()` |
| `sb_weighting.c` | 10 量化 | `compute_gtli_tables()` |
| `quant.c` | 10 量化 | `quant()`, `dequant()`, `deadzone_dq()`, `uniform_dq()` |
| `packing.c` | 11 打包 | `pack_precinct()`, `unpack_precinct()` |
| `bitpacking.c` | 11 打包 | `bitpacker_write()`, `bitunpacker_read()` |
| `xs_markers.c` | 11 Marker | `xs_write_head()`, `xs_parse_head()` |

### 配置与辅助

| 文件 | 用途 |
|------|------|
| `xs_config.c` | Profile/Level/Sublevel 表、参数校验 |
| `ids.c` | 子带/precinct 空间索引构建 |
| `budget.c` | 预算计算辅助函数 |
| `pred.c` | GCLI 预测（垂直/无预测） |
| `sig_flags.c` | 显著性标志编码 |

### 公共头文件

| 文件 | 用途 |
|------|------|
| `libjxs.h` | 所有公共类型和 API |
| `common.h` | 内部通用宏和类型 |

## 映射格式

在 LaTeX 章节正文中优先使用 `implmap` 环境，入口文件列使用 `\texttt{file.c:line}`，并配合 `codefact` / `sourcetrace` 环境补充来源。

在 ElegantBook 下，源码映射表应遵循：

- 风格上服从 ElegantBook 的表题、浮动体和版心约束
- 内容上保留“标准概念 -> 入口文件 -> 关键函数 -> 说明”的教学结构
- 说明列必须是完整句子，不能退化成开发者速记

```tex
\begin{implmap}
\begin{tabularx}{\textwidth}{@{}l l l X@{}}
\toprule
标准概念 & 入口文件 & 关键函数/结构 & 说明 \\
\midrule
XXX & \texttt{xxx.c:123} & \texttt{xxx\_func()} & 一句话 \\
\bottomrule
\end{tabularx}
\end{implmap}
```

对于长函数名、长说明、多个函数并列，不要使用固定列宽 `llll`，优先使用：

- `tabularx` 的 `X` 列
- `longtable`
- `p{}` / `m{}` 列

避免表格因为长函数名或中文说明超出版心。

如果某张实现映射表对初学者来说过于密集，优先：

1. 拆成两张表
2. 把设计解释移回正文
3. 在表前增加“如何读这张表”的短引导

不要为了塞进一页而压缩到难以阅读。

## 源码引用格式（强制）

LaTeX 教材中默认使用：

```tex
\texttt{func\_name()}
\texttt{file.c:123}
```

并在 `codefact` / `sourcetrace` / 章节正文中明确指出该函数所在文件和行号。

如果确实需要 PDF 内点击跳转，可按需使用：

```tex
\href{run:../../libjxs/src/file.c}{\texttt{file.c:123}}
```

但默认不强制依赖本地文件跳转，避免不同 PDF 阅读器行为不一致。

原则：
- LaTeX 正文以“可读、稳定、可维护”为优先
- 文件与行号必须保留
- 不使用模糊的“某处代码里”表达
- 不为了做局部链接跳转而破坏 ElegantBook 的整体阅读体验

## 代码直接事实 vs 实现推断

教材中涉及源码的描述分为两类，必须加以区分：

### 代码直接事实

可从源码逐字验证的描述。适用于：
- 变量名、函数名、宏名
- 循环顺序、条件分支逻辑
- 位移方向、舍入方式、对齐规则
- 函数调用关系和参数传递
- 数组索引、内存布局

**标记方式**：正常叙述即可，但必须在附近给出文件名、函数名、行号作为依据。

### 实现推断 / 工程解释

从代码行为出发的合理解释，但不是代码字面直接写出的设计意图。适用于：
- "为什么作者这样设计"
- "这样更 cache-friendly"
- "这样更适合硬件实现"
- "这通常意味着..."
- "可以把它理解成..."
- "选择 X 而非 Y 的原因可能是..."

**标记方式**：在句首或段首加标记 `工程解释：` 或 `实现推断：`，让读者知道这是作者的推断而非源码原文。

**示例**：

```tex
\texttt{dwt\_forward\_transform()}（\texttt{dwt.c:161}）先调用垂直变换再调用水平变换。（代码直接事实）

\begin{engineeringnote}
工程解释：先垂直后水平的原因可能是图像按行优先存储，垂直变换时相邻元素间隔较小，cache 命中率更高。
\end{engineeringnote}
```

## 初学者导向要求

在做源码映射时，不要默认读者已经懂参数或术语。尤其是：

- Profile / Level / Sublevel
- GCLI / GTLI
- precinct / packet / subpacket
- `Q`, `R`, `Bw`, `Fq`, `NLx`, `NLy`

应先解释“它控制什么”，再映射到代码。实现映射表是“代码入口索引”，不是概念解释的替代品。

## LaTeX 排版建议

- 实现映射表优先用 `tabularx`
- 章节内长说明优先放入 `X` 列
- 多个函数并列时可拆成两行，避免 overfull
- 修改后应检查 `main.log` 中的 `Overfull \hbox` / `Overfull \vbox`
- 若 ElegantBook 的表题样式、字号或浮动策略需要调整，优先在 `preamble.tex` 中统一处理，不要在单章里局部打补丁
