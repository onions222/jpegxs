# MATLAB 使用说明

这份文档说明如何使用当前仓库中的 MATLAB 版 JPEG XS 代码进行：

- 读取图像并转成内部 `jxs.internal.image`
- 调用 `jpegxs_encode` 生成 `.jxs`
- 调用 `jpegxs_decode` 还原图像
- 运行 bit-exact 验证

本文面向“第一次上手这份 MATLAB 代码”的读者，尽量只讲最常用路径。

## 1. 目录结构

MATLAB 相关代码主要在下面这些位置：

- 入口函数：
  - [/Users/silas/Desktop/code/VideoCompress/jpegxs/matlab/jpegxs_encode.m](/Users/silas/Desktop/code/VideoCompress/jpegxs/matlab/jpegxs_encode.m)
  - [/Users/silas/Desktop/code/VideoCompress/jpegxs/matlab/jpegxs_decode.m](/Users/silas/Desktop/code/VideoCompress/jpegxs/matlab/jpegxs_decode.m)
- 内部实现：
  - [/Users/silas/Desktop/code/VideoCompress/jpegxs/matlab/+jxs/+internal](/Users/silas/Desktop/code/VideoCompress/jpegxs/matlab/+jxs/+internal)
- bit-exact 验证：
  - [/Users/silas/Desktop/code/VideoCompress/jpegxs/matlab/helpers/verify_bitexact.sh](/Users/silas/Desktop/code/VideoCompress/jpegxs/matlab/helpers/verify_bitexact.sh)
  - [/Users/silas/Desktop/code/VideoCompress/jpegxs/matlab/tests/verify_bitexact.m](/Users/silas/Desktop/code/VideoCompress/jpegxs/matlab/tests/verify_bitexact.m)
- bit-exact 说明：
  - [/Users/silas/Desktop/code/VideoCompress/jpegxs/matlab/VERIFY_BITEXACT.md](/Users/silas/Desktop/code/VideoCompress/jpegxs/matlab/VERIFY_BITEXACT.md)

## 2. 当前支持范围

当前这套 MATLAB 实现最稳妥的使用方式是：

- 输入图像按 8-bit RGB 处理
- 推荐先用 `ppm` 做输入，因为仓库里的验证样本和脚本都围绕 `ppm`
- 编码输出是内存中的 `uint8` 码流，需要你自己写成 `.jxs`
- 解码输出是 `jxs.internal.image`，可以再转成 `ppm` / `bmp`

当前不建议你假设它支持所有 JPEG XS 特性。尤其要注意：

- `Tetrix/Bayer` 相关路径还没有实现
- 这套验证的核心标准是“与 C 参考一致”，不是“编码解码后一定等于原图”
- 很多 case 本来就是有损的

## 3. 最小使用步骤

在 MATLAB 里先进入 `matlab/` 目录并加路径：

```matlab
cd('/Users/silas/Desktop/code/VideoCompress/jpegxs/matlab');
addpath(genpath(pwd));
```

之后最常见的流程是：

1. 用 `imread` 读入 `ppm`
2. 转成 `jxs.internal.image`
3. 创建配置 `cfg`
4. 调用 `jpegxs_encode`
5. 把得到的 `uint8` 写成 `.jxs`
6. 再调用 `jpegxs_decode`
7. 把解码结果转回 `uint8 RGB`，再 `imwrite`

## 4. 读取 PPM 并转内部格式

`jpegxs_encode` 的输入不是普通 MATLAB 的 `HxWx3 uint8`，而是 `jxs.internal.image`。

最直接的写法如下：

```matlab
rgb = imread('/Users/silas/Desktop/code/VideoCompress/jpegxs/samples/input.ppm');

im = jxs.internal.image();
im.ncomps = int32(size(rgb, 3));
im.width  = int32(size(rgb, 2));
im.height = int32(size(rgb, 1));
im.depth  = int32(8);
im.sx(1:double(im.ncomps)) = int32(1);
im.sy(1:double(im.ncomps)) = int32(1);
im.allocate(true);

for c = 1:double(im.ncomps)
    im.comps_array{c} = reshape(int32(rgb(:, :, c)).', [], 1);
end
```

这里最容易看错的一点是：

- `rgb(:, :, c)` 在 MATLAB 里是按列主序存储
- 内部 `comps_array{c}` 用的是“转置后再拉直”的平铺方式
- 这样是为了和 C 版本的行扫描布局对齐

