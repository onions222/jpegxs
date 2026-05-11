cd('/Users/silas/Desktop/code/VideoCompress/jpegxs/matlab');
addpath(genpath(cd));

diag_path = '/private/tmp/matlab_fixed_ref13_diag.txt';
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

    cfg = jxs.internal.xs_config.default_config();
    cfg.bitstream_size_in_bytes = uint64(1103754);
    [~, cfg] = jxs.internal.xs_config.resolve_auto_values(cfg, im);

    ids_obj = jxs.internal.ids();
    ids_obj.construct(im, cfg.p.NLx, cfg.p.NLy, cfg.p.Sd, cfg.p.Cw, cfg.p.Lh);

    jxs.internal.nlt.forward_transform(im, cfg.p);
    jxs.internal.mct.forward_transform(im, cfg.p);
    jxs.internal.dwt.forward_transform(ids_obj, im);

    prec = jxs.internal.precinct();
    prec.open_column(ids_obj, cfg.p.N_g, 0);
    prec.set_y_idx(0);
    prec.from_image(im, cfg.p.Fq);
    prec.update_gclis();

    rc = jxs.internal.rate_control();
    rc.open(cfg, ids_obj, 0);
    rc.init(int32(1101056), int32(0));

    first_of_slice = prec.is_first_of_slice(cfg.p.slice_height);
    if first_of_slice
        precinct_top = [];
    else
        precinct_top = rc.precinct_top;
    end

    jxs.internal.gcli_budget.fill(rc.gc_enabled_modes, prec, precinct_top, [], rc.pbt, rc.pred_residuals, 0, cfg.p.S_s);
    jxs.internal.data_budget.fill_data_budget_table(prec, rc.pbt, cfg.p.N_g, cfg.p.Fs, cfg.p.Qpih);

    quantization = int32(4);
    refinement = int32(13);
    [gtli_data, gtli_gcli, empty] = jxs.internal.sb_weighting.compute_gtli_tables( ...
        quantization, refinement, prec.bands_count(), cfg.p.lvl_gains, cfg.p.lvl_priorities);

    methods_c = int32([ ...
        2 2 2 2 2 2 2 2 2 2 6 2 ...
        2 6 6 2 6 6 2 6 6 2 6 6 ...
        2 6 6 2 6 6]);
    methods_matlab = jxs.internal.precinct_budget.get_best_gcli_method(prec, rc.pbt, gtli_gcli);

    fprintf(fid, 'nbands=%d empty=%d\n', prec.bands_count(), empty);
    fprintf(fid, 'quant=%d ref=%d\n', quantization, refinement);
    for i = 1:prec.bands_count()
        fprintf(fid, 'gtli[%d] data=%d gcli=%d method_matlab=%d method_c=%d\n', ...
            i - 1, gtli_data(i), gtli_gcli(i), methods_matlab(i), methods_c(i));
    end

    [bits_m, pkt_m, sigf_m, gcli_m, data_m, sign_m, raw_m, rawflag_m, hdr_m] = ...
        jxs.internal.precinct_budget.get_budget(prec, rc.pbt, gtli_gcli, gtli_data, cfg.p.Rl, methods_matlab);
    [bits_c, pkt_c, sigf_c, gcli_c, data_c, sign_c, raw_c, rawflag_c, hdr_c] = ...
        jxs.internal.precinct_budget.get_budget(prec, rc.pbt, gtli_gcli, gtli_data, cfg.p.Rl, methods_c);

    fprintf(fid, 'budget_matlab total=%d hdr=%d\n', bits_m, hdr_m);
    fprintf(fid, 'budget_c total=%d hdr=%d\n', bits_c, hdr_c);
    for sp = 1:prec.nb_subpkts()
        fprintf(fid, 'budget_matlab subpkt[%d] raw=%d pkt=%d sigf=%d gcli=%d data=%d sign=%d rawgcli=%d\n', ...
            sp - 1, rawflag_m(sp), pkt_m(sp), sigf_m(sp), gcli_m(sp), data_m(sp), sign_m(sp), raw_m(sp));
        fprintf(fid, 'budget_c subpkt[%d] raw=%d pkt=%d sigf=%d gcli=%d data=%d sign=%d rawgcli=%d\n', ...
            sp - 1, rawflag_c(sp), pkt_c(sp), sigf_c(sp), gcli_c(sp), data_c(sp), sign_c(sp), raw_c(sp));
    end

    pack_ctx = jxs.internal.packing.packer_open(cfg, prec);
    [asigf_m, agcli_m, adata_m, asign_m] = measure_actual(prec, gtli_data, gtli_gcli, methods_matlab, rawflag_m, rc.pred_residuals, pack_ctx);
    [asigf_c, agcli_c, adata_c, asign_c] = measure_actual(prec, gtli_data, gtli_gcli, methods_c, rawflag_c, rc.pred_residuals, pack_ctx);

    for sp = 1:prec.nb_subpkts()
        fprintf(fid, 'actual_matlab subpkt[%d] sigf=%d gcli=%d data=%d sign=%d\n', ...
            sp - 1, asigf_m(sp), agcli_m(sp), adata_m(sp), asign_m(sp));
        fprintf(fid, 'actual_c subpkt[%d] sigf=%d gcli=%d data=%d sign=%d\n', ...
            sp - 1, asigf_c(sp), agcli_c(sp), adata_c(sp), asign_c(sp));
    end
