% dwt.m — 5/3 整数提升小波变换。
%
% 对应 C 参考实现：libjxs/src/dwt.c
% 标准位置：ISO/IEC 21122-1 Annex E
%
% JPEG XS 在这里使用的是 Le Gall 5/3 整数 lifting 变换。
% 这个文件负责：
%   - 一维 forward/inverse filter
%   - 按 IDS 规定的层级顺序做水平/垂直分解
%   - 正反变换都严格保持和 C 一致的边界处理
% JPEG XS.  The 1-D filter operates in-place on strided data (rows or
% columns), supporting both horizontal-only and mixed H/V decompositions.
%
% Decomposition levels are controlled by NLx (horizontal) and NLy (vertical)
% from the coding parameters.

classdef dwt
    methods (Static)
        function data = inverse_filter_1d(data, start_idx, end_idx, inc)
            % INVERSE_FILTER_1D  Bounds-safe 5/3 inverse lifting step.
            %   data = inverse_filter_1d(data, START, END, INC)
            %   reconstructs the signal between START and END with stride INC.
            %
            %   C reference: dwt_inverse_filter_1d_()  (dwt.c:40)
            %   Standard:    Annex E, Eq. (E-3) and (E-4)

            % inverse 顺序和 forward 相反：
            %   先恢复偶数位置（低频）
            %   再恢复奇数位置（高频）
            p = start_idx;
            data(p) = data(p) - bitshift(data(p + inc) + 1, -1);
            p = p + 2 * inc;
            while p < end_idx - inc
                data(p) = data(p) - bitshift(data(p - inc) + data(p + inc) + 2, -2);
                p = p + 2 * inc;
            end
            if p < end_idx
                data(p) = data(p) - bitshift(data(p - inc) + 1, -1);
            end

            % Step 2 — update odd (high-pass) samples
            p = start_idx + inc;
            while p < end_idx - inc
                data(p) = data(p) + bitshift(data(p - inc) + data(p + inc), -1);
                p = p + 2 * inc;
            end
            if p < end_idx
                data(p) = data(p) + data(p - inc);
            end
        end

        function data = forward_filter_1d(data, start_idx, end_idx, inc)
            % FORWARD_FILTER_1D  Bounds-safe 5/3 forward lifting step.
            %   data = forward_filter_1d(data, START, END, INC)
            %   decomposes the signal between START and END with stride INC.
            %
            %   C reference: dwt_forward_filter_1d_()  (dwt.c:14)
            %   Standard:    Annex E, Eq. (E-1) and (E-2)

            % 5/3 lifting 的 forward 两步：
            %   1. 用相邻偶样本预测奇样本，得到高频
            %   2. 再用高频更新偶样本，得到低频
            p = start_idx + inc;
            while p < end_idx - inc
                data(p) = data(p) - bitshift(data(p - inc) + data(p + inc), -1);
                p = p + 2 * inc;
            end
            if p < end_idx
                data(p) = data(p) - data(p - inc);
            end

            % Step 2 — update even (low-pass) samples
            p = start_idx;
            data(p) = data(p) + bitshift(data(p + inc) + 1, -1);
            p = p + 2 * inc;
            while p < end_idx - inc
                data(p) = data(p) + bitshift(data(p - inc) + data(p + inc) + 2, -2);
                p = p + 2 * inc;
            end
            if p < end_idx
                data(p) = data(p) + bitshift(data(p - inc) + 1, -1);
            end
        end

        function transform_vertical(ids, im, k, h_level, v_level, filter_func)
            % TRANSFORM_VERTICAL  Apply 1-D filter to every column of component k.
            %   The column stride is comp_w * 2^v_level; each column spans
            %   the full component height.
            %
            %   C reference: dwt_transform_vertical_()  (dwt.c:66)
            % x_inc 表示当前 level 下，相邻“列”的步长。
            % y_inc 表示在平铺向量里，同一列上下两个样本之间隔多少元素。
            x_inc = int32(bitshift(1, h_level));
            y_inc = int32(bitshift(ids.comp_w(k), v_level));
            comp = im.comps_array{k};
            for base = 1:x_inc:ids.comp_w(k)
                % 注意这里的 end 不是“最后一个有效下标”，而是类似半开区间终点。
                col_end = base + int32(ids.comp_w(k)) * int32(ids.comp_h(k));
                comp = filter_func(comp, int32(base), col_end, int32(y_inc));
            end
            im.comps_array{k} = comp;
        end

        function transform_horizontal(ids, im, k, h_level, v_level, filter_func)
            % TRANSFORM_HORIZONTAL  Apply 1-D filter to every row of component k.
            %   The sample stride is 2^h_level; rows are spaced by
            %   comp_w * 2^v_level.
            %
            %   C reference: dwt_transform_horizontal_()  (dwt.c:82)
            % 水平变换时：
            %   x_inc 控制行内采样间隔
            %   y_inc 控制下一行在平铺数组里的起始偏移
            x_inc = int32(bitshift(1, h_level));
            y_inc = int32(bitshift(ids.comp_w(k), v_level));
            comp = im.comps_array{k};
            end_arr = int32(ids.comp_w(k)) * int32(ids.comp_h(k));
            for base = 1:y_inc:end_arr
                row_end = base + ids.comp_w(k);
                comp = filter_func(comp, int32(base), int32(row_end), int32(x_inc));
            end
            im.comps_array{k} = comp;
        end

        function inverse_transform(ids, im)
            % INVERSE_TRANSFORM  Full inverse DWT across all components.
            %   Reconstructs from wavelet domain to spatial domain.
            %   Horizontal-only levels are processed first (NLx down to NLy+1),
            %   then mixed H+V levels (NLy down to 1).
            %
            %   C reference: dwt_inverse_transform()  (dwt.c:136)
            import jxs.internal.dwt;
            for k = 1:int32(ids.ncomps - ids.sd)
                assert(ids.nlxyp(k).y <= ids.nlxyp(k).x);
                for d = ids.nlxyp(k).x:-1:(ids.nlxyp(k).y + 1)
                    dwt.transform_horizontal(ids, im, k, d - 1, ids.nlxyp(k).y, @dwt.inverse_filter_1d);
                end
                for d = ids.nlxyp(k).y:-1:1
                    dwt.transform_horizontal(ids, im, k, d - 1, d - 1, @dwt.inverse_filter_1d);
                    dwt.transform_vertical(ids, im, k, d - 1, d - 1, @dwt.inverse_filter_1d);
                end
            end
        end

        function forward_transform(ids, im)
            % FORWARD_TRANSFORM  Full forward DWT across all components.
            %   Decomposes from spatial domain to wavelet domain.
            %   Mixed H+V levels are processed first (1 up to NLy),
            %   then horizontal-only levels (NLy+1 up to NLx).
            %
            %   C reference: dwt_forward_transform()  (dwt.c:113)
            import jxs.internal.dwt;
            for k = 1:int32(ids.ncomps - ids.sd)
                assert(ids.nlxyp(k).y <= ids.nlxyp(k).x);
                for d = 1:ids.nlxyp(k).y
                    % 当 d <= NLy 时，既有垂直分解也有水平分解。
                    dwt.transform_vertical(ids, im, k, d - 1, d - 1, @dwt.forward_filter_1d);
                    dwt.transform_horizontal(ids, im, k, d - 1, d - 1, @dwt.forward_filter_1d);
                end
                for d = ids.nlxyp(k).y + 1:ids.nlxyp(k).x
                    dwt.transform_horizontal(ids, im, k, d - 1, ids.nlxyp(k).y, @dwt.forward_filter_1d);
                end
            end
        end
    end
end
