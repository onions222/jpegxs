% predbuffer.m — GCLI 预测残差缓存。
%
% 对应 C 参考实现：libjxs/src/predbuffer.c
%
% 为了避免 rate control 反复重算预测残差，
% 这里把不同 band / ypos / gtli 下的 residual 和 predictor 先缓存起来。
% (PRED_NONE=0, PRED_VER=1).  This avoids redundant recomputation
% during the rate-allocation search loop.
%
% Layout:
%   direction{1}  — PRED_NONE residuals
%   direction{2}  — PRED_VER  residuals
% Each direction contains:
%   .values{band, ypos, gtli}     — int8 residual vector
%   .predictors{band, ypos, gtli} — int8 predictor vector

classdef predbuffer < handle
    properties
        direction  % {1 x PRED_COUNT} struct with .values, .predictors, .idx_from_level
    end

    methods
        function obj = predbuffer(prec)
            % PREDBUFFER  Allocate residual buffers for all (band, ypos, gtli).
            %
            %   C reference: predbuffer_open()  (predbuffer.c:20)
            import jxs.Constants;
            n_lines = prec.ids.npi;
            n_bands = prec.bands_count();
            obj.direction = cell(1, Constants.PRED_COUNT);
            for p = 1:Constants.PRED_COUNT
                dp = struct();
                dp.values = cell(n_bands, 4, Constants.MAX_GCLI + 1);       % {band x ypos x (gtli+1)}
                dp.predictors = cell(n_bands, 4, Constants.MAX_GCLI + 1);
                dp.idx_from_level = zeros(4, Constants.MAX_NBANDS, 'int32');
                idx = int32(1);
                for lvl = int32(0):(n_bands - 1)
                    height = prec.in_band_height_of(lvl);
                    for ypos = int32(0):(height - 1)
                        w = prec.gcli_width_of(lvl);
                        % idx_from_level 保留了 C 里“(lvl,y) -> 线性行号”的习惯，
                        % 后面做调试或和 C trace 对照时会比较方便。
                        dp.idx_from_level(ypos + 1, lvl + 1) = idx;
                        for gtli = int32(0):Constants.MAX_GCLI
                            % 每个 GTLI 都要单独缓存一份 residual/predictor，
                            % 因为同一条 GCLI 行在不同 GTLI 下的预测结果并不相同。
                            dp.values{lvl + 1, ypos + 1, gtli + 1} = zeros(w, 1, 'int8');
                            dp.predictors{lvl + 1, ypos + 1, gtli + 1} = zeros(w, 1, 'int8');
                        end
                        idx = idx + 1;
                    end
                end
                obj.direction{p} = dp;
            end
        end

        function dp = directional_data_of(obj, dir)
            % DIRECTIONAL_DATA_OF  Access residual data for a prediction direction.
            %   dp = directional_data_of(DIR) where DIR is 0-based (C convention).
            dp = obj.direction{dir + 1};
        end
    end
end
