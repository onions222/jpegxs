% rate_control.m — precinct 级码率控制与 rate allocation。
%
% 对应 C 参考实现：libjxs/src/rate_control.c
% 标准位置：ISO/IEC 21122-1 Annex G
%
% 它的核心任务是：
%   在给定预算下，决定当前 precinct 的
%   - quantization
%   - refinement
%   - 各个 band 的 GCLI 编码方法
%
% 搜索逻辑分两段：
%   1. 先增大 quantization，直到总 bits 压进预算
%   2. 再增大 refinement，把剩余预算尽量填满
%
% 同时它还维护跨 precinct 的状态：
%   - 上一行 precinct 的 GCLI（给垂直预测用）
%   - CBR nibble 级累计消耗
%   - padding / report budget

classdef rate_control < handle
    properties
        xs_config
        image_height int32
        precinct            % working copy of precinct for rate control
        pbt                 % precinct_budget_table_t
        pred_residuals      % predbuffer_t
        precinct_top        % top precinct for vertical prediction
        gc_enabled_modes int32

        nibbles_image int32
        nibbles_report int32
        nibbles_consumed int32
        lines_consumed int32

        ra_params           % struct: Rl, budget, all_enabled_methods, lvl_gains, lvl_priorities
        gtli_table_data
        gtli_table_gcli
        gtli_table_gcli_prec
        gcli_methods_table int32
        gcli_sb_methods
        pbinfo
    end

    methods
        function obj = rate_control()
        end

        function open(obj, xs_config, ids_ref, column)
            import jxs.Constants;
            obj.xs_config = xs_config;
            obj.precinct = jxs.internal.precinct();
            obj.precinct.open_column(ids_ref, xs_config.p.N_g, column);
            obj.pbt = jxs.internal.precinct_budget_table();
            obj.pbt.open(ids_ref.npi, Constants.GCLI_METHODS_NB);
            obj.pred_residuals = jxs.internal.predbuffer(obj.precinct);
            obj.precinct_top = jxs.internal.precinct();
            obj.precinct_top.open_column(ids_ref, xs_config.p.N_g, column);

            nbands = double(ids_ref.nbands);
            obj.gtli_table_data = zeros(1, nbands, 'int32');
            obj.gtli_table_gcli_prec = zeros(1, nbands, 'int32');
            obj.gtli_table_gcli = zeros(1, nbands, 'int32');
            obj.gcli_sb_methods = zeros(1, Constants.MAX_NBANDS, 'int32');

            obj.ra_params = struct();
            obj.ra_params.Rl = xs_config.p.Rl;
            % all_enabled_methods 是“这份配置理论上允许尝试的方法全集”；
            % 真正某个 precinct / 某个位置能不能用，还要结合
            % first-of-slice、vertical predictor 是否可用等条件进一步过滤。
            obj.ra_params.all_enabled_methods = jxs.internal.gcli_methods.get_enabled(xs_config);
            obj.ra_params.lvl_gains = xs_config.p.lvl_gains;
            obj.ra_params.lvl_priorities = xs_config.p.lvl_priorities;

            obj.image_height = ids_ref.h;
            obj.gc_enabled_modes = jxs.internal.gcli_methods.get_enabled(xs_config);
        end

        function init(obj, image_rate_bytes, report_nbytes)
            % JPEG XS 这里很多预算相关计算都用 nibble（4 bit）为单位，
            % 所以初始化时直接把 byte 预算换成 nibble 预算，后续能少做位移。
            obj.nibbles_consumed = int32(0);
            obj.lines_consumed = int32(0);
            obj.nibbles_image = int32(image_rate_bytes * 2);
            obj.nibbles_report = int32(report_nbytes * 2);
        end

        function close(obj)
            obj.precinct_top.close();
            obj.precinct.close();
        end

        function rc_results = process_precinct(obj, precinct_in)
            % PROCESS_PRECINCT  Run full rate control for one precinct.
            %   rc_results = process_precinct(PRECINCT_IN)
            %   Returns a struct with quantization, refinement, GTLI tables,
            %   selected GCLI methods, padding, and sub-packet sizes.
            %
            %   C reference: rate_control_process_precinct()  (rate_control.c:90)
            import jxs.Constants;
            rc_results = struct();
            rc_results.rc_error = int32(0);
            % “无限预算”模式常用于功能验证：
            % 我们仍然会跑完整的 rate-control 流程，
            % 但 budget 会被设成一个极大值，等价于“尽量不截断”。
            infinite_budget = (obj.xs_config.bitstream_size_in_bytes == intmax('uint64'));

            % 这里有两个 precinct 副本：
            %   obj.precinct      —— 当前 working copy
            %   obj.precinct_top  —— 上一行的 precinct
            %
            % 垂直预测依赖“上一行同 band 的 GCLI”，所以每处理完一个 precinct，
            % 都要先把当前 GCLI 保存到 top。
            obj.precinct_top.copy_gclis(obj.precinct);
            % rate control 过程中会修改 working copy，因此先从输入复制一份。
            obj.precinct.precinct_copy(precinct_in);

            first_of_slice = precinct_in.is_first_of_slice(obj.xs_config.p.slice_height);
            precinct_top = jxs.Constants.iif(first_of_slice, [], obj.precinct_top);
            % slice 的第一块没有“上一块同列 precinct”，
            % 因而所有 vertical prediction 都必须退化掉。

            % 第一步：预估 GCLI 相关的码长。
            % 这里还没有真正打包，只是在预算表里把各种候选方案的代价算出来。
            jxs.internal.gcli_budget.fill(obj.gc_enabled_modes, precinct_in, ...
                precinct_top, [], obj.pbt, obj.pred_residuals, 0, obj.xs_config.p.S_s);

            % 第二步：预估 DATA / SIGN 的码长。
            jxs.internal.data_budget.fill_data_budget_table(precinct_in, obj.pbt, ...
                obj.xs_config.p.N_g, obj.xs_config.p.Fs, obj.xs_config.p.Qpih);

            % 如果不是 slice 的第一块，还需要补上“垂直预测方法”的预算表。
            if ~first_of_slice
                ver_modes = jxs.internal.gcli_methods.get_enabled_ver(obj.gc_enabled_modes);
                % update_only=1 的意思是：
                % 只回填“需要 top precinct 才能成立”的垂直预测预算，
                % 已经算过的其他方法不要重新覆盖。
                jxs.internal.gcli_budget.fill(ver_modes, obj.precinct, obj.precinct_top, ...
                    obj.gtli_table_gcli_prec, obj.pbt, obj.pred_residuals, 1, obj.xs_config.p.S_s);
            end

            % spacial_lines 表示当前 precinct 在原图垂直方向上实际消耗了多少空间行。
            % 之所以不是固定 ph，是因为最底部 precinct 可能不足整块高度。
            spacial_lines = precinct_in.spacial_lines_of(obj.image_height);
            budget_cbr = jxs.internal.budget.getcbr(obj.nibbles_image, ...
                obj.lines_consumed + spacial_lines, obj.image_height);
            % report budget 可以理解成一个“别过早把预算花光”的保护带。
            % 在当前进度位置，至少还要为后面的 precinct 预留这么多 nibble。
            budget_minimum = int32(budget_cbr) - obj.nibbles_report;

            if infinite_budget
                obj.ra_params.budget = int32(hex2dec('FFFFFFF'));
            else
                % budget_cbr 和 nibbles_consumed 都是 nibble 单位，
                % 最后左移 2 位换回 bit 单位，因为 precinct_budget 返回的是 bit 数。
                obj.ra_params.budget = bitshift(int32(budget_cbr) - obj.nibbles_consumed, 2);
            end

            % 真正开始搜索 quantization / refinement。
            [quantization, refinement] = obj.do_rate_allocation(precinct_in);
            [gtli_data, gtli_gcli, ~] = jxs.internal.sb_weighting.compute_gtli_tables(...
                quantization, refinement, precinct_in.bands_count(), ...
                obj.ra_params.lvl_gains, obj.ra_params.lvl_priorities);
            obj.gtli_table_gcli_prec = gtli_gcli;
            obj.gtli_table_data = gtli_data;

            % 在 quant/ref 确定后，再为每个 band 选最便宜的 GCLI method。
            obj.gcli_sb_methods = jxs.internal.precinct_budget.get_best_gcli_method(...
                precinct_in, obj.pbt, obj.gtli_table_gcli_prec);

            % 这里拿到的是“当前 precinct 真正将要写入多少 bit”的最终统计。
            [precinct_bits, pkt_hdr, sigf_sz, gcli_sz, data_sz, sign_sz, gcli_raw_sz, raw_flags, prec_hdr] = ...
                jxs.internal.precinct_budget.get_budget(precinct_in, obj.pbt, ...
                obj.gtli_table_gcli_prec, obj.gtli_table_data, obj.ra_params.Rl, obj.gcli_sb_methods);

            % 累计总消耗，供后续 precinct 的 CBR 预算继续使用。
            % 这里用 nibble 记账，所以要把 bit 数右移 2 位。
            obj.lines_consumed = obj.lines_consumed + spacial_lines;
            obj.nibbles_consumed = obj.nibbles_consumed + bitshift(int32(precinct_bits), -2);

            % 某些情况下需要补 padding：
            %   - 最后一块为了精确填满总预算
            %   - 或为了满足 report budget 的下界
            padding_nibbles = int32(0);
            if ~infinite_budget
                if precinct_in.is_last_of_image(obj.image_height)
                    % 最后一块直接把剩余 nibble 全补满，
                    % 确保最终 codestream 精确命中目标大小。
                    padding_nibbles = obj.nibbles_image - obj.nibbles_consumed;
                elseif obj.nibbles_consumed < budget_minimum
                    % 还没到最后一块，但如果当前累计消耗落后于“最低进度线”，
                    % 也要补 padding，避免后面没有足够空间满足 report 约束。
                    padding_nibbles = budget_minimum - obj.nibbles_consumed;
                end
                obj.nibbles_consumed = obj.nibbles_consumed + padding_nibbles;
            end

            % 把本次搜索的所有关键结果打包返回给编码主循环。
            rc_results.quantization = quantization;
            rc_results.refinement = refinement;
            rc_results.gcli_method = obj.gcli_methods_table;
            rc_results.gcli_sb_methods = obj.gcli_sb_methods;
            rc_results.bits_consumed = bitshift(obj.nibbles_consumed, 2);
            rc_results.gtli_table_data = obj.gtli_table_data;
            rc_results.gtli_table_gcli = obj.gtli_table_gcli_prec;
            rc_results.pbinfo = struct('precinct_bits', precinct_bits, ...
                'prec_header_size', prec_hdr, 'pkt_header_size', pkt_hdr, ...
                'subpkt_size_sigf', sigf_sz, 'subpkt_size_gcli', gcli_sz, ...
                'subpkt_size_data', data_sz, 'subpkt_size_sign', sign_sz, ...
                'subpkt_uses_raw_fallback', raw_flags, ...
                'subpkt_size_gcli_raw', gcli_raw_sz);
            rc_results.padding_bits = bitshift(padding_nibbles, 2);
            rc_results.precinct_total_bits = int32(precinct_bits) + bitshift(padding_nibbles, 2);
            rc_results.pred_residuals = obj.pred_residuals;
            rc_results.rc_error = int32(0);
        end

        function [quantization, refinement] = do_rate_allocation(obj, precinct_in)
            % DO_RATE_ALLOCATION  Two-phase quantization/refinement search.
            %   Phase 1: step quantization up until bits <= budget.
            %   Phase 2: step refinement up to fill remaining budget.
            %
            %   C reference: rate_control_do_rate_allocation()  (rate_control.c:140)
            import jxs.Constants;
            quantization = int32(0);
            refinement = int32(0);
            % refinement 最多只需要扫到“band 数 - 1”。
            % 再往上加也不会让更多 band 获得额外 1 bit-plane。
            max_refinement = precinct_in.bands_count() - 1;

            % Phase 1:
            %   从 quant=0 开始逐步增大，直到当前 precinct 总 bit 数
            %   第一次落到预算以内。
            while true
                [gtli_data, gtli_gcli, empty] = jxs.internal.sb_weighting.compute_gtli_tables(...
                    quantization, refinement, precinct_in.bands_count(), ...
                    obj.ra_params.lvl_gains, obj.ra_params.lvl_priorities);

                gcli_methods = jxs.internal.precinct_budget.get_best_gcli_method(...
                    precinct_in, obj.pbt, gtli_gcli);

                [total_bits, ~, ~, ~, ~, ~, ~, ~, ~] = ...
                    jxs.internal.precinct_budget.get_budget(precinct_in, obj.pbt, ...
                    gtli_gcli, gtli_data, obj.ra_params.Rl, gcli_methods);

                % 三种可能：
                %   1. 正好命中预算：直接结束
                %   2. 已经低于预算：quant 足够大，可以进入 refinement 阶段
                %   3. 还高于预算：继续增大 quant
                %
                % 这里 quantization 越大，GTLI 越大，留下的 bit-plane 越少，
                % 所以 total_bits 通常单调下降，可以放心线性搜索。
                if total_bits == obj.ra_params.budget
                    return;
                elseif total_bits < obj.ra_params.budget
                    break;
                elseif ~empty
                    quantization = quantization + 1;
                else
                    % empty=true 说明所有 band 都被截空了，
                    % 再增大 quant 已经没有意义，只能停在当前点。
                    break;
                end
            end

            % Phase 2:
            %   预算已经“压进来了”，现在从当前 refinement 开始往上加，
            %   尽可能把剩余预算吃满；一旦超出，就退回上一个 refinement。
            while true
                [gtli_data, gtli_gcli, ~] = jxs.internal.sb_weighting.compute_gtli_tables(...
                    quantization, refinement, precinct_in.bands_count(), ...
                    obj.ra_params.lvl_gains, obj.ra_params.lvl_priorities);

                gcli_methods = jxs.internal.precinct_budget.get_best_gcli_method(...
                    precinct_in, obj.pbt, gtli_gcli);

                [total_bits, ~, ~, ~, ~, ~, ~, ~, ~] = ...
                    jxs.internal.precinct_budget.get_budget(precinct_in, obj.pbt, ...
                    gtli_gcli, gtli_data, obj.ra_params.Rl, gcli_methods);

                if total_bits > obj.ra_params.budget
                    % 刚刚超出预算，说明最优值是前一个 refinement。
                    % refinement 增大会让部分高优先级 band 多保留 1 个 bit-plane，
                    % 所以 total_bits 通常单调上升。
                    refinement = refinement - 1;
                    return;
                elseif refinement == max_refinement
                    % 已经把所有可补偿 band 都补过一遍了。
                    return;
                else
                    refinement = refinement + 1;
                end
            end
        end
    end
end
