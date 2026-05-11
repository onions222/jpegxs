cd('/Users/silas/Desktop/code/VideoCompress/jpegxs/matlab');
addpath(genpath(cd));

in_path = '/private/tmp/c_encoder_output_size1103754.jxs';
diag_path = '/private/tmp/c_first_precinct_diag.txt';
fid = fopen(diag_path, 'w');

try
    bytes = fread(fopen(in_path, 'rb'), inf, 'uint8=>uint8')';

    bu = jxs.internal.bitunpacker();
    bu.set_buffer(bytes, length(bytes));

    cfg = jxs.internal.xs_config.default_config();
    im = jxs.internal.image();
    im.ncomps = int32(3);
    im.width = int32(64);
    im.height = int32(64);
    im.depth = int32(8);
    im.sx = ones(1, 4, 'int32');
    im.sy = ones(1, 4, 'int32');

    [ok, cfg] = jxs.internal.xs_markers.parse_head(bu, im, cfg);
    if ~ok
        error('parse_head failed');
    end

    ids_obj = jxs.internal.ids();
    ids_obj.construct(im, cfg.p.NLx, cfg.p.NLy, cfg.p.Sd, cfg.p.Cw, cfg.p.Lh);

    [ok, slice_idx] = jxs.internal.xs_markers.parse_slice_header(bu);
    if ~ok || slice_idx ~= 0
        error('bad first slice header');
    end

    prec = jxs.internal.precinct();
    prec.open_column(ids_obj, cfg.p.N_g, 0);
    prec.set_y_idx(0);

    c = jxs.Constants;
    [v, ~] = bu.read(c.PREC_HDR_PREC_SIZE); Lprc = bitshift(int32(v), 3);
    [v, ~] = bu.read(c.PREC_HDR_QUANTIZATION_SIZE); quantization = int32(v);
    [v, ~] = bu.read(c.PREC_HDR_REFINEMENT_SIZE); refinement = int32(v);

    n_bands = prec.bands_count();
    gcli_sb_methods = zeros(1, n_bands, 'int32');
    for band = int32(0):(n_bands - 1)
        [v, ~] = bu.read(c.GCLI_METHOD_NBITS);
        gcli_sb_methods(band + 1) = jxs.internal.gcli_methods.from_signaling(int32(v), ...
            jxs.internal.gcli_methods.get_enabled(cfg));
    end
    bu.align(c.PREC_HDR_ALIGNMENT);

    [gtli_data, gtli_gcli, ~] = jxs.internal.sb_weighting.compute_gtli_tables(...
        quantization, refinement, n_bands, cfg.p.lvl_gains, cfg.p.lvl_priorities);

    fprintf(fid, 'quant=%d ref=%d Lprc=%d\n', quantization, refinement, Lprc);
    for i = 1:numel(gcli_sb_methods)
        fprintf(fid, 'method[%d]=%d gtli_gcli[%d]=%d gtli_data[%d]=%d\n', ...
            i - 1, gcli_sb_methods(i), ...
            i - 1, gtli_gcli(i), ...
            i - 1, gtli_data(i));
    end

    position_count = prec.ids.npi;
    use_long = prec.use_long_headers();
    subpkt = int32(0);
    idx_start = int32(0);
    while idx_start < position_count
        idx_stop = idx_start;
        while idx_stop < position_count - 1 && prec.subpkt_of(idx_stop) == prec.subpkt_of(idx_stop + 1)
            idx_stop = idx_stop + 1;
        end
        lvl = prec.band_index_of(idx_start);
        ypos = prec.ypos_of(idx_start);
        if ypos >= prec.in_band_height_of(lvl)
            subpkt = subpkt + 1;
            idx_start = idx_stop + 1;
            continue;
        end

        [v, ~] = bu.read(1); uses_raw = int32(v);
        sz_bits = jxs.Constants.iif(use_long, c.PKT_HDR_DATA_SIZE_LONG, c.PKT_HDR_DATA_SIZE_SHORT);
        [v, ~] = bu.read(sz_bits); data_len = int32(v) * 8;
        sz_bits = jxs.Constants.iif(use_long, c.PKT_HDR_GCLI_SIZE_LONG, c.PKT_HDR_GCLI_SIZE_SHORT);
        [v, ~] = bu.read(sz_bits); gcli_len = int32(v) * 8;
        sz_bits = jxs.Constants.iif(use_long, c.PKT_HDR_SIGN_SIZE_LONG, c.PKT_HDR_SIGN_SIZE_SHORT);
        [v, ~] = bu.read(sz_bits); sign_len = int32(v) * 8;
        bu.align(c.PKT_HDR_ALIGNMENT);

        fprintf(fid, 'subpkt[%d] raw=%d data=%d gcli=%d sign=%d\n', ...
            subpkt, uses_raw, data_len, gcli_len, sign_len);

        skip_bits = gcli_len + data_len + sign_len;
        if uses_raw == 0
            % SIGF length is implicit from remaining precinct bit accounting; for this
            % script we only need the explicit packet-header lengths and top-level params.
        end
        bu.skip(skip_bits);
        bu.align(c.SUBPKT_ALIGNMENT);

        subpkt = subpkt + 1;
        idx_start = idx_stop + 1;
        if subpkt >= 12
            break;
        end
    end
catch ME
    fprintf(fid, 'ERROR:%s\n', ME.message);
    for i = 1:numel(ME.stack)
        fprintf(fid, 'STACK:%s:%d\n', ME.stack(i).file, ME.stack(i).line);
    end
end

fclose(fid);

end
