% packing.m — precinct 码流打包/解包核心引擎。
%
% 对应 C 参考实现：libjxs/src/packing.c
% 标准位置：ISO/IEC 21122-1 Annex F
%
% 这是整个 MATLAB 端最复杂的模块之一，负责把“一个 precinct
% 的量化后系数”变成“JPEG XS 语法规定的 bitstream 片段”，反向也一样。
%
% 主要职责：
%   - pack_precinct / unpack_precinct
%   - GCLI 熵编码
%   - DATA bit-plane 编码
%   - SIGN 子包编码
%   - precinct/subpacket header 的写入与解析
%
% 一个 precinct 在码流里的大致结构是：
%   [precinct header]
%   [subpkt0 header][SIGF][GCLI][DATA][SIGN]
%   [subpkt1 header][...]

classdef packing
    methods (Static)
        function ctx = packer_open(xs_config, prec)
            % pack/unpack 上下文并不保存“当前 bitstream 位置”这类瞬时状态，
            % 它主要保存两个长生命周期对象：
            % 1. 当前配置允许哪些 GCLI 编码方法；
            % 2. 编码过程中反复复用的 significance buffer，
            %    避免每个 sub-packet 都重新分配临时内存。
            ctx = struct();
            ctx.xs_config = xs_config;
            ctx.enabled_methods = jxs.internal.gcli_methods.get_enabled(xs_config);
            ctx.gcli_significance = jxs.internal.sigbuffer(prec);
            ctx.gcli_nonsig_flags = jxs.internal.sigbuffer(prec);
        end

        function ctx = unpacker_open(xs_config, prec)
            import jxs.Constants;
            ctx = struct();
            ctx.xs_config = xs_config;
            ctx.level_count = prec.bands_count();
            max_gcli_w = prec.ids.band_max_width;
            Ng = int32(xs_config.p.N_g);
            pred_buf_len = idivide(max_gcli_w + Ng - 1, Ng, 'floor');
            ctx.gtli_table_data = zeros(1, max(1, prec.ids.npi), 'int32');
            ctx.gtli_table_gcli = zeros(1, max(1, prec.ids.npi), 'int32');
            ctx.gclis_pred = zeros(max(1, pred_buf_len), 1, 'int8');
            ctx.use_sign_subpkt = (xs_config.p.Fs == 1);
            ctx.inclusion_mask = zeros(max(1, pred_buf_len), 1, 'int32');
            ctx.enabled_methods = jxs.internal.gcli_methods.get_enabled(xs_config);
            ctx.gclis_significance = jxs.internal.sigbuffer(prec);
        end

        function nbits = pack_data(bitstream, buf, buf_len, gclis, group_size, gtli, sign_packing)
            % PACK_DATA  Write wavelet coefficient bit-planes to bitstream.
            %   For each GCLI group with gcli > gtli, writes sign bits
            %   (unless Fs=1) followed by magnitude bit-planes from
            %   MSB (gcli-1) down to LSB (gtli).
            %
            %   C reference: pack_data()  (packing.c:172)
            import jxs.Constants;
            nbits = int32(0); idx = int32(1);
            gs = int32(group_size); gtl = int32(gtli);
            % 一个 GCLI 对应一整组样本，所以 group 数 = ceil(buf_len / group_size)。
            n_groups = idivide(int32(buf_len) + gs - 1, gs, 'floor');
            for group = 1:n_groups
                if int32(gclis(group)) > gtl
                    % 当 group 的 GCLI 小于等于 GTLI 时，
                    % 说明这一组所有可见 bit-plane 都已经被截断，不写任何 DATA。
                    if sign_packing == 0
                        % Fs=0: 符号位直接混在 DATA 前面写。
                        % 规范要求组内按样本顺序先写 sign，再写各个 bit-plane。
                        for i = int32(1):gs
                            if idx <= buf_len
                                nbits = nbits + bitstream.write(uint64(bitshift(buf(idx), -Constants.SIGN_BIT_POSITION)), 1);
                            end
                            idx = idx + 1;
                        end
                    else
                        % Fs=1: SIGN 单独放到 sign sub-packet，
                        % DATA 这里只负责 magnitude bit-planes。
                        idx = idx + gs;
                    end
                    idx = idx - gs;
                    % DATA 按“从高 bit-plane 到低 bit-plane”输出。
                    % bp = gcli-1 ... gtli，对应 Annex F 的 MSB-first 顺序。
                    for bp = int32(gclis(group)) - 1:-1:gtl
                        for i = int32(1):gs
                            if idx + i - 1 <= buf_len
                                nbits = nbits + bitstream.write(uint64(bitand(bitshift(buf(idx + i - 1), -bp), uint32(1))), 1);
                            end
                        end
                    end
                end
                idx = idx + gs;
            end
        end

        function unpack_data(bitstream, buf, buf_len, gclis, group_size, gtli, sign_packing)
            % Mirrors unpack_data in packing.c lines 201-231 exactly
            import jxs.Constants;
            gs = int32(group_size); gtl = int32(gtli);
            idx = int32(1);
            n_groups = idivide(int32(buf_len) + gs - 1, gs, 'floor');
            for group = 1:n_groups
                % 解码前先把当前组清零，后面通过 OR 的方式逐 bit-plane 拼回去。
                for i = int32(1):gs
                    if idx + i - 1 <= buf_len, buf(idx + i - 1) = uint32(0); end
                end
                if int32(gclis(group)) > gtl
                    if sign_packing == 0
                        % Fs=0 时，码流里先出现 sign bit，
                        % 所以要先把 sign 放回 sign-magnitude 的最高位。
                        for i = int32(1):gs
                            [v, ~] = bitstream.read(1);
                            if idx + i - 1 <= buf_len
                                buf(idx + i - 1) = bitor(buf(idx + i - 1), bitshift(uint32(v), Constants.SIGN_BIT_POSITION));
                            end
                        end
                    end
                    for bp = int32(gclis(group)) - 1:-1:gtl
                        for i = int32(1):gs
                            [v, ~] = bitstream.read(1);
                            if idx + i - 1 <= buf_len
                                buf(idx + i - 1) = bitor(buf(idx + i - 1), bitshift(bitand(v, uint64(1)), bp));
                            end
                        end
                    end
                end
                idx = idx + gs;
            end
        end

        function nbits = pack_sign(bitstream, buf, buf_len, gclis, group_size, gtli)
            import jxs.Constants;
            nbits = int32(0); idx = int32(1);
            n_groups = idivide(int32(buf_len) + group_size - 1, group_size, 'floor');
            for group = 1:n_groups
                for i = 1:group_size
                    if idx > buf_len, break; end
                    % Fs=1 时，只有“这个样本在当前 GTLI 下仍非零”才会写 sign。
                    % 条件里的 bitcmp(sign_mask) 用来去掉最高位，只保留 magnitude。
                    if int32(gclis(group)) > gtli && ...
                       bitshift(bitand(buf(idx), bitcmp(Constants.SIGN_BIT_MASK, 'uint32')), -gtli) ~= 0
                        nbits = nbits + bitstream.write(uint64(bitshift(buf(idx), -Constants.SIGN_BIT_POSITION)), 1);
                    end
                    idx = idx + 1;
                end
            end
        end

        function unpack_sign(bitstream, buf, buf_len, group_size)
            import jxs.Constants;
            idx = int32(1);
            n_groups = idivide(int32(buf_len) + group_size - 1, group_size, 'floor');
            for group = 1:n_groups
                for i = 1:group_size
                    if idx > buf_len, break; end
                    if buf(idx) ~= 0
                        [v, ~] = bitstream.read(1);
                        if idx <= buf_len
                            buf(idx) = bitor(buf(idx), bitshift(bitand(uint32(v), uint32(1)), Constants.SIGN_BIT_POSITION));
                        end
                    end
                    idx = idx + 1;
                end
            end
        end

        function nbits = unary_encode(bitstream, pred_buf, len_val, no_sign, alph)
            nbits = int32(0);
            for i = 1:len_val
                % no_sign=true 表示 residual 一定非负，可以走 unsigned unary；
                % 否则要用带符号 alphabet，把正负 residual 都编码进去。
                if ~no_sign
                    nbits = nbits + bitstream.write_unary_signed(pred_buf(i), alph);
                else
                    nbits = nbits + bitstream.write_unary_unsigned(pred_buf(i));
                end
            end
        end

        function [pred_buf, nbits] = unary_decode(bitstream, pred_buf, inclusion_mask, len_val, no_sign, alph)
            nbits = int32(0);
            for i = 1:len_val
                if i <= length(inclusion_mask) && inclusion_mask(i)
                    if ~no_sign
                        [v, nb] = bitstream.read_unary_signed_val(alph);
                        pred_buf(i) = v; nbits = nbits + nb;
                    else
                        [v, nb] = bitstream.read_unary_unsigned_val();
                        pred_buf(i) = v; nbits = nbits + nb;
                    end
                else
                    if i <= length(pred_buf), pred_buf(i) = int8(0); end
                end
            end
        end

        function nbits = pack_raw_gclis(bitstream, gclis, len_val)
            nbits = int32(0);
            for i = 1:len_val
                nbits = nbits + bitstream.write(uint64(gclis(i)), 4);
            end
        end

        function unpack_raw_gclis(bitstream, gclis, len_val)
            for i = 1:len_val
                [v, ~] = bitstream.read(4);
                gclis(i) = int8(v);
            end
        end

        function pack_precinct(ctx, bitstream, precinct, ra_result, precinct_top)
            % PACK_PRECINCT  Encode one full precinct into the bitstream.
            %   Emits: precinct header, then for each sub-packet:
            %   [subpkt_hdr] [SIGF] [GCLI] [DATA] [SIGN] [padding]
            %
            %   C reference: pack_precinct()  (packing.c:260)
            import jxs.Constants;
            position_count = precinct.ids.npi;
            use_long = precinct.use_long_headers();
            % precinct header 记录 3 类全局信息：
            % 1. 当前 precinct 去掉 header 后一共多少字节；
            % 2. 全局 quantization / refinement；
            % 3. 每个 band 选中的 GCLI 熵编码方法。
            bitstream.write(uint64(bitshift(ra_result.precinct_total_bits - ra_result.pbinfo.prec_header_size, -3)), Constants.PREC_HDR_PREC_SIZE);
            bitstream.write(uint64(ra_result.quantization), Constants.PREC_HDR_QUANTIZATION_SIZE);
            bitstream.write(uint64(ra_result.refinement), Constants.PREC_HDR_REFINEMENT_SIZE);
            for band = int32(0):(precinct.bands_count() - 1)
                method_signaling = jxs.internal.gcli_methods.get_signaling(ra_result.gcli_sb_methods(band + 1), ctx.enabled_methods);
                if method_signaling < 0
                    error('raw GCLI method cannot be signaled in precinct header');
                end
                bitstream.write(uint64(method_signaling), Constants.GCLI_METHOD_NBITS);
            end
            bitstream.align(Constants.PREC_HDR_ALIGNMENT);

            len_before_prc_data = bitstream.get_len();
            subpkt = int32(0); idx_start = int32(0);
            while idx_start < position_count
                % position 是把“band + y 行号”摊平成的一维索引。
                % 这里先找到一个 sub-packet 覆盖的连续 position 区间 [idx_start, idx_stop]。
                idx_stop = idx_start;
                while idx_stop < position_count - 1 && precinct.subpkt_of(idx_stop) == precinct.subpkt_of(idx_stop + 1)
                    idx_stop = idx_stop + 1;
                end
                lvl = precinct.band_index_of(idx_start);
                ypos = precinct.ypos_of(idx_start);
                if ypos >= precinct.in_band_height_of(lvl)
                    % 有些 position 只是为了让表结构完整，实际并没有对应有效行。
                    % 这种“逻辑占位行”直接跳过，但 sub-packet 编号仍要推进。
                    subpkt = subpkt + 1; idx_start = idx_stop + 1; continue;
                end

                sp1 = subpkt + 1;
                % sub-packet header 给后面的 3 段变长内容(DATA/GCLI/SIGN)定界。
                % 这些长度在 rate allocation 阶段已经提前估好。
                bitstream.write(uint64(ra_result.pbinfo.subpkt_uses_raw_fallback(sp1)), 1);
                sz = jxs.Constants.iif(use_long, Constants.PKT_HDR_DATA_SIZE_LONG, Constants.PKT_HDR_DATA_SIZE_SHORT);
                bitstream.write(uint64(bitshift(ra_result.pbinfo.subpkt_size_data(sp1), -3)), sz);
                sz = jxs.Constants.iif(use_long, Constants.PKT_HDR_GCLI_SIZE_LONG, Constants.PKT_HDR_GCLI_SIZE_SHORT);
                bitstream.write(uint64(bitshift(ra_result.pbinfo.subpkt_size_gcli(sp1), -3)), sz);
                sz = jxs.Constants.iif(use_long, Constants.PKT_HDR_SIGN_SIZE_LONG, Constants.PKT_HDR_SIGN_SIZE_SHORT);
                bitstream.write(uint64(bitshift(ra_result.pbinfo.subpkt_size_sign(sp1), -3)), sz);
                bitstream.align(Constants.PKT_HDR_ALIGNMENT);

                len_before_subpkt = bitstream.get_len();
                if ra_result.pbinfo.subpkt_uses_raw_fallback(sp1) == 0
                    % raw fallback 时不会写 SIGF，因为 raw GCLI 已经逐组直接给出 4bit 值。
                    jxs.internal.packing.pack_gclis_significance(ctx, bitstream, precinct, ra_result, idx_start, idx_stop);
                end
                bitstream.align(Constants.SUBPKT_ALIGNMENT);
                if bitstream.get_len() - len_before_subpkt ~= ra_result.pbinfo.subpkt_size_sigf(sp1)
                    error('SIGF length mismatch');
                end

                len_before_subpkt = bitstream.get_len();
                for idx = idx_start:idx_stop
                    lvl = precinct.band_index_of(idx);
                    ypos = precinct.ypos_of(idx);
                    if ypos >= precinct.in_band_height_of(lvl), continue; end
                    % 这里 pack 的是“每一行 band-line 的 GCLI 语法”，
                    % 不是原始 wavelet 数据。真正的系数数据在后面的 DATA/SIGN 段。
                    jxs.internal.packing.pack_gclis(ctx, bitstream, precinct, ra_result, idx);
                end
                bitstream.align(Constants.SUBPKT_ALIGNMENT);
                if bitstream.get_len() - len_before_subpkt ~= ra_result.pbinfo.subpkt_size_gcli(sp1)
                    error('GCLI length mismatch');
                end

                len_before_subpkt = bitstream.get_len();
                for idx = idx_start:idx_stop
                    lvl = precinct.band_index_of(idx);
                    ypos = precinct.ypos_of(idx);
                    if ypos >= precinct.in_band_height_of(lvl), continue; end
                    gtli = ra_result.gtli_table_data(lvl + 1);
                    % DATA 用 gtli_table_data，而不是 gtli_table_gcli。
                    % 这是因为 GCLI 的截断阈值和真实系数的截断阈值在标准里可以不同。
                    jxs.internal.packing.pack_data(bitstream, precinct.line_of(lvl, ypos), ...
                        int32(precinct.width_of(lvl)), precinct.gcli_of(lvl, ypos), ...
                        precinct.group_size, gtli, ctx.xs_config.p.Fs);
                end
                bitstream.align(Constants.SUBPKT_ALIGNMENT);
                if bitstream.get_len() - len_before_subpkt ~= ra_result.pbinfo.subpkt_size_data(sp1)
                    error('DATA length mismatch');
                end

                len_before_subpkt = bitstream.get_len();
                if ctx.xs_config.p.Fs == 1
                    for idx = idx_start:idx_stop
                        lvl = precinct.band_index_of(idx);
                        ypos = precinct.ypos_of(idx);
                        if ypos >= precinct.in_band_height_of(lvl), continue; end
                        gtli = ra_result.gtli_table_data(lvl + 1);
                        jxs.internal.packing.pack_sign(bitstream, precinct.line_of(lvl, ypos), ...
                            int32(precinct.width_of(lvl)), precinct.gcli_of(lvl, ypos), ...
                            precinct.group_size, gtli);
                    end
                    bitstream.align(Constants.SUBPKT_ALIGNMENT);
                end
                if bitstream.get_len() - len_before_subpkt ~= ra_result.pbinfo.subpkt_size_sign(sp1)
                    error('SIGN length mismatch');
                end

                subpkt = subpkt + 1;
                idx_start = idx_stop + 1;
            end

            if ra_result.pbinfo.precinct_bits > 0 && ...
               (bitstream.get_len() - len_before_prc_data) ~= ...
               (ra_result.pbinfo.precinct_bits - ra_result.pbinfo.prec_header_size)
                error('precinct packed length mismatch');
            end
            if mod(bitstream.get_len(), 4) ~= 0
                error('precinct end is not aligned to 4 bits');
            end
            % precinct 末尾可能还要补 padding_bits，
            % 用于满足整个 slice / frame 预算，补位本身不携带语义信息。
            bitstream.add_padding(ra_result.padding_bits);
        end

        function nbits = pack_gclis_significance(ctx, bitstream, precinct, ra_result, idx_start, idx_stop)
            nbits = int32(0);
            sig_flags_obj = [];
            for idx = idx_start:idx_stop
                lvl = precinct.band_index_of(idx);
                ypos = precinct.ypos_of(idx);
                if ypos >= precinct.in_band_height_of(lvl)
                    continue;
                end
                gtli = ra_result.gtli_table_gcli(lvl + 1);
                sb_method = ra_result.gcli_sb_methods(lvl + 1);
                if jxs.Constants.method_uses_sig_flags(sb_method)
                    if isempty(sig_flags_obj)
                        sig_flags_obj = jxs.internal.sig_flags(precinct.ids.band_max_width, ctx.xs_config.p.S_s);
                    end
                    % 大多数方法用“预测 residual 是否显著”来生成 significance flags；
                    % 但 ZRCSF 要用 no-pred 残差来决定 runs，这里要切换数据源。
                    pred_type = jxs.Constants.method_get_pred(sb_method);
                    pred_res = ra_result.pred_residuals.direction{pred_type + 1};
                    pred_sig = pred_res;
                    if jxs.Constants.method_get_run(sb_method) == jxs.Constants.RUN_SIGFLAGS_ZRCSF
                        pred_sig = ra_result.pred_residuals.direction{jxs.Constants.PRED_NONE + 1};
                    end
                    gcli_len = precinct.gcli_width_of(lvl);
                    sig_flags_obj.init(pred_sig.values{lvl + 1, ypos + 1, gtli + 1}, gcli_len, ctx.xs_config.p.S_s);
                    nbits = nbits + sig_flags_obj.write(bitstream);
                end
            end
        end

        function err = pack_gclis(ctx, bitstream, precinct, ra_result, position)
            lvl = precinct.band_index_of(position);
            ypos = precinct.ypos_of(position);
            gtli = ra_result.gtli_table_gcli(lvl + 1);
            subpkt = precinct.subpkt_of(position);
            if ra_result.pbinfo.subpkt_uses_raw_fallback(subpkt + 1) == 1
                % raw fallback 是兜底策略：
                % 不再做任何预测/熵编码，直接把每个 GCLI 用 4 bit 原样写出。
                jxs.internal.packing.pack_raw_gclis(bitstream, precinct.gcli_of(lvl, ypos), precinct.gcli_width_of(lvl));
                err = 0;
                return;
            end

            sb_method = ra_result.gcli_sb_methods(lvl + 1);
            pred_type = jxs.Constants.method_get_pred(sb_method);
            pred = ra_result.pred_residuals.direction{pred_type + 1};
            values_to_code = pred.values{lvl + 1, ypos + 1, gtli + 1};
            predictors = pred.predictors{lvl + 1, ypos + 1, gtli + 1};
            values_len = precinct.gcli_width_of(lvl);

            if jxs.Constants.method_uses_sig_flags(sb_method)
                % filter_values 会把“不显著的组”从 residual 序列里删掉，
                % 因而真正熵编码的长度可能小于原始 gcli_width。
                sig_source = values_to_code;
                if jxs.Constants.method_get_run(sb_method) == jxs.Constants.RUN_SIGFLAGS_ZRCSF
                    pred_none = ra_result.pred_residuals.direction{jxs.Constants.PRED_NONE + 1};
                    sig_source = pred_none.values{lvl + 1, ypos + 1, gtli + 1};
                end
                sf = jxs.internal.sig_flags(precinct.ids.band_max_width, ctx.xs_config.p.S_s);
                sf.init(sig_source, values_len, ctx.xs_config.p.S_s);
                [values_to_code, values_len] = sf.filter_values(values_to_code);
                values_to_code = values_to_code(1:values_len);
                [predictors, pred_len] = sf.filter_values(predictors);
                predictors = predictors(1:pred_len);
            else
                values_to_code = values_to_code(1:values_len);
                predictors = predictors(1:values_len);
            end

            no_sign = jxs.Constants.method_uses_no_pred(sb_method);
            if jxs.Constants.method_get_alphabet(sb_method) ~= jxs.Constants.ALPHABET_UNARY_UNSIGNED_BOUNDED || ...
               jxs.Constants.method_get_pred(sb_method) == jxs.Constants.PRED_NONE
                % 普通 unary alphabet：直接编码 residual 序列。
                jxs.internal.packing.unary_encode(bitstream, values_to_code, values_len, no_sign, jxs.Constants.FIRST_ALPHABET);
            else
                % bounded alphabet 不是直接写 residual，而是先把 residual
                % 投影到 [min_v, max_v] 对应的 unary code index，再写 unsigned unary。
                for i = 1:values_len
                    [min_v, max_v] = jxs.internal.bitpacker.bounded_code_get_min_max(predictors(i), gtli);
                    code = jxs.internal.bitpacker.bounded_code_get_unary_code(values_to_code(i), min_v, max_v);
                    bitstream.write_unary_unsigned(code);
                end
            end
            err = 0;
        end

        function vals = get_prediction_values(ra_result, lvl, ypos, gtli, sb_method, precinct, precinct_top)
            % Get GCLI prediction residuals, computing them if needed
            import jxs.Constants;
            gclis = precinct.gcli_of(lvl, ypos);
            gcli_width = precinct.gcli_width_of(lvl);

            % Try to get from predbuffer
            pred_type = Constants.method_get_pred(sb_method);
            if isfield(ra_result, 'pred_residuals') && ~isempty(ra_result.pred_residuals) ...
               && isprop(ra_result.pred_residuals, 'direction')
                dp = ra_result.pred_residuals.direction{pred_type + 1};
                vals = dp.values{lvl + 1, ypos + 1, gtli + 1};
                if ~isempty(vals) && length(vals) >= gcli_width
                    vals = vals(1:gcli_width);
                    return;
                end
            end

            % Fallback: compute residuals
            vals = zeros(gcli_width, 1, 'int8');
            if Constants.method_uses_ver_pred(sb_method) && ~isempty(precinct_top)
                gclis_top = precinct.gcli_top_of(precinct_top, lvl, ypos);
                if ~isempty(gclis_top)
                    [vals, ~] = jxs.internal.pred.ver(gclis, gclis_top, gcli_width, vals, vals, gtli, gtli);
                end
            else
                vals = jxs.internal.pred.none(gclis, gcli_width, vals, gtli);
            end
        end

        function predictors = get_prediction_predictors(ra_result, lvl, ypos, gtli, sb_method)
            import jxs.Constants;
            gcli_width = int32(1);
            pred_type = Constants.method_get_pred(sb_method);
            if isfield(ra_result, 'pred_residuals') && ~isempty(ra_result.pred_residuals) ...
               && isprop(ra_result.pred_residuals, 'direction')
                dp = ra_result.pred_residuals.direction{pred_type + 1};
                preds = dp.predictors{lvl + 1, ypos + 1, gtli + 1};
                if ~isempty(preds)
                    predictors = preds;
                    return;
                end
            end
            predictors = zeros(1, 1, 'int8');
        end

        function [gtli_data, gtli_gcli] = unpack_precinct(ctx, bitstream, precinct, precinct_top, gtli_table_top, info_out)
            % UNPACK_PRECINCT  Decode one full precinct from the bitstream.
            %   Reads: precinct header, then for each sub-packet:
            %   [subpkt_hdr] [SIGF] [GCLI] [DATA] [SIGN]
            %   Returns GTLI tables for downstream dequantization.
            %
            %   C reference: unpack_precinct()  (packing.c:340)
            import jxs.Constants;
            % Lprc 是“当前 precinct 除去 precinct header 后”的总长度，单位 byte。
            % 读出来后左移 3，是为了统一转成 bit 数做后续边界检查。
            [v, ~] = bitstream.read(Constants.PREC_HDR_PREC_SIZE); Lprc = bitshift(int32(v), 3);
            [v, ~] = bitstream.read(Constants.PREC_HDR_QUANTIZATION_SIZE); quantization = int32(v);
            [v, ~] = bitstream.read(Constants.PREC_HDR_REFINEMENT_SIZE); refinement = int32(v);

            n_bands = precinct.bands_count();
            gcli_sb_methods = zeros(1, n_bands, 'int32');
            for band = int32(0):(n_bands - 1)
                [v, ~] = bitstream.read(Constants.GCLI_METHOD_NBITS);
                gcli_sb_methods(band + 1) = jxs.internal.gcli_methods.from_signaling(int32(v), ctx.enabled_methods);
            end
            bitstream.align(Constants.PREC_HDR_ALIGNMENT);

            bitpos_at_prc_data = int32(bitstream.consumed_bits());

            [gtli_data, gtli_gcli, ~] = jxs.internal.sb_weighting.compute_gtli_tables(...
                quantization, refinement, n_bands, ...
                ctx.xs_config.p.lvl_gains, ctx.xs_config.p.lvl_priorities);
            % 解码时不需要重新搜索 rate allocation，
            % 但必须用 header 里的 quant/ref 重新推导出每个 band 的 GTLI。
            ctx.gtli_table_data = gtli_data;
            ctx.gtli_table_gcli = gtli_gcli;

            position_count = precinct.ids.npi;
            use_long = precinct.use_long_headers();
            subpkt = int32(0);
            idx_start = int32(0);
            while idx_start < position_count
                idx_stop = idx_start;
                while idx_stop < position_count - 1 && precinct.subpkt_of(idx_stop) == precinct.subpkt_of(idx_stop + 1)
                    idx_stop = idx_stop + 1;
                end

                lvl = precinct.band_index_of(idx_start);
                ypos = precinct.ypos_of(idx_start);
                if ypos >= precinct.in_band_height_of(lvl)
                    subpkt = subpkt + 1; idx_start = idx_stop + 1; continue;
                end

                [v, ~] = bitstream.read(1); uses_raw = int32(v);
                % header 里的长度字段按 byte 存储；
                % 这里先按字段宽度读出来，后面真正比较边界时再统一换算。
                sz_bits = jxs.Constants.iif(use_long, Constants.PKT_HDR_DATA_SIZE_LONG, Constants.PKT_HDR_DATA_SIZE_SHORT);
                [v, ~] = bitstream.read(sz_bits); info_out.data_len(subpkt + 1) = int32(v);
                sz_bits = jxs.Constants.iif(use_long, Constants.PKT_HDR_GCLI_SIZE_LONG, Constants.PKT_HDR_GCLI_SIZE_SHORT);
                [v, ~] = bitstream.read(sz_bits); info_out.gcli_len(subpkt + 1) = int32(v);
                sz_bits = jxs.Constants.iif(use_long, Constants.PKT_HDR_SIGN_SIZE_LONG, Constants.PKT_HDR_SIGN_SIZE_SHORT);
                [v, ~] = bitstream.read(sz_bits); info_out.sign_len(subpkt + 1) = int32(v);
                bitstream.align(Constants.PKT_HDR_ALIGNMENT);

                % Read SIGF subpacket if any band uses sig_flags
                has_sigf = false;
                for idx = idx_start:idx_stop
                    lvl = precinct.band_index_of(idx);
                    if precinct.ypos_of(idx) >= precinct.in_band_height_of(lvl), continue; end
                    if jxs.Constants.method_uses_sig_flags(gcli_sb_methods(lvl + 1))
                        has_sigf = true; break;
                    end
                end

                if has_sigf && ~uses_raw
                    % Read significance flags for all bands in this subpacket
                    for idx = idx_start:idx_stop
                        lvl = precinct.band_index_of(idx);
                        ypos = precinct.ypos_of(idx);
                        if ypos >= precinct.in_band_height_of(lvl), continue; end
                        if ~jxs.Constants.method_uses_sig_flags(gcli_sb_methods(lvl + 1))
                            continue;
                        end
                        gcli_width = precinct.gcli_width_of(lvl);
                        sf = jxs.internal.sig_flags(precinct.ids.band_max_width, ctx.xs_config.p.S_s);
                        sf.read_flags(bitstream, gcli_width, ctx.xs_config.p.S_s);
                        % 这里不直接存“原始 flags 比特”，而是存 inclusion_mask。
                        % 后续 GCLI 熵解码时会用它决定哪些 group 需要真正读 residual。
                        sig_vals = ctx.gclis_significance.values(lvl, ypos);
                        inclusion = sf.inclusion_mask();
                        for gi = 1:min(length(sig_vals), gcli_width)
                            if gi <= length(inclusion)
                                sig_vals(gi) = int8(inclusion(gi));
                            end
                        end
                        sig_idx = ctx.gclis_significance.idx_from_level(ypos + 1, lvl + 1);
                        ctx.gclis_significance.sig_values{sig_idx} = sig_vals;
                    end
                end
                bitstream.align(Constants.SUBPKT_ALIGNMENT);

                % Unpack GCLIs with proper prediction and inclusion masks
                for idx = idx_start:idx_stop
                    lvl = precinct.band_index_of(idx);
                    ypos = precinct.ypos_of(idx);
                    if ypos >= precinct.in_band_height_of(lvl), continue; end
                    gclis = precinct.gcli_of(lvl, ypos);
                    gcli_width = precinct.gcli_width_of(lvl);
                    sb_method = gcli_sb_methods(lvl + 1);
                    gtli = ctx.gtli_table_gcli(lvl + 1);

                    if uses_raw || jxs.Constants.method_is_raw(sb_method)
                        % Raw GCLI: read exactly 4 bits per group (extra values consumed as padding)
                        for gi = int32(1):gcli_width
                            [v, ~] = bitstream.read(4);
                            if gi <= length(gclis)
                                gclis(gi) = int8(v);
                            end
                        end
                        precinct.set_gcli(lvl, ypos, gclis);
                    else
                        gclis_top = [];
                        gtli_top = gtli;
                        if ~isempty(precinct_top)
                            gclis_top = precinct.gcli_top_of(precinct_top, lvl, ypos);
                            if ypos == 0 && ~isempty(gtli_table_top)
                                gtli_top = gtli_table_top(lvl + 1);
                            end
                        end

                        % Build inclusion mask
                        sig_flags_zrcsf = (jxs.Constants.method_get_run(sb_method) == jxs.Constants.RUN_SIGFLAGS_ZRCSF);
                        if jxs.Constants.method_uses_sig_flags(sb_method)
                            sig_vals = ctx.gclis_significance.values(lvl, ypos);
                            for gi = int32(1):min(gcli_width, int32(length(ctx.inclusion_mask)))
                                ctx.inclusion_mask(gi) = int32(sig_vals(gi));
                            end
                        else
                            for gi = int32(1):gcli_width
                                ctx.inclusion_mask(gi) = int32(1);
                            end
                        end

                        no_pred = jxs.Constants.method_uses_no_pred(sb_method) || ...
                                  (jxs.Constants.method_uses_ver_pred(sb_method) && isempty(gclis_top));

                        if no_pred || jxs.Constants.method_get_alphabet(sb_method) ~= Constants.ALPHABET_UNARY_UNSIGNED_BOUNDED
                            [ctx.gclis_pred, ~] = jxs.internal.packing.unary_decode(bitstream, ctx.gclis_pred, ...
                                ctx.inclusion_mask, gcli_width, no_pred, Constants.FIRST_ALPHABET);
                        else
                            for gi = int32(1):gcli_width
                                if gi <= length(ctx.inclusion_mask) && ctx.inclusion_mask(gi)
                                    pred_val = int32(0);
                                    if ~isempty(gclis_top) && gi <= length(gclis_top)
                                        pred_val = jxs.internal.pred.ver_compute_predictor(int32(gclis_top(gi)), int32(gtli_top), int32(gtli));
                                    end
                                    [min_v, max_v] = jxs.internal.bitpacker.bounded_code_get_min_max(pred_val, gtli);
                                    [val, ~] = bitstream.read_bounded_code_val(int8(min_v), int8(max_v));
                                    ctx.gclis_pred(gi) = val;
                                else
                                    ctx.gclis_pred(gi) = int8(0);
                                end
                            end
                        end

                        if jxs.Constants.method_uses_ver_pred(sb_method) && ~isempty(gclis_top)
                            gclis = jxs.internal.pred.ver_inverse(ctx.gclis_pred, gclis_top, gcli_width, gclis, int32(gtli), int32(gtli_top));
                            if sig_flags_zrcsf
                                for gi = int32(1):gcli_width
                                    if gi <= length(ctx.inclusion_mask) && ~ctx.inclusion_mask(gi)
                                        gclis(gi) = int8(0);
                                    end
                                end
                            end
                        else
                            gclis = jxs.internal.pred.none_inverse(ctx.gclis_pred, gcli_width, gclis, int32(gtli));
                        end
                        precinct.set_gcli(lvl, ypos, gclis);
                    end
                end
                bitstream.align(Constants.SUBPKT_ALIGNMENT);

                % Unpack DATA
                for idx = idx_start:idx_stop
                    lvl = precinct.band_index_of(idx);
                    ypos = precinct.ypos_of(idx);
                    if ypos >= precinct.in_band_height_of(lvl), continue; end
                    gtli = ctx.gtli_table_data(lvl + 1);
                    gclis = precinct.gcli_of(lvl, ypos);
                    buf = precinct.line_of(lvl, ypos);
                    gs = precinct.group_size; gtl = int32(gtli);
                    n_groups = idivide(int32(precinct.width_of(lvl)) + gs - 1, gs, 'floor');
                    idx_d = int32(1);
                    for group = 1:n_groups
                        for i = int32(1):gs
                            if idx_d + i - 1 <= length(buf), buf(idx_d + i - 1) = uint32(0); end
                        end
                        if group <= length(gclis) && int32(gclis(group)) > gtl
                            if ctx.use_sign_subpkt == 0
                                for i = int32(1):gs
                                    [v, ~] = bitstream.read(1);
                                    if idx_d + i - 1 <= length(buf)
                                        buf(idx_d + i - 1) = bitor(buf(idx_d + i - 1), uint32(bitshift(v, jxs.Constants.SIGN_BIT_POSITION)));
                                    end
                                end
                            end
                            for bp = int32(gclis(group)) - 1:-1:gtl
                                for i = int32(1):gs
                                    [v, ~] = bitstream.read(1);
                                    if idx_d + i - 1 <= length(buf)
                                        buf(idx_d + i - 1) = bitor(buf(idx_d + i - 1), uint32(bitshift(bitand(v, uint64(1)), bp)));
                                    end
                                end
                            end
                        end
                        idx_d = idx_d + gs;
                    end
                    precinct.set_line(lvl, ypos, buf);
                end
                bitstream.align(Constants.SUBPKT_ALIGNMENT);

                % Unpack SIGN
                if ctx.use_sign_subpkt
                    for idx = idx_start:idx_stop
                        lvl = precinct.band_index_of(idx);
                        ypos = precinct.ypos_of(idx);
                        if ypos >= precinct.in_band_height_of(lvl), continue; end
                        buf = precinct.line_of(lvl, ypos);
                        gs = precinct.group_size;
                        n_groups = idivide(int32(precinct.width_of(lvl)) + gs - 1, gs, 'floor');
                        idx_s = int32(1);
                        for group = 1:n_groups
                            for i = int32(1):gs
                                if idx_s > length(buf), break; end
                                if buf(idx_s) ~= 0
                                    [v, ~] = bitstream.read(1);
                                    if idx_s <= length(buf)
                                        buf(idx_s) = bitor(buf(idx_s), uint32(bitshift(bitand(v, uint64(1)), jxs.Constants.SIGN_BIT_POSITION)));
                                    end
                                end
                                idx_s = idx_s + 1;
                            end
                        end
                        precinct.set_line(lvl, ypos, buf);
                    end
                    bitstream.align(Constants.SUBPKT_ALIGNMENT);
                end

                subpkt = subpkt + 1;
                idx_start = idx_stop + 1;
            end

            % Skip padding
            padding_len = Lprc - (int32(bitstream.consumed_bits()) - bitpos_at_prc_data);
            if padding_len > 0, bitstream.skip(padding_len); end

            gtli_data = ctx.gtli_table_data;
            gtli_gcli = ctx.gtli_table_gcli;
        end
    end
end
