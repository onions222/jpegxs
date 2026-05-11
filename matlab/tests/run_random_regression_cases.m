function run_random_regression_cases()
cd('/Users/silas/Desktop/code/VideoCompress/jpegxs/matlab');
addpath(genpath(cd));

report = '/private/tmp/random_regression_report.txt';
fid = fopen(report, 'w');
if fid < 0
    error('Cannot open report: %s', report);
end
cleanup_obj = onCleanup(@() fclose(fid)); %#ok<NASGU>

cases = [ ...
    struct( ...
        'name', 'case1_24', ...
        'source_bmp', '/Users/silas/Desktop/code/VideoCompress/jpegxs/data/images/24.bmp', ...
        'ppm', '/Users/silas/Desktop/code/VideoCompress/jpegxs/samples/random_regression/case1_24.ppm', ...
        'size', uint64(7192817), ...
        'c_jxs', '/private/tmp/case1_24_c.jxs', ...
        'c_bmp', '/private/tmp/case1_24_c.bmp', ...
        'm_jxs', '/private/tmp/case1_24_m.jxs', ...
        'm_bmp', '/private/tmp/case1_24_m.bmp'), ...
    struct( ...
        'name', 'case2_person_1080x1920_4', ...
        'source_bmp', '/Users/silas/Desktop/code/VideoCompress/jpegxs/data/images/人物1080x1920_4.bmp', ...
        'ppm', '/Users/silas/Desktop/code/VideoCompress/jpegxs/samples/random_regression/case2_person_1080x1920_4.ppm', ...
        'size', uint64(6220817), ...
        'c_jxs', '/private/tmp/case2_person_1080x1920_4_c.jxs', ...
        'c_bmp', '/private/tmp/case2_person_1080x1920_4_c.bmp', ...
        'm_jxs', '/private/tmp/case2_person_1080x1920_4_m.jxs', ...
        'm_bmp', '/private/tmp/case2_person_1080x1920_4_m.bmp'), ...
    struct( ...
        'name', 'case3_18', ...
        'source_bmp', '/Users/silas/Desktop/code/VideoCompress/jpegxs/data/images/18.bmp', ...
        'ppm', '/Users/silas/Desktop/code/VideoCompress/jpegxs/samples/random_regression/case3_18.ppm', ...
        'size', uint64(7192817), ...
        'c_jxs', '/private/tmp/case3_18_c.jxs', ...
        'c_bmp', '/private/tmp/case3_18_c.bmp', ...
        'm_jxs', '/private/tmp/case3_18_m.jxs', ...
        'm_bmp', '/private/tmp/case3_18_m.bmp') ...
];

fprintf(fid, 'criterion_1=MATLAB encoded codestream must match C encoded codestream byte-for-byte\n');
fprintf(fid, 'criterion_2=MATLAB decoded BMP must match C decoded BMP pixel-for-pixel\n');
fprintf(fid, 'criterion_3=These are lossy cases, so decoded output need not equal original input\n');

all_ok = true;
for k = 1:numel(cases)
    cs = cases(k);
    fprintf('RUN %s\n', cs.name);
    fprintf(fid, 'CASE %s\n', cs.name);
    fprintf(fid, 'source_bmp=%s\n', cs.source_bmp);
    fprintf(fid, 'sample_ppm=%s\n', cs.ppm);
    fprintf(fid, 'target_size=%u\n', cs.size);

    require_file(cs.ppm);
    require_file(cs.c_jxs);
    require_file(cs.c_bmp);

    rgb = imread(cs.ppm);
    im = load_ppm_as_image(rgb);
    im_enc = clone_image(im);

    cfg = jxs.internal.xs_config.default_config();
    cfg.bitstream_size_in_bytes = cs.size;
    [~, cfg] = jxs.internal.xs_config.resolve_auto_values(cfg, im);
    fprintf(fid, 'resolved color_transform=%d level=0x%02x sublevel=0x%02x\n', ...
        cfg.p.color_transform, cfg.level, cfg.sublevel);

    bs = jpegxs_encode(im_enc, cfg);
    write_bytes(cs.m_jxs, bs);

    c_bytes = read_bytes(cs.c_jxs);
    jxs_equal = isequal(bs, c_bytes);
    fprintf(fid, 'jxs_equal=%d matlab_bytes=%d c_bytes=%d\n', jxs_equal, numel(bs), numel(c_bytes));
    if ~jxs_equal
        all_ok = false;
        report_first_byte_diff(fid, bs, c_bytes);
    end

    im_dec = jpegxs_decode(bs);
    matlab_rgb = image_to_rgb(im_dec);
    imwrite(matlab_rgb, cs.m_bmp, 'bmp');

    c_rgb = imread(cs.c_bmp);
    bmp_equal = isequal(matlab_rgb, c_rgb);
    fprintf(fid, 'bmp_equal=%d\n', bmp_equal);
    if ~bmp_equal
        all_ok = false;
        report_first_pixel_diff(fid, matlab_rgb, c_rgb);
    end

    fprintf(fid, '\n');
end

if all_ok
    fprintf(fid, 'RANDOM_REGRESSION_OK\n');
    fprintf('RANDOM_REGRESSION_OK\n');
else
    fprintf(fid, 'RANDOM_REGRESSION_FAIL\n');
    error('Random regression cases found mismatches');
end

type(report);
end

function im = load_ppm_as_image(rgb)
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

function require_file(path_in)
if exist(path_in, 'file') ~= 2
    error('Required file not found: %s', path_in);
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

function report_first_byte_diff(fid, lhs, rhs)
n = min(numel(lhs), numel(rhs));
idx = find(lhs(1:n) ~= rhs(1:n), 1, 'first');
if isempty(idx)
    idx = n + 1;
end
fprintf(fid, 'first_jxs_diff=%d matlab=%d c=%d\n', idx, get_byte(lhs, idx), get_byte(rhs, idx));
end

function report_first_pixel_diff(fid, lhs, rhs)
d = abs(double(lhs) - double(rhs));
idx = find(d > 0, 1, 'first');
[row, col, ch] = ind2sub(size(d), idx);
fprintf(fid, 'first_bmp_diff row=%d col=%d ch=%d matlab=%d c=%d max_diff=%d\n', ...
    row, col, ch, lhs(row, col, ch), rhs(row, col, ch), max(d(:)));
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
