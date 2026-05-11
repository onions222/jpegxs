cd('/Users/silas/Desktop/code/VideoCompress/jpegxs/matlab');
addpath(genpath(cd));

diag_path = '/private/tmp/trace_encode_progress.txt';
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

    n_cols = ids_obj.npx;
    precincts = cell(1, n_cols);
    precincts_top = cell(1, n_cols);
    rc_list = cell(1, n_cols);
    for col = 1:n_cols
        precincts{col} = jxs.internal.precinct();
        precincts{col}.open_column(ids_obj, cfg.p.N_g, col - 1);
        precincts_top{col} = jxs.internal.precinct();
        precincts_top{col}.open_column(ids_obj, cfg.p.N_g, col - 1);
        rc_list{col} = jxs.internal.rate_control();
        rc_list{col}.open(cfg, ids_obj, col - 1);
    end

    buf_size = int32(im.width) * int32(im.height) * int32(im.ncomps) * 2 + 1024 * 1024;
    bitstream_bytes = zeros(1, double(buf_size), 'uint8');
    bp = jxs.internal.bitpacker();
    bp.set_buffer(bitstream_bytes, double(buf_size));
    pack_ctx = jxs.internal.packing.packer_open(cfg, precincts{1});

    cfg.p.lvl_gains(ids_obj.nbands + 1) = int32(255);
    cfg.p.lvl_priorities(ids_obj.nbands + 1) = int32(255);
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
    last_col_bytes = rc_bytes - int64(n_cols - 1) * bytes_per_col;
    last_col_report = report_bytes - int64(n_cols - 1) * report_per_col;
    for col = 1:(n_cols - 1)
        rc_list{col}.init(int32(bytes_per_col), int32(report_per_col));
    end
    rc_list{n_cols}.init(int32(last_col_bytes), int32(last_col_report));

    jxs.internal.nlt.forward_transform(im, cfg.p);
    jxs.internal.mct.forward_transform(im, cfg.p);
    jxs.internal.dwt.forward_transform(ids_obj, im);

    slice_idx = int32(0);
    precinct_counter = int32(0);
    for line_idx = int32(0):ids_obj.ph:(int32(im.height) - 1)
        prec_y_idx = idivide(line_idx, ids_obj.ph, 'floor');
        fprintf(fid, 'row_start y=%d slice_idx=%d bitpos=%d\n', prec_y_idx, slice_idx, bp.get_len());
        fprintf(1, 'row_start y=%d slice_idx=%d bitpos=%d\n', prec_y_idx, slice_idx, bp.get_len());
        for col = 1:n_cols
            fprintf(fid, '  before_rc y=%d col=%d\n', prec_y_idx, col - 1);
            fprintf(1, '  before_rc y=%d col=%d\n', prec_y_idx, col - 1);
            precincts{col}.set_y_idx(prec_y_idx);
            precincts{col}.from_image(im, cfg.p.Fq);
            precincts{col}.update_gclis();

            rc_results = rc_list{col}.process_precinct(precincts{col});
            fprintf(fid, '  after_rc y=%d col=%d quant=%d ref=%d Lprc=%d\n', ...
                prec_y_idx, col - 1, rc_results.quantization, rc_results.refinement, ...
                rc_results.pbinfo.precinct_bits - rc_results.pbinfo.prec_header_size);
            fprintf(1, '  after_rc y=%d col=%d quant=%d ref=%d Lprc=%d\n', ...
                prec_y_idx, col - 1, rc_results.quantization, rc_results.refinement, ...
                rc_results.pbinfo.precinct_bits - rc_results.pbinfo.prec_header_size);
            precincts{col}.quantize(rc_results.gtli_table_data, cfg.p.Qpih);

            if precincts{col}.is_first_of_slice(cfg.p.slice_height) && col == 1
                jxs.internal.xs_markers.write_slice_header(bp, slice_idx);
                slice_idx = slice_idx + 1;
            end

            first_of_slice = precincts{col}.is_first_of_slice(cfg.p.slice_height);
            prec_top = jxs.Constants.iif(first_of_slice, [], precincts_top{col});
            jxs.internal.packing.pack_precinct(pack_ctx, bp, precincts{col}, rc_results, prec_top);
            fprintf(fid, '  after_pack y=%d col=%d bitpos=%d\n', prec_y_idx, col - 1, bp.get_len());
            fprintf(1, '  after_pack y=%d col=%d bitpos=%d\n', prec_y_idx, col - 1, bp.get_len());

            precinct_counter = precinct_counter + 1;
            if precinct_counter >= 128
                fprintf(fid, 'STOP_AFTER precincts=%d\n', precinct_counter);
                fprintf(1, 'STOP_AFTER precincts=%d\n', precinct_counter);
                fclose(fid);
                return;
            end
        end

        for col = 1:n_cols
            tmp = precincts_top{col};
            precincts_top{col} = precincts{col};
            precincts{col} = tmp;
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
