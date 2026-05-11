% gcli_budget.m — GCLI 码长表填充逻辑。
%
% 对应 C 参考实现：libjxs/src/gcli_budget.c
%
% 它会枚举不同编码方法、不同位置、不同 GTLI，
% 预先估出 GCLI 子流需要多少 bit，并写入预算表。
% precinct budget table (pbt) and consumed by the rate allocator to
% select the cheapest GCLI coding method per sub-band.

classdef gcli_budget
    methods (Static)
        function fill(active_methods, prec, prec_top, gtli_top_array, pbt, residuals, update_only, sigflags_group_width)
            % FILL  Compute GCLI bit budgets for all enabled methods.
            %   fill(METHODS, PREC, PREC_TOP, GTLI_TOP, PBT, RESIDUALS, UPDATE, S_s)
            %   First computes prediction residuals, then estimates the
            %   bit cost for each method at every GTLI level.
            %
            %   C reference: fill_gcli_budget_tables()  (gcli_budget.c:100)
            import jxs.Constants;

            % 预算表依赖“预测后的 residual”，不是直接依赖原始 GCLI。
            % 所以无论最终选哪一种熵编码方法，第一步都要先把 residual 全预计算好。
            jxs.internal.gcli_budget.compute_residuals(active_methods, prec, prec_top, gtli_top_array, residuals);

            for method = int32(0):(Constants.GCLI_METHODS_NB - 1)
                precinct_group = jxs.Constants.iif(isempty(prec_top), Constants.PRECINCT_FIRST_OF_SLICE, Constants.PRECINCT_OTHERS);
                if ~jxs.internal.gcli_methods.is_enabled(active_methods, method, precinct_group)
                    if ~update_only
                        jxs.internal.gcli_budget.invalid_coding(pbt, method);
                    end
                elseif Constants.method_is_raw(method)
                    jxs.internal.gcli_budget.raw_coding(prec, pbt, method);
                else
                    jxs.internal.gcli_budget.compute_generic(prec, method, pbt, residuals, sigflags_group_width, active_methods);
                end
            end
        end

        function invalid_coding(pbt, gcli_method)
            import jxs.Constants;
            for position = int32(0):(pbt.position_count - 1)
                for gtli = int32(0):Constants.MAX_GCLI
                    % 失效方法的约定写法：
                    % SIGF 预算记 0，GCLI 预算记 INVALID。
                    % 这样上层在累加时能快速识别“该方法不可选”。
                    sigf_buf = pbt.sigf_bgt_of(gcli_method, position);
                    gcli_buf = pbt.gcli_bgt_of(gcli_method, position);
                    if gtli + 1 <= length(sigf_buf), sigf_buf(gtli + 1) = uint32(0); end
                    if gtli + 1 <= length(gcli_buf), gcli_buf(gtli + 1) = Constants.RA_BUDGET_INVALID; end
                    pbt.set_sigf_bgt_of(gcli_method, position, sigf_buf);
                    pbt.set_gcli_bgt_of(gcli_method, position, gcli_buf);
                end
            end
        end

        function raw_coding(prec, pbt, gcli_method)
            for position = int32(0):(pbt.position_count - 1)
                lvl = prec.band_index_of(position);
                % raw GCLI 与 GTLI 无关，每个 group 恒定写 4 bit。
                % 因此同一 position 下所有 gtli 的 raw 预算都是同一个值。
                size_gcli_raw = int32(4 * prec.gcli_width_of(lvl));
                for gtli = int32(0):jxs.Constants.MAX_GCLI
                    sigf_buf = pbt.sigf_bgt_of(gcli_method, position);
                    gcli_buf = pbt.gcli_bgt_of(gcli_method, position);
                    if gtli + 1 <= length(sigf_buf), sigf_buf(gtli + 1) = uint32(0); end
                    if gtli + 1 <= length(gcli_buf), gcli_buf(gtli + 1) = size_gcli_raw; end
                    pbt.set_sigf_bgt_of(gcli_method, position, sigf_buf);
                    pbt.set_gcli_bgt_of(gcli_method, position, gcli_buf);
                end
            end
        end

        function compute_generic(prec, gcli_method, pbt, residuals, sigflags_group_width, active_methods)
            import jxs.Constants;

            pred_type = Constants.method_get_pred(gcli_method);
            dp = residuals.direction{pred_type + 1};
            dp_nopred = residuals.direction{Constants.PRED_NONE + 1};
            alph = Constants.FIRST_ALPHABET;

            for position = int32(0):(pbt.position_count - 1)
                lvl = prec.band_index_of(position);
                ypos = prec.ypos_of(position);
                if ypos >= prec.in_band_height_of(lvl), continue; end

                for gtli = int32(0):Constants.MAX_GCLI
                    bgt_sigf = uint32(0);
                    bgt_gcli = uint32(0);

                    % residuals 是按 [level, y, gtli] 三维预存的。
                    % 这里不再重算，只按当前 method 选择对应方向/版本的数据。
                    res_buf = dp.values{lvl + 1, ypos + 1, gtli + 1};
                    res_len = prec.gcli_width_of(lvl);
                    predictors_buf = dp.predictors{lvl + 1, ypos + 1, gtli + 1};
                    values_buf = dp_nopred.values{lvl + 1, ypos + 1, gtli + 1};

                    res_buf_coded = res_buf;
                    res_len_coded = res_len;

                    if Constants.method_uses_sig_flags(gcli_method)
                        % sig_flags 的本质是：
                        % 先用一段 run-length 风格的 side information 标出
                        % “哪些组需要真正熵编码”，然后只对这些显著组写 residual。
                        sig_flags_buf = res_buf;
                        if Constants.method_get_run(gcli_method) == Constants.RUN_SIGFLAGS_ZRCSF
                            % ZRCSF 的显著性判定基于 no-pred residual，
                            % 但真正被编码的 residual 仍然可能来自另一个 predictor。
                            sig_flags_buf = values_buf;
                        end
                        sf = jxs.internal.sig_flags(prec.ids.band_max_width, sigflags_group_width);
                        sf.init(sig_flags_buf, res_len, sigflags_group_width);
                        bgt_sigf = sf.budget();
                        [coded_buf, new_len] = sf.filter_values(res_buf);
                        [coded_predictors, ~] = sf.filter_values(predictors_buf);
                        res_buf_coded = coded_buf(1:new_len);
                        predictors_buf = coded_predictors(1:new_len);
                        res_len_coded = new_len;
                    end

                    if Constants.method_uses_no_pred(gcli_method)
                        % no-pred residual 永远非负，可以直接走 unsigned unary。
                        bgt_gcli = bgt_gcli + jxs.internal.budget.getunary_unsigned(res_buf_coded, res_len_coded);
                    elseif Constants.method_get_alphabet(gcli_method) == Constants.ALPHABET_UNARY_UNSIGNED_BOUNDED
                        % bounded alphabet 的每个 residual 可编码区间依赖 predictor 和 gtli，
                        % 所以这里需要单独调用 bounded_code 预算器。
                        bgt_gcli = bgt_gcli + jxs.internal.budget.bounded_code(res_buf_coded, predictors_buf, gtli, res_len_coded, lvl);
                    else
                        bgt_gcli = bgt_gcli + jxs.internal.budget.getunary(res_buf_coded, res_len_coded, alph);
                    end

                    sigf_buf = pbt.sigf_bgt_of(gcli_method, position);
                    gcli_buf = pbt.gcli_bgt_of(gcli_method, position);
                    if gtli + 1 <= length(sigf_buf), sigf_buf(gtli + 1) = bgt_sigf; end
                    if gtli + 1 <= length(gcli_buf), gcli_buf(gtli + 1) = bgt_gcli; end
                    pbt.set_sigf_bgt_of(gcli_method, position, sigf_buf);
                    pbt.set_gcli_bgt_of(gcli_method, position, gcli_buf);
                end
            end
        end

        function compute_residuals(active_methods, prec, prec_top, gtli_top_array, residuals)
            % COMPUTE_RESIDUALS  Pre-compute GCLI prediction residuals.
            %   For each prediction direction and every (band, ypos, gtli),
            %   compute and store the residual and predictor vectors.
            %
            %   C reference: compute_residuals()  (gcli_budget.c:140)
            import jxs.Constants;
            for pred = int32(0):(Constants.PRED_COUNT - 1)
                dp = residuals.direction{pred + 1};
                for gcli_method = int32(0):(Constants.GCLI_METHODS_NB - 1)
                    precinct_group = jxs.Constants.iif(isempty(prec_top), Constants.PRECINCT_FIRST_OF_SLICE, Constants.PRECINCT_OTHERS);
                    if ~jxs.internal.gcli_methods.is_enabled(active_methods, gcli_method, precinct_group)
                        continue;
                    end
                    if Constants.method_get_pred(gcli_method) == pred || ...
                       (Constants.method_get_run(gcli_method) == Constants.RUN_SIGFLAGS_ZRCSF && pred == Constants.PRED_NONE)
                        for lvl = int32(0):(prec.bands_count() - 1)
                            height = prec.in_band_height_of(lvl);
                            for ypos = int32(0):(height - 1)
                                gclis_top = prec.gcli_top_of(prec_top, lvl, ypos);
                                for gtli = int32(0):Constants.MAX_GCLI
                                    if pred == Constants.PRED_VER && ~isempty(gclis_top)
                                        % slice 第一行做垂直预测时，top precinct 的 gtli
                                        % 可能和当前 precinct 不同，所以 gtli_top 需要单独传入。
                                        if ~isempty(gtli_top_array) && ypos == 0
                                            gtli_top_val = gtli_top_array(lvl + 1);
                                        else
                                            gtli_top_val = gtli;
                                        end
                                        [dp.values{lvl + 1, ypos + 1, gtli + 1}, ...
                                         dp.predictors{lvl + 1, ypos + 1, gtli + 1}] = jxs.internal.pred.ver(...
                                            prec.gcli_of(lvl, ypos), gclis_top, ...
                                            prec.gcli_width_of(lvl), ...
                                            dp.values{lvl + 1, ypos + 1, gtli + 1}, ...
                                            dp.predictors{lvl + 1, ypos + 1, gtli + 1}, ...
                                            gtli, gtli_top_val);
                                    else
                                        % none predictor 只需要保存 residual；
                                        % predictor 数组显式清零，便于后面统一访问。
                                        dp.values{lvl + 1, ypos + 1, gtli + 1} = jxs.internal.pred.none(...
                                            prec.gcli_of(lvl, ypos), ...
                                            prec.gcli_width_of(lvl), ...
                                            dp.values{lvl + 1, ypos + 1, gtli + 1}, gtli);
                                        predictors_buf = dp.predictors{lvl + 1, ypos + 1, gtli + 1};
                                        predictors_buf(:) = int8(0);
                                        dp.predictors{lvl + 1, ypos + 1, gtli + 1} = predictors_buf;
                                    end
                                end
                            end
                        end
                        break;
                    end
                end
                residuals.direction{pred + 1} = dp;
            end
        end
    end
end