catch ME
    fprintf(fid, 'ERROR:%s\n', ME.message);
    for i = 1:numel(ME.stack)
        fprintf(fid, 'STACK:%s:%d\n', ME.stack(i).file, ME.stack(i).line);
    end
end

fclose(fid);

function [sigf_bits, gcli_bits, data_bits, sign_bits] = measure_actual(prec_in, gtli_data_in, gtli_gcli_in, methods_in, raw_flags_in, pred_residuals_in, pack_ctx_in)
    ra = struct();
    ra.gtli_table_data = gtli_data_in;
    ra.gtli_table_gcli = gtli_gcli_in;
    ra.gcli_sb_methods = methods_in;
    ra.pred_residuals = pred_residuals_in;
    ra.pbinfo = struct('subpkt_uses_raw_fallback', raw_flags_in);

    sigf_bits = zeros(1, double(prec_in.nb_subpkts()), 'int32');
    gcli_bits = zeros(1, double(prec_in.nb_subpkts()), 'int32');
    data_bits = zeros(1, double(prec_in.nb_subpkts()), 'int32');
    sign_bits = zeros(1, double(prec_in.nb_subpkts()), 'int32');

    qprec = jxs.internal.precinct();
    qprec.open_column(prec_in.ids, prec_in.group_size, prec_in.column);
    qprec.precinct_copy(prec_in);
    qprec.quantize(gtli_data_in, pack_ctx_in.xs_config.p.Qpih);

    position_count = prec_in.ids.npi;
    subpkt = int32(0);
    idx_start = int32(0);
    while idx_start < position_count
        idx_stop = idx_start;
        while idx_stop < position_count - 1 && prec_in.subpkt_of(idx_stop) == prec_in.subpkt_of(idx_stop + 1)
            idx_stop = idx_stop + 1;
        end

        lvl0 = prec_in.band_index_of(idx_start);
        ypos0 = prec_in.ypos_of(idx_start);
        if ypos0 >= prec_in.in_band_height_of(lvl0)
            subpkt = subpkt + 1;
            idx_start = idx_stop + 1;
            continue;
        end

        bp = jxs.internal.bitpacker();
        buf = zeros(1, bitshift(1, 20), 'uint8');
        bp.set_buffer(buf, length(buf));
        if raw_flags_in(subpkt + 1) == 0
            jxs.internal.packing.pack_gclis_significance(pack_ctx_in, bp, qprec, ra, idx_start, idx_stop);
            bp.align(jxs.Constants.SUBPKT_ALIGNMENT);
            sigf_bits(subpkt + 1) = bp.get_len();
        end

        bp = jxs.internal.bitpacker();
        buf = zeros(1, bitshift(1, 20), 'uint8');
        bp.set_buffer(buf, length(buf));
        for idx = idx_start:idx_stop
            lvl = prec_in.band_index_of(idx);
            ypos = prec_in.ypos_of(idx);
            if ypos >= prec_in.in_band_height_of(lvl)
                continue;
            end
            jxs.internal.packing.pack_gclis(pack_ctx_in, bp, qprec, ra, idx);
        end
        bp.align(jxs.Constants.SUBPKT_ALIGNMENT);
        gcli_bits(subpkt + 1) = bp.get_len();

        bp = jxs.internal.bitpacker();
        buf = zeros(1, bitshift(1, 20), 'uint8');
        bp.set_buffer(buf, length(buf));
        for idx = idx_start:idx_stop
            lvl = prec_in.band_index_of(idx);
            ypos = prec_in.ypos_of(idx);
            if ypos >= prec_in.in_band_height_of(lvl)
                continue;
            end
            gtli = gtli_data_in(lvl + 1);
            jxs.internal.packing.pack_data(bp, qprec.line_of(lvl, ypos), int32(qprec.width_of(lvl)), ...
                qprec.gcli_of(lvl, ypos), qprec.group_size, gtli, pack_ctx_in.xs_config.p.Fs);
        end
        bp.align(jxs.Constants.SUBPKT_ALIGNMENT);
        data_bits(subpkt + 1) = bp.get_len();

        bp = jxs.internal.bitpacker();
        buf = zeros(1, bitshift(1, 20), 'uint8');
        bp.set_buffer(buf, length(buf));
        if pack_ctx_in.xs_config.p.Fs == 1
            for idx = idx_start:idx_stop
                lvl = prec_in.band_index_of(idx);
                ypos = prec_in.ypos_of(idx);
                if ypos >= prec_in.in_band_height_of(lvl)
                    continue;
                end
                gtli = gtli_data_in(lvl + 1);
                jxs.internal.packing.pack_sign(bp, qprec.line_of(lvl, ypos), int32(qprec.width_of(lvl)), ...
                    qprec.gcli_of(lvl, ypos), qprec.group_size, gtli);
            end
            bp.align(jxs.Constants.SUBPKT_ALIGNMENT);
        end
        sign_bits(subpkt + 1) = bp.get_len();

        subpkt = subpkt + 1;
        idx_start = idx_stop + 1;
    end
end
