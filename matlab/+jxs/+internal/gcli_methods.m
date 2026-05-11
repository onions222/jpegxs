% gcli_methods.m — GCLI 编码方法的枚举与筛选。
%
% 对应 C 参考实现：libjxs/src/gcli_methods.c
% 标准位置：ISO/IEC 21122-1 Annex F.3
%
% 一个 GCLI method 实际上把三种选择打包在一起：
%   - predictor
%   - alphabet
%   - run/significance 模式
%   bit 0     : prediction  (PRED_NONE=0, PRED_VER=1)
%   bit 1     : alphabet    (RAW_4BITS=0, UNARY_UNSIGNED_BOUNDED=1)
%   bits 3:2  : run-mode    (NONE=0, ZRF=1, ZRCSF=2)
%
% This class provides helpers to:
%   - Determine which methods are enabled for a given configuration
%   - Convert between internal method index and 2-bit signaling code
%   - Filter enabled methods for vertical-only or no-vertical subsets

classdef gcli_methods
    methods (Static)
        function enabled = get_enabled(xs_config)
            % GET_ENABLED  Compute bitmask of all enabled GCLI methods.
            %   The enabled set depends on the Rm parameter (run-mode
            %   selection between ZRF and ZRCSF).
            %
            %   C reference: gcli_methods_get_enabled()  (gcli_methods.c:20)
            c = jxs.Constants;
            % 当前 MATLAB/C 对齐实现里只启用两类 alphabet：
            %   1. RAW_4BITS                      作为 raw fallback
            %   2. UNARY_UNSIGNED_BOUNDED        作为主要熵编码 alphabet
            % 其它标准允许的变体这里没有单独展开。
            enabled_alphabets = bitor(bitshift(int32(1), c.ALPHABET_RAW_4BITS), ...
                                      bitshift(int32(1), c.ALPHABET_UNARY_UNSIGNED_BOUNDED));
            enabled_predictions = bitor(bitshift(int32(1), c.PRED_VER), ...
                                        bitshift(int32(1), c.PRED_NONE));
            if xs_config.p.Rm == 1
                % Rm 在这里控制“带 sig_flags 时到底选哪种 run 语义”。
                enabled_runs = bitshift(int32(1), c.RUN_SIGFLAGS_ZRCSF);
            else
                enabled_runs = bitshift(int32(1), c.RUN_SIGFLAGS_ZRF);
            end
            enabled_runs = bitor(enabled_runs, bitshift(int32(1), c.RUN_NONE));
            % enabled 是一个大 bitmask，不是 method 列表。
            % 它按 alphabet / predictor / run 三个维度分别占不同 bit 段。
            enabled = bitor(bitor(...
                bitshift(enabled_alphabets, c.METHOD_ENABLE_MASK_ALPHABETS_OFFSET), ...
                bitshift(enabled_predictions, c.METHOD_ENABLE_MASK_PREDICTIONS_OFFSET)), ...
                bitshift(enabled_runs, c.METHOD_ENABLE_MASK_RUNS_OFFSET));
        end

        function enabled = get_enabled_ver(enabled)
            % GET_ENABLED_VER  Mask out PRED_NONE to keep only vertical methods.
            %
            %   C reference: gcli_methods_get_enabled_ver()  (gcli_methods.c:50)
            c = jxs.Constants;
            mask = bitcmp(bitshift(int32(1), c.PRED_NONE + c.METHOD_ENABLE_MASK_PREDICTIONS_OFFSET));
            enabled = bitand(int32(enabled), mask);
        end

        function enabled = get_enabled_nover(enabled)
            % GET_ENABLED_NOVER  Mask out PRED_VER to keep only non-vertical methods.
            %
            %   C reference: gcli_methods_get_enabled_nover()  (gcli_methods.c:58)
            c = jxs.Constants;
            mask = bitcmp(bitshift(int32(1), c.PRED_VER + c.METHOD_ENABLE_MASK_PREDICTIONS_OFFSET));
            enabled = bitand(int32(enabled), mask);
        end

        function ok = is_enabled(enabled, gcli_method, precinct_group)
            % IS_ENABLED  Check whether a specific method is enabled.
            %   ok = is_enabled(ENABLED_MASK, METHOD, PRECINCT_GROUP)
            %   PRECINCT_GROUP is PRECINCT_ALL, PRECINCT_FIRST_OF_SLICE,
            %   or PRECINCT_OTHERS.  Vertical prediction is disabled for
            %   the first precinct of each slice.
            %
            %   C reference: gcli_methods_is_enabled()  (gcli_methods.c:66)
            c = jxs.Constants;
            en = int32(enabled);
            a_off = int32(c.METHOD_ENABLE_MASK_ALPHABETS_OFFSET);
            p_off = int32(c.METHOD_ENABLE_MASK_PREDICTIONS_OFFSET);
            r_off = int32(c.METHOD_ENABLE_MASK_RUNS_OFFSET);
            enabled_alphabets = bitand(bitshift(en, -a_off), bitshift(int32(1), c.ALPHABET_COUNT) - 1);
            enabled_predictions = bitand(bitshift(en, -p_off), bitshift(int32(1), c.PRED_COUNT) - 1);
            enabled_runs = bitand(bitshift(en, -r_off), bitshift(int32(1), c.RUN_COUNT) - 1);
            alphabet = c.method_get_alphabet(gcli_method);
            pred = c.method_get_pred(gcli_method);
            run = c.method_get_run(gcli_method);
            % method 是否可用，要同时满足三层约束：
            %   1. alphabet 被允许
            %   2. run 模式被允许
            %   3. predictor 被允许，且如果是 slice 首块则不能依赖 vertical
            if bitand(bitshift(int32(1), alphabet), enabled_alphabets) == 0, ok = false; return; end
            if alphabet ~= c.ALPHABET_RAW_4BITS
                if bitand(bitshift(int32(1), run), enabled_runs) == 0, ok = false; return; end
                if bitand(bitshift(int32(1), pred), enabled_predictions) == 0, ok = false; return; end
                if precinct_group == c.PRECINCT_FIRST_OF_SLICE && pred ~= c.PRED_NONE
                    ok = false; return;
                end
            else
                if run ~= c.RUN_NONE || pred ~= c.PRED_NONE, ok = false; return; end
            end
            ok = true;
        end

        function signaling = get_signaling(gcli_method, enabled_methods)
            % GET_SIGNALING  Convert internal method index to 2-bit signaling code.
            %   Returns -1 for RAW method (not signaled in precinct header).
            %   Bit 0 = uses vertical prediction, bit 1 = uses sig flags.
            %
            %   C reference: gcli_method_get_signaling()  (gcli_methods.c:102)
            c = jxs.Constants;
            if gcli_method == c.method_get_idx(c.ALPHABET_RAW_4BITS, 0, 0)
                % raw fallback 不通过 precinct header 的 signaling 字段表达，
                % 它是由 sub-packet header 里的 uses_raw_fallback 单独指示的。
                signaling = int32(-1); return;
            end
            uses_run = (c.method_get_run(gcli_method) == c.RUN_SIGFLAGS_ZRF || ...
                        c.method_get_run(gcli_method) == c.RUN_SIGFLAGS_ZRCSF);
            % precinct header 实际只编码两个布尔量：
            %   bit0: 是否使用 vertical predictor
            %   bit1: 是否带 significance flags / run 语义
            signaling = bitor(jxs.Constants.iif(uses_run, int32(2), int32(0)), ...
                             jxs.Constants.iif(c.method_get_pred(gcli_method) == c.PRED_VER, int32(1), int32(0)));
        end

        function gcli_method = from_signaling(signaling, enabled_methods)
            % FROM_SIGNALING  Recover internal method index from 2-bit signaling code.
            %   Searches enabled methods for one whose signaling code matches.
            %
            %   C reference: gcli_method_from_signaling()  (gcli_methods.c:118)
            c = jxs.Constants;
            for gm = int32(0):(c.GCLI_METHODS_NB - 1)
                % 同一个 signaling 只会映射到当前 enabled 集合中的一个合法方法；
                % 所以这里直接线性扫一遍候选方法就够了。
                if jxs.internal.gcli_methods.is_enabled(enabled_methods, gm, c.PRECINCT_ALL) && ...
                   jxs.internal.gcli_methods.get_signaling(gm, enabled_methods) == int32(signaling)
                    gcli_method = gm; return;
                end
            end
            gcli_method = c.method_get_idx(c.ALPHABET_RAW_4BITS, 0, 0);
        end
    end
end
