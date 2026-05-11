# xs_enc_image() 逐行解析

文件: `libjxs/src/xs_enc.c:216-286`

这是 JPEG XS 编码器的核心入口函数。它接收一幅图像，经过完整的 8 步管道，
生成 JPEG XS 码流。

---

## 函数签名

```c
bool xs_enc_image(
    xs_enc_context_t* ctx,     // 编码器上下文（包含 ids, precinct, rate_control 等）
    xs_image_t* image,         // 输入图像（将被就地修改！）
    void* codestream_buf,      // 输出缓冲区（存放生成的 .jxs 码流）
    size_t codestream_buf_byte_size,  // 输出缓冲区大小（字节）
    size_t* codestream_byte_size      // 实际生成的码流大小（输出参数）
);
```

## 逐段解析

### 第 1 段：初始化和头部写入 (L218-233)

```c
rc_results_t rc_results;    // 码率控制的结果：包含 GTLI 表、选中的方法等
int slice_idx   = 0;        // slice 索引计数器
int markers_len = 0;        // 头部标记消耗的比特数

// 检查输出缓冲区是否足够大
// 对于非 MLS 模式，缓冲区必须 >= 目标码流大小
if ((ctx->xs_config->bitstream_size_in_bytes != (size_t)-1) &&
    (codestream_buf_byte_size / 8) * 8 < ctx->xs_config->bitstream_size_in_bytes) {
    // 缓冲区太小，报错
    return false;
}

// 初始化比特打包器，指向输出缓冲区
bitpacker_set_buffer(ctx->bitstream, codestream_buf, (int)codestream_buf_byte_size);

// 写入码流头部标记：
//   SOC (Start of Codestream)
//   SIZ (Image and component size)
//   COD (Coding style default)
//   QCD (Quantization default)
//   等等...
// header_len 是头部消耗的比特数
const int header_len = xs_write_head(ctx->bitstream, image, ctx->xs_config);
```

### 第 2 段：列码率分配 (L235-239)

```c
// 根据总码流大小，计算每列的码率预算
// 预算按列均匀分配（最后一列可能不同）
if (!_xs_enc_init_column_rates(ctx, image->width, image->height, header_len)) {
    // 预算不够，报错
    return false;
}
```

### 第 3 段：全图正向变换 (L241-243) ⭐ 核心

```c
/*
 * 这三行是 JPEG XS 压缩的核心变换链。
 * 它们按顺序修改 image 缓冲区：
 *
 * 变换前: image->comps_array[c] 存储像素值 (0..255 对于 8-bit)
 * NLT 后: DC 电平偏移后的值（可能为负）
 * MCT 后: RCT 去相关（RGB→YUV-like），MCT 可能改变分量数
 * DWT 后: 小波系数（LL 子带 + 各级 HL/LH/HH 子带系数）
 *
 * 每个变换都是数学上可逆的（在适当精度下）。
 */
nlt_forward_transform(image, &(ctx->xs_config->p));
mct_forward_transform(image, &(ctx->xs_config->p));
dwt_forward_transform(&ctx->ids, image);
```

### 第 4 段：Precinct 循环 (L245-278) ⭐ 核心

