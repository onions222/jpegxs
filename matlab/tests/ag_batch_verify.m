% ag_batch_verify.m
% Batch-encode all PPM images in a directory and write .jxs output files.
% Target size: ~3 bpp per image (W * H * 3 / 8 bytes).
% Skips files that already exist in the output directory.

function ag_batch_verify()
    script_dir = fileparts(mfilename('fullpath'));
    matlab_dir = fileparts(script_dir);

    cd(matlab_dir);
    addpath(genpath(matlab_dir));

    ppm_dir  = '/private/tmp/ag_batch_verify/ppm';
    out_dir  = '/private/tmp/ag_batch_verify/matlab_jxs';

    listing = dir(fullfile(ppm_dir, '*.ppm'));
    n = numel(listing);
    fprintf('Found %d PPM files\n', n);

    % Sort by file size (smallest first) for faster early results
    sizes = [listing.bytes];
    [~, order] = sort(sizes);
    listing = listing(order);

    skipped = 0;
    encoded = 0;
    for i = 1:n
        name = listing(i).name;
        base = name(1:end-4);
        out_path = fullfile(out_dir, [base, '.jxs']);

        if exist(out_path, 'file') == 2
            skipped = skipped + 1;
            fprintf('[%d/%d] SKIP %s (already exists)\n', i, n, base);
            continue;
        end

        ppm_path = fullfile(ppm_dir, name);
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
            im.comps_array{idx} = reshape(int32(rgb(:,:,idx)).', [], 1);
        end

        target_bytes = uint64(floor(double(im.width) * double(im.height) * 3 / 8));

        cfg = jxs.internal.xs_config.default_config();
        cfg.bitstream_size_in_bytes = target_bytes;
        [~, cfg] = jxs.internal.xs_config.resolve_auto_values(cfg, im);

        t0 = tic;
        bs = jpegxs_encode(im, cfg);
        elapsed = toc(t0);

        fid = fopen(out_path, 'wb');
        fwrite(fid, bs, 'uint8');
        fclose(fid);

        encoded = encoded + 1;
        fprintf('[%d/%d] %s: %dx%d -> %d bytes (%.1fs)\n', ...
            i, n, base, im.width, im.height, numel(bs), elapsed);
    end
    fprintf('Done: %d encoded, %d skipped\n', encoded, skipped);
end
