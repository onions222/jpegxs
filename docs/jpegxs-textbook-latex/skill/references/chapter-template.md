# 章节模板（ElegantBook / LaTeX 版）

每章必须按以下结构写作。不得跳过任何必选项。目标是生成 `docs/jpegxs-textbook-latex/chapters/*.tex`，并与 `preamble.tex` 的环境保持一致。

默认假设当前教材工程使用 **ElegantBook** 文档类。因此：

- 章节层级、标题风格、目录结构默认服从 ElegantBook
- 不要在章节文件里私自重新定义 chapter/section 的标题样式
- 若需要特殊盒子、表格、流程图风格，应优先通过 `preamble.tex` 与 ElegantBook 共存，而不是在章节内临时覆盖

表格/插图版式约束见 `latex-table-and-figure-style.md`。  
初学者导向写法约束见 `latex-beginner-writing-style.md`。

## 必选结构

### 1. 标题与标签

```tex
\chapter{XX 中文标题（English Title）}\label{ch:xx-name}
```

说明：

- 章节标题默认走 ElegantBook 的原生章标题风格
- 不要在单章里用 `titlesec`、`\titleformat` 等方式局部重写章标题

### 2. 本章目标（3–6 条）

```tex
\section{本章目标}
\begin{itemize}
  \item 理解 ...
  \item 掌握 ...
  \item 学会 ...
\end{itemize}
```

### 3. 背景与标准语义

```tex
\section{背景与标准语义}

（先讲“这是什么”和“为什么需要它”，再讲标准中的定义）
```

对初学者困难章节，建议在这里先补一段“最小直觉”说明，再进入正式定义。

### 4. 数学定义

```tex
\section{数学定义}

\subsection{变量表}
\begin{table}[H]
\centering
\begin{tabularx}{\textwidth}{@{}l l X@{}}
\toprule
符号 & 含义 & 备注 \\
\midrule
$X$ & ... & \texttt{code\_name} \\
\bottomrule
\end{tabularx}
\end{table}

\subsection{公式}
\begin{equation}
...
\label{eq:xx-1}
\end{equation}

公式后跟一句自然语言解释：“这个式子控制了……”

\subsection{整数近似与舍入}

明确写出所有舍入、截断、饱和操作。
```

### 5. 处理流程

```tex
\section{处理流程}

\subsection{编码端}
Step 1: ...
Step 2: ...
...
```

### 5.5 处理流程图

```tex
\begin{figure}[H]
\centering
\begin{tikzpicture}[...]
...
\end{tikzpicture}
\caption{XXX 流程图}
\label{fig:xx-flow}
\end{figure}
```

要求：
- 至少 1 张可编译流程图
- 优先使用 TikZ
- 节点文本允许换行，避免超出版心
- 图中文字过多时，优先缩短节点文案并把解释放回正文
- 流程图节点样式、`text width`、字号和间距应尽量复用 `preamble.tex` 中的统一设置
- 图题、编号和浮动体风格默认服从 ElegantBook，不要局部重写全局 caption 风格

### 6. 实现映射

```tex
\section{实现映射}

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

要求：
- 优先使用 `tabularx` / `longtable` / `p{}` 列，避免 `llll` 固定列导致溢出
- 长函数名和说明必须允许换行
- “入口文件”列写成 `\texttt{file.c:line}`
- 若表中说明列过长，优先拆分表格或将解释挪回正文，而不是整体缩放
- 表格标题、字号和间距应尽量服从 ElegantBook 的整体表格风格；如需调整，优先在 `preamble.tex` 中统一处理

### 6.5 代码来源核验

```tex
\begin{codefact}
本章关键结论依据以下函数：
\begin{itemize}
  \item \texttt{func\_name()} --- \texttt{file.c:123} --- 一句话说明
\end{itemize}
\end{codefact}
```

### 7. Worked Example

```tex
\section{算例}

详见附录中的相关算例；如本章较难，正文中至少保留一个最小示例。
```

### 8. 常见误解

```tex
\section{常见误解}

\begin{misunderstanding}
\begin{enumerate}
  \item \textbf{“...”} --- 解释为什么不对
\end{enumerate}
\end{misunderstanding}
```

### 8.5 章节衔接

```tex
\section{与前后章衔接}

\begin{itemize}
  \item \textbf{输入}：本章的输入数据来自第 XX 章的输出（具体说明）
  \item \textbf{输出}：本章的输出数据将被第 XX 章使用（具体说明）
\end{itemize}
```

### 9. 本章小结与下一章连接

```tex
\section{本章小结}

（1-2 段总结本章要点）

下一章将讲解...
```

## 初学者导向要求

- 变量必须在首次出现附近定义，不能只在附录出现
- Profile / Level / Sublevel、GCLI / GTLI、NLT / MCT / DWT 等术语首次出现时，要先解释“它是什么 / 它控制什么”
- 对难章节建议增加“最小直觉例子”
- 对不是源码直接事实的设计解释，应使用 `engineeringnote` 环境或句首标 `工程解释：` / `实现推断：`
- 章节正文应优先遵循“直觉 -> 目标问题 -> 最小例子 -> 正式定义 -> 数学表达 -> 实现映射”的节奏

## 可选结构

- “边界条件”（如果某章有较多边界情况）
- “扩展阅读”（引用标准条款号）
- “参数如何读表”（特别适合配置章节）

## 公式编号

- 使用 LaTeX 自动编号
- 每章内公式应用 `\label` 便于交叉引用
- 公式后必须跟一句中文解释

## 排版检查

完成章节后自检：

1. 是否出现过宽表格
2. 是否出现图中文字超界
3. 是否有超长公式需要 `align` / `split`
4. 是否需要在 `main.log` 中检查 overfull/underfull 报告
5. 是否满足 `latex-beginner-writing-style.md` 中对变量定义和最小例子的要求
6. 是否与 ElegantBook 的标题、浮动体、页边距和字体风格兼容
