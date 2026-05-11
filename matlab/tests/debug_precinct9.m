cd('/Users/silas/Desktop/code/VideoCompress/jpegxs/matlab');
addpath(genpath(cd));

diag_path = '/private/tmp/debug_precinct9.txt';
fid = fopen(diag_path, 'w');

try
    target_y = int32(9);

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

    cfg = jxs.internal.xs_config.default_config();
    cfg.bitstream_size_in_bytes = uint64(1103754);
    [~, cfg] = jxs.internal.xs_config.resolve_auto_values(cfg, im);

    ids_obj = jxs.internal.ids();
    ids_obj.construct(im, cfg.p.NLx, cfg.p.NLy, cfg.p.Sd, cfg.p.Cw, cfg.p.Lh);

    rc = jxs.internal.rate_control();
    rc.open(cfg, ids_obj, 0);

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
    rc.init(int32(bytes_per_col), int32(report_per_col));

    jxs.internal.nlt.forward_transform(im, cfg.p);
    jxs.internal.mct.forward_transform(im, cfg.p);
    jxs.internal.dwt.forward_transform(ids_obj, im);

    prec = jxs.internal.precinct();
    prec.open_column(ids_obj, cfg.p.N_g, 0);

    for y = int32(0):(target_y - 1)
        prec.set_y_idx(y);
        prec.from_image(im, cfg.p.Fq);
        prec.update_gclis();
        rc_results = rc.process_precinct(prec);
        prec.quantize(rc_results.gtli_table_data, cfg.p.Qpih);
    end

    prec.set_y_idx(target_y);
    prec.from_image(im, cfg.p.Fq);
    prec.update_gclis();

    rc.precinct_top.copy_gclis(rc.precinct);
    rc.precinct.precinct_copy(prec);
    precinct_top = jxs.Constants.iif(prec.is_first_of_slice(cfg.p.slice_height), [], rc.precinct_top);

    jxs.internal.gcli_budget.fill(rc.gc_enabled_modes, prec, precinct_top, [], rc.pbt, rc.pred_residuals, 0, cfg.p.S_s);
    jxs.internal.data_budget.fill_data_budget_table(prec, rc.pbt, cfg.p.N_g, cfg.p.Fs, cfg.p.Qpih);
    if ~prec.is_first_of_slice(cfg.p.slice_height)
        ver_modes = jxs.internal.gcli_methods.get_enabled_ver(rc.gc_enabled_modes);
        jxs.internal.gcli_budget.fill(ver_modes, rc.precinct, rc.precinct_top, rc.gtli_table_gcli_prec, rc.pbt, rc.pred_residuals, 1, cfg.p.S_s);
    end

    spacial_lines = prec.spacial_lines_of(rc.image_height);
    budget_cbr = jxs.internal.budget.getcbr(rc.nibbles_image, rc.lines_consumed + spacial_lines, rc.image_height);
    budget_minimum = int32(budget_cbr) - rc.nibbles_report;
    budget_bits = bitshift(int32(budget_cbr) - rc.nibbles_consumed, 2);
    fprintf(fid, 'y=%d lines_consumed=%d nibbles_consumed=%d budget_cbr=%d budget_min=%d budget_bits=%d\n', ...
        target_y, rc.lines_consumed, rc.nibbles_consumed, budget_cbr, budget_minimum, budget_bits);

    for refinement = int32(17):int32(21)
        quantization = int32(4);
        [gtli_data, gtli_gcli, ~] = jxs.internal.sb_weighting.compute_gtli_tables( ...
            quantization, refinement, prec.bands_count(), cfg.p.lvl_gains, cfg.p.lvl_priorities);
        methods = jxs.internal.precinct_budget.get_best_gcli_method(prec, rc.pbt, gtli_gcli);
        [prec_bits, pkt_hdr, sigf_sz, gcli_sz, data_sz, sign_sz, ~, raw_flags, prec_hdr] = ...
            jxs.internal.precinct_budget.get_budget(prec, rc.pbt, gtli_gcli, gtli_data, cfg.p.Rl, methods);
        fprintf(fid, 'ref=%d prec_bits=%d payload=%d hdr=%d\n', refinement, prec_bits, prec_bits - prec_hdr, prec_hdr);
        fprintf(fid, '  methods:');
        for i = 1:min(12, numel(methods))
            fprintf(fid, ' %d', methods(i));
        end
        fprintf(fid, '\n');
        for sp = 1:prec.nb_subpkts()
            fprintf(fid, '  subpkt[%d] raw=%d pkt=%d sigf=%d gcli=%d data=%d sign=%d\n', ...
                sp - 1, raw_flags(sp), pkt_hdr(sp), sigf_sz(sp), gcli_sz(sp), data_sz(sp), sign_sz(sp));
        end
    end

    actual = rc.process_precinct(prec);
    fprintf(fid, 'actual_process quant=%d ref=%d total=%d payload=%d\n', ...
        actual.quantization, actual.refinement, actual.precinct_total_bits, ...
        actual.pbinfo.precinct_bits - actual.pbinfo.prec_header_size);
catch ME
    fprintf(fid, 'ERROR:%s\n', ME.message);
    for i = 1:numel(ME.stack)
        fprintf(fid, 'STACK:%s:%d\n', ME.stack(i).file, ME.stack(i).line);
    end
end

fclose(fid);

end
