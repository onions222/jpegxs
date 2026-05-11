# 剩余问题修复计划

## 问题 1: PIH 标记解析 — Qpih/Fs/Rm 读错

**现象**: C编码器写 Qpih=1(uniform), Fs=0(joint), Rm=0。MATLAB读到 Qpih=0, Fs=1, Rm=0。

**影响**: 
- Qpih错误 → 反量化用 deadzone 而不是 uniform，系数值完全错误
- Fs错误 → 期望独立符号子包，但 C 编码器把符号嵌入数据子包中

**修复方案**:
1. 用 C 编码器编码一个已知参数的测试图像
2. 用 hexdump 对比 C 编码器写的 PIH 标记和 MATLAB 解析器读的位
3. 逐位验证 PIH 解析器的每个 read() 调用消耗的正确位数
4. 特别检查 `slice_height *= (1<<NLy)` 这行（它不消耗位，但要确认没有意外跳过）

**预计修改文件**: `+jxs/+internal/xs_markers.m` 中的 `parse_picture_header`

---

## 问题 2: Subpkt 0 GCLI 组数差 1 组

**现象**: MATLAB subpkt 0 有 15 个 GCLI 组(60 bits)，C 编码器有 16 组(64 bits)

**影响**: 数据子包错位 4 bits，所有数据位面读的是垃圾

**修复方案**:
1. 在 C 参考代码中加入 printf，dump 出 subpkt 0 每个 band 的 pwb 和 gcli_width
2. 编译运行 C 编码器，获取实际的 band geometry
3. 对比 MATLAB 的 pwb/gcli_width 计算，找到差异的 band
4. 检查 `pwb` 计算公式中 `is_last_column` 和 `sx/sy` 的 1-based offset

**预计修改文件**: `+jxs/+internal/ids.m` 中的 `construct` (pwb 计算部分)

---

## 问题 3: 验证与收尾

**修复方案**:
1. 修复问题 1 和 2 后，运行交叉解码测试
2. 对比 MATLAB 解码输出与 C 解码器输出
3. 如果还有差异，dump 中间值逐 band 对比
4. 清理所有 debug 打印

---

## 执行顺序

```
问题 1 (PIH解析) → 问题 2 (GCLI组数) → 验证
```

问题 1 必须先修，因为 Qpih 影响反量化（系数值），Fs 影响数据子包格式。问题 2 修复后码流对齐应该完全正确。
