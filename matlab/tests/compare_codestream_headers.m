cd('/Users/silas/Desktop/code/VideoCompress/jpegxs/matlab');
addpath(genpath(cd));

path_a = '/Users/silas/Desktop/code/VideoCompress/jpegxs/samples/matlab_encoder_output_size1103754.jxs';
path_b = '/private/tmp/c_encoder_output_size1103754.jxs';
diag_path = '/private/tmp/compare_codestream_headers.txt';
fid = fopen(diag_path, 'w');

try
    hdrs_a = read_precinct_headers(path_a);
    hdrs_b = read_precinct_headers(path_b);

    fprintf(fid, 'count_a=%d count_b=%d\n', numel(hdrs_a), numel(hdrs_b));
    count = min(numel(hdrs_a), numel(hdrs_b));
    mismatch_count = 0;
    for i = 1:count
        a = hdrs_a(i);
        b = hdrs_b(i);
        same_methods = isequal(a.methods, b.methods);
        same = (a.Lprc == b.Lprc) && (a.quant == b.quant) && (a.ref == b.ref) && same_methods;
        if ~same
            mismatch_count = mismatch_count + 1;
            fprintf(fid, 'mismatch precinct=%d slice=%d col=%d y=%d\n', i - 1, a.slice_idx, a.column, a.y_idx);
            fprintf(fid, '  matlab Lprc=%d quant=%d ref=%d\n', a.Lprc, a.quant, a.ref);
            fprintf(fid, '  cref   Lprc=%d quant=%d ref=%d\n', b.Lprc, b.quant, b.ref);
            diff_idx = find(a.methods ~= b.methods);
            if isempty(diff_idx)
                fprintf(fid, '  methods: identical\n');
            else
                fprintf(fid, '  method diffs:');
                for k = 1:numel(diff_idx)
                    idx = diff_idx(k);
                    fprintf(fid, ' [%d]%d/%d', idx - 1, a.methods(idx), b.methods(idx));
                end
                fprintf(fid, '\n');
            end
            if mismatch_count >= 12
                break;
            end
        end
    end

    if mismatch_count == 0 && numel(hdrs_a) == numel(hdrs_b)
        fprintf(fid, 'ALL_HEADERS_MATCH\n');
    end
catch ME
    fprintf(fid, 'ERROR:%s\n', ME.message);
    for i = 1:numel(ME.stack)
        fprintf(fid, 'STACK:%s:%d\n', ME.stack(i).file, ME.stack(i).line);
    end
end

fclose(fid);

function hdrs = read_precinct_headers(path_in)
    bytes = fread(fopen(path_in, 'rb'), inf, 'uint8=>uint8')';
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

    prec = jxs.internal.precinct();
    c = jxs.Constants;
    hdrs = repmat(struct('slice_idx', int32(0), 'column', int32(0), 'y_idx', int32(0), ...
        'Lprc', int32(0), 'quant', int32(0), 'ref', int32(0), 'methods', zeros(1, ids_obj.nbands, 'int32')), ...
        1, double(ids_obj.np));

    out_idx = 1;
    slice_idx = int32(0);
    for y = int32(0):(ids_obj.npy - 1)
        for col = int32(0):(ids_obj.npx - 1)
            prec.open_column(ids_obj, cfg.p.N_g, col);
            prec.set_y_idx(y);
            if prec.is_first_of_slice(cfg.p.slice_height) && col == 0
                [ok, got_slice_idx] = jxs.internal.xs_markers.parse_slice_header(bu);
                if ~ok
                    error('bad slice header');
                end
                slice_idx = int32(got_slice_idx);
            end

            [v, ~] = bu.read(c.PREC_HDR_PREC_SIZE); Lprc = bitshift(int32(v), 3);
            [v, ~] = bu.read(c.PREC_HDR_QUANTIZATION_SIZE); quantization = int32(v);
            [v, ~] = bu.read(c.PREC_HDR_REFINEMENT_SIZE); refinement = int32(v);

            methods = zeros(1, prec.bands_count(), 'int32');
            for band = int32(0):(prec.bands_count() - 1)
                [v, ~] = bu.read(c.GCLI_METHOD_NBITS);
                methods(band + 1) = jxs.internal.gcli_methods.from_signaling(int32(v), ...
                    jxs.internal.gcli_methods.get_enabled(cfg));
            end
            bu.align(c.PREC_HDR_ALIGNMENT);
            bu.skip(Lprc);

            hdrs(out_idx).slice_idx = slice_idx;
            hdrs(out_idx).column = col;
            hdrs(out_idx).y_idx = y;
            hdrs(out_idx).Lprc = Lprc;
            hdrs(out_idx).quant = quantization;
            hdrs(out_idx).ref = refinement;
            hdrs(out_idx).methods = methods;
            out_idx = out_idx + 1;
        end
    end

    hdrs = hdrs(1:out_idx - 1);
end
