% jpegxs_encode.m — JPEG XS 编码主入口。
%
% 对应 C 参考实现：libjxs/src/xs_enc.c (xs_enc_image)
%
% 作用：
%   把已经装入 jxs.internal.image 的图像，压缩成 JPEG XS 码流
%   （返回 uint8 行向量）。
%
% 输入：
%   IMAGE  — jxs.internal.image 对象，内部保存各分量的平铺像素
%   CONFIG — 由 xs_config.default_config() 生成的配置结构体
%
% 主流程：
%   1. 解析并补全自动配置项
%   2. 构建 IDS（分解结构 / band / precinct 组织关系）
%   3. 写入码流头，并初始化每列 precinct 的 rate-control 状态
%   4. 依次执行 NLT / MCT / DWT 正变换
%   5. 逐个 precinct 做：
%        提取系数 -> 计算 GCLI -> 码率控制 -> 量化 -> 打包
%   6. 写入 slice header 和 EOC，输出最终 bitstream

function bitstream = jpegxs_encode(image, config)

    import jxs.*; import jxs.internal.*;

    if nargin < 2, config = xs_config.default_config(); end
    [~, config] = xs_config.resolve_auto_values(config, image);
    xs_config.validate(config, image);

    if config.p.color_transform == Constants.XS_CPIH_TETRIX
        error('Tetrix/Bayer not yet supported');
    end

    % IDS 描述整张图在 JPEG XS 下如何被切成 band、packet、precinct。
    ids_obj = ids();
    ids_obj.construct(image, config.p.NLx, config.p.NLy, config.p.Sd, config.p.Cw, config.p.Lh);

    n_cols = ids_obj.npx;
    % 每一列 precinct 都有一套独立的工作对象：
    %   precincts      —— 当前行正在处理的 precinct
    %   precincts_top  —— 上一行 precinct，用于垂直预测
    %   rc_list        —— 每列自己的码率控制状态
    precincts = cell(1, n_cols);
    precincts_top = cell(1, n_cols);
    rc_list = cell(1, n_cols);
    for col = 1:n_cols
        precincts{col} = precinct();
        precincts{col}.open_column(ids_obj, config.p.N_g, col - 1);
        precincts_top{col} = precinct();
        precincts_top{col}.open_column(ids_obj, config.p.N_g, col - 1);
        rc_list{col} = rate_control();
        rc_list{col}.open(config, ids_obj, col - 1);
    end

    % 先分配一个偏保守的输出缓冲区；真正返回时会裁成实际长度。
    buf_size = int32(image.width) * int32(image.height) * int32(image.ncomps) * 2 + 1024*1024;
    bitstream_bytes = zeros(1, double(buf_size), 'uint8');
    bp = bitpacker();
    bp.set_buffer(bitstream_bytes, double(buf_size));

    pack_ctx = packing.packer_open(config, precincts{1});
    % WGT marker 用 255 作为权重表终止哨兵，这里确保 sentinel 落在 nbands+1。
    config.p.lvl_gains(ids_obj.nbands + 1) = int32(255);
    config.p.lvl_priorities(ids_obj.nbands + 1) = int32(255);
    header_len = xs_markers.write_head(bp, image, config);

    if config.bitstream_size_in_bytes == intmax('uint64')
        % 无限码率模式：直接给一个极大预算，相当于不做 CBR 约束。
        for col = 1:n_cols
            rc_list{col}.init(int32(hex2dec('FFFFFFF')), int32(hex2dec('FFFFFFF')));
        end
    else
        % 有限码率模式：先从总目标大小里扣掉头部、slice header 等固定开销，
        % 再把剩余预算按列拆开。
        min_col_nbytes = int64(ids_obj.npy) * 4;
        overhead = int64(bitshift(header_len, -3)) + 2 + 6 * ...
            int64(idivide(int32(image.height) + int32(config.p.slice_height) - 1, int32(config.p.slice_height), 'floor'));
        total_bytes = int64(config.bitstream_size_in_bytes);
        rc_bytes = total_bytes - overhead;
        report_bytes = int64(floor(double(int32(config.budget_report_lines) / 2 * 2) * double(config.bitstream_size_in_bytes) / double(image.height)));
        bytes_per_col = idivide((rc_bytes - min_col_nbytes) * int64(ids_obj.cs), int64(image.width), 'floor');
        report_per_col = idivide(report_bytes * int64(ids_obj.cs), int64(image.width), 'floor');
        last_col_bytes = rc_bytes - int64(n_cols - 1) * bytes_per_col;
        last_col_report = report_bytes - int64(n_cols - 1) * report_per_col;
        for col = 1:(n_cols - 1)
            rc_list{col}.init(int32(bytes_per_col), int32(report_per_col));
        end
        rc_list{n_cols}.init(int32(last_col_bytes), int32(last_col_report));
    end

    % 先把像素域数据变到 JPEG XS 的变换域。
    nlt.forward_transform(image, config.p);
    mct.forward_transform(image, config.p);
    dwt.forward_transform(ids_obj, image);

    slice_idx = int32(0);
    % 按 precinct 高度逐行推进；同一行内再按列处理。
    for line_idx = int32(0):ids_obj.ph:(int32(image.height) - 1)
        prec_y_idx = idivide(line_idx, ids_obj.ph, 'floor');
        for col = 1:n_cols
            % 1. 从当前变换域图像中抽出这一块 precinct 系数
            precincts{col}.set_y_idx(prec_y_idx);
            precincts{col}.from_image(image, config.p.Fq);
            precincts{col}.update_gclis();

            % 2. 先做 rate control，决定量化强度与 refinement
            rc_results = rc_list{col}.process_precinct(precincts{col});
            precincts{col}.quantize(rc_results.gtli_table_data, config.p.Qpih);

            % 3. 每个 slice 的第一个 precinct 前都要插入 slice header
            if precincts{col}.is_first_of_slice(config.p.slice_height) && col == 1
                xs_markers.write_slice_header(bp, slice_idx);
                slice_idx = slice_idx + 1;
            end

            % 4. 正式把 precinct 打包进码流
            first_of_slice = precincts{col}.is_first_of_slice(config.p.slice_height);
            prec_top = jxs.Constants.iif(first_of_slice, [], precincts_top{col});
            packing.pack_precinct(pack_ctx, bp, precincts{col}, rc_results, prec_top);
        end
        % 当前行处理完成后，交换 top/current 缓冲，给下一行做垂直预测。
        for col = 1:n_cols
            tmp = precincts_top{col};
            precincts_top{col} = precincts{col};
            precincts{col} = tmp;
        end
    end

    % 码流尾部只需写 EOC，然后裁出实际已写入的字节。
    xs_markers.write_tail(bp);
    bitstream = bp.get_bytes();
end
