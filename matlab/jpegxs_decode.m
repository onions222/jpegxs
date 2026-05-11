% jpegxs_decode.m — JPEG XS 解码主入口。
%
% 对应 C 参考实现：xs_dec.c
%
% 作用：
%   把一段 JPEG XS 码流解开，恢复成 jxs.internal.image。
%
% 解码流程和编码正好相反：
%   1. 解析头部，恢复配置和图像尺寸
%   2. 逐 precinct 解包 header / GCLI / DATA / SIGN
%   3. dequantize 后把 precinct 写回变换域图像
%   4. 依次执行 DWT / MCT / NLT 逆变换

function image = jpegxs_decode(bitstream_bytes)
    import jxs.*; import jxs.internal.*;

    % 先构造 bitunpacker，用于从 uint8 码流里逐 bit 读取字段。
    bu = bitunpacker();
    bu.set_buffer(bitstream_bytes(:)', length(bitstream_bytes));

    config = xs_config.default_config();
    % 先给一个最小占位 image，真正尺寸会在 parse_head 里被覆盖。
    im = jxs.internal.image();
    im.ncomps = int32(3); im.width = int32(64); im.height = int32(64);
    im.depth = int32(8);
    im.sx = ones(1, 4, 'int32'); im.sy = ones(1, 4, 'int32');

    [ok, config] = xs_markers.parse_head(bu, im, config);
    if ~ok, error('Failed to parse codestream header'); end
    fprintf('Parsed: %dx%d, ncomps=%d, depth=%d\n', im.width, im.height, im.ncomps, im.depth);

    % 头解析出来后，才能按真实尺寸分配输出图像。
    im.allocate(false);

    % IDS 必须和编码端完全一致，否则 band/precinct 定位会错位。
    ids_obj = ids();
    ids_obj.construct(im, config.p.NLx, config.p.NLy, config.p.Sd, config.p.Cw, config.p.Lh);
    fprintf('IDs: nbands=%d, npx=%d, npy=%d\n', ids_obj.nbands, ids_obj.npx, ids_obj.npy);

    % precincts / precincts_top / gtlis_table_top 分别对应：
    %   当前行工作块、上一行工作块、上一行 GCLI 表
    n_cols = ids_obj.npx;
    precincts = cell(1, n_cols);
    precincts_top = cell(1, n_cols);
    gtlis_table_top = cell(1, n_cols);
    for col = 1:n_cols
        precincts{col} = precinct();
        precincts{col}.open_column(ids_obj, config.p.N_g, col - 1);
        precincts_top{col} = precinct();
        precincts_top{col}.open_column(ids_obj, config.p.N_g, col - 1);
        gtlis_table_top{col} = zeros(1, Constants.MAX_NBANDS, 'int32');
    end

    unpack_ctx = packing.unpacker_open(config, precincts{1});

    % unpack_precinct 需要从码流起点重新顺序读取一次，这里把游标复位。
    bu.set_buffer(bitstream_bytes(:)', length(bitstream_bytes));
    [~, ~] = xs_markers.parse_head(bu, [], []);

    % 逐 precinct 解包；顺序必须和编码端完全一致。
    slice_idx = int32(0);
    for line_idx = int32(0):ids_obj.ph:(int32(im.height) - 1)
        prec_y_idx = idivide(line_idx, ids_obj.ph, 'floor');
        for col = 1:n_cols
            precincts{col}.set_y_idx(prec_y_idx);
            % 每个 slice 的起点必须先读 slice header，并校验索引。
            if precincts{col}.is_first_of_slice(config.p.slice_height) && col == 1
                [ok, chk] = xs_markers.parse_slice_header(bu);
                if ~ok, error('Bad slice header'); end
                assert(chk == slice_idx);
                slice_idx = slice_idx + 1;
            end

            first_of_slice = precincts{col}.is_first_of_slice(config.p.slice_height);
            prec_top = jxs.Constants.iif(first_of_slice, [], precincts_top{col});

            % gtlis_table_top 保存上一行 precinct 的 GCLI 表，
            % 解码垂直预测方法时会用到。
            info_out = struct('data_len', zeros(1, 79, 'int32'), ...
                'gcli_len', zeros(1, 79, 'int32'), ...
                'sign_len', zeros(1, 79, 'int32'), ...
                'gtli_table_data', zeros(1, 79, 'int32'), ...
                'gtli_table_gcli', zeros(1, 79, 'int32'));

            % 先解出量化后的 sign-magnitude 系数，再反量化写回图像。
            [gtli_data, gtli_gcli] = packing.unpack_precinct(unpack_ctx, bu, precincts{col}, prec_top, gtlis_table_top{col}, info_out);

            precincts{col}.dequantize(gtli_data, config.p.Qpih);
            precincts{col}.to_image(im, config.p.Fq);

            % 更新上一行缓存，供下一行 precinct 使用。
            tmp = precincts_top{col};
            precincts_top{col} = precincts{col};
            precincts{col} = tmp;
            gtlis_table_top{col} = gtli_gcli;
        end
    end

    % 回到像素域。
    fprintf('Inverse DWT...\n');
    dwt.inverse_transform(ids_obj, im);
    fprintf('Inverse MCT...\n');
    mct.inverse_transform(im, config.p);
    fprintf('Inverse NLT...\n');
    nlt.inverse_transform(im, config.p);

    ok = xs_markers.parse_tail(bu);
    if ~ok, warning('Missing EOC marker'); end
    image = im;
end
