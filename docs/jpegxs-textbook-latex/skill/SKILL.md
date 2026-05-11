---
name: jpegxs-textbook-writer
description: Write and maintain the JPEG XS textbook in the ElegantBook-based LaTeX book project with consistent structure, notation, examples, and code-grounded explanations
---

# JPEG XS Textbook Writer Skill

## 触发条件

当用户要求撰写、扩展、校对 JPEG XS 教材章节、算例、公式说明，且目标产物是 LaTeX 教材工程时触发。

本 Skill 不负责“讲 JPEG XS”，只负责“如何稳定地产出这本基于 ElegantBook 的 LaTeX 教材工程”。

版式与初学者写法的额外约束分别见：

- `references/latex-table-and-figure-style.md`
- `references/latex-beginner-writing-style.md`
- `references/textbook-lifecycle-workflow.md`
- `references/textbook-readiness-checklist.md`
- `references/pdf-typesetting-audit.md`（编译后排版质量检查方法论）

默认版式假设：

- 教材工程默认使用 **ElegantBook** 文档类
- 不再以通用 `book` 类为目标
- 新增章节、算例、附录时，应默认兼容 `elegantbook.cls` 的版式与章节风格

默认工作方式：

- 不把教材写作当成“一次性生成文档”，而是走**多轮闭环**：
  1. 建骨架
  2. 写首版
  3. 初学者友好化
  4. 代码正确性修订
  5. 全书一致性验收
  6. 终稿可用性检查
- 详细流程见 `references/textbook-lifecycle-workflow.md`

## 强制模板

每章必须按以下结构写作（详见 `references/chapter-template.md`）：

1. 章节标题与 `\label`
2. 本章目标：3–6 条
3. 背景与标准语义：先讲理论对象和目标
4. 数学定义：统一变量表、公式编号
5. 处理流程：用步骤或子节描述
6. 流程图：优先 TikZ，必要时图片插入
7. 实现映射：统一 LaTeX 表格/盒子环境
8. 代码来源核验：列出关键函数与文件位置
9. Worked Example：给出输入、参数、中间变量、推导、结果
10. 常见误解 / 边界条件
11. 本章小结与下一章连接

如果用户的请求不是“写某一章”，而是“搭教材 / 修教材 / 做一致性检查 / 做终稿验收”，优先按 `references/textbook-lifecycle-workflow.md` 选择当前阶段，而不是直接开始写正文。

## 写作约束

- **语言**：默认中文；变量名、函数名、标准术语保留英文
- **公式**：优先使用标准数学表达式，不直接把 C 代码当公式
- **变量定义**：所有变量首次出现必须在正文或变量表中定义
- **算例**：复杂流程必须带至少一个可复算的整数算例
- **实现映射**：只解释"这份代码怎么实现该理论"，不把教材写成代码注释翻译
- **LaTeX 目标目录**：默认写入 `docs/jpegxs-textbook-latex/`，而不是 `docs/jpegxs-textbook/`
- **默认模板**：默认基于 ElegantBook；除非用户明确要求，不要再为普通 `book` 类单独设计章节样式或封面样式
- **流程图**：每章必须包含至少 1 张可编译的流程图。优先用 TikZ；如图太复杂，可使用静态图片插入，但必须在 README 中说明维护方式
- **源码引用**：LaTeX 正文中统一使用 `\texttt{file.c:123}` 或 `\texttt{func_name()}`，并在“代码来源核验”或“与代码位置对应”环境中集中给出文件与行号
- **源码摘录**：重要函数必须展示实际 C 代码片段（不是伪代码）并附逐段解释（用 ①②③ 标注）。每章至少 2 个源码摘录，放在“数学定义”或“处理流程”节内。核心模块（DWT、码率控制、打包）必须摘录关键循环和边界处理逻辑
- **LaTeX 环境**：优先复用 `preamble.tex` 中已有环境：`examplebox`、`engineeringnote`、`codefact`、`sourcetrace`、`implmap`、`misunderstanding`
- **ElegantBook 兼容性**：新增宏包、标题样式、页面布局、字体设置前，优先确认不会和 `elegantbook.cls` 冲突。不要重新引入一套独立的 chapter/page geometry 方案
- **初学者导向**：参数、变量、缩写必须先解释再使用。Profile / Level / Sublevel、GCLI / GTLI、NLT / MCT / DWT 等术语首次出现时要有“这是什么/为什么需要它”的说明
- **排版健壮性**：提交前必须关注 `main.log` 中的 `Overfull \hbox` / `Overfull \vbox`，但 **overfull 警告不会报告列间文字重叠和节点文字溢出**——必须额外执行视觉/脚本检查。具体检查方法见 `references/pdf-typesetting-audit.md`
- **内容保护**：修改已有章节时默认"增补优先"，不得删除前文已有的重要概念、算例、公式、图，除非新版本完整覆盖并保留等价信息
- **表格与插图风格**：遵循 `references/latex-table-and-figure-style.md`，优先使用可换行列、统一 TikZ 节点样式、避免整体缩放掩盖问题
- **初学者写作风格**：遵循 `references/latex-beginner-writing-style.md`，确保变量先定义、概念先解释、再进入公式和实现细节

