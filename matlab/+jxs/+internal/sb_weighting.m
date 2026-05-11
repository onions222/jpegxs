% sb_weighting.m — 子带权重与 GTLI 表计算。
%
% 对应 C 参考实现：libjxs/src/sb_weighting.c
% 标准位置：ISO/IEC 21122-1 Annex G
%
% rate allocation 真正搜索的是 quantization / refinement，
% 但最终要落到每个 band 的 GTLI 表，这里就是中间映射逻辑。
% quantization.  Each sub-band's GTLI is derived from a global
% quantization parameter, a per-band gain value, and an optional
% refinement bit controlled by the sub-band priority.

classdef sb_weighting
    methods (Static)
        function gtli = compute_gtli_single(scenario, gain, add_1bp)
            % COMPUTE_GTLI_SINGLE  Derive GTLI for one sub-band.
            %   gtli = compute_gtli_single(SCENARIO, GAIN, ADD_1BP)
            %   returns max(0, min(SCENARIO - GAIN - ADD_1BP, MAX_GCLI)).
            %
            %   C reference: compute_gtli_single()  (sb_weighting.c:10)
            import jxs.Constants;
            % scenario 可以理解成全局量化强度；
            % gain 越大，说明这个 band 越“重要”，因此对应 GTLI 会更小，保留更多 bit-plane。
            gtli = int32(scenario) - int32(gain);
            if add_1bp, gtli = int32(gtli - 1); end
            % GTLI 本质是截断阈值，所以必须被夹在 [0, MAX_GCLI] 内。
            gtli = Constants.MAX(gtli, int32(0));
            gtli = Constants.MIN(gtli, Constants.MAX_GCLI);
        end

        function [gtli_table_data, gtli_table_gcli, empty] = compute_gtli_tables(quantization, refinement, n_lvls, sb_gains, sb_priority)
            % COMPUTE_GTLI_TABLES  Build GTLI tables for all sub-bands.
            %   [DATA_GTLI, GCLI_GTLI, EMPTY] = compute_gtli_tables(Q, R, N, GAINS, PRIOS)
            %   DATA_GTLI  — truncation levels for coefficient data
            %   GCLI_GTLI  — truncation levels for GCLI values
            %   EMPTY      — true when all bands are fully truncated (GTLI==MAX_GCLI)
            %
            %   The refinement parameter selectively decreases the GTLI by 1
            %   for bands whose priority is below the refinement threshold.
            %
            %   C reference: compute_gtli_tables()  (sb_weighting.c:22)
            import jxs.Constants;
            gtli_table_data = zeros(1, n_lvls, 'int32');
            gtli_table_gcli = zeros(1, n_lvls, 'int32');
            lvls_empty = int32(0);
            for lvl = 1:n_lvls
                % priority < refinement 表示这个 band 可以额外“送回 1 bit-plane”，
                % 也就是 GTLI 再减 1。这样 refinement 越大，被补偿的 band 越多。
                gtli_table_data(lvl) = jxs.internal.sb_weighting.compute_gtli_single(quantization, sb_gains(lvl), sb_priority(lvl) < refinement);
                gtli_table_gcli(lvl) = gtli_table_data(lvl);
                if gtli_table_data(lvl) == Constants.MAX_GCLI
                    % GTLI==MAX_GCLI 代表这个 band 已经被完全截空，没有任何数据需要编码。
                    lvls_empty = lvls_empty + 1;
                end
            end
            empty = (lvls_empty == n_lvls);
        end
    end
end
