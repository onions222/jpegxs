% mct.m — 多分量颜色变换。
%
% 对应 C 参考实现：libjxs/src/mct.c
% 标准位置：ISO/IEC 21122-1 Annex D
%
% 当前主要实现的是 RCT（RGB <-> YCoCg 风格可逆 decorrelation）。
% 它的目的不是压缩本身，而是降低颜色通道之间的相关性，
% 让后面的 DWT + 熵编码更有效率。
% which decorrelates RGB into a luminance + two chrominance channels.
% Tetrix (Bayer CFA) transform is declared but not yet implemented.

classdef mct
    methods (Static)
        function forward_rct(im)
            % FORWARD_RCT  RGB → YCoCg-like decorrelation (in-place).
            %   Operates on the first three components of IM.
            %   After transform: comp1=Y, comp2=Co, comp3=Cg.
            %
            %   C reference: mct_forward_rct()  (mct.c:78)
            %   Standard:    Eq. (D-1) in ISO/IEC 21122-1
            assert(im.ncomps >= 3);
            len = int32(im.width) * int32(im.height);
            c0 = im.comps_array{1}; c1 = im.comps_array{2}; c2 = im.comps_array{3};
            for i = 1:len
                g = c1(i);
                % 这几步正好对应标准里的整数 lifting 形式，
                % 全程只用加减和右移，保证可逆且不会引入浮点误差。
                tmp = bitshift(c0(i) + 2 * g + c2(i), -2);
                c1(i) = c2(i) - g; c2(i) = c0(i) - g; c0(i) = tmp;
            end
            im.comps_array{1} = c0; im.comps_array{2} = c1; im.comps_array{3} = c2;
        end

        function inverse_rct(im)
            % INVERSE_RCT  YCoCg-like → RGB reconstruction (in-place).
            %
            %   C reference: mct_inverse_rct()  (mct.c:102)
            %   Standard:    Eq. (D-2) in ISO/IEC 21122-1
            assert(im.ncomps >= 3);
            len = int32(im.width) * int32(im.height);
            c0 = im.comps_array{1}; c1 = im.comps_array{2}; c2 = im.comps_array{3};
            for i = 1:len
                % 逆变换严格按 forward 的反顺序恢复，
                % 因而只要整数位宽足够，就能逐样本 bit-exact 回到 RGB。
                tmp = c0(i) - bitshift(c1(i) + c2(i), -2);
                c0(i) = tmp + c2(i); c2(i) = tmp + c1(i); c1(i) = tmp;
            end
            im.comps_array{1} = c0; im.comps_array{2} = c1; im.comps_array{3} = c2;
        end

        function forward_transform(im, p)
            % FORWARD_TRANSFORM  Dispatch to the selected MCT variant.
            %
            %   C reference: mct_forward_transform()  (mct.c:210)
            import jxs.Constants;
            switch p.color_transform
                case Constants.XS_CPIH_NONE
                    % no-op
                case Constants.XS_CPIH_RCT
                    jxs.internal.mct.forward_rct(im);
                case Constants.XS_CPIH_TETRIX
                    % TODO: mct_forward_tetrix
                    error('Tetrix not yet implemented');
                otherwise
                    error('Unknown color transform');
            end
        end

        function inverse_transform(im, p)
            % INVERSE_TRANSFORM  Dispatch to the selected inverse MCT variant.
            %
            %   C reference: mct_inverse_transform()  (mct.c:248)
            import jxs.Constants;
            switch p.color_transform
                case Constants.XS_CPIH_NONE
                    % no-op
                case Constants.XS_CPIH_RCT
                    jxs.internal.mct.inverse_rct(im);
                case Constants.XS_CPIH_TETRIX
                    % TODO: mct_inverse_tetrix
                    error('Tetrix not yet implemented');
                otherwise
                    error('Unknown color transform');
            end
        end
    end
end
