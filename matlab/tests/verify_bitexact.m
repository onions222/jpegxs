function verify_bitexact(preset)
if nargin < 1 || strlength(string(preset)) == 0
    preset = "input";
else
    preset = string(preset);
end

script_dir = fileparts(mfilename('fullpath'));
matlab_dir = fileparts(script_dir);
repo_root = fileparts(matlab_dir);

cd(matlab_dir);
addpath(genpath(matlab_dir));

cfgv = get_preset_config(preset, repo_root);
fid = fopen(cfgv.report_path, 'w');
if fid < 0
    error('Cannot open report for write: %s', cfgv.report_path);
end
cleanup_obj = onCleanup(@() fclose(fid)); %#ok<NASGU>

try
    fprintf(fid, 'preset=%s\n', cfgv.name);
    fprintf(fid, 'criterion_1=MATLAB encoded codestream must match C encoded codestream byte-for-byte\n');
    fprintf(fid, 'criterion_2=MATLAB decoding of the C codestream must match C decoding pixel-for-pixel\n');
    fprintf(fid, 'criterion_3=For lossy profiles, roundtrip-to-input equality is NOT required\n');

    require_file(cfgv.input_ppm);
    require_file(cfgv.c_encode_jxs);
    require_file(cfgv.c_encode_ppm);
    if strlength(cfgv.sample_jxs) > 0
        require_file(cfgv.sample_jxs);
    end

    run_smoke_test(fid, 'test_bitpacker', 'ALL PASS');
    run_smoke_test(fid, 'test_transforms', 'ALL TRANSFORMS BIT-EXACT');

    input_im = load_ppm_as_image(cfgv.input_ppm);
    encode_im = clone_image(input_im);

    xs_cfg = jxs.internal.xs_config.default_config();
    xs_cfg.bitstream_size_in_bytes = cfgv.bitstream_size_in_bytes;
    if ~isnan(double(cfgv.level))
        xs_cfg.level = cfgv.level;
    end
    if ~isnan(double(cfgv.sublevel))
        xs_cfg.sublevel = cfgv.sublevel;
    end
    [~, xs_cfg] = jxs.internal.xs_config.resolve_auto_values(xs_cfg, input_im);
    fprintf(fid, 'resolved color_transform=%d level=0x%02x sublevel=0x%02x size=%u\n', ...
        xs_cfg.p.color_transform, xs_cfg.level, xs_cfg.sublevel, xs_cfg.bitstream_size_in_bytes);

    bs = jpegxs_encode(encode_im, xs_cfg);
    write_bytes(cfgv.matlab_jxs, bs);
    fprintf(fid, 'encode_output=%s bytes=%d\n', cfgv.matlab_jxs, numel(bs));

    c_bytes = read_bytes(cfgv.c_encode_jxs);
    if ~isequal(bs, c_bytes)
        report_first_byte_diff(fid, bs, c_bytes, 'matlab_encode_vs_c_encode');
        error('Encoded codestream mismatch for preset %s', cfgv.name);
    end
    fprintf(fid, 'encode_matches_c=1\n');

    decoded_from_c = jpegxs_decode(c_bytes);
    write_image_to_ppm(decoded_from_c, cfgv.matlab_decode_from_c_ppm);
    compare_image_to_ppm(decoded_from_c, cfgv.c_encode_ppm, 'decode_from_c');
    fprintf(fid, 'decode_from_c=%s\n', cfgv.matlab_decode_from_c_ppm);

    if strlength(cfgv.sample_jxs) > 0
        sample_bytes = read_bytes(cfgv.sample_jxs);
        if ~isequal(sample_bytes, c_bytes)
            report_first_byte_diff(fid, sample_bytes, c_bytes, 'sample_jxs_vs_c_encode');
            error('Sample codestream does not match fresh C encode for preset %s', cfgv.name);
        end
        fprintf(fid, 'sample_jxs_matches_c=1\n');

        decoded_sample = jpegxs_decode(sample_bytes);
        write_image_to_ppm(decoded_sample, cfgv.matlab_decode_sample_ppm);
        compare_image_to_ppm(decoded_sample, cfgv.c_encode_ppm, 'decode_sample');
        fprintf(fid, 'decode_sample=%s\n', cfgv.matlab_decode_sample_ppm);
    end

    if cfgv.check_roundtrip_to_input
        input_rgb = imread(cfgv.input_ppm);
        roundtrip_rgb = image_to_rgb(decoded_from_c);
        is_lossless = isequal(input_rgb, roundtrip_rgb);
        fprintf(fid, 'roundtrip_equals_input=%d\n', is_lossless);
    end

    fprintf(fid, 'VERIFY_BITEXACT_OK\n');
    fprintf('VERIFY_BITEXACT_OK\n');
    fprintf('  preset: %s\n', cfgv.name);
    fprintf('  report: %s\n', cfgv.report_path);
    fprintf('  encoded jxs: %s\n', cfgv.matlab_jxs);
    fprintf('  decoded from C: %s\n', cfgv.matlab_decode_from_c_ppm);
    if strlength(cfgv.matlab_decode_sample_ppm) > 0
        fprintf('  decoded sample: %s\n', cfgv.matlab_decode_sample_ppm);
    end
