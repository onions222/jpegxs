% ag_recheck_t2.m — Minimal, transparent T2 recheck.
% Encodes debug_input.ppm with explicit parameters and prints all config values.

function ag_recheck_t2()
    script_dir = fileparts(mfilename('fullpath'));
    matlab_dir = fileparts(script_dir);
    repo_root  = fileparts(matlab_dir);

    cd(matlab_dir);
    addpath(genpath(matlab_dir));

    c = jxs.Constants;

    % Load image
    ppm_path = fullfile(repo_root, 'samples', 'debug_input.ppm');
    rgb = imread(ppm_path);
    fprintf('Image loaded: %s\n', ppm_path);
    fprintf('  size(rgb) = [%d %d %d], class=%s\n', size(rgb,1), size(rgb,2), size(rgb,3), class(rgb));

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
    fprintf('  image: %dx%d, ncomps=%d, depth=%d\n', im.width, im.height, im.ncomps, im.depth);

    % Build config — explicitly matching C: profile=Main444.12;level=1k-1;sublevel=9bpp;size=4096
    cfg = jxs.internal.xs_config.default_config();
    cfg.bitstream_size_in_bytes = uint64(4096);
    cfg.level   = int32(c.XS_LEVEL_1K_1);
    cfg.sublevel = int32(c.XS_SUBLEVEL_9_BPP);

    fprintf('\nBEFORE resolve:\n');
    fprintf('  profile=%d (0x%04x)\n', cfg.profile, cfg.profile);
    fprintf('  color_transform=%d\n', cfg.p.color_transform);
    fprintf('  level=0x%02x, sublevel=0x%02x\n', cfg.level, cfg.sublevel);
    fprintf('  size=%u\n', cfg.bitstream_size_in_bytes);
    fprintf('  NLx=%d, NLy=%d, Bw=%d, Fq=%d\n', cfg.p.NLx, cfg.p.NLy, cfg.p.Bw, cfg.p.Fq);
    fprintf('  slice_height=%d, N_g=%d, S_s=%d, B_r=%d\n', cfg.p.slice_height, cfg.p.N_g, cfg.p.S_s, cfg.p.B_r);
    fprintf('  budget_report_lines=%.1f\n', cfg.budget_report_lines);

    [~, cfg] = jxs.internal.xs_config.resolve_auto_values(cfg, im);

    fprintf('\nAFTER resolve:\n');
    fprintf('  profile=%d (0x%04x)\n', cfg.profile, cfg.profile);
    fprintf('  color_transform=%d\n', cfg.p.color_transform);
    fprintf('  level=0x%02x, sublevel=0x%02x\n', cfg.level, cfg.sublevel);
    fprintf('  size=%u\n', cfg.bitstream_size_in_bytes);
    fprintf('  NLx=%d, NLy=%d, Bw=%d, Fq=%d\n', cfg.p.NLx, cfg.p.NLy, cfg.p.Bw, cfg.p.Fq);
    fprintf('  Qpih=%d, Rm=%d, Rl=%d, Fs=%d, Sd=%d\n', cfg.p.Qpih, cfg.p.Rm, cfg.p.Rl, cfg.p.Fs, cfg.p.Sd);
    fprintf('  slice_height=%d, N_g=%d, S_s=%d, B_r=%d\n', cfg.p.slice_height, cfg.p.N_g, cfg.p.S_s, cfg.p.B_r);
    fprintf('  budget_report_lines=%.1f\n', cfg.budget_report_lines);
    fprintf('  cap_bits=0x%04x\n', cfg.cap_bits);
    fprintf('  gains=%s\n', mat2str(cfg.p.lvl_gains(1:25)));
    fprintf('  prios=%s\n', mat2str(cfg.p.lvl_priorities(1:25)));

    % Encode
    fprintf('\nEncoding...\n');
    bs = jpegxs_encode(im, cfg);
    fprintf('Encoded: %d bytes\n', numel(bs));

    % Write output
    out_path = '/private/tmp/ag_recheck_matlab.jxs';
    fid = fopen(out_path, 'wb');
    fwrite(fid, bs, 'uint8');
    fclose(fid);
    fprintf('Written: %s\n', out_path);

    % Print first 16 bytes of output for sanity check
    fprintf('\nFirst 32 bytes (hex): ');
    for i = 1:min(32, numel(bs))
        fprintf('%02x ', bs(i));
    end
    fprintf('\n');

    fprintf('\nDone.\n');
end
