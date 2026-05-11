# 算例写作规范（ElegantBook / LaTeX 版）

本文件默认假设教材工程使用 **ElegantBook** 文档类。算例不仅要数学上正确、可追溯到代码，还要符合书籍式阅读节奏。

## 固定结构

每个算例必须包含以下六个部分，并写入 `docs/jpegxs-textbook-latex/examples/*.tex`：

### 1. 输入条件

明确给出数值输入，不使用符号代替（除非已在变量表中定义）。

### 2. 已知参数

以表格列出所有相关参数及其值。

### 3. 中间变量表

逐步列出计算过程中的中间值，使用表格格式：

| 步骤 | 操作 | 结果 |
|------|------|------|
| 1 | $a + b$ | 15 |
| 2 | $a \times c$ | 20 |

### 4. 逐步计算

每一步写出：
- 公式
- 代入数值
- 计算结果

### 5. 最终结果

明确标出最终结果，使用 `**最终结果**` 标记。

### 6. 与代码位置对应

**每个算例内部**必须包含“与代码位置对应”小节（或等价的 `sourcetrace` 环境），标注该算例验证的关键函数：

```tex
\begin{sourcetrace}
本算例验证 \texttt{func\_name()}（\texttt{file.c:123}）的 Eq.~\eqref{eq:xx} 计算。
\end{sourcetrace}
```

不只是在整份文件末尾统一放代码表——每个重点算例都要有局部对应，让读者能逐例追溯。

每个独立算例文件末尾还应包含"代码位置"总表，列出本文件所有引用的函数：

```tex
\section{代码位置}
\begin{tabularx}{\textwidth}{@{}l l l@{}}
\toprule
操作 & 文件 & 函数 \\
\midrule
XXX & \texttt{xxx.c:123} & \texttt{xxx\_func()} \\
\bottomrule
\end{tabularx}
```

默认使用 `\texttt{file.c:123}`，必要时可使用 `\href` 提供点击跳转，但不是硬性要求。

## 代码事实 vs 推断

- 算例中直接从源码提取的计算步骤（位移、舍入、分支）是**代码直接事实**，正常叙述即可
- 对设计意图、效率优势、硬件适配的解释属于**实现推断**，应标 `工程解释：` / `实现推断：`，或使用 `engineeringnote` 环境
- 详见 `repo-mapping-guide.md` 的"代码直接事实 vs 实现推断"节

## 数值要求

- 优先使用整数输入
- 避免使用需要浮点运算的算例（除非该算法本身就是浮点的）
- 每个算法至少一个完整算例
- 复杂算法（DWT、码率控制、packing）需要多个算例

## 独立文件 vs 章节内

- 简单算例（1-2 步计算）可以放在章节正文中
- 复杂算例（3 步以上计算）必须放入 `examples/` 目录的独立 `.tex` 文件
- 独立算例文件开头应写出对应章节，例如：

```tex
\chapter{DWT 算例}\label{ex:dwt}
对应章节：第~\ref{ch:dwt} 章（DWT）
```

在 ElegantBook 下，建议让算例承担“章节正文之后的递进教学”作用：

- 正文先给最小直觉例子
- 独立算例册再给完整推导
- 不要让第一次出现的核心概念只存在于附录算例里

## LaTeX 建议写法

### 结构建议

```tex
\section{例 X：标题}
\subsection*{输入条件}
...
\subsection*{已知参数}
\begin{table}[H] ... \end{table}
\subsection*{中间变量表}
\begin{table}[H] ... \end{table}
\subsection*{逐步计算}
...
\subsection*{最终结果}
...
\begin{sourcetrace}
...
\end{sourcetrace}
```

### 表格建议

- 参数表优先用 `tabularx`
- 超宽表优先允许换行，不要整体强缩放
- 数值推导表优先列少一点，避免挤压版面
- 表题和浮动体风格默认服从 ElegantBook；若算例表很多，优先统一在 `preamble.tex` 里调整，而不是单个算例局部改样式

### 初学者要求

- 先讲输入是什么，再讲公式
- 公式中的变量在算例附近再次解释，不要只依赖章节主文
- 如果一个算例只是“结构示意”而不是全精确数值推导，要明确写出来
- 算例要读起来像“书中的例题”，而不是调试记录或代码注释翻译

## 算例文件命名

`<模块名>-worked-examples.tex`，例如：
- `nlt-worked-examples.tex`
- `mct-worked-examples.tex`
- `dwt-worked-examples.tex`
- `rate-control-search-examples.tex`