catch ME
    fprintf(fid, 'ERROR:%s\n', ME.message);
    for i = 1:numel(ME.stack)
        fprintf(fid, 'STACK:%s:%d\n', ME.stack(i).file, ME.stack(i).line);
    end
    rethrow(ME);
end
end

function cfgv = get_preset_config(preset, repo_root)
c = jxs.Constants;
cfgv = struct();
cfgv.name = char(preset);
cfgv.sample_jxs = "";
cfgv.matlab_decode_sample_ppm = "";
cfgv.check_roundtrip_to_input = true;

switch char(preset)
    case 'input'
        cfgv.input_ppm = fullfile(repo_root, 'samples', 'input.ppm');
        cfgv.bitstream_size_in_bytes = uint64(1103754);
        cfgv.level = nan;
        cfgv.sublevel = nan;
        cfgv.c_encode_jxs = '/private/tmp/c_encoder_output_size1103754_verify.jxs';
        cfgv.c_encode_ppm = '/private/tmp/c_encoder_output_size1103754_verify.ppm';
        cfgv.matlab_jxs = fullfile(repo_root, 'samples', 'matlab_encoder_output_size1103754.jxs');
        cfgv.matlab_decode_from_c_ppm = '/private/tmp/matlab_decode_from_c_verify.ppm';
        cfgv.report_path = '/private/tmp/matlab_verify_bitexact_report.txt';
    case 'debug_input'
        cfgv.input_ppm = fullfile(repo_root, 'samples', 'debug_input.ppm');
        cfgv.bitstream_size_in_bytes = uint64(4096);
        cfgv.level = c.XS_LEVEL_1K_1;
        cfgv.sublevel = c.XS_SUBLEVEL_9_BPP;
        cfgv.c_encode_jxs = '/private/tmp/debug_input_c_4096_verify.jxs';
        cfgv.c_encode_ppm = '/private/tmp/debug_input_c_4096_verify.ppm';
        cfgv.matlab_jxs = '/private/tmp/debug_input_matlab_4096_verify.jxs';
        cfgv.matlab_decode_from_c_ppm = '/private/tmp/debug_input_matlab_decode_from_c_verify.ppm';
        cfgv.sample_jxs = fullfile(repo_root, 'samples', 'debug_output.jxs');
        cfgv.matlab_decode_sample_ppm = '/private/tmp/debug_input_matlab_decode_sample_verify.ppm';
        cfgv.report_path = '/private/tmp/matlab_verify_bitexact_debug_input_report.txt';
    otherwise
        error('Unknown preset: %s', preset);
end
end

function run_smoke_test(fid, test_name, success_token)
output = evalc(test_name);
fprintf(fid, '=== %s ===\n%s\n', test_name, output);
if ~contains(output, success_token)
    error('%s did not report success token "%s"', test_name, success_token);
end
end

function require_file(path_in)
if exist(path_in, 'file') ~= 2
    error('Required file not found: %s', path_in);
end
end

function im = load_ppm_as_image(ppm_path)
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

function bytes = read_bytes(path_in)
fid = fopen(path_in, 'rb');
if fid < 0
    error('Cannot open file for read: %s', path_in);
end
cleanup_obj = onCleanup(@() fclose(fid)); %#ok<NASGU>
bytes = fread(fid, inf, 'uint8=>uint8')';
end

function write_bytes(path_out, bytes)
fid = fopen(path_out, 'wb');
if fid < 0
    error('Cannot open file for write: %s', path_out);
end
cleanup_obj = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, bytes, 'uint8');
end

function write_image_to_ppm(im, out_path)
rgb = image_to_rgb(im);
imwrite(rgb, out_path, 'ppm');
end

function compare_image_to_ppm(im, ppm_path, label)
actual = image_to_rgb(im);
expected = imread(ppm_path);
if ~isequal(size(actual), size(expected))
    error('%s size mismatch: actual=%s expected=%s', ...
        label, mat2str(size(actual)), mat2str(size(expected)));
end
if isequal(actual, expected)
    return;
end

delta = abs(double(actual) - double(expected));
max_diff = max(delta(:));
idx = find(delta > 0, 1, 'first');
[row, col, ch] = ind2sub(size(delta), idx);
error('%s pixel mismatch at row=%d col=%d ch=%d actual=%d expected=%d max_diff=%d', ...
    label, row, col, ch, actual(row, col, ch), expected(row, col, ch), max_diff);
end

function report_first_byte_diff(fid, lhs, rhs, label)
n = min(numel(lhs), numel(rhs));
idx = find(lhs(1:n) ~= rhs(1:n), 1, 'first');
if isempty(idx)
    idx = n + 1;
end
lhs_val = get_byte(lhs, idx);
rhs_val = get_byte(rhs, idx);
fprintf(fid, '%s first_byte_diff=%d lhs=%d rhs=%d lhs_len=%d rhs_len=%d\n', ...
    label, idx, lhs_val, rhs_val, numel(lhs), numel(rhs));
end

function v = get_byte(bytes, idx)
if idx >= 1 && idx <= numel(bytes)
    v = bytes(idx);
else
    v = -1;
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