```c
/*
 * JPEG XS 将小波系数划分为 "precinct"（分区）来处理。
 * 每个 precinct 是一个空间列 × (数行像素) 的矩形区域，
 * 包含所有子带中对应位置的系数。
 *
 * 外层循环: 按 precinct 高度 (ph) 逐行推进
 *   内层循环: 按 precinct 列 (npx) 从左到右处理
 *
 * 这样设计的好处是：只需要缓存 ph 行像素就可以开始编码，
 * 实现了极低的延迟。
 */
for (int line_idx = 0; line_idx < image->height; line_idx += ctx->ids.ph)  // ph ≈ 16-32
{
    const int prec_y_idx = (line_idx / ctx->ids.ph);  // precinct 垂直索引

    for (int column = 0; column < ctx->ids.npx; ++column)  // npx = 列数
    {
        // --- 步骤 4: 提取 precinct 系数 ---
        // 设置当前 precinct 的 y 坐标
        precinct_set_y_idx_of(ctx->precinct[column], prec_y_idx);
        // 从小波系数缓冲区提取当前 precinct 的系数
        // Fq 是分数位，用于保持数学精度
        precinct_from_image(ctx->precinct[column], image, ctx->xs_config->p.Fq);

        // --- 步骤 5: 计算 GCLI ---
        // GCLI = Greatest Coded Line Index
        // 对于每组 N_g=4 个小波系数，计算最高有效位的位置
        // GCLI = BSR(系数组幅度的 OR) + 1
        update_gclis(ctx->precinct[column]);

        // --- 步骤 6: 码率控制 ---
        // 根据目标码率，选择：
        //   - Q (量化级别)
        //   - R (细化级别)
        //   - per-band GTLI (全局截断级别)
        //   - 最优的 GCLI 编码方法 (alphabet × prediction × run)
        if (rate_control_process_precinct(ctx->rc[column],
                                           ctx->precinct[column],
                                           &rc_results) < 0) {
            return false;  // 预算不足，无法编码
        }

        // --- 步骤 7: 量化 ---
        // 根据 rc_results 中的 GTLI 表进行量化
        // GTLI = 5 意味着丢弃最低 5 个比特平面（除以 32）
        // Qpih=0: 死区量化   Qpih=1: 均匀量化
        quantize_precinct(ctx->precinct[column],
                          rc_results.gtli_table_data,
                          ctx->xs_config->p.Qpih);

        // --- 如果这是 slice 的第一个 precinct，写 slice header ---
        // Slice 是一组行的集合，包含 SOS 标记
        if (precinct_is_first_of_slice(ctx->precinct[column],
                                       ctx->xs_config->p.slice_height) && (column == 0))
        {
            markers_len += xs_write_slice_header(ctx->bitstream, slice_idx++);
        }

        // --- 步骤 8: 打包写入码流 ---
        // 将当前 precinct 的数据打包成比特流：
        //   1. GCLI 子包 (GCLI 值和预测残差)
        //   2. 显著性标志子包 (哪些系数是非零的)
        //   3. 数据子包 (系数幅度的 MSB 和细化比特)
        if (pack_precinct(ctx->packer, ctx->bitstream,
                          ctx->precinct[column],
                          &rc_results) < 0) {
            return false;
        }

        if (rc_results.rc_error == 1)
            break;  // 码率控制出错，跳过剩余列
    }
}
```

### 第 5 段：尾部写入和清理 (L280-285)

```c
// 写入 EOC (End of Codestream) 标记
xs_write_tail(ctx->bitstream);

// 验证：对于 CBR 模式，实际码流大小应该等于目标大小
assert((ctx->xs_config->bitstream_size_in_bytes == (size_t)-1) ||
       bitpacker_get_len(ctx->bitstream) / 8 == ctx->xs_config->bitstream_size_in_bytes);

// 返回实际码流大小
*codestream_byte_size = ((bitpacker_get_len(ctx->bitstream) + 7) / 8);
bitpacker_flush(ctx->bitstream);
return true;
```

---

## 数据流动图

```
输入像素 (comps_array)
  │
  ├─ NLT ──→ DC偏移后的值（可为负）
  │
  ├─ MCT ──→ 去相关后的值（RCT: RGB→YUV-like）
  │
  ├─ DWT ──→ 小波系数（LL, HL, LH, HH 子带）
  │
  ├─ precinct_from_image ──→ 按 precinct 分组的系数
  │
  ├─ update_gclis ──→ 每组系数的 GCLI 值
  │
  ├─ rate_control ──→ 选择的 Q, R, GTLI, 方法
  │
  ├─ quantize ──→ 量化后的系数
  │
  └─ pack_precinct ──→ .jxs 码流比特
```

## 关键设计决策

1. **为什么 NLT/MCT/DWT 在整个图像上执行一次，而量化/打包按 precinct 循环？**
   因为 NLT/MCT/DWT 需要完整的空间上下文才能正确计算（特别是 DWT 的多级分解），而一旦进入小波域，每个 precinct 的数据是独立的，可以独立量化和打包。这种设计在大图像上可以实现流水线处理。

2. **为什么 precinct 循环按行推进？**
   这是 JPEG XS 低延迟的关键。编码器只需缓存 `ph` 行（通常 16-32 行）即可开始输出码流，而不是等整个图像处理完。这对于视频传输至关重要。

3. **`ctx->ids` 存储了什么？**
   `ids_t` 包含所有从配置参数推导出的几何信息：precinct 列数 (npx)、列宽、precinct 高度 (ph)、子带数量、每个子带的尺寸等。它在 `ids_construct()` 中计算一次，在整个编码过程中不变。
