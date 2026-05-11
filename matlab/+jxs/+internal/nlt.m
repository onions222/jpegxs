% nlt.m — 非线性点变换（含 DC level shift）。
%
% 对应 C 参考实现：libjxs/src/nlt.c
% 标准位置：ISO/IEC 21122-1 Annex C
%
% 这个模块处理 JPEG XS 在空间变换前后的逐点映射：
%   - 最常见的是线性 DC level shift
%   - 也支持 quadratic / extended NLT
%
% 注意：
%   MATLAB 的 cell / 数组是值语义，
%   对组件缓冲区做修改后必须显式写回 comps_array{c}。
% pixel values into a signed working range prior to the DWT:
%   - Linear   (NLT_NONE):      simple DC level shift by Bw/2
%   - Quadratic (NLT_QUADRATIC): square-root / square mapping  (Annex C.3)
%   - Extended  (NLT_EXTENDED):  piecewise linear-quadratic     (Annex C.4)
%
% NOTE: MATLAB copy-on-write requires im.comps_array{c}=ptr after modification.

classdef nlt
    methods (Static)
        function v = clamp(v, max_v)
            % CLAMP  Clamp int32 value to [0, max_v].
            if v > max_v, v = max_v; end
            if v < 0, v = int32(0); end
        end

        function v = clamp64(v, max_v)
            % CLAMP64  Clamp int64 value to [0, max_v].
            if v > max_v, v = max_v; end
            if v < int64(0), v = int64(0); end
        end

        function r = sqrt_approx_fixpoint(v, Bw)
            % SQRT_APPROX_FIXPOINT  Fixed-point integer square root.
            %   r = sqrt_approx_fixpoint(V, BW) computes floor(sqrt(V))
            %   using a bit-serial algorithm with BW iterations.
            %
            %   C reference: sqrt_approx_fixpoint()  (nlt.c:15)
            assert(v >= 0);
            r = int64(0); bw_val = int32(Bw);
            for i = 1:bw_val
                r = bitshift(r, 1); v = bitshift(v, 2);
                if bitshift(v, -bw_val) > r
                    v = v - bitshift(r + 1, bw_val); r = r + 2;
                end
            end
            r = bitshift(r, -1);
        end

        function inverse_linear(im, Bw)
            % INVERSE_LINEAR  Inverse DC level shift (signed → unsigned).
            %   Adds DC offset (2^(Bw-1)) and right-shifts by (Bw - depth).
            %
            %   C reference: nlt_inverse_linear()  (nlt.c:36)
            %   Standard:    Annex C.2
            s = int32(Bw) - im.depth;
            dclev_and_rounding = bitshift(int32(1), int32(Bw - 1)) + bitshift(int32(1), int32(s) - 1);
            max_val = bitshift(int32(1), im.depth) - 1;
            for c = 1:double(im.ncomps)
                ptr = im.comps_array{c};
                for i = 1:length(ptr)
                    ptr(i) = jxs.internal.nlt.clamp(bitshift(ptr(i) + dclev_and_rounding, -s), max_val);
                end
                im.comps_array{c} = ptr;
            end
        end

        function forward_linear(im, Bw)
            % FORWARD_LINEAR  Forward DC level shift (unsigned → signed).
            %   Left-shifts by (Bw - depth) and subtracts DC offset (2^(Bw-1)).
            %
            %   C reference: nlt_forward_linear()  (nlt.c:55)
            %   Standard:    Annex C.2
            s = int32(Bw) - im.depth;
            dclev = bitshift(int32(1), int32(Bw - 1));
            for c = 1:double(im.ncomps)
                ptr = im.comps_array{c};
                for i = 1:length(ptr)
                    ptr(i) = bitshift(ptr(i), s) - dclev;
                end
                im.comps_array{c} = ptr;
            end
        end

        function inverse_quadratic(im, Bw, nlt_params)
            % INVERSE_QUADRATIC  Inverse quadratic NLT (square mapping).
            %   v_out = clamp( v^2 / 2^s + vdco )
            %
            %   C reference: nlt_inverse_quadratic()  (nlt.c:74)
            %   Standard:    Annex C.3, Eq. (C-3)
            vdco = int32(nlt_params.quadratic.alpha) - int32(nlt_params.quadratic.sigma) * 32768;
            s = int32(Bw * 2) - im.depth;
            dclev = bitshift(int32(1), int32(Bw - 1));
            s_r = bitshift(int32(1), s - 1);
            max_val = bitshift(int32(1), im.depth) - 1;
            max_coef = bitshift(int32(1), int32(Bw)) - 1;
            for c = 1:double(im.ncomps)
                ptr = im.comps_array{c};
                for i = 1:length(ptr)
                    v = int64(jxs.internal.nlt.clamp(ptr(i) + dclev, max_coef));
                    ptr(i) = int32(jxs.internal.nlt.clamp64(bitshift(v * v + int64(s_r), -s) + int64(vdco), int64(max_val)));
                end
                im.comps_array{c} = ptr;
            end
        end

        function forward_quadratic(im, Bw, nlt_params)
            % FORWARD_QUADRATIC  Forward quadratic NLT (square-root mapping).
            %   v_out = sqrt_approx(v_shifted) - dclev
            %
            %   C reference: nlt_forward_quadratic()  (nlt.c:100)
            %   Standard:    Annex C.3, Eq. (C-4)
            vdco = int32(nlt_params.quadratic.alpha) - int32(nlt_params.quadratic.sigma) * 32768;
            s = int32(Bw) - im.depth;
            max_val = bitshift(int32(1), im.depth) - 1;
            dclev = bitshift(int32(1), int32(Bw - 1));
            for c = 1:double(im.ncomps)
                ptr = im.comps_array{c};
                for i = 1:length(ptr)
                    v = int64(jxs.internal.nlt.clamp(ptr(i) - vdco, max_val));
                    v = bitshift(v, s);
                    v = jxs.internal.nlt.sqrt_approx_fixpoint(v, Bw);
                    ptr(i) = int32(v - int64(dclev));
                end
                im.comps_array{c} = ptr;
            end
        end

        function inverse_extended(im, Bw, nlt_params)
            % INVERSE_EXTENDED  Inverse extended piecewise NLT.
            %   Three regions: parabolic (< T1), linear, parabolic (> T2).
            %
            %   C reference: nlt_inverse_extended()  (nlt.c:127)
            %   Standard:    Annex C.4, Eq. (C-5)
            e = int32(Bw) - int32(nlt_params.extended.E);
            T1 = int64(nlt_params.extended.T1); T2 = int64(nlt_params.extended.T2);
            B2 = T1 * T1;
            A1 = B2 + bitshift(T1, e) + bitshift(int64(1), 2 * e - 2);
            B1 = T1 + bitshift(int64(1), e - 1);
            A3 = B2 + bitshift(T2, e) - bitshift(int64(1), 2 * e - 2);
            B3 = T2 - bitshift(int64(1), e - 1);
            s = int32(Bw * 2) - im.depth; s_r = bitshift(int32(1), s - 1);
            max_val = bitshift(int32(1), im.depth) - 1;
            max_coef = bitshift(int32(1), int32(Bw)) - 1;
            dclev = bitshift(int32(1), int32(Bw - 1));
            for c = 1:double(im.ncomps)
                ptr = im.comps_array{c};
                for i = 1:length(ptr)
                    v = int64(ptr(i)) + int64(dclev);
                    if v < T1
                        v = jxs.internal.nlt.clamp64(B1 - v, int64(max_coef)); v = A1 - v * v;
                    elseif v < T2
                        v = bitshift(v, e) + B2;
                    else
                        v = jxs.internal.nlt.clamp64(v - B3, int64(max_coef)); v = A3 + v * v;
                    end
                    ptr(i) = int32(jxs.internal.nlt.clamp64(bitshift(v + int64(s_r), -s), int64(max_val)));
                end
                im.comps_array{c} = ptr;
            end
        end

        function forward_extended(im, Bw, nlt_params)
            % FORWARD_EXTENDED  Forward extended piecewise NLT.
            %   Three regions: parabolic (< Q1), linear, parabolic (> Q2).
            %
            %   C reference: nlt_forward_extended()  (nlt.c:167)
            %   Standard:    Annex C.4, Eq. (C-6)
            e = int32(Bw) - int32(nlt_params.extended.E);
            T1 = int64(nlt_params.extended.T1); T2 = int64(nlt_params.extended.T2);
            B2 = T1 * T1;
            A1 = B2 + bitshift(T1, e) + bitshift(int64(1), 2 * e - 2);
            B1 = T1 + bitshift(int64(1), e - 1);
            A3 = B2 + bitshift(T2, e) - bitshift(int64(1), 2 * e - 2);
            B3 = T2 - bitshift(int64(1), e - 1);
            Q1 = B2 + bitshift(T1, e); Q2 = B2 + bitshift(T2, e);
            s = int32(Bw * 2) - im.depth; s_r = bitshift(int32(1), s - 1);
            dclev = bitshift(int32(1), int32(Bw - 1));
            for c = 1:double(im.ncomps)
                ptr = im.comps_array{c};
                for i = 1:length(ptr)
                    v = bitshift(int64(ptr(i)), s);
                    if v < Q1
                        v = B1 - int64(sqrt(double(A1 - v) + 0.5));
                    elseif v < Q2
                        v = bitshift(v - B2, -e);
                    else
                        v = B3 + int64(sqrt(double(v - A3) + 0.5));
                    end
                    ptr(i) = int32(v - int64(dclev));
                end
                im.comps_array{c} = ptr;
            end
        end

        function inverse_transform(im, p)
            % INVERSE_TRANSFORM  Dispatch to the selected inverse NLT.
            %
            %   C reference: nlt_inverse_transform()  (nlt.c:210)
            import jxs.Constants;
            switch p.Tnlt
                case Constants.XS_NLT_NONE, jxs.internal.nlt.inverse_linear(im, p.Bw);
                case Constants.XS_NLT_QUADRATIC, jxs.internal.nlt.inverse_quadratic(im, p.Bw, p.Tnlt_params);
                case Constants.XS_NLT_EXTENDED, jxs.internal.nlt.inverse_extended(im, p.Bw, p.Tnlt_params);
                otherwise, error('Unknown NLT type');
            end
        end

        function forward_transform(im, p)
            % FORWARD_TRANSFORM  Dispatch to the selected forward NLT.
            %
            %   C reference: nlt_forward_transform()  (nlt.c:224)
            import jxs.Constants;
            switch p.Tnlt
                case Constants.XS_NLT_NONE, jxs.internal.nlt.forward_linear(im, p.Bw);
                case Constants.XS_NLT_QUADRATIC, jxs.internal.nlt.forward_quadratic(im, p.Bw, p.Tnlt_params);
                case Constants.XS_NLT_EXTENDED, jxs.internal.nlt.forward_extended(im, p.Bw, p.Tnlt_params);
                otherwise, error('Unknown NLT type');
            end
        end
    end
end
