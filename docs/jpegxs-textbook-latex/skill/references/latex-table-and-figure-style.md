# LaTeX 表格与插图风格指南（ElegantBook 版）

本文件用于约束 `docs/jpegxs-textbook-latex/` 中的表格、流程图、实现映射表、源码摘录周边排版。默认假设教材使用 **ElegantBook** 文档类。

目标是：

1. 避免 `Overfull \hbox` / `Overfull \vbox`
2. 保持初学者可读性，而不是只追求“塞得下”
3. 让各章节表格与图的风格一致，避免每章各写各的

## 总原则

- 优先让内容自然换行，不要依赖整体缩放掩盖问题
- 优先在 `preamble.tex` 中定义统一列类型和 TikZ 样式，而不是在单章里反复手写
- 表格、流程图、实现映射表都要以“中文长句能否读清”为标准
- 当内容过多时，优先拆分、分层、移动说明到正文，而不是无节制缩字号
- 优先与 ElegantBook 原生标题、caption、版心和浮动体样式协调，不要额外再造一套独立版式系统

## 表格环境选择

### 推荐顺序

1. `tabularx`
2. `longtable` / `ltablex`
3. `tabular` + `p{}` / `m{}` 列

### 不推荐

- `\begin{tabular}{llll}` 这类固定列宽表格直接承载长中文说明
- 用 `\resizebox{\textwidth}{!}{...}` 作为默认方案
- 为了“模仿别的模板”而在单章局部改写 caption、table spacing 或 page geometry

### 推荐场景

- 实现映射表：优先 `tabularx`，最后一列使用 `X`
- 参数说明表：优先 `tabularx`，说明列使用 `X`
- 跨页长表：优先 `longtable` 或 `ltablex`
- 变量表：列数少时可用 `tabularx`

## 实现映射表规范

实现映射表通常包含：

1. 标准概念
2. 入口文件
3. 关键函数/结构
4. 说明

当前工程统一使用固定列宽 + 可换行 typewriter 的方案：

```tex
\begin{implmap}
\begin{tabular}{@{}L{1.8cm}L{1.5cm}L{3.0cm}L{4.5cm}@{}}
\toprule
标准概念 & 入口文件 & 关键函数/结构 & 说明 \\
\midrule
Precinct 预算汇总 & \btt{precinct\_budget.c:164} & \btt{precinct\_get\_budget()} & 汇总 GCLI、数据、符号和头部开销，生成当前 precinct 的总 bit 预算。 \\
\bottomrule
\end{tabular}
\end{implmap}
```

### 关键：`\btt{}` 命令

`\btt{}` 在 `preamble.tex` 中定义：

```latex
\usepackage{seqsplit}
\newcommand{\btt}[1]{\texttt{\seqsplit{#1}}}
```

**为什么需要它**：`\texttt{long_function_names_with_underscores}` 在 TeX 中被视为一个不可分割的单词（下划线不是断字符）。放在 `p{}` / `L{}` 固定宽度列中时，如果函数名长度超过列宽，文字会**溢出到右侧相邻列**，造成列间重叠。`Overfull \hbox` 警告**不会**报告这种重叠。

**`\btt{}` 的作用**：`\seqsplit` 将文字拆成单个字符并在每个字符间插入 `\allowbreak`，使 typewriter 文字可以在任意字符间换行。

### 使用规则

- 所有 `implmap` 表格的 `\texttt{...}` **必须**替换为 `\btt{...}`
- 任何固定宽度列（`p{}` / `L{}` / `C{}` / `R{}`）中出现长度 > 15 字符的 `\texttt{...}` **必须**使用 `\btt{}`
- 自然宽度列（`l` / `c` / `r`）可以保留 `\texttt{}`，因为列会自动扩宽

### 要求

## 参数说明表规范

初学者最怕“表里全是符号但不知道它们控制什么”。参数说明表至少应包含：

1. 参数名
2. 数学/标准含义
3. 在流程中作用于哪一步
4. 备注或常见误解

推荐模板：

```tex
\begin{table}[H]
\centering
\footnotesize
\begin{tabularx}{\textwidth}{@{}l l X X@{}}
\toprule
参数 & 含义 & 作用阶段 & 备注 \\
\midrule
$NL_x$ & 水平方向小波分解层数 & DWT & 决定水平继续细分到多少层。 \\
\bottomrule
\end{tabularx}
\caption{核心编码参数说明}
\end{table}
```

## 表格排版检查清单

提交前至少检查：

1. 是否出现 `Overfull \hbox`
2. 固定宽度列中的 `\texttt{...}` 是否全部替换为 `\btt{...}`（长度 > 15 字符的必须替换）
3. 是否有列标题过长，适合拆成两行
4. 是否有说明列只剩 1-2 个字符一行
5. 是否可以把部分长解释移到正文
6. 是否应改成跨页长表

## 流程图总原则

- 图只承载“步骤关系”和“关键分支”
- 过长解释放回正文，不要把整段教材塞进节点
- 中文节点文本默认允许换行
- 节点大小、`text width`、`node distance`、字体应统一
- 图的标题、编号与周围留白默认服从 ElegantBook；流程图样式应是“在 ElegantBook 上增补”，而不是与其对抗

## TikZ 节点建议

推荐统一样式放进 `preamble.tex`，例如：

```tex
\tikzset{
  flowbox/.style={
    draw,
    rounded corners,
    align=left,
    text width=0.22\textwidth,
    inner sep=6pt,
    font=\small
  },
  flowarrow/.style={->, thick}
}
```

要求：

- `align` 优先 `left` 或 `center`
- 中文长句的节点一般要给 `text width`
- 若节点文字仍然过长，先缩短文案，再考虑减小字号

## 流程图布局建议

### 适合上下流程

- 编码主链
- 解码逆链
- 预算搜索过程

### 适合左右对照

- 编码 / 解码对照
- 正向 / 逆向变换对照
- 标准概念 / 代码实现对照

### 适合拆分成两张图

- 节点超过 8 个
- 每个节点都需要长句说明
- 同时包含主流程和多个分支

## 图中文字超界时的处理顺序

1. 缩短节点文案
2. 给节点设置合适的 `text width`
3. 调整 `node distance`
4. 拆成两张图
5. 最后才考虑整体缩放

## 图表与正文的分工

图表负责：

- 关系
- 顺序
- 分类
- 对照

正文负责：

- 变量定义
- 数学推导
- 边界条件
- 工程解释

如果一张图承担了太多正文功能，就应回退一部分解释到正文。

## 日志检查

编译后必须查看 `main.log` 中与图表相关的问题：

- `Overfull \hbox`
- `Overfull \vbox`
- TikZ 警告

若问题来自单个表格或单张图，不要只修该处文本，优先想是否需要抽象成模板修复。
