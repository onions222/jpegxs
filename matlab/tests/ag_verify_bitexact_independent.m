% ag_verify_bitexact_independent.m
% Independent bit-exact verification script.
% Encodes test images with the MATLAB JPEG-XS encoder and writes output .jxs files.
% Standalone script — no dependency on verify_bitexact.sh or its helpers.

function ag_verify_bitexact_independent()
    script_dir = fileparts(mfilename('fullpath'));
    matlab_dir = fileparts(script_dir);
    repo_root  = fileparts(matlab_dir);

    cd(matlab_dir);
    addpath(genpath(matlab_dir));

    c = jxs.Constants;

    % ===== Test T1: input.ppm, size=1103754 =====
    fprintf('\n====== T1: input.ppm, size=1103754 ======\n');
    ppm_path_t1 = fullfile(repo_root, 'samples', 'input.ppm');
    im_t1 = load_ppm(ppm_path_t1);
    cfg_t1 = jxs.internal.xs_config.default_config();
    cfg_t1.bitstream_size_in_bytes = uint64(1103754);
    [~, cfg_t1] = jxs.internal.xs_config.resolve_auto_values(cfg_t1, im_t1);
    fprintf('  Config: profile=%d, color_transform=%d, level=0x%02x, sublevel=0x%02x, size=%u\n', ...
        cfg_t1.profile, cfg_t1.p.color_transform, cfg_t1.level, cfg_t1.sublevel, cfg_t1.bitstream_size_in_bytes);

    bs_t1 = jpegxs_encode(im_t1, cfg_t1);
    out_t1 = '/private/tmp/ag_verify_T1_matlab.jxs';
    write_jxs(out_t1, bs_t1);
    fprintf('  Written: %s (%d bytes)\n', out_t1, numel(bs_t1));

    % ===== Test T2: debug_input.ppm, size=4096 =====
    fprintf('\n====== T2: debug_input.ppm, size=4096 ======\n');
    ppm_path_t2 = fullfile(repo_root, 'samples', 'debug_input.ppm');
    im_t2 = load_ppm(ppm_path_t2);
    cfg_t2 = jxs.internal.xs_config.default_config();
    cfg_t2.bitstream_size_in_bytes = uint64(4096);
    cfg_t2.level  = int32(c.XS_LEVEL_1K_1);
    cfg_t2.sublevel = int32(c.XS_SUBLEVEL_9_BPP);
    [~, cfg_t2] = jxs.internal.xs_config.resolve_auto_values(cfg_t2, im_t2);
    fprintf('  Config: profile=%d, color_transform=%d, level=0x%02x, sublevel=0x%02x, size=%u\n', ...
        cfg_t2.profile, cfg_t2.p.color_transform, cfg_t2.level, cfg_t2.sublevel, cfg_t2.bitstream_size_in_bytes);

    bs_t2 = jpegxs_encode(im_t2, cfg_t2);
    out_t2 = '/private/tmp/ag_verify_T2_matlab.jxs';
    write_jxs(out_t2, bs_t2);
    fprintf('  Written: %s (%d bytes)\n', out_t2, numel(bs_t2));

    fprintf('\nMATLAB encoding complete.\n');
end

function im = load_ppm(ppm_path)
    rgb = imread(ppm_path);
    im = jxs.internal.image();
    im.ncomps = int32(size(rgb, 3));
    im.width  = int32(size(rgb, 2));
    im.height = int32(size(rgb, 1));
    im.depth  = int32(8);
    im.sx(1:double(im.ncomps)) = int32(1);
    im.sy(1:double(im.ncomps)) = int32(1);
    im.allocate(true);
    for idx = 1:double(im.ncomps)
        im.comps_array{idx} = reshape(int32(rgb(:, :, idx)).', [], 1);
    end
end

function write_jxs(path_out, bytes)
    fid = fopen(path_out, 'wb');
    if fid < 0
        error('Cannot write to %s', path_out);
    end
    fwrite(fid, bytes, 'uint8');
    fclose(fid);
end
