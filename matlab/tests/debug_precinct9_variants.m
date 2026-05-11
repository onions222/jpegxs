cd('/Users/silas/Desktop/code/VideoCompress/jpegxs/matlab');
addpath(genpath(cd));

diag_path = '/private/tmp/debug_precinct9_variants.txt';
fid = fopen(diag_path, 'w');

try
    variants = { ...
        struct('name', 'rc_only', 'do_quant', false, 'do_swap', false, 'do_pack', false), ...
        struct('name', 'quant_only', 'do_quant', true, 'do_swap', false, 'do_pack', false), ...
        struct('name', 'quant_swap', 'do_quant', true, 'do_swap', true, 'do_pack', false), ...
        struct('name', 'quant_swap_pack', 'do_quant', true, 'do_swap', true, 'do_pack', true)};

    for vi = 1:numel(variants)
        v = variants{vi};
        res = run_variant(v);
        fprintf(fid, '%s: quant=%d ref=%d Lprc=%d\n', ...
            v.name, res.quantization, res.refinement, ...
            res.pbinfo.precinct_bits - res.pbinfo.prec_header_size);
    end
catch ME
    fprintf(fid, 'ERROR:%s\n', ME.message);
    for i = 1:numel(ME.stack)
        fprintf(fid, 'STACK:%s:%d\n', ME.stack(i).file, ME.stack(i).line);
    end
end

fclose(fid);

function rc_results = run_variant(v)
target_y = int32(9);
[im, cfg, ids_obj] = setup_case();

rc = setup_rc(im, cfg, ids_obj);
bp = [];
pack_ctx = [];

if v.do_swap
    prec_cur = jxs.internal.precinct();
    prec_cur.open_column(ids_obj, cfg.p.N_g, 0);
    prec_top = jxs.internal.precinct();
    prec_top.open_column(ids_obj, cfg.p.N_g, 0);
else
    prec_cur = jxs.internal.precinct();
    prec_cur.open_column(ids_obj, cfg.p.N_g, 0);
    prec_top = [];
end

if v.do_pack
    buf_size = int32(im.width) * int32(im.height) * int32(im.ncomps) * 2 + 1024 * 1024;
    bitstream_bytes = zeros(1, double(buf_size), 'uint8');
    bp = jxs.internal.bitpacker();
    bp.set_buffer(bitstream_bytes, double(buf_size));
    pack_ctx = jxs.internal.packing.packer_open(cfg, prec_cur);
    cfg.p.lvl_gains(ids_obj.nbands + 1) = int32(255);
    cfg.p.lvl_priorities(ids_obj.nbands + 1) = int32(255);
    jxs.internal.xs_markers.write_head(bp, im, cfg);
end

slice_idx = int32(0);
for y = int32(0):(target_y - 1)
    prec_cur.set_y_idx(y);
    prec_cur.from_image(im, cfg.p.Fq);
    prec_cur.update_gclis();
    prev_top = jxs.Constants.iif(v.do_swap && ~prec_cur.is_first_of_slice(cfg.p.slice_height), prec_top, []);
    rc_prev = rc.process_precinct(prec_cur);
    if v.do_quant
        prec_cur.quantize(rc_prev.gtli_table_data, cfg.p.Qpih);
    end
    if v.do_pack
        if prec_cur.is_first_of_slice(cfg.p.slice_height)
            jxs.internal.xs_markers.write_slice_header(bp, slice_idx);
            slice_idx = slice_idx + 1;
        end
        jxs.internal.packing.pack_precinct(pack_ctx, bp, prec_cur, rc_prev, prev_top);
    end
    if v.do_swap
        tmp = prec_top;
        prec_top = prec_cur;
        prec_cur = tmp;
    end
end

prec_cur.set_y_idx(target_y);
prec_cur.from_image(im, cfg.p.Fq);
prec_cur.update_gclis();
rc_results = rc.process_precinct(prec_cur);
end

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

end
