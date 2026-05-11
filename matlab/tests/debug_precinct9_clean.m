cd('/Users/silas/Desktop/code/VideoCompress/jpegxs/matlab');
addpath(genpath(cd));

diag_path = '/private/tmp/debug_precinct9_clean.txt';
fid = fopen(diag_path, 'w');

try
    if exist('target_y_override', 'var')
        target_y = int32(target_y_override);
    else
        target_y = int32(9);
    end

    [im_manual, cfg_manual, ids_manual] = setup_case();
    rc_manual = setup_rc(im_manual, cfg_manual, ids_manual);
    prec_manual = jxs.internal.precinct();
    prec_manual.open_column(ids_manual, cfg_manual.p.N_g, 0);

    for y = int32(0):(target_y - 1)
        prec_manual.set_y_idx(y);
        prec_manual.from_image(im_manual, cfg_manual.p.Fq);
        prec_manual.update_gclis();
        rc_manual.process_precinct(prec_manual);
    end

    prec_manual.set_y_idx(target_y);
    prec_manual.from_image(im_manual, cfg_manual.p.Fq);
    prec_manual.update_gclis();

    rc_manual.precinct_top.copy_gclis(rc_manual.precinct);
    rc_manual.precinct.precinct_copy(prec_manual);
    precinct_top = jxs.Constants.iif(prec_manual.is_first_of_slice(cfg_manual.p.slice_height), [], rc_manual.precinct_top);

    jxs.internal.gcli_budget.fill(rc_manual.gc_enabled_modes, prec_manual, ...
        precinct_top, [], rc_manual.pbt, rc_manual.pred_residuals, 0, cfg_manual.p.S_s);
    jxs.internal.data_budget.fill_data_budget_table(prec_manual, rc_manual.pbt, ...
        cfg_manual.p.N_g, cfg_manual.p.Fs, cfg_manual.p.Qpih);
    if ~prec_manual.is_first_of_slice(cfg_manual.p.slice_height)
        ver_modes = jxs.internal.gcli_methods.get_enabled_ver(rc_manual.gc_enabled_modes);
        jxs.internal.gcli_budget.fill(ver_modes, rc_manual.precinct, rc_manual.precinct_top, ...
            rc_manual.gtli_table_gcli_prec, rc_manual.pbt, rc_manual.pred_residuals, 1, cfg_manual.p.S_s);
    end

    spacial_lines = prec_manual.spacial_lines_of(rc_manual.image_height);
    budget_cbr = jxs.internal.budget.getcbr(rc_manual.nibbles_image, ...
        rc_manual.lines_consumed + spacial_lines, rc_manual.image_height);
    rc_manual.ra_params.budget = bitshift(int32(budget_cbr) - rc_manual.nibbles_consumed, 2);
    fprintf(fid, 'manual budget_bits=%d lines_consumed=%d nibbles_consumed=%d\n', ...
        rc_manual.ra_params.budget, rc_manual.lines_consumed, rc_manual.nibbles_consumed);

    [quant_manual, ref_manual] = rc_manual.do_rate_allocation(prec_manual);
    [gtli_data, gtli_gcli, ~] = jxs.internal.sb_weighting.compute_gtli_tables( ...
        quant_manual, ref_manual, prec_manual.bands_count(), ...
        cfg_manual.p.lvl_gains, cfg_manual.p.lvl_priorities);
    methods_manual = jxs.internal.precinct_budget.get_best_gcli_method( ...
        prec_manual, rc_manual.pbt, gtli_gcli);
    [prec_bits_manual, ~, sigf_manual, gcli_manual, data_manual, sign_manual, ~, raw_manual, prec_hdr_manual] = ...
        jxs.internal.precinct_budget.get_budget(prec_manual, rc_manual.pbt, ...
        gtli_gcli, gtli_data, cfg_manual.p.Rl, methods_manual);
    fprintf(fid, 'manual quant=%d ref=%d Lprc=%d\n', ...
        quant_manual, ref_manual, prec_bits_manual - prec_hdr_manual);
    dump_subpkts(fid, sigf_manual, gcli_manual, data_manual, sign_manual, raw_manual);
    dump_methods(fid, 'manual_methods', methods_manual);

    for refinement = max(int32(0), ref_manual - 1):min(int32(prec_manual.bands_count() - 1), ref_manual + 1)
        [cand_data, cand_gcli, ~] = jxs.internal.sb_weighting.compute_gtli_tables( ...
            quant_manual, refinement, prec_manual.bands_count(), ...
            cfg_manual.p.lvl_gains, cfg_manual.p.lvl_priorities);
        cand_methods = jxs.internal.precinct_budget.get_best_gcli_method( ...
            prec_manual, rc_manual.pbt, cand_gcli);
        [cand_bits, ~, ~, ~, ~, ~, ~, ~, cand_hdr] = ...
            jxs.internal.precinct_budget.get_budget(prec_manual, rc_manual.pbt, ...
            cand_gcli, cand_data, cfg_manual.p.Rl, cand_methods);
        fprintf(fid, 'candidate ref=%d Lprc=%d\n', refinement, cand_bits - cand_hdr);
    end

    [im_actual, cfg_actual, ids_actual] = setup_case();
    rc_actual = setup_rc(im_actual, cfg_actual, ids_actual);
    prec_actual = jxs.internal.precinct();
    prec_actual.open_column(ids_actual, cfg_actual.p.N_g, 0);

    for y = int32(0):(target_y - 1)
        prec_actual.set_y_idx(y);
        prec_actual.from_image(im_actual, cfg_actual.p.Fq);
        prec_actual.update_gclis();
        rc_actual.process_precinct(prec_actual);
    end

    prec_actual.set_y_idx(target_y);
    prec_actual.from_image(im_actual, cfg_actual.p.Fq);
    prec_actual.update_gclis();
    actual = rc_actual.process_precinct(prec_actual);
    fprintf(fid, 'actual quant=%d ref=%d Lprc=%d\n', ...
        actual.quantization, actual.refinement, ...
        actual.pbinfo.precinct_bits - actual.pbinfo.prec_header_size);
    dump_subpkts(fid, actual.pbinfo.subpkt_size_sigf, actual.pbinfo.subpkt_size_gcli, ...
        actual.pbinfo.subpkt_size_data, actual.pbinfo.subpkt_size_sign, ...
        actual.pbinfo.subpkt_uses_raw_fallback);
    dump_methods(fid, 'actual_methods', actual.gcli_sb_methods);
