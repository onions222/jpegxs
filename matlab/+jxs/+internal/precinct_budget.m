% precinct_budget.m — precinct 总预算汇总器。
%
% 对应 C 参考实现：libjxs/src/precinct_budget.c
%
% 它把 SIGF / GCLI / DATA / SIGN 各部分预算合并，
% 给出一个 precinct 在当前参数下的总 bit 数。
% coding method per sub-band and determines raw-fallback decisions.

classdef precinct_budget
    methods (Static)
        function bgt_info = get_best_gcli_method(prec, pbt, gtli_table_gcli)
            % GET_BEST_GCLI_METHOD  Select cheapest GCLI method per sub-band.
            %   For each band, evaluate all enabled methods and pick the
            %   one with the lowest total bit cost at the given GTLI.
            %
            %   C reference: precinct_get_best_gcli_method()  (precinct_budget.c:16)
            import jxs.Constants;
            n_bands = prec.bands_count();
            gcli_sb_methods = zeros(1, n_bands, 'int32');
            for lvl = int32(0):(n_bands - 1)
                bgt_min = Constants.RA_BUDGET_INVALID;
                bgt_min_method = int32(-1);
                for gcli_method = int32(0):(Constants.GCLI_METHODS_NB - 1)
                    gtli = gtli_table_gcli(lvl + 1);
                    % raw method 不在这里参与“最佳熵编码方法”竞争，
                    % raw fallback 会在下一阶段单独比较整个 sub-packet 的总成本。
                    if gcli_method == Constants.method_get_idx(Constants.ALPHABET_RAW_4BITS, Constants.PRED_NONE, Constants.RUN_NONE)
                        continue;
                    end
                    buf = pbt.gcli_bgt_of(gcli_method, 0);
                    if gtli + 1 > length(buf) || buf(gtli + 1) == Constants.RA_BUDGET_INVALID
                        continue;
                    end
                    bgt_method = int32(0);
                    height = prec.in_band_height_of(lvl);
                    for y_pos = int32(0):(height - 1)
                        position = prec.position_of(lvl, y_pos);
                        sigf_buf = pbt.sigf_bgt_of(gcli_method, position);
                        gcli_buf = pbt.gcli_bgt_of(gcli_method, position);
                        % 一条 band-line 的 GCLI 成本 = significance flags + GCLI residual 本体。
                        line_bgt = int32(0);
                        if gtli + 1 <= length(sigf_buf), line_bgt = line_bgt + int32(sigf_buf(gtli + 1)); end
                        if gtli + 1 <= length(gcli_buf), line_bgt = line_bgt + int32(gcli_buf(gtli + 1)); end
                        bgt_method = bgt_method + line_bgt;
                    end
                    if bgt_min == Constants.RA_BUDGET_INVALID || bgt_method < bgt_min
                        bgt_min = bgt_method;
                        bgt_min_method = int32(gcli_method);
                    end
                end
                if bgt_min == Constants.RA_BUDGET_INVALID
                    bgt_min_method = int32(Constants.method_get_idx(Constants.ALPHABET_RAW_4BITS, Constants.PRED_NONE, Constants.RUN_NONE));
                end
                gcli_sb_methods(lvl + 1) = bgt_min_method;
            end
            bgt_info = gcli_sb_methods;
        end

        function [precinct_bits, pkt_header_size, subpkt_size_sigf, subpkt_size_gcli, subpkt_size_data, subpkt_size_sign, subpkt_size_gcli_raw, subpkt_uses_raw, prec_header_size] = ...
                get_budget(prec, pbt, gtli_table_gcli, gtli_table_data, Rl, gcli_sb_methods)
            % GET_BUDGET  Compute total precinct bit budget with raw fallback.
            %   Sums per-sub-packet sizes (SIGF + GCLI + DATA + SIGN),
            %   aligns each to byte boundaries, and applies raw-fallback
            %   logic (replacing GCLI+SIGF with raw 4-bit GCLIs when cheaper).
            %
            %   C reference: precinct_get_budget()  (precinct_budget.c:56)
            import jxs.Constants;
            nb_subpkts = double(prec.nb_subpkts());
            position_count = double(prec.ids.npi);
            use_long = prec.use_long_headers();

            subpkt_size_sigf = zeros(1, nb_subpkts, 'int32');
            subpkt_size_gcli = zeros(1, nb_subpkts, 'int32');
            subpkt_size_data = zeros(1, nb_subpkts, 'int32');
            subpkt_size_sign = zeros(1, nb_subpkts, 'int32');
            subpkt_size_gcli_raw = zeros(1, nb_subpkts, 'int32');
            subpkt_uses_raw = zeros(1, nb_subpkts, 'int32');
            pkt_header_size = zeros(1, nb_subpkts, 'int32');

            prec_header_size = jxs.internal.precinct_budget_table.align_to_bits(...
                Constants.PREC_HDR_PREC_SIZE + Constants.PREC_HDR_QUANTIZATION_SIZE + ...
                Constants.PREC_HDR_REFINEMENT_SIZE + prec.bands_count() * Constants.GCLI_METHOD_NBITS, ...
                Constants.PREC_HDR_ALIGNMENT);
            % precinct_bits 从“固定 header 开销”开始累计，
            % 后面再把每个 sub-packet 的 header + payload 叠加上去。
            precinct_bits = int32(prec_header_size);

            raw_method = Constants.method_get_idx(Constants.ALPHABET_RAW_4BITS, Constants.PRED_NONE, Constants.RUN_NONE);

            for position = int32(0):(position_count - 1)
                lvl = prec.band_index_of(position);
                ypos = prec.ypos_of(position);
                if ypos >= prec.in_band_height_of(lvl), continue; end

                subpkt = double(prec.subpkt_of(position));
                if use_long
                    pkt_header_size(subpkt + 1) = jxs.internal.precinct_budget_table.align_to_bits(...
                        Constants.PKT_HDR_DATA_SIZE_LONG + Constants.PKT_HDR_GCLI_SIZE_LONG + ...
                        Constants.PKT_HDR_SIGN_SIZE_LONG + 1, Constants.PKT_HDR_ALIGNMENT);
                else
                    pkt_header_size(subpkt + 1) = jxs.internal.precinct_budget_table.align_to_bits(...
                        Constants.PKT_HDR_DATA_SIZE_SHORT + Constants.PKT_HDR_GCLI_SIZE_SHORT + ...
                        Constants.PKT_HDR_SIGN_SIZE_SHORT + 1, Constants.PKT_HDR_ALIGNMENT);
                end

                gtli_gcli = gtli_table_gcli(lvl + 1);
                gtli_data = gtli_table_data(lvl + 1);
                gcli_method = gcli_sb_methods(lvl + 1);

                sigf_buf = pbt.sigf_bgt_of(gcli_method, position);
                gcli_buf = pbt.gcli_bgt_of(gcli_method, position);
                data_buf = pbt.data_bgt_of(position);
                sign_buf = pbt.sign_bgt_of(position);

                if gtli_gcli + 1 <= length(sigf_buf)
                    subpkt_size_sigf(subpkt + 1) = subpkt_size_sigf(subpkt + 1) + int32(sigf_buf(gtli_gcli + 1));
                end
                if gtli_gcli + 1 <= length(gcli_buf)
                    subpkt_size_gcli(subpkt + 1) = subpkt_size_gcli(subpkt + 1) + int32(gcli_buf(gtli_gcli + 1));
                end
                % DATA/SIGN 使用 data GTLI 表，而不是 gcli GTLI 表。
                % 这两个表在 refinement 打开时可能不同。
                if gtli_data + 1 <= length(data_buf)
                    subpkt_size_data(subpkt + 1) = subpkt_size_data(subpkt + 1) + int32(data_buf(gtli_data + 1));
                end
                if gtli_data + 1 <= length(sign_buf)
                    subpkt_size_sign(subpkt + 1) = subpkt_size_sign(subpkt + 1) + int32(sign_buf(gtli_data + 1));
                end

                raw_buf = pbt.gcli_bgt_of(raw_method, position);
                if gtli_gcli + 1 <= length(raw_buf)
                    raw_bgt = int32(raw_buf(gtli_gcli + 1));
                    if raw_bgt == Constants.RA_BUDGET_INVALID
                        subpkt_size_gcli_raw(subpkt + 1) = Constants.RA_BUDGET_INVALID;
                    elseif subpkt_size_gcli_raw(subpkt + 1) ~= Constants.RA_BUDGET_INVALID
                        subpkt_size_gcli_raw(subpkt + 1) = subpkt_size_gcli_raw(subpkt + 1) + raw_bgt;
                    end
                end
            end

            % Align subpkt sizes
            for s = 1:nb_subpkts
                % 真实码流里每段子流写完后都会对齐到 byte 边界，
                % 预算器必须提前把这些对齐损耗算进去，否则 rate-control 会系统性偏小。
                if subpkt_size_gcli_raw(s) ~= Constants.RA_BUDGET_INVALID
                    subpkt_size_gcli_raw(s) = jxs.internal.precinct_budget_table.align_to_bits(subpkt_size_gcli_raw(s), 8);
                end
                subpkt_size_sigf(s) = jxs.internal.precinct_budget_table.align_to_bits(subpkt_size_sigf(s), 8);
                subpkt_size_gcli(s) = jxs.internal.precinct_budget_table.align_to_bits(subpkt_size_gcli(s), 8);
                subpkt_size_data(s) = jxs.internal.precinct_budget_table.align_to_bits(subpkt_size_data(s), 8);
                subpkt_size_sign(s) = jxs.internal.precinct_budget_table.align_to_bits(subpkt_size_sign(s), 8);
            end

            % Raw fallback detection
            if Rl == 0
                % Rl=0 时 fallback 粒度是“整 band”：
                % 只有当这个 band 涉及的所有 sub-packet 全部切到 raw 更划算时才切。
                for band = int32(0):(prec.bands_count() - 1)
                    size_noraw = int32(0); size_raw = int32(0);
                    height = prec.in_band_height_of(band);
                    for ypos = int32(0):(height - 1)
                        pos = prec.position_of(band, ypos);
                        subpkt = double(prec.subpkt_of(pos)) + 1;
                        if subpkt_uses_raw(subpkt) == 1, break; end
                        size_noraw = size_noraw + subpkt_size_gcli(subpkt) + subpkt_size_sigf(subpkt);
                        size_raw = size_raw + subpkt_size_gcli_raw(subpkt);
                    end
                    if subpkt_uses_raw(subpkt) == 0 && size_raw <= size_noraw
                        for ypos = int32(0):(height - 1)
                            pos = prec.position_of(band, ypos);
                            subpkt = double(prec.subpkt_of(pos)) + 1;
                            subpkt_size_sigf(subpkt) = int32(0);
                            subpkt_size_gcli(subpkt) = subpkt_size_gcli_raw(subpkt);
                            subpkt_uses_raw(subpkt) = int32(1);
                        end
                    end
                end
            else
                % Rl=1 时 fallback 粒度是“每个 sub-packet 独立决定”。
                for subpkt = 1:nb_subpkts
                    if subpkt_size_gcli_raw(subpkt) <= subpkt_size_gcli(subpkt) + subpkt_size_sigf(subpkt)
                        subpkt_size_sigf(subpkt) = int32(0);
                        subpkt_size_gcli(subpkt) = subpkt_size_gcli_raw(subpkt);
                        subpkt_uses_raw(subpkt) = int32(1);
                    end
                end
            end

            for subpkt = 1:nb_subpkts
                precinct_bits = precinct_bits + pkt_header_size(subpkt);
                precinct_bits = precinct_bits + subpkt_size_sigf(subpkt);
                precinct_bits = precinct_bits + subpkt_size_gcli(subpkt);
                precinct_bits = precinct_bits + subpkt_size_data(subpkt);
                precinct_bits = precinct_bits + subpkt_size_sign(subpkt);
            end
        end
    end
end
