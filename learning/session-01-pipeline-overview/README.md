# Session 1: JPEG XS 编码管道概览与首次运行

## 学习目标

完成本会话后，你将能够：
1. 构建 libjxs 库和命令行工具
2. 运行编码器和解码器，完成图像→.jxs→图像的完整流程
3. 理解 JPEG XS 编码的 8 步管道
4. 知道每个步骤在哪个 C 源文件中实现

## 预备知识

- 基本的 C 语言知识（指针、结构体、循环）
- 了解图像的基本概念（像素、RGB、位深度）

## 1. JPEG XS 是什么？

JPEG XS (ISO/IEC 21122) 是一种**低延迟、低复杂度的图像/视频压缩标准**。它的设计目标是：

- **极低延迟**：仅几行像素的延迟（不是几帧）
- **低复杂度**：不需要复杂的算术编码，可以在 FPGA/ASIC 上高效实现
- **视觉无损**：在高码率下人眼无法察觉压缩痕迹
- **固定码率 (CBR)**：适合视频传输链路（如 SDI、DisplayPort 替代方案）

## 2. 编码管道总览

JPEG XS 编码器将输入图像经过以下 8 个步骤，最终生成 .jxs 码流：

```
输入图像 (xs_image_t)
    |
    |-- [预处理] Bayer 解复用（仅 Bayer 图像）
    |
    v
  ┌─────────────────────────────────────┐
  │ 步骤 1: NLT  (非线性变换)           │  nlt.c
  │   压缩高光，更好地利用比特深度      │
  ├─────────────────────────────────────┤
  │ 步骤 2: MCT  (多分量变换)           │  mct.c
  │   RCT 色彩去相关 (RGB→类似YCgCo)    │
  ├─────────────────────────────────────┤
  │ 步骤 3: DWT  (离散小波变换)         │  dwt.c
  │   5/3 提升小波，多级分解           │
  ├─────────────────────────────────────┤
  │   以上 3 步对整个图像执行一次        │
  │   以下步骤按 precinct 逐块循环执行   │
  ├─────────────────────────────────────┤
  │ 步骤 4: 提取 precinct 系数          │  precinct.c
  │   将小波系数按空间列分组            │
  ├─────────────────────────────────────┤
  │ 步骤 5: 计算 GCLI                   │  precinct.c
  │   每个系数组的最高有效比特平面      │
  ├─────────────────────────────────────┤
  │ 步骤 6: 码率控制                    │  rate_control.c
  │   选择 Q, R, GCLI 方法              │
  ├─────────────────────────────────────┤
  │ 步骤 7: 量化                        │  quant.c
  │   根据 GTLI 截断比特平面            │
  ├─────────────────────────────────────┤
  │ 步骤 8: 打包写入码流                │  packing.c
  │   组装成 protocol packet            │
  └─────────────────────────────────────┘
    |
    v
  .jxs 码流文件
```

### 关键设计理念

JPEG XS 与传统 JPEG 的根本区别：

| 特性 | 传统 JPEG | JPEG XS |
|------|----------|---------|
| 变换 | 8×8 DCT | 5/3 提升小波 (DWT) |
| 熵编码 | Huffman / 算术编码 | GCLI + 比特平面编码 |
| 延迟 | 8 行以上 | 可低至 ~32 行 |
| 码率控制 | 通过量化表间接 | 直接搜索 Q/R 参数 |

## 3. 核心代码阅读

### 3.1 编码器主循环 (`xs_enc.c:216-286`)

打开 `libjxs/src/xs_enc.c`，找到 `xs_enc_image()` 函数。这个函数是整个编码过程的核心编排者。

**关键代码段 1 — 全图变换（L241-243）：**
```c
nlt_forward_transform(image, &(ctx->xs_config->p));
mct_forward_transform(image, &(ctx->xs_config->p));
dwt_forward_transform(&ctx->ids, image);
```
这三行对整个图像执行了前三大变换。注意它们**修改图像缓冲区本身**（in-place），输入是像素值，输出是小波系数。

**关键代码段 2 — precinct 循环（L245-278）：**
```c
for (int line_idx = 0; line_idx < image->height; line_idx += ctx->ids.ph)
{
    for (int column = 0; column < ctx->ids.npx; ++column)
    {
        precinct_from_image(...);            // 步骤 4: 提取系数
        update_gclis(...);                   // 步骤 5: 计算 GCLI
        rate_control_process_precinct(...);  // 步骤 6: 码率控制
        quantize_precinct(...);              // 步骤 7: 量化
        pack_precinct(...);                   // 步骤 8: 打包
    }
}
```

`ctx->ids.ph` = Precinct Height（通常 16-32 行），`ctx->ids.npx` = 水平方向的 precinct 列数。内层循环每次处理一个 precinct（一个空间列），外层循环逐行推进。这保证了**行级低延迟**。

### 3.2 解码器主循环 (`xs_dec.c:227-305`)

