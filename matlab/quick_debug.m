% quick_debug.m
%
% 一个“开箱即跑”的 MATLAB 调试脚本。
%
% 适合做这几类事情：
%   1. 读一张 ppm，直接编码成 .jxs
%   2. 读一个 .jxs，直接解码成 bmp/ppm
%   3. 做一次 MATLAB encode -> MATLAB decode 的 roundtrip
%   4. 调用仓库里现成的 bit-exact 验证
%
% 用法：
%   - 直接在 MATLAB 里打开这个脚本
%   - 只改“用户配置区”的几个变量
%   - 点击 Run 即可
%
% 推荐第一次先用：
%   mode   = "roundtrip";
%   preset = "input";

%% 用户配置区

mode = "roundtrip";
% 可选：
%   "encode_only"    只编码
%   "decode_only"    只解码
%   "roundtrip"      编码后立刻再解码
%   "verify_preset"  调用 verify_bitexact(preset)

preset = "input";
% 可选：
%   "input"
%   "debug_input"
%   "custom"

% 当 preset="custom" 时，下面这些字段会被真正使用。
custom_input_ppm = "/Users/silas/Desktop/code/VideoCompress/jpegxs/samples/input.ppm";
custom_input_jxs = "output/custom_input.jxs";
custom_bitstream_size_in_bytes = uint64(1103754);
custom_level = NaN;
custom_sublevel = NaN;

% 输出路径。
% 为空字符串时，脚本会自动根据 preset/mode 生成默认路径。
output_jxs = "";
output_bmp = "";
output_ppm = "";

% 调试开关。
write_decode_ppm = true;
print_config_summary = true;

%% 环境初始化

script_path = mfilename('fullpath');
matlab_dir = fileparts(script_path);
repo_root = fileparts(matlab_dir);

cd(matlab_dir);
addpath(genpath(matlab_dir));

fprintf('=== MATLAB JPEG XS Quick Debug ===\n');
fprintf('mode   = %s\n', mode);
fprintf('preset = %s\n', preset);

cfg = build_run_config(repo_root, preset, ...
    custom_input_ppm, custom_input_jxs, ...
    custom_bitstream_size_in_bytes, custom_level, custom_sublevel, ...
    output_jxs, output_bmp, output_ppm);

%% 主执行

switch char(mode)
    case 'verify_preset'
        fprintf('Run verify_bitexact("%s") ...\n', cfg.verify_preset);
        verify_bitexact(cfg.verify_preset);

    case 'encode_only'
        im = load_ppm_as_image(cfg.input_ppm);
        xs_cfg = build_xs_config(im, cfg.bitstream_size_in_bytes, cfg.level, cfg.sublevel);
        if print_config_summary
            print_cfg(xs_cfg);
        end
        bs = jpegxs_encode(clone_image(im), xs_cfg);
        write_bytes(cfg.output_jxs, bs);
        fprintf('Encoded JXS written to:\n  %s\n', cfg.output_jxs);
        fprintf('Bytes: %d\n', numel(bs));

    case 'decode_only'
        bs = read_bytes(cfg.input_jxs);
        im_dec = jpegxs_decode(bs);
        rgb_out = image_to_rgb(im_dec);
        imwrite(rgb_out, cfg.output_bmp, 'bmp');
        fprintf('Decoded BMP written to:\n  %s\n', cfg.output_bmp);
        if write_decode_ppm
            imwrite(rgb_out, cfg.output_ppm, 'ppm');
            fprintf('Decoded PPM written to:\n  %s\n', cfg.output_ppm);
        end

    case 'roundtrip'
        im = load_ppm_as_image(cfg.input_ppm);
        xs_cfg = build_xs_config(im, cfg.bitstream_size_in_bytes, cfg.level, cfg.sublevel);
        if print_config_summary
            print_cfg(xs_cfg);
        end

        bs = jpegxs_encode(clone_image(im), xs_cfg);
        write_bytes(cfg.output_jxs, bs);
        fprintf('Encoded JXS written to:\n  %s\n', cfg.output_jxs);
        fprintf('Bytes: %d\n', numel(bs));

        im_dec = jpegxs_decode(bs);
        rgb_out = image_to_rgb(im_dec);
        imwrite(rgb_out, cfg.output_bmp, 'bmp');
        fprintf('Decoded BMP written to:\n  %s\n', cfg.output_bmp);
        if write_decode_ppm
            imwrite(rgb_out, cfg.output_ppm, 'ppm');
            fprintf('Decoded PPM written to:\n  %s\n', cfg.output_ppm);
        end

    otherwise
        error('Unknown mode: %s', mode);
end

fprintf('=== Quick Debug Done ===\n');

%% 本地函数

function cfg = build_run_config(repo_root, preset, custom_input_ppm, custom_input_jxs, ...
    custom_size, custom_level, custom_sublevel, output_jxs, output_bmp, output_ppm)

cfg = struct();
cfg.verify_preset = char(preset);