## 5. 编码示例

### 5.1 使用默认配置编码

```matlab
cfg = jxs.internal.xs_config.default_config();
[~, cfg] = jxs.internal.xs_config.resolve_auto_values(cfg, im);

bs = jpegxs_encode(im, cfg);

fid = fopen('/private/tmp/out.jxs', 'wb');
fwrite(fid, bs, 'uint8');
fclose(fid);
```

这里要注意两件事：

- `default_config()` 只是默认初值
- 真正编码前一定要再跑一次 `resolve_auto_values()`，把 `AUTO` 项补成最终值

### 5.2 指定目标码流大小

如果你希望和 C 一样按目标大小编码，可以这样：

```matlab
cfg = jxs.internal.xs_config.default_config();
cfg.bitstream_size_in_bytes = uint64(1103754);
[~, cfg] = jxs.internal.xs_config.resolve_auto_values(cfg, im);

bs = jpegxs_encode(im, cfg);
```

这也是我们当前大图 bit-exact 验证最常用的方式。

### 5.3 指定 level / sublevel

例如 `debug_input.ppm` 那条小图验证链：

```matlab
c = jxs.Constants;

cfg = jxs.internal.xs_config.default_config();
cfg.bitstream_size_in_bytes = uint64(4096);
cfg.level = c.XS_LEVEL_1K_1;
cfg.sublevel = c.XS_SUBLEVEL_9_BPP;
[~, cfg] = jxs.internal.xs_config.resolve_auto_values(cfg, im);

bs = jpegxs_encode(im, cfg);
```

## 6. 解码示例

先把 `.jxs` 读成 `uint8`：

```matlab
fid = fopen('/private/tmp/out.jxs', 'rb');
bs = fread(fid, inf, 'uint8=>uint8')';
fclose(fid);
```

再解码：

```matlab
im_dec = jpegxs_decode(bs);
```

`jpegxs_decode` 的返回值仍然是 `jxs.internal.image`，不是普通 RGB 数组。

## 7. 解码结果转回 BMP / PPM

把 `jxs.internal.image` 转回 `uint8 RGB` 的常用写法：

```matlab
rgb_out = zeros(double(im_dec.height), double(im_dec.width), double(im_dec.ncomps), 'uint8');

for c = 1:double(im_dec.ncomps)
    plane = reshape(im_dec.comps_array{c}, double(im_dec.width), double(im_dec.height)).';
    plane = min(max(plane, 0), 255);
    rgb_out(:, :, c) = uint8(plane);
end

imwrite(rgb_out, '/private/tmp/out.bmp', 'bmp');
imwrite(rgb_out, '/private/tmp/out.ppm', 'ppm');
```

这里做了两件事：

- 先把内部平铺向量 reshape 回二维图像
- 再裁剪到 `[0, 255]`，转回 `uint8`

## 8. 一条龙示例

下面这段是最常用的“读 PPM -> 编码 -> 保存 JXS -> 解码 -> 保存 BMP”的完整例子：

```matlab
cd('/Users/silas/Desktop/code/VideoCompress/jpegxs/matlab');
addpath(genpath(pwd));

rgb = imread('/Users/silas/Desktop/code/VideoCompress/jpegxs/samples/input.ppm');

im = jxs.internal.image();
im.ncomps = int32(size(rgb, 3));
im.width  = int32(size(rgb, 2));
im.height = int32(size(rgb, 1));
im.depth  = int32(8);
im.sx(1:double(im.ncomps)) = int32(1);
im.sy(1:double(im.ncomps)) = int32(1);
im.allocate(true);

for c = 1:double(im.ncomps)
    im.comps_array{c} = reshape(int32(rgb(:, :, c)).', [], 1);
end

cfg = jxs.internal.xs_config.default_config();
cfg.bitstream_size_in_bytes = uint64(1103754);
[~, cfg] = jxs.internal.xs_config.resolve_auto_values(cfg, im);

bs = jpegxs_encode(im, cfg);

fid = fopen('/private/tmp/example_out.jxs', 'wb');
fwrite(fid, bs, 'uint8');
fclose(fid);

im_dec = jpegxs_decode(bs);

rgb_out = zeros(double(im_dec.height), double(im_dec.width), double(im_dec.ncomps), 'uint8');
for c = 1:double(im_dec.ncomps)
    plane = reshape(im_dec.comps_array{c}, double(im_dec.width), double(im_dec.height)).';
    plane = min(max(plane, 0), 255);
    rgb_out(:, :, c) = uint8(plane);
end

imwrite(rgb_out, '/private/tmp/example_out.bmp', 'bmp');
```

