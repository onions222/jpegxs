% Constants.m — JPEG XS 常量、枚举和小工具函数总表。
%
% 对应 C 参考头文件：
%   - common.h
%   - bitpacking.h
%   - packing.h
%   - gcli_methods.h
%   - xs_markers.h
%   - libjxs.h
%
% 这个文件的目标很简单：
%   把所有“散落在规范和 C 代码里的魔法数字”集中到一个地方，
%   这样其他 MATLAB 模块就能尽量写成可读的名字，而不是直接写常数。
% code used across the JPEG XS codec.  All values use int32 to ensure
% consistent behaviour in mixed-type arithmetic (MATLAB promotes to
% the type of the first operand in many bit operations).
%
% Also provides static utility functions for GCLI method field
% extraction and MSB-packing pattern classification.

classdef Constants
    % ---- libjxs.h -----------------------------------------------------------
    properties (Constant)
        MAX_NDECOMP_H = int32(5)
        MAX_NDECOMP_V = int32(2)
        MAX_NCOMPS = int32(4)
        MAX_NFILTER_TYPES = int32(10)
        MAX_NBANDS = int32(40)
    end

    % ---- common.h -----------------------------------------------------------
    properties (Constant)
        MAX_PACKETS = int32(52)
        MAX_SUBPKTS = int32(52)
        MAX_PREC_COLS = int32(130)
        MAX_GCLI = int32(15)
        RA_BUDGET_INVALID = int32(hex2dec('8000000'))
        SIGN_BIT_POSITION = int32(31)
        SIGN_BIT_MASK = uint32(hex2dec('80000000'))
    end

    % ---- enums (uint8 for compact storage, int32 for arithmetic) ------------
    properties (Constant)
        XS_GAINS_OPT_PSNR = int32(0)
        XS_GAINS_OPT_VISUAL = int32(1)
        XS_GAINS_OPT_EXPLICIT = int32(2)

        XS_PROFILE_AUTO = int32(hex2dec('ffff'))
        XS_PROFILE_UNRESTRICTED = int32(0)
        XS_PROFILE_MAIN_444_12 = int32(hex2dec('3a40'))

        XS_LEVEL_AUTO = int32(hex2dec('ff'))
        XS_LEVEL_UNRESTRICTED = int32(hex2dec('00'))
        XS_LEVEL_1K_1 = int32(hex2dec('04'))
        XS_LEVEL_2K_1 = int32(hex2dec('10'))
        XS_LEVEL_4K_1 = int32(hex2dec('20'))

        XS_SUBLEVEL_AUTO = int32(hex2dec('ff'))
        XS_SUBLEVEL_UNRESTRICTED = int32(hex2dec('00'))
        XS_SUBLEVEL_FULL = int32(hex2dec('80'))
        XS_SUBLEVEL_12_BPP = int32(hex2dec('10'))
        XS_SUBLEVEL_9_BPP = int32(hex2dec('0c'))
        XS_SUBLEVEL_6_BPP = int32(hex2dec('08'))
        XS_SUBLEVEL_4_BPP = int32(hex2dec('06'))
        XS_SUBLEVEL_3_BPP = int32(hex2dec('04'))
        XS_SUBLEVEL_2_BPP = int32(hex2dec('03'))

        XS_CAP_AUTO = int32(hex2dec('ffff'))
        XS_CAP_STAR_TETRIX = int32(hex2dec('4000'))
        XS_CAP_NLT_Q = int32(hex2dec('2000'))
        XS_CAP_NLT_E = int32(hex2dec('1000'))
        XS_CAP_SY = int32(hex2dec('0800'))
        XS_CAP_SD = int32(hex2dec('0400'))
        XS_CAP_MLS = int32(hex2dec('0200'))
        XS_CAP_RAW_PER_PKT = int32(hex2dec('0080'))

        XS_CPIH_AUTO = int32(hex2dec('ff'))
        XS_CPIH_NONE = int32(0)
        XS_CPIH_RCT = int32(1)
        XS_CPIH_TETRIX = int32(3)

        XS_NLT_NONE = int32(0)
        XS_NLT_QUADRATIC = int32(1)
        XS_NLT_EXTENDED = int32(2)

        XS_TETRIX_FULL = int32(0)
        XS_TETRIX_INLINE = int32(3)

        XS_CFA_RGGB = int32(0)
        XS_CFA_BGGR = int32(1)
        XS_CFA_GRBG = int32(2)
        XS_CFA_GBRG = int32(3)
        XS_CFA_NONE = int32(0)

        % bitpacking.h
        UNARY_ALPHABET_0 = int32(0)
        UNARY_ALPHABET_4_CLIPPED = int32(1)
        UNARY_ALPHABET_FULL = int32(2)
        UNARY_ALPHABET_NB = int32(3)
        FIRST_ALPHABET = int32(0)
        MAX_UNARY = int32(15)
        MAX_UNARY_CLIPPED = int32(13)

        % packing.h
        GCLI_METHOD_NBITS = int32(2)
        PREC_HDR_PREC_SIZE = int32(24)
        PREC_HDR_QUANTIZATION_SIZE = int32(8)
        PREC_HDR_REFINEMENT_SIZE = int32(8)
        PREC_HDR_ALIGNMENT = int32(8)
        PKT_HDR_DATA_SIZE_SHORT = int32(15)
        PKT_HDR_DATA_SIZE_LONG = int32(20)
        PKT_HDR_GCLI_SIZE_SHORT = int32(13)
        PKT_HDR_GCLI_SIZE_LONG = int32(20)
        PKT_HDR_SIGN_SIZE_SHORT = int32(11)
        PKT_HDR_SIGN_SIZE_LONG = int32(15)
        PKT_HDR_ALIGNMENT = int32(8)
        SUBPKT_ALIGNMENT = int32(8)

        % gcli_methods.h
        ALPHABET_NBITS = int32(1)
        ALPHABET_RAW_4BITS = int32(0)
        ALPHABET_UNARY_UNSIGNED_BOUNDED = int32(1)
        ALPHABET_COUNT = int32(2)
        PRED_NBITS = int32(1)
        PRED_NONE = int32(0)
        PRED_VER = int32(1)
        PRED_COUNT = int32(2)
        RUN_NBITS = int32(2)
        RUN_NONE = int32(0)
        RUN_SIGFLAGS_ZRF = int32(1)
        RUN_SIGFLAGS_ZRCSF = int32(2)
        RUN_COUNT = int32(3)
        GCLI_METHODS_NB = int32(16)
        PRED_OFFSET = int32(0)
        ALPHABET_OFFSET = int32(1)
        RUN_OFFSET = int32(2)

        METHOD_ENABLE_MASK_PREDICTIONS_OFFSET = int32(0)
        METHOD_ENABLE_MASK_ALPHABETS_OFFSET = int32(2)
        METHOD_ENABLE_MASK_RUNS_OFFSET = int32(4)

        PRECINCT_ALL = int32(0)
        PRECINCT_FIRST_OF_SLICE = int32(1)
        PRECINCT_OTHERS = int32(2)

        % xs_markers.h
        XS_MARKER_NBYTES = int32(2)
        XS_MARKER_SOC = int32(hex2dec('ff10'))
        XS_MARKER_EOC = int32(hex2dec('ff11'))
        XS_MARKER_PIH = int32(hex2dec('ff12'))
        XS_MARKER_CDT = int32(hex2dec('ff13'))
        XS_MARKER_WGT = int32(hex2dec('ff14'))
        XS_MARKER_COM = int32(hex2dec('ff15'))
        XS_MARKER_NLT = int32(hex2dec('ff16'))
        XS_MARKER_CWD = int32(hex2dec('ff17'))
        XS_MARKER_CTS = int32(hex2dec('ff18'))
        XS_MARKER_CRG = int32(hex2dec('ff19'))
        XS_MARKER_SLH = int32(hex2dec('ff20'))
        XS_MARKER_CAP = int32(hex2dec('ff50'))
    end

    % ---- Utility functions (used across multiple modules) -------------------
    methods (Static)
        function r = MAX(a, b)
            % MAX  Integer max (avoids MATLAB's max() which may change types).
            if a > b, r = a; else, r = b; end
        end
        function r = MIN(a, b)
            % MIN  Integer min.
            if a < b, r = a; else, r = b; end
        end
        function r = ABS(a)
            if a < 0, r = -a; else, r = a; end
        end

        function r = iif(cond, t, f)
            % IIF  Inline if-else expression (ternary operator equivalent).
            if cond, r = t; else, r = f; end
        end


        function a = method_get_alphabet(gcli_method)
            % METHOD_GET_ALPHABET  Extract alphabet field from packed GCLI method.
            %   C reference: method_get_alphabet()  (gcli_methods.h)
            c = jxs.Constants;
            a = bitand(bitshift(int32(gcli_method), -c.ALPHABET_OFFSET), bitshift(int32(1), c.ALPHABET_NBITS) - 1);
        end
        function p = method_get_pred(gcli_method)
            % METHOD_GET_PRED  Extract prediction field from packed GCLI method.
            c = jxs.Constants;
            p = bitand(bitshift(int32(gcli_method), -c.PRED_OFFSET), bitshift(int32(1), c.PRED_NBITS) - 1);
        end
        function r = method_get_run(gcli_method)
            % METHOD_GET_RUN  Extract run-mode field from packed GCLI method.
            c = jxs.Constants;
            r = bitand(bitshift(int32(gcli_method), -c.RUN_OFFSET), bitshift(int32(1), c.RUN_NBITS) - 1);
        end
        function idx = method_get_idx(alphabet, pred, run)
            % METHOD_GET_IDX  Pack alphabet, prediction, and run-mode into a method index.
            c = jxs.Constants;
            idx = bitor(bitor(bitshift(int32(alphabet), c.ALPHABET_OFFSET), ...
                              bitshift(int32(pred), c.PRED_OFFSET)), ...
                        bitshift(int32(run), c.RUN_OFFSET));
        end
        function tf = method_uses_ver_pred(gcli_method)
            tf = (jxs.Constants.method_get_pred(gcli_method) == jxs.Constants.PRED_VER);
        end
        function tf = method_uses_no_pred(gcli_method)
            tf = (jxs.Constants.method_get_pred(gcli_method) == jxs.Constants.PRED_NONE);
        end
        function tf = method_is_raw(gcli_method)
            tf = (jxs.Constants.method_get_alphabet(gcli_method) == jxs.Constants.ALPHABET_RAW_4BITS);
        end
        function tf = method_uses_sig_flags(gcli_method)
            r = jxs.Constants.method_get_run(gcli_method);
            tf = (r == jxs.Constants.RUN_SIGFLAGS_ZRF) || (r == jxs.Constants.RUN_SIGFLAGS_ZRCSF);
        end
        function tf = msbp_is_short_code(nibble)
            tf = (nibble == 1 || nibble == 2 || nibble == 4 || nibble == 8);
        end
        function tf = msbp_is_rot1(nibble)
            tf = (nibble == 5 || nibble == 7 || nibble == 13);
        end
        function tf = msbp_is_rot0(nibble)
            tf = (nibble == 10 || nibble == 14 || nibble == 11);
        end
    end
end
