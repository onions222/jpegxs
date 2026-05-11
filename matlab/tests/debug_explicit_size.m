cd('/Users/silas/Desktop/code/VideoCompress/jpegxs/matlab');
addpath(genpath(cd));

diag_path = '/private/tmp/matlab_explicit_size_diag.txt';
out_path = '/Users/silas/Desktop/code/VideoCompress/jpegxs/samples/matlab_encoder_output_size1103754.jxs';
fid = fopen(diag_path, 'w');

try
    rgb = imread('/Users/silas/Desktop/code/VideoCompress/jpegxs/samples/input.ppm');
    im = jxs.internal.image();
    im.ncomps = int32(size(rgb, 3));
    im.width = int32(size(rgb, 2));
    im.height = int32(size(rgb, 1));
    im.depth = int32(8);
    im.sx(1:3) = int32([1 1 1]);
    im.sy(1:3) = int32([1 1 1]);
    im.allocate(true);
    for c = 1:3
        im.comps_array{c} = reshape(int32(rgb(:, :, c)).', [], 1);
    end
    im_encode = jxs.internal.image();
    im_encode.ncomps = im.ncomps;
    im_encode.width = im.width;
    im_encode.height = im.height;
    im_encode.depth = im.depth;
    im_encode.sx = im.sx;
    im_encode.sy = im.sy;
    im_encode.allocate(true);
    for c = 1:im.ncomps
        im_encode.comps_array{c} = im.comps_array{c};
    end

    cfg = jxs.internal.xs_config.default_config();
    cfg.bitstream_size_in_bytes = uint64(1103754);
    [~, cfg] = jxs.internal.xs_config.resolve_auto_values(cfg, im);

    ids_obj = jxs.internal.ids();
    ids_obj.construct(im, cfg.p.NLx, cfg.p.NLy, cfg.p.Sd, cfg.p.Cw, cfg.p.Lh);

    bp = jxs.internal.bitpacker();
    header_buf = zeros(1, 65536, 'uint8');
    bp.set_buffer(header_buf, 65536);
    header_len = jxs.internal.xs_markers.write_head(bp, im, cfg);
    min_col_nbytes = int64(ids_obj.npy) * 4;
    overhead = int64(bitshift(header_len, -3)) + 2 + 6 * ...
        int64(idivide(int32(im.height) + int32(cfg.p.slice_height) - 1, int32(cfg.p.slice_height), 'floor'));
    total_bytes = int64(cfg.bitstream_size_in_bytes);
    rc_bytes = total_bytes - overhead;
    report_bytes = int64(floor(double(int32(cfg.budget_report_lines) / 2 * 2) * ...
        double(cfg.bitstream_size_in_bytes) / double(im.height)));
    bytes_per_col = idivide((rc_bytes - min_col_nbytes) * int64(ids_obj.cs), int64(im.width), 'floor');
    report_per_col = idivide(report_bytes * int64(ids_obj.cs), int64(im.width), 'floor');

    fprintf(fid, 'header_len=%d\n', header_len);
    fprintf(fid, 'overhead=%d rc_bytes=%d bytes_per_col=%d report_per_col=%d\n', ...
        overhead, rc_bytes, bytes_per_col, report_per_col);
    fprintf(fid, 'profile=0x%04x level=0x%02x sublevel=0x%02x cap=0x%04x\n', ...
        cfg.profile, cfg.level, cfg.sublevel, cfg.cap_bits);

    prec = jxs.internal.precinct();
    prec.open_column(ids_obj, cfg.p.N_g, 0);
    rc = jxs.internal.rate_control();
    rc.open(cfg, ids_obj, 0);
    rc.init(int32(bytes_per_col), int32(report_per_col));

    jxs.internal.nlt.forward_transform(im, cfg.p);
    jxs.internal.mct.forward_transform(im, cfg.p);
    jxs.internal.dwt.forward_transform(ids_obj, im);

    prec.set_y_idx(0);
    prec.from_image(im, cfg.p.Fq);
    prec.update_gclis();

    rc_results = rc.process_precinct(prec);
    fprintf(fid, 'first_precinct quant=%d ref=%d total_bits=%d\n', ...
        rc_results.quantization, rc_results.refinement, rc_results.precinct_total_bits);
    fprintf(fid, 'subpkt0 raw=%d sigf=%d gcli=%d data=%d sign=%d\n', ...
        rc_results.pbinfo.subpkt_uses_raw_fallback(1), ...
        rc_results.pbinfo.subpkt_size_sigf(1), ...
        rc_results.pbinfo.subpkt_size_gcli(1), ...
        rc_results.pbinfo.subpkt_size_data(1), ...
        rc_results.pbinfo.subpkt_size_sign(1));

    for i = 1:min(12, numel(rc_results.gcli_sb_methods))
        fprintf(fid, 'method[%d]=%d gtli_gcli[%d]=%d gtli_data[%d]=%d\n', ...
            i - 1, rc_results.gcli_sb_methods(i), ...
            i - 1, rc_results.gtli_table_gcli(i), ...
            i - 1, rc_results.gtli_table_data(i));
    end

    bs = jpegxs_encode(im_encode, cfg);
    out_fid = fopen(out_path, 'wb');
    fwrite(out_fid, bs, 'uint8');
    fclose(out_fid);
    d = dir(out_path);
    fprintf(fid, 'encode_ok bytes=%d\n', d.bytes);
catch ME
    fprintf(fid, 'ERROR:%s\n', ME.message);
    for i = 1:numel(ME.stack)
        fprintf(fid, 'STACK:%s:%d\n', ME.stack(i).file, ME.stack(i).line);
    end
end

fclose(fid);
