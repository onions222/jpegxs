# PDF 排版质量检查方法论

本文件描述在编译后如何系统化检查教材 PDF 的排版问题——重点是流程图文字重叠和表格列溢出。目标是让每次检查都可重现、不遗漏。

## 核心教训：为什么检查会漏

1. **grep 结果被截断**：`grep ... | head -40` 会跳过排在第 40 行之后的结果。审计类搜索**禁止**使用 `head` / `tail` 截断。
2. **凭记忆而非重新扫描**：第二次检查时容易依赖第一次记住的文件列表，漏掉第一次被截断或根本未进入视野的章节。
3. **只读 log 不看视觉**：`Overfull \hbox` 警告只反映整体盒子超界，**不会**报告列间文字重叠（因为列边界是 TeX 内部计算的，文字溢出到相邻列不会产生额外 overfull）。
4. **tcolorbox 不可跨页截断内容**：`tcolorbox` 默认 `breakable=false`。当盒内内容（多个表格 + 流程图）超过一页高度时，底部内容在页边界被**静默截断**，无任何 LaTeX 警告。`Overfull \vbox` 不会报告这个问题。

## 检查步骤（编译后逐项执行）

### Step 1：枚举所有流程图

```bash
# 不加 head 截断
grep -rn '\\begin{tikzpicture}' chapters/ --include="*.tex" | grep -v '\.aux'
```

对找到的**每一个** tikzpicture，检查以下项目：

| 检查项 | 命令 | 关注点 |
|--------|------|--------|
| 菱形节点 | `grep -rn 'diamond' chapters/` | `text width` 是否小于菱形内接区域所需宽度（菱形内接宽度约 = `text_width * 0.7`，取决于 `aspect`） |
| 分支节点间距 | 读源码计算 | `left=1.5cm of X` + `text width=4cm` → 两个分支节点中心距仅 3cm 但盒子各宽 4cm → 重叠 1cm |
| 箭头标签位置 | 看 `node[above/font=` | 标签是否与节点边框或另一条箭头的标签重叠 |
| 对角线穿越 | 看 `\draw (A) -- (B)` | 斜穿另一条垂直流的路径是否经过节点文字区域 |

### Step 2：枚举所有表格

```bash
# 不加 head 截断
grep -rn '\\begin{tabular}' chapters/ --include="*.tex" | grep -v '\.aux'
```

对每个表格，提取列定义并检查：

```bash
# 列出每个表格的列规格（列类型 + 宽度）
grep -n 'begin{tabular}' chapters/XX-file.tex
```

#### 检查矩阵

| 列类型 | `\texttt` 超长会怎样 | 需要修复？ |
|--------|---------------------|-----------|
| `l` / `c` / `r`（自然宽度） | 列自动扩宽。单格文字 > 50 中文字符时整表可能超出纸面 → **文字被截断** | **需检查**：如果任一单元格 > 50 字符，必须改为固定宽度列 |
| `p{3.0cm}` / `L{3.0cm}`（固定宽度） | **文字溢出到右侧列** | **必须修复** |
| `X`（tabularx 弹性列） | 自动换行 | 不需要 |

#### 查找固定宽度列中的长 `\texttt`

```bash
# 找固定宽度表格中的长 typewriter 文本（> 15 字符）
python3 << 'PYEOF'
import re, os
for fname in os.listdir('chapters'):
    if not fname.endswith('.tex'): continue
    content = open(f'chapters/{fname}').read()
    # 移除 implmap（已统一用 \btt）
    content = re.sub(r'\\begin\{implmap\}.*?\\end\{implmap\}', '', content, flags=re.DOTALL)
    for m in re.finditer(r'\\begin\{tabular\}.*?\\end\{tabular\}', content, re.DOTALL):
        if '\\texttt{' in m.group():
            for tt in re.findall(r'\\texttt\{([^}]+)\}', m.group()):
                if len(tt) > 15:
                    print(f'{fname}: {tt[:60]}')
PYEOF
```

#### 查找全自然宽度列中的超长文字（页边溢出）

