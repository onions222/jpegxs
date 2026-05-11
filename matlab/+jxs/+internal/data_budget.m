% data_budget.m — DATA / SIGN 子包码长预估。
%
% 对应 C 参考实现：libjxs/src/data_budget.c
%
% 在真正做 rate allocation 之前，先把不同 GTLI 下的数据位数估出来，
% 这样搜索 quantization / refinement 时就不需要每次完整试打包。
% populate the precinct budget table (pbt) so the rate-allocation loop
% can evaluate different quantization settings without re-encoding.

classdef data_budget
    methods (Static)
        function fill_data_budget_table(prec, pbt, group_size, sign_packing, dq_type)
            % FILL_DATA_BUDGET_TABLE  Populate data/sign budgets for all positions.
            %   fill_data_budget_table(PREC, PBT, N_g, Fs, Qpih)
            %
            %   C reference: fill_data_budget_table()  (data_budget.c:82)
            import jxs.Constants;
            gs = int32(group_size);
            for position = int32(0):(pbt.position_count - 1)
                lvl = prec.band_index_of(position);
                ypos = prec.ypos_of(position);
                if ypos >= prec.in_band_height_of(lvl), continue; end

                gclis = prec.gcli_of(lvl, ypos);
                gcli_width = prec.gcli_width_of(lvl);
                data_buf = pbt.data_bgt_of(position);
                % data 预算只看“在每个 GTLI 下会留下多少 magnitude/sign bit-plane”，
                % 不需要真的把样本重新量化再打包。
                data_buf = jxs.internal.data_budget.budget_get_data(data_buf, gclis, gcli_width, gs, sign_packing == 0);
                pbt.set_data_bgt_of(position, data_buf);

                if sign_packing == 1
                    % Fs=1: sign bits go into a separate sub-packet
                    sign_buf = pbt.sign_bgt_of(position);
                    sign_buf = jxs.internal.data_budget.budget_get_sign(sign_buf, prec.line_of(lvl, ypos), ...
                        int32(prec.width_of(lvl)), gclis, gcli_width, gs, dq_type);
                    pbt.set_sign_bgt_of(position, sign_buf);
                else
                    % Fs=0: signs embedded in data sub-packet
                    sign_buf = pbt.sign_bgt_of(position);
                    sign_buf(:) = uint32(0);
                    pbt.set_sign_bgt_of(position, sign_buf);
                end
            end
        end

        function budget_table = budget_get_data(budget_table, gclis, gclis_len, group_size, include_sign)
            % BUDGET_GET_DATA  Compute data bit cost at every GTLI for one band-line.
            %   For each GCLI group, the number of significant bit-planes
            %   (gcli - gtli) determines the bit cost, optionally including
            %   one sign bit per sample.
            %
            %   C reference: budget_get_data()  (data_budget.c:16)
            budget_table(:) = uint32(0);
            table_size = int32(length(budget_table));
            gs = int32(group_size);
            for i = int32(1):gclis_len
                for gtli = int32(0):(table_size - 1)
                    % gcli-gtli 表示当前 group 在该 GTLI 下还剩多少个 magnitude bit-plane。
                    n_bitplanes = int32(gclis(i)) - gtli;
                    if gs == 1
                        % group_size=1 是特殊情形：
                        % C 参考实现里会把“最高位隐含的存在性”折掉 1 bit，
                        % 这样预算与逐样本写法一致。
                        n_bitplanes = n_bitplanes - 1;
                        if include_sign, n_bitplanes = n_bitplanes + 1; end
                    end
                    if n_bitplanes <= 0, break; end
                    if gs > 1 && include_sign
                        % 多样本 group 且 Fs=0 时，sign 会嵌在 data 里，
                        % 每个样本额外多 1 个 sign bit，因此组预算整体 +gs。
                        n_bitplanes = n_bitplanes + 1;
                    end
                    budget_table(gtli + 1) = budget_table(gtli + 1) + uint32(n_bitplanes * gs);
                end
            end
        end

        function budget_table = budget_get_sign(budget_table, datas_buf, data_len, gclis, gclis_len, group_size, dq_type)
            % BUDGET_GET_SIGN  Compute sign bit cost at every GTLI for one band-line.
            %   Only non-zero quantized samples require a sign bit.
            %
            %   C reference: budget_get_sign()  (data_budget.c:48)
            budget_table(:) = uint32(0);
            table_size = int32(length(budget_table));
            gs = int32(group_size);
            idx = int32(1);
            dl = int32(data_len);
            for group = int32(1):gclis_len
                gcli = int32(gclis(group));
                for k = int32(1):gs
                    pos = idx + k - 1;
                    if pos > dl, break; end
                    for gtli = int32(0):(table_size - 1)
                        % 这里不是直接看原始 sign-magnitude 是否非零，
                        % 而是先调用 apply_dq() 判断“该样本在当前 GTLI 下经过反量化后是否仍非零”。
                        % 只有仍非零的样本，最终 sign 子包里才需要 1 个 sign bit。
                        quant_val = jxs.internal.quant_ops.apply_dq(dq_type, datas_buf(pos), gcli, gtli);
                        if quant_val ~= 0
                            budget_table(gtli + 1) = budget_table(gtli + 1) + uint32(1);
                        else
                            % GTLI 越大，保留下来的信息只会更少；
                            % 一旦在某个 GTLI 下已经变成 0，更高 GTLI 也一定是 0，可以直接 break。
                            break;
                        end
                    end
                end
                idx = idx + gs;
            end
        end
    end
end