解码器是编码器的**精确镜像**。找到 `xs_dec_bitstream()`：

```c
// 逆向 precinct 循环 (L241-282):
for (line_idx...) {
    for (column...) {
        unpack_precinct(...);     // 解包
        dequantize_precinct(...); // 反量化
        precinct_to_image(...);   // 写回图像
    }
}

// 逆向全图变换 (L284-286):
dwt_inverse_transform(&ctx->ids, image_out);
mct_inverse_transform(image_out, &(ctx->xs_config->p));
nlt_inverse_transform(image_out, &(ctx->xs_config->p));
```

注意 **解码器的变换顺序与编码器完全相反**，并且解码时是先 unpack 再逆变换，而编码时是先正变换再 pack。

### 3.3 图像数据结构 (`libjxs.h:274-284`)

```c
typedef struct xs_image_t {
    int ncomps;                          // 分量数 (1=灰度, 3=RGB, 4=RGB+alpha)
    int width, height;                   // 图像尺寸
    int sx[MAX_NCOMPS], sy[MAX_NCOMPS]; // 每个分量的亚采样比例
    int depth;                           // 位深度 (8, 10, 12, 16)
    xs_data_in_t* comps_array[MAX_NCOMPS]; // 每个分量的像素数据指针
};
```

## 4. 动手练习

### 练习 1a: 构建项目

```bash
cd /Users/silas/Desktop/code/VideoCompress/jpegxs/.build/debug
# 如果之前没有构建过：
cmake ../.. -DCMAKE_BUILD_TYPE=Debug
make -j$(sysctl -n hw.ncpu)

# 验证构建成功
./bin/jxs_encoder --help 2>&1 || ./bin/jxs_encoder -v 2>&1
```

### 练习 1b: 创建测试图像并编码

```bash
# 使用 data 目录中的测试图像（如果存在）
ls ../../data/

# 或者使用 Python 创建一个简单的测试图像
python3 -c "
import struct
w, h = 64, 64
with open('/tmp/test_64x64.ppm', 'wb') as f:
    f.write(f'P6\n{w} {h}\n255\n'.encode())
    for y in range(h):
        for x in range(w):
            r = (x * 4) % 256
            g = (y * 4) % 256
            b = ((x + y) * 2) % 256
            f.write(struct.pack('BBB', r, g, b))
print('Created /tmp/test_64x64.ppm')
"

# 编码到 4 bpp
./bin/jxs_encoder -c "profile=Main444.12;rate=4" /tmp/test_64x64.ppm /tmp/test_64x64.jxs
```

### 练习 1c: 解码并对比

```bash
# 解码
./bin/jxs_decoder -D /tmp/test_64x64.jxs /tmp/test_64x64_decoded.ppm

# 查看配置
./bin/jxs_decoder -D /tmp/test_64x64.jxs

# 对比原始和解码文件的差异
python3 -c "
with open('/tmp/test_64x64.ppm', 'rb') as f1, open('/tmp/test_64x64_decoded.ppm', 'rb') as f2:
    data1 = f1.read()
    data2 = f2.read()
diffs = sum(1 for a, b in zip(data1, data2) if a != b)
print(f'Different bytes: {diffs} / {len(data1)}')
print(f'Match: {diffs == 0}')
"
```

### 练习 1d: 尝试不同参数

```bash
# 尝试不同码率
for rate in 1 2 4 8; do
    ./bin/jxs_encoder -c "profile=Main444.12;rate=$rate" /tmp/test_64x64.ppm /tmp/test_${rate}bpp.jxs
    echo "Rate ${rate} bpp: $(wc -c < /tmp/test_${rate}bpp.jxs) bytes"
done
```

### 练习 1e: 追踪函数调用链

阅读 `xs_enc.c` 并回答：
1. `xs_enc_init()` 中创建了哪些对象？（L97-134）
2. `_xs_enc_init_column_rates()` 做了什么？（L170-214）
3. 编码管道中，哪 3 个变换在 precinct 循环之外？哪 5 个步骤在循环之内？
4. 为什么解码器的逆变换调用顺序是 DWT → MCT → NLT？

## 5. 本会话关键文件

| 文件 | 作用 | 行数 |
|------|------|------|
| `libjxs/src/xs_enc.c` | 编码器编排 | 287 |
| `libjxs/src/xs_dec.c` | 解码器编排 | 318 |
| `libjxs/public/libjxs.h` | 公开 API 和类型 | 324 |
| `libjxs/src/common.h` | 内部类型和宏 | 89 |
| `programs/xs_enc_main.c` | 编码器 CLI 入口 | ~100 |
| `programs/xs_dec_main.c` | 解码器 CLI 入口 | ~100 |

## 6. 下一会话预告

Session 2 将深入配置系统和图像数据模型，理解：
- 配置字符串如何解析为内部参数
- `ids_t` 结构如何描述 precinct 几何
- 图像缓冲区如何在各变换间传递