当表格**所有列**都是 `l`/`c`/`r`（自然宽度）时，如果某个单元格文字超过 50 字符，该列会无限扩宽，导致整表超出纸面，**文字在页面右边界外被截断**。

```bash
# 查找全自然宽度列 + 超长单元格（> 50 字符）
python3 << 'PYEOF'
import re, os
for root, dirs, files in os.walk('.'):
    for f in files:
        if not f.endswith('.tex'): continue
        fpath = os.path.join(root, f)
        content = open(fpath).read()
        for m in re.finditer(r'\\begin\{tabular\}\{(@\{\})?([^}]+)\}', content):
            colspec = m.group(2)
            start = m.end()
            # 判断是否所有列都是 l/c/r（无 p/L/X）
            if re.search(r'[pP廖X]', colspec):
                continue  # 有固定宽度列或 tabularx，跳过
            end_match = content.find('\\end{tabular}', start)
            if end_match == -1: continue
            block = content[start:end_match]
            max_len = 0
            longest = ''
            for row in block.split('\\\\'):
                for cell in row.split('&'):
                    clean = re.sub(r'\\[a-zA-Z]+\{', '', cell)
                    clean = re.sub(r'[{}]', '', clean)
                    clean = re.sub(r'\$[^$]*\$', 'XX', clean)
                    if len(clean) > max_len:
                        max_len = len(clean)
                        longest = clean.strip()[:120]
            if max_len > 50:
                line_num = content[:m.start()].count('\n') + 1
                print(f'{fpath}:{line_num} max_cell={max_len}chars')
                print(f'  >> {longest}')
PYEOF
```

修复方式：将宽列从 `l` 改为 `L{width}`（或其他固定宽度），让文字在列内换行。

### Step 3：检查 tcolorbox 的 breakable 属性

所有自定义 `tcolorbox` 环境必须设置 `breakable`，否则内容超过一页时底部被截断。

```bash
# 检查所有 tcolorbox 定义是否包含 breakable
grep -A6 '\\newtcolorbox{' preamble.tex | grep -v 'breakable'
# 如果有输出 → 该环境缺少 breakable，存在截断风险
```

同时检查是否有内容特别长的盒子（内含多个 `[H]` 表格 + 流程图的 `examplebox` 风险最高）：

```bash
# 找跨度 > 50 行的 tcolorbox 实例
grep -n '\\begin{\(examplebox\|engineeringnote\|codefact\|sourcetrace\|implmap\|misunderstanding\)}' chapters/*.tex
# 对每个匹配，计算到对应 \end 的行数差
```

如果行数差 > 50 且环境缺少 `breakable`，**一定**会在某处被截断。

### Step 4：检查菱形节点的实际可用空间

菱形节点的文字可用高度 ≈ 节点总高度 × 0.5（内接矩形），可用宽度 ≈ `text_width` × 0.7。在 `aspect=2` 的菱形中，如果 `text width=2cm`，实际内接宽度仅约 1.4cm。一段 17 字符的 typewriter 文字（如 `color_transform?`）需要约 3cm，**必然溢出**。

快速判断公式：
- 英文 typewriter 文字所需宽度 ≈ 字符数 × 0.22cm（`\small` 下约 0.18cm）
- 中文字符所需宽度 ≈ 字符数 × 0.45cm（`\small` 下约 0.40cm）
- 菱形节点 `text width` 应 ≥ 所需宽度 × 1.4

### Step 5：检查分支节点是否相互重叠

对每个包含分支（`left=... of` / `right=... of`）的流程图：

1. 取两个相邻分支节点的水平间距 = `left` + `right` 的值
2. 取每个节点的 `text width`
3. 如果 `间距 < text_width`，**节点重叠**，必须修复

修复方式：缩小 `text width`、增大间距、或改用上下堆叠。

### Step 6：检查 overfull 趋势

```bash
# 编译前后对比 overfull 数量
grep -c 'Overfull' main.log
```

- 新增章节后 overfull 不应显著增加（+5 以内可接受）
- 超过 20pt 的 overfull 必须逐条定位并修复