switch char(preset)
    case 'input'
        cfg.input_ppm = fullfile(repo_root, 'samples', 'input.ppm');
        cfg.input_jxs = fullfile(repo_root, 'samples', 'matlab_encoder_output_size1103754.jxs');
        cfg.bitstream_size_in_bytes = uint64(1103754);
        cfg.level = NaN;
        cfg.sublevel = NaN;
        default_tag = 'input';

    case 'debug_input'
        c = jxs.Constants;
        cfg.input_ppm = fullfile(repo_root, 'samples', 'debug_input.ppm');
        cfg.input_jxs = fullfile(repo_root, 'samples', 'debug_output.jxs');
        cfg.bitstream_size_in_bytes = uint64(4096);
        cfg.level = c.XS_LEVEL_1K_1;
        cfg.sublevel = c.XS_SUBLEVEL_9_BPP;
        default_tag = 'debug_input';

    case 'custom'
        cfg.input_ppm = char(custom_input_ppm);
        cfg.input_jxs = char(custom_input_jxs);
        cfg.bitstream_size_in_bytes = uint64(custom_size);
        cfg.level = custom_level;
        cfg.sublevel = custom_sublevel;
        default_tag = 'custom';

    otherwise
        error('Unknown preset: %s', preset);
end

if strlength(string(output_jxs)) == 0
    cfg.output_jxs = sprintf('/private/tmp/%s_quick_debug.jxs', default_tag);
else
    cfg.output_jxs = char(output_jxs);
end

if strlength(string(output_bmp)) == 0
    cfg.output_bmp = sprintf('/private/tmp/%s_quick_debug.bmp', default_tag);
else
    cfg.output_bmp = char(output_bmp);
end

if strlength(string(output_ppm)) == 0
    cfg.output_ppm = sprintf('/private/tmp/%s_quick_debug.ppm', default_tag);
else
    cfg.output_ppm = char(output_ppm);
end
end

function xs_cfg = build_xs_config(im, bitstream_size_in_bytes, level, sublevel)
xs_cfg = jxs.internal.xs_config.default_config();
xs_cfg.bitstream_size_in_bytes = uint64(bitstream_size_in_bytes);
if ~isnan(double(level))
    xs_cfg.level = level;
end
if ~isnan(double(sublevel))
    xs_cfg.sublevel = sublevel;
end
[~, xs_cfg] = jxs.internal.xs_config.resolve_auto_values(xs_cfg, im);
end

function print_cfg(xs_cfg)
fprintf('Resolved config:\n');
fprintf('  profile         = 0x%04x\n', xs_cfg.profile);
fprintf('  level           = 0x%02x\n', xs_cfg.level);
fprintf('  sublevel        = 0x%02x\n', xs_cfg.sublevel);
fprintf('  color_transform = %d\n', xs_cfg.p.color_transform);
fprintf('  slice_height    = %d\n', xs_cfg.p.slice_height);
fprintf('  N_g             = %d\n', xs_cfg.p.N_g);
fprintf('  S_s             = %d\n', xs_cfg.p.S_s);
fprintf('  Bw              = %d\n', xs_cfg.p.Bw);
fprintf('  Fq              = %d\n', xs_cfg.p.Fq);
fprintf('  NLx             = %d\n', xs_cfg.p.NLx);
fprintf('  NLy             = %d\n', xs_cfg.p.NLy);
fprintf('  target_bytes    = %u\n', xs_cfg.bitstream_size_in_bytes);
end

function im = load_ppm_as_image(ppm_path)
require_file(ppm_path);
rgb = imread(ppm_path);
im = jxs.internal.image();
im.ncomps = int32(size(rgb, 3));
im.width = int32(size(rgb, 2));
im.height = int32(size(rgb, 1));
im.depth = int32(8);
im.sx(1:double(im.ncomps)) = int32(1);
im.sy(1:double(im.ncomps)) = int32(1);
im.allocate(true);
for idx = 1:double(im.ncomps)
    im.comps_array{idx} = reshape(int32(rgb(:, :, idx)).', [], 1);
end
end

function out = clone_image(im)
out = jxs.internal.image();
out.ncomps = im.ncomps;
out.width = im.width;
out.height = im.height;
out.depth = im.depth;
out.sx = im.sx;
out.sy = im.sy;
out.allocate(true);
for idx = 1:double(im.ncomps)
    out.comps_array{idx} = im.comps_array{idx};
end
end

function rgb = image_to_rgb(im)
rgb = zeros(double(im.height), double(im.width), double(im.ncomps), 'uint8');
for idx = 1:double(im.ncomps)
    plane = reshape(im.comps_array{idx}, double(im.width), double(im.height)).';
    plane = min(max(plane, 0), 255);
    rgb(:, :, idx) = uint8(plane);
end
end

function bytes = read_bytes(path_in)
require_file(path_in);
fid = fopen(path_in, 'rb');
if fid < 0
    error('Cannot open file for read: %s', path_in);
end
cleanup_obj = onCleanup(@() fclose(fid));
bytes = fread(fid, inf, 'uint8=>uint8')';
end

function write_bytes(path_out, bytes)
fid = fopen(path_out, 'wb');
if fid < 0
    error('Cannot open file for write: %s', path_out);
end
cleanup_obj = onCleanup(@() fclose(fid));
fwrite(fid, bytes, 'uint8');
end

function require_file(path_in)
if exist(path_in, 'file') ~= 2
    error('Required file not found: %s', path_in);
end
end
