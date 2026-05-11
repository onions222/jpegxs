% budget.m — bit budget 估算辅助函数。
%
% 对应 C 参考实现：libjxs/src/budget.c
%
% 这里放的是一些基础的“算 bit 数”工具，
% 主要供 GCLI / DATA / precinct budget 模块复用。
% unary unsigned, bounded code) and for computing the CBR (constant bit
% rate) budget target per precinct row.

classdef budget
    methods (Static)
        function bgt = single_value_getunary(value, alphabet)
            % SINGLE_VALUE_GETUNARY  Bit cost of one signed unary codeword.
            %   bgt = single_value_getunary(VALUE, ALPHABET)
            %   Returns the number of bits needed to encode VALUE using the
            %   specified unary ALPHABET (0, 4-clipped, or full).
            %
            %   C reference: budget_getunary_single_value()  (budget.c:16)
            import jxs.Constants;
            if alphabet == Constants.UNARY_ALPHABET_4_CLIPPED
                % 4-clipped alphabet 对小残差给非常短的码字，
                % 对较大绝对值则封顶到 16 bit。
                % 这里直接展开成查表式 if/elseif，和 C 参考实现保持一一对应。
                if value == 0, bgt = uint32(1);
                elseif value == 1, bgt = uint32(3);
                elseif value == -1, bgt = uint32(2);
                elseif value == 2, bgt = uint32(5);
                elseif value == -2, bgt = uint32(4);
                elseif abs(value) < 13
                    bgt = uint32(abs(value) + 4);
                else
                    bgt = uint32(16);
                end
            elseif alphabet == Constants.UNARY_ALPHABET_0
                % alphabet_0 的规律更简单：
                %   0      -> 1 bit
                %   +k/-k  -> k+2 bit（再封顶到 16）
                if value > 0
                    bgt = uint32(Constants.MIN(int32(value + 2), 16));
                elseif value < 0
                    bgt = uint32(Constants.MIN(int32(-value + 2), 16));
                else
                    bgt = uint32(1);
                end
            else
                bgt = uint32(0);
            end
        end

        function bgt = getunary(pred_buf, len_val, alphabet)
            % GETUNARY  Total bit cost for a signed unary-coded vector.
            %
            %   C reference: budget_getunary()  (budget.c:58)
            bgt = uint32(0);
            for i = 1:len_val
                bgt = bgt + jxs.internal.budget.single_value_getunary(pred_buf(i), alphabet);
            end
        end

        function bgt = bounded_code(pred_buf, decoded_predictors, gtli, len_val, band_index)
            % BOUNDED_CODE  Total bit cost for bounded-alphabet coding.
            %   Uses per-element predictor values to determine the code range.
            %
            %   C reference: budget_bounded_code()  (budget.c:70)
            bgt = uint32(0);
            for i = 1:len_val
                if ~isempty(decoded_predictors)
                    % bounded alphabet 的关键在于：
                    % residual 并不是在一个固定范围里编码，
                    % 而是围绕 predictor/gtli 推导出的 [min_v, max_v] 区间来编号。
                    [min_v, max_v] = jxs.internal.bitpacker.bounded_code_get_min_max(decoded_predictors(i), gtli);
                    code = jxs.internal.bitpacker.bounded_code_get_unary_code(pred_buf(i), min_v, max_v);
                else
                    code = jxs.internal.bitpacker.bounded_code_get_unary_code(pred_buf(i), int8(-20), int8(20));
                end
                % unsigned unary 中数值 N 的码长就是 N+1，
                % 因而这里直接累加 code+1。
                bgt = bgt + uint32(code + 1);
            end
        end

        function bgt = getunary_unsigned(pred_buf, len_val)
            % GETUNARY_UNSIGNED  Total bit cost for unsigned unary coding.
            %   Each value V costs (V + 1) bits.
            %
            %   C reference: budget_getunary_unsigned()  (budget.c:92)
            bgt = uint32(0);
            for i = 1:len_val
                bgt = bgt + uint32(pred_buf(i) + 1);
            end
        end

        function bgt = getcbr(total_budget, n_lines, total_lines)
            % GETCBR  Compute CBR (constant bit-rate) budget milestone.
            %   bgt = getcbr(TOTAL, N_LINES, TOTAL_LINES) returns the
            %   number of nibbles that should have been consumed after
            %   encoding N_LINES of TOTAL_LINES, rounded down to even.
            %
            %   C reference: budget_getcbr()  (budget.c:103)
            bigint = uint64(total_budget);
            bigint = bigint * uint64(n_lines);
            bigint = idivide(bigint, uint64(total_lines));
            % 结果按偶数 nibble 对齐，和 C 端的 budget 记账粒度一致。
            bgt = uint32(bitand(bigint, bitcmp(uint64(1), 'uint64')));
        end
    end
end