## 修复模式速查

### 表列文字溢出 → `\btt`

在 `preamble.tex` 中已定义：
```latex
\usepackage{seqsplit}
\newcommand{\btt}[1]{\texttt{\seqsplit{#1}}}
```

将固定宽度列中的 `\texttt{long_name}` 替换为 `\btt{long_name}`，允许在任意字符间换行。

### 菱形文字溢出 → 加宽 + 分行

```latex
% 错误
decision/.style={diamond, ..., text width=1.5cm}
\node[decision] {...} {$d < NL_y{-}1$?};

% 正确
decision/.style={diamond, ..., text width=2.8cm, aspect=2.2, font=\footnotesize}
\node[decision] {...} {继续\\Phase 1?};
```

### 分支节点重叠 → 缩节点 + 增间距

```latex
% 错误：4cm 宽节点，间距仅 3cm
\node[block, text width=4cm, left=1.5cm of center] (a) {...};
\node[block, text width=4cm, right=1.5cm of center] (b) {...};

% 正确：3.2cm 宽节点，间距 4cm
\node[block, text width=3.2cm, left=2cm of center] (a) {...};
\node[block, text width=3.2cm, right=2cm of center] (b) {...};
```

### 对角线穿越 → 正交路由

```latex
% 错误：斜穿
\draw[arrow] (right_node) -- (left_node);

% 正确：先下后左
\draw[arrow] (right_node.south) -- ++(0,-0.6) -| (left_node.east);
```

### tcolorbox 内容被截断 → 加 breakable

```latex
% 错误：内容超过一页时底部被截断
\newtcolorbox{examplebox}[1][]{
    colback=exampleframe!8,
    title={Worked Example},
    #1
}

% 正确：加 breakable 允许跨页
\newtcolorbox{examplebox}[1][]{
    colback=exampleframe!8,
    title={Worked Example},
    breakable,
    #1
}
```

**注意**：`#1` 必须在 `breakable` 之后，这样用户仍可通过可选参数覆盖（包括设置 `breakable=false`）。

### 全自然宽度列表格超出页宽 → 改为固定宽度列

```latex
% 错误：所有列都是 l（自然宽度），长文本让列无限扩宽
\begin{tabular}{@{}cll@{}}
\# & 误解 & 正确理解 \\
1 & ``短误解'' & 这段正确理解的文字有 60 多个中文字符，会导致此列撑到 20cm 宽，整表超出 A4 纸面被截断，读者看不到完整内容。 \\
\end{tabular}

% 正确：给长文本列设置固定宽度 L{7.5cm}，文字自动换行
\begin{tabular}{@{}cL{2.5cm}L{7.5cm}@{}}
\# & 误解 & 正确理解 \\
1 & ``短误解'' & 这段正确理解的文字有 60 多个中文字符，现在会在 7.5cm 列宽内自动换行，不会超出纸面。 \\
\end{tabular}
```

### 三路分支 → 左-中-右布局

```latex
% 三分支分别用 below left、below、below right，避免挤在一起
\node[block, below left=1.8cm and 2.2cm of diamond] (left)   {...};
\node[block, below=2cm of diamond]                 (center) {...};
\node[block, below right=1.8cm and 2.2cm of diamond] (right) {...};
```

## 不通过检查的底线标准

以下任一情况出现即判定为未通过：

1. 任何流程图节点的文字超出节点边框，与相邻节点或箭头标签重叠
2. 任何固定宽度表格列（`p{}` / `L{}` / `C{}` / `R{}`）中的 `\texttt{...}` 长度超过列宽且未使用 `\btt{}`
3. 任何全自然宽度列表格（只有 `l`/`c`/`r`）中，任一单元格 > 50 中文字符且未改为固定宽度列
4. 编译后 `Overfull \hbox` > 20pt 且未定位原因
5. 任何 `\newtcolorbox` 环境缺少 `breakable` 属性（会导致跨页内容被截断）
6. 同一问题在多个章节重复出现而只在单章修复（应抽象到 preamble 或全局替换）
