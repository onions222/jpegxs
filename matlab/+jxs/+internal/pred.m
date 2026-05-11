% pred.m — GCLI 预测器。
%
% 对应 C 参考实现：libjxs/src/pred.c
% 标准位置：ISO/IEC 21122-1 Annex F.3
%
% 这里实现的主要是：
%   - 无预测模式
%   - 垂直预测模式
%
% 编码端输出 residual，解码端再把 residual 还原回真实 GCLI。
% (decoder side) for GCLI (Greatest Coded Level Index) values.
%   - "ver"  mode: predict from the GCLI row above (vertical).
%   - "none" mode: predict from zero (baseline).
%
% Prediction residuals are entropy-coded; the predictor value is used
% for bounded-code alphabet selection.

classdef pred
    methods (Static)
        function predictor = ver_compute_predictor(gcli_top, gtli_top, gtli)
            % VER_COMPUTE_PREDICTOR  Vertical prediction reference value.
            %   predictor = max(gcli_top, max(gtli, gtli_top))
            %
            %   C reference: tco_pred_ver_compute_predictor()  (pred.c:20)
            import jxs.Constants;
            % 这里取 max 的原因是：GCLI 被 GTLI 截断后，任何有效值都不应低于对应阈值。
            % 因而预测器至少要站在“top 行 GCLI”和“上下两侧 GTLI 下界”中的较大者上。
            predictor = int32(Constants.MAX(int32(gcli_top), Constants.MAX(int32(gtli), int32(gtli_top))));
        end

        function [pred_buf, predictors_buf] = ver(gcli_buf, gcli_buf_top, buf_len, pred_buf_out, predictors_out, gtli, gtli_top)
            % VER  Forward vertical prediction.
            %   [RESIDUALS, PREDICTORS] = ver(GCLI, GCLI_TOP, LEN, ...)
            %   Residual = max(gcli, gtli) - predictor
            %
            %   C reference: tco_pred_ver()  (pred.c:30)
            n = min(buf_len, int32(length(pred_buf_out)));
            if n > 0
                for i = 1:n
                    p = jxs.internal.pred.ver_compute_predictor(gcli_buf_top(i), gtli_top, gtli);
                    predictors_out(i) = int8(p);
                    % residual 不是 gcli - predictor，而是 max(gcli, gtli) - predictor。
                    % 这样即便真实 gcli 已经低于 gtli，也会被“钳”到 gtli 再参与预测，
                    % 保证编码 residual 后解码端能够按同一规则恢复。
                    pred_buf_out(i) = int8(jxs.Constants.MAX(int32(gcli_buf(i)), int32(gtli)) - p);
                end
            end
            pred_buf = pred_buf_out;
            predictors_buf = predictors_out;
        end

        function gcli_buf = ver_inverse(pred_buf, gcli_buf_top, buf_len, gcli_buf_out, gtli, gtli_top)
            % VER_INVERSE  Inverse vertical prediction (decoder).
            %   GCLI = predictor + residual, clamped when <= gtli.
            %
            %   C reference: tco_pred_ver_inverse()  (pred.c:50)
            n = min(buf_len, int32(length(pred_buf)));
            if n > 0
                for i = 1:n
                    top = jxs.internal.pred.ver_compute_predictor(gcli_buf_top(i), gtli_top, gtli);
                    gcli_buf_out(i) = int8(top + int32(pred_buf(i)));
                    if gcli_buf_out(i) <= int8(gtli)
                        % 对应 forward 端的 max(gcli, gtli) 规则：
                        % 当恢复值没有超过 gtli，说明原始语义应当是“该 group 无有效 bit-plane”，
                        % 这里把它折回到 0 或负偏移的表示形式，与 C 端保持一致。
                        gcli_buf_out(i) = int8(int32(gcli_buf_out(i)) - int32(gtli));
                    end
                end
            end
            gcli_buf = gcli_buf_out;
        end

        function ok = ver_check_gclis(gcli_buf, buf_len)
            % VER_CHECK_GCLIS  Validate GCLI buffer (stub, always returns true).
            %
            %   C reference: tco_pred_ver_check_gclis()  (pred.c:71)
            ok = (buf_len <= 0) || (gcli_buf(1) > gcli_buf(1)); % always false
            if buf_len > 0
                for i = 1:buf_len
                    ok = false; return;
                end
            end
            ok = true;
        end

        function pred_buf = none(gcli_buf, buf_len, pred_buf_out, gtli)
            % NONE  No-prediction mode (baseline).
            %   Residual = max(0, gcli - gtli)
            %
            %   C reference: tco_pred_none()  (pred.c:84)
            n = min(buf_len, int32(length(pred_buf_out)));
            for i = 1:n
                % none 模式下 predictor 恒为 0，
                % 所以 residual 就是“超出 gtli 阈值的那一部分”。
                pred_buf_out(i) = int8(jxs.Constants.MAX(int32(0), int32(gcli_buf(i)) - int32(gtli)));
            end
            pred_buf = pred_buf_out;
        end

        function gcli_buf = none_inverse(pred_buf, buf_len, gcli_buf_out, gtli)
            % NONE_INVERSE  Inverse of no-prediction mode (decoder).
            %   GCLI = residual + gtli  (or 0 if residual == 0)
            %
            %   C reference: tco_pred_none_inverse()  (pred.c:97)
            n = min(buf_len, int32(length(pred_buf)));
            for i = 1:n
                if pred_buf(i) > 0
                    gcli_buf_out(i) = int8(int32(pred_buf(i)) + int32(gtli));
                else
                    % residual 为 0 表示该 group 在 gtli 以上没有任何有效 bit-plane。
                    gcli_buf_out(i) = int8(0);
                end
            end
            gcli_buf = gcli_buf_out;
        end
    end
end