catch ME
    fprintf(fid, 'ERROR:%s\n', ME.message);
    for i = 1:numel(ME.stack)
        fprintf(fid, 'STACK:%s:%d\n', ME.stack(i).file, ME.stack(i).line);
    end
end

fclose(fid);

function [im, cfg, ids_obj] = setup_case()
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
end

function rc = setup_rc(im, cfg, ids_obj)
bp = jxs.internal.bitpacker();
header_buf = zeros(1, 65536, 'uint8');
bp.set_buffer(header_buf, 65536);
header_len = jxs.internal.xs_markers.write_head(bp, im, cfg);

rc = jxs.internal.rate_control();
rc.open(cfg, ids_obj, 0);

min_col_nbytes = int64(ids_obj.npy) * 4;
overhead = int64(bitshift(header_len, -3)) + 2 + 6 * ...
    int64(idivide(int32(ids_obj.h) + int32(cfg.p.slice_height) - 1, int32(cfg.p.slice_height), 'floor'));
total_bytes = int64(cfg.bitstream_size_in_bytes);
rc_bytes = total_bytes - overhead;
report_bytes = int64(floor(double(int32(cfg.budget_report_lines) / 2 * 2) * ...
    double(cfg.bitstream_size_in_bytes) / double(ids_obj.h)));
bytes_per_col = idivide((rc_bytes - min_col_nbytes) * int64(ids_obj.cs), int64(ids_obj.w), 'floor');
report_per_col = idivide(report_bytes * int64(ids_obj.cs), int64(ids_obj.w), 'floor');
last_col_bytes = rc_bytes - int64(ids_obj.npx - 1) * bytes_per_col;
last_col_report = report_bytes - int64(ids_obj.npx - 1) * report_per_col;
rc.init(int32(last_col_bytes), int32(last_col_report));
end

function dump_subpkts(fid, sigf_sz, gcli_sz, data_sz, sign_sz, raw_flags)
for sp = 1:numel(sigf_sz)
    fprintf(fid, '  subpkt[%d] raw=%d sigf=%d gcli=%d data=%d sign=%d\n', ...
        sp - 1, raw_flags(sp), sigf_sz(sp), gcli_sz(sp), data_sz(sp), sign_sz(sp));
end
end

function dump_methods(fid, label, methods)
fprintf(fid, '%s:', label);
for i = 1:numel(methods)
    fprintf(fid, ' %d', methods(i));
end
fprintf(fid, '\n');
end

end