## 符号体系

严格遵循 `references/notation-style.md` 中定义的符号。新增变量必须先更新该文件。

## 算例格式

遵循 `references/worked-example-rules.md` 中定义的算例结构：

1. 输入条件
2. 已知参数
3. 中间变量表
4. 逐步计算
5. 最终结果
6. 与代码位置对应

## 生命周期流程

教材的推荐工作流不是线性写完，而是阶段化闭环：

1. **Phase 0 — 约束冻结**：明确读者、源码真值、模板、命名、符号
2. **Phase 1 — 工程骨架**：搭主工程、章节/算例/附录结构、可编译最小版本
3. **Phase 2 — 首版内容生成**：先把主线讲全，再补公式和实现映射
4. **Phase 3 — 初学者友好化**：补直觉、最小例子、变量定义、如何读表
5. **Phase 4 — 内容正确性修订**：逐章对代码核验，修错误概括、错公式、错单位、错机制
6. **Phase 5 — 全书一致性审校**：检查主文、算例、trace、notes 是否同步
7. **Phase 6 — 可用性验收**：确认“说明清楚、说明白、说得对”

具体执行办法见：

- `references/textbook-lifecycle-workflow.md`
- `references/textbook-readiness-checklist.md`

## 代码映射格式

```tex
\begin{implmap}
\begin{tabularx}{\textwidth}{@{}l l l X@{}}
\toprule
标准概念 & 入口文件 & 关键函数/结构 & 说明 \\
\midrule
XXX & \texttt{xxx.c:123} & \texttt{xxx\_func()} & 一句话说明 \\
\bottomrule
\end{tabularx}
\end{implmap}
```

详见 `references/repo-mapping-guide.md`。

## 代码事实 vs 推断标注

- **代码直接事实**（变量名、循环、分支、位移等）：正常叙述，并在附近的 `codefact` / `sourcetrace` 环境中给出文件与行号
- **实现推断 / 工程解释**（设计意图、cache 友好性、硬件适配等）：优先放入 `engineeringnote` 环境，或在句首标 `工程解释：` / `实现推断：`

详见 `references/repo-mapping-guide.md` 的"代码直接事实 vs 实现推断"节。

## 产物路径

- 主工程：`docs/jpegxs-textbook-latex/main.tex`
- 公共样式：`docs/jpegxs-textbook-latex/preamble.tex`
- 章节：`docs/jpegxs-textbook-latex/chapters/XX-*.tex`
- 算例：`docs/jpegxs-textbook-latex/examples/*-worked-examples.tex`
- 附录：`docs/jpegxs-textbook-latex/appendices/*.tex`
- README：`docs/jpegxs-textbook-latex/README.md`

## 文件命名

- 章节：`00-notation.tex` 到 `15-notes.tex`
- 算例：`nlt-worked-examples.tex`, `dwt-worked-examples.tex` 等

## 额外检查

完成章节或算例修改后，优先自检：

1. 是否符合 `preamble.tex` 的现有环境和样式
2. 是否新增了初学者难以理解但未定义的变量
3. 是否有过宽表格、过宽公式、过宽代码块
4. 是否需要在 `README.md` 中补充新的维护说明
5. 是否符合 `references/latex-table-and-figure-style.md` 的版式约束
6. 是否符合 `references/latex-beginner-writing-style.md` 的初学者导向约束
7. 是否与 ElegantBook 当前样式兼容，尤其是标题、字体、盒子和页边距
8. 是否符合当前生命周期阶段的目标，而不是提前/滞后处理错误类型
9. 若已到修订后期，是否通过 `references/textbook-readiness-checklist.md` 的终稿前检查
10. **编译后必须执行** `references/pdf-typesetting-audit.md` 中的 6 步检查：枚举流程图 → 枚举表格 → 检查 tcolorbox breakable → 检查菱形节点 → 检查分支重叠 → 检查 overfull 趋势。**禁止对审计搜索使用 `head` 截断**
