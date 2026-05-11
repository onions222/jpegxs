# 符号风格指南

## 核心原则

1. 全书符号自洽：同一符号在不同章节含义一致
2. 首次出现必须定义
3. 优先使用标准中的符号，除非标准中无定义

## 图像与分量

| 符号 | 含义 | 代码 |
|------|------|------|
| $W$ | 图像宽度 | `width` |
| $H$ | 图像高度 | `height` |
| $C$ | 分量总数 | `ncomps` |
| $c$ | 分量索引 | — |
| $(x, y)$ | 像素坐标 | — |
| $d$ | 样本位深 | `depth` |
| $s_x[c], s_y[c]$ | 子采样因子 | `sx[c], sy[c]` |

## NLT

| 符号 | 含义 | 代码 |
|------|------|------|
| $B_w$ | 内部工作位宽 | `Bw` |
| $F_q$ | 小数位数 | `Fq` |
| $T_1, T_2$ | Extended 阈值 | `T1, T2` |
| $E$ | Extended 斜率控制 | `E` |
| $\sigma, \alpha$ | Quadratic 参数 | `sigma, alpha` |

## MCT

| 符号 | 含义 | 代码 |
|------|------|------|
| $C_{pih}$ | 颜色变换类型 | `color_transform` |
| $C_f$ | Tetrix 滤波器模式 | `Cf` |
| $e_1, e_2$ | Tetrix 加权参数 | `e1, e2` |

## DWT

| 符号 | 含义 | 代码 |
|------|------|------|
| $NL_x$ | 水平分解层数 | `NLx` |
| $NL_y$ | 垂直分解层数 | `NLy` |
| $b$ | 子带索引 | — |
| $S_d$ | DWT 抑制分量数 | `Sd` |

## Precinct & Packet

| 符号 | 含义 | 代码 |
|------|------|------|
| $C_w$ | 列宽 | `Cw` |
| $H_{sl}$ | slice 高度 | `slice_height` |
| $(p_x, p_y)$ | precinct 行列索引 | — |
| $N_g$ | GCLI 组大小 | `N_g` |
| $S_s$ | 显著性标志步长 | `S_s` |

## 量化与码率控制

| 符号 | 含义 | 代码 |
|------|------|------|
| $GCLI$ | 全局 CLI | `gcli` |
| $GTLI$ | 全局截断位位置 | `gtli` |
| $Q$ | 量化参数 | `quantization` |
| $R$ | 细化参数 | `refinement` |
| $B_{total}$ | 总预算 (bits) | — |
| $B_{cbr}$ | CBR 分配预算 | `budget_cbr` |

## 舍入与位运算

- $\lfloor x \rfloor$：向下取整
- $\lceil x \rceil$：向上取整
- $\operatorname{round}(x)$：四舍五入
- $\operatorname{trunc}(x)$：向零截断
- $\operatorname{clip}(x, a, b)$：钳位
- $x \gg n$, $x \ll n$：位移
- $x \mathbin{\&} y$, $x \mid y$：按位与/或

## 新增符号规则

1. 如果标准中已定义，使用标准符号
2. 如果标准中未定义，选择一个不与现有符号冲突的字母
3. 必须同时更新本文件和 `00-notation-and-conventions.md`