## 9. 如何验证当前 MATLAB 版本是否正确

如果你要验证“MATLAB 是否与 C 参考一致”，不要只看：

- 编码后再解码是否等于原图

因为很多配置是有损的，这个判断会误伤正确实现。

正确做法请直接用仓库里的 bit-exact 工具：

```bash
./matlab/helpers/verify_bitexact.sh input
./matlab/helpers/verify_bitexact.sh debug_input
```

对应详细说明见：

- [/Users/silas/Desktop/code/VideoCompress/jpegxs/matlab/VERIFY_BITEXACT.md](/Users/silas/Desktop/code/VideoCompress/jpegxs/matlab/VERIFY_BITEXACT.md)

## 10. 随机图片回归

如果你想复用我们之前做过的随机图片回归，可以看：

- [/Users/silas/Desktop/code/VideoCompress/jpegxs/matlab/tests/run_random_regression_cases.m](/Users/silas/Desktop/code/VideoCompress/jpegxs/matlab/tests/run_random_regression_cases.m)

它做的是：

- 读取 `samples/random_regression/` 下的 `ppm`
- MATLAB 编码
- MATLAB 解码后写 `bmp`
- 与 C 版本处理后的 `bmp` 做逐像素比较

报告输出在：

- [/private/tmp/random_regression_report.txt](/private/tmp/random_regression_report.txt)

## 11. 常见问题

### 11.1 为什么 `jpegxs_encode` 不是直接收 `rgb`？

因为内部实现是按 C 版本的内存布局和处理顺序移植的。  
直接使用 `jxs.internal.image`，能让 DWT、precinct 抽取、bit-exact 对齐都更直接。

### 11.2 为什么解码结果有时不等于原图？

因为当前很多测试配置本来就是有损的。  
这不代表 MATLAB 实现错了。更关键的是：

- MATLAB 编码结果是否和 C 编码结果一致
- MATLAB 解码结果是否和 C 解码结果一致

### 11.3 为什么一定要先 `resolve_auto_values()`？

因为 `default_config()` 里有不少字段只是 `AUTO` 或占位默认值。  
如果不先 resolve，最终 profile / level / sublevel / 权重表 / color transform 可能都不是实际要用的值。

### 11.4 生成的 `.jxs` / `.bmp` 放哪里比较合适？

建议：

- 临时文件放 `/private/tmp`
- 想保留到仓库里用于回归的样本，放 `samples/`

## 12. 推荐阅读顺序

如果你后面想继续读源码，推荐按这个顺序看：

1. [/Users/silas/Desktop/code/VideoCompress/jpegxs/matlab/jpegxs_encode.m](/Users/silas/Desktop/code/VideoCompress/jpegxs/matlab/jpegxs_encode.m)
2. [/Users/silas/Desktop/code/VideoCompress/jpegxs/matlab/jpegxs_decode.m](/Users/silas/Desktop/code/VideoCompress/jpegxs/matlab/jpegxs_decode.m)
3. [/Users/silas/Desktop/code/VideoCompress/jpegxs/matlab/+jxs/+internal/xs_config.m](/Users/silas/Desktop/code/VideoCompress/jpegxs/matlab/+jxs/+internal/xs_config.m)
4. [/Users/silas/Desktop/code/VideoCompress/jpegxs/matlab/+jxs/+internal/precinct.m](/Users/silas/Desktop/code/VideoCompress/jpegxs/matlab/+jxs/+internal/precinct.m)
5. [/Users/silas/Desktop/code/VideoCompress/jpegxs/matlab/+jxs/+internal/rate_control.m](/Users/silas/Desktop/code/VideoCompress/jpegxs/matlab/+jxs/+internal/rate_control.m)
6. [/Users/silas/Desktop/code/VideoCompress/jpegxs/matlab/+jxs/+internal/packing.m](/Users/silas/Desktop/code/VideoCompress/jpegxs/matlab/+jxs/+internal/packing.m)

这样最容易先建立整体流程，再去看底层位流和预算细节。
