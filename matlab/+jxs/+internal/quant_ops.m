% quant_ops.m — 系数量化与反量化。
%
% 对应 C 参考实现：libjxs/src/quant.c
% 标准位置：ISO/IEC 21122-1 Annex G.4
%
% 这里封装 JPEG XS 对波形系数做 quantize / dequantize 的规则，
% 包括 sign-magnitude 表示下的边界细节。
% sign-magnitude wavelet coefficients.  All values are stored in
% sign-magnitude format: bit 31 = sign, bits [30:0] = magnitude.
%
% Two quantizer modes:
%   dq_type=1 (Qpih=1): Uniform — preserves more precision via
%                        geometric-series reconstruction.
%   dq_type=0 (Qpih=0): Deadzone — simple right-shift truncation
%                        with mid-point reconstruction.

classdef quant_ops
    properties (Constant)
        SBM = uint32(hex2dec('80000000'))       % Sign-bit mask (bit 31)
        MAG_MASK = uint32(hex2dec('7fffffff'))   % Magnitude mask (bits 30:0)
    end

    methods (Static)
        function dq_out = uniform_dq(sig_mag_value, gcli, gtli)
            % UNIFORM_DQ  Forward uniform quantization of one coefficient.
            %   Truncates and rescales using the formula:
            %     mag_out = (mag << zeta - mag + 2^gcli) >> (gcli+1)
            %   where zeta = gcli - gtli + 1.
            %
            %   C reference: quant_uniform_dq()  (quant.c:14)
            % 这里输入/输出都是 sign-magnitude 格式：
            %   bit31      = 符号位
            %   bit[30:0]  = 幅度
            %
            % uniform_dq 的核心思想不是简单右移，而是：
            %   先按 gcli / gtli 关系把高位截断，
            %   再用一个几何级数近似保留更多幅度信息。
            dq_out = uint32(0);
            if gcli > gtli
                zeta = int32(gcli - gtli + 1);
                sig_u = uint32(sig_mag_value);
                d = int32(bitand(sig_u, jxs.internal.quant_ops.MAG_MASK));
                % 这条式子直接对应 C 参考实现。
                % 可以粗略理解成：
                %   “保留主要高位 + 对被丢掉低位做一个折中补偿”
                dq_mag = uint32(bitshift(bitshift(d, zeta) - d + bitshift(int32(1), gcli), -(gcli + 1)));
                if dq_mag ~= 0
                    dq_out = bitor(dq_mag, bitand(sig_u, jxs.internal.quant_ops.SBM));
                else
                    dq_out = dq_mag;
                end
            end
        end

        function sigmag = uniform_dq_inverse(dq_in, gcli, gtli)
            % UNIFORM_DQ_INVERSE  Inverse uniform dequantization.
            %   Reconstructs magnitude via geometric-series summation:
            %     rho = phi + (phi >> zeta) + (phi >> 2*zeta) + ...
            %
            %   C reference: quant_uniform_dq_inverse()  (quant.c:36)
            sign_val = bitand(uint32(dq_in), jxs.internal.quant_ops.SBM);
            phi = int32(bitand(uint32(dq_in), jxs.internal.quant_ops.MAG_MASK));
            zeta = int32(gcli - gtli + 1);
            rho = int32(0);
            % 这里的 while 循环对应几何级数求和：
            %   rho = phi + phi/2^zeta + phi/2^(2*zeta) + ...
            % 目的是把编码端压缩过的幅度近似还原回来。
            while phi > 0
                rho = rho + phi;
                phi = bitshift(phi, -zeta);
            end
            sigmag = bitor(sign_val, uint32(rho));
        end

        function dq_out = deadzone_dq(sig_mag_value, gcli, gtli)
            % DEADZONE_DQ  Forward deadzone quantization of one coefficient.
            %   Simple right-shift: mag_out = mag >> gtli.
            %
            %   C reference: quant_deadzone_dq()  (quant.c:52)
            % deadzone 量化就是更直接的“右移截断”。
            % 它比 uniform 更简单，但重建精度会差一些。
            sig_u = uint32(sig_mag_value);
            dq_out = bitshift(bitand(sig_u, jxs.internal.quant_ops.MAG_MASK), -int32(gtli));
            if dq_out ~= 0
                dq_out = bitor(dq_out, bitand(sig_u, jxs.internal.quant_ops.SBM));
            end
        end

        function sigmag = deadzone_dq_inverse(dq_in, gcli, gtli)
            % DEADZONE_DQ_INVERSE  Inverse deadzone dequantization.
            %   Reconstructs by adding midpoint: mag |= (1 << (gtli-1)).
            %
            %   C reference: quant_deadzone_dq_inverse()  (quant.c:64)
            % 反量化时把被截断区间的中点补回来，相当于 midpoint reconstruction。
            sigmag = uint32(dq_in);
            if gtli > 0 && bitand(uint32(dq_in), jxs.internal.quant_ops.MAG_MASK) ~= 0
                sigmag = bitor(sigmag, uint32(bitshift(int32(1), int32(gtli - 1))));
            end
        end

        function dq_out = apply_dq(dq_type, sig_mag_value, gcli, gtli)
            % APPLY_DQ  Forward quantization dispatcher.
            %   dq_type=1 → uniform, dq_type=0 → deadzone.
            switch dq_type
                case 1
                    dq_out = jxs.internal.quant_ops.uniform_dq(sig_mag_value, gcli, gtli);
                case 0
                    dq_out = jxs.internal.quant_ops.deadzone_dq(sig_mag_value, gcli, gtli);
                otherwise
                    error('invalid quantizer type');
            end
        end

        function sigmag = apply_dq_inverse(dq_type, dq_in, gcli, gtli)
            % APPLY_DQ_INVERSE  Inverse quantization dispatcher.
            %   dq_type=1 → uniform inverse, dq_type=0 → deadzone inverse.
            switch dq_type
                case 1
                    sigmag = jxs.internal.quant_ops.uniform_dq_inverse(dq_in, gcli, gtli);
                case 0
                    sigmag = jxs.internal.quant_ops.deadzone_dq_inverse(dq_in, gcli, gtli);
                otherwise
                    error('invalid quantizer type');
            end
        end

        function buf = quant(buf, ~, gclis, group_size, gtli, dq_type)
            % QUANT  Quantize all coefficients in a precinct band line.
            %   Processes groups of GROUP_SIZE samples.  Groups with
            %   GCLI <= GTLI are zeroed; others are quantized in-place.
            %
            %   C reference: precinct_quantize()  (quant.c:82)
            SBM = jxs.internal.quant_ops.SBM;
            buf_len = int32(length(buf));
            n_groups = idivide(buf_len + int32(group_size) - 1, int32(group_size), 'floor');
            idx = int32(1);
            for group = 1:n_groups
                gcli = int32(gclis(group));
                if gcli <= int32(gtli)
                    % 如果 group 的最大有效 bitplane 都不超过 gtli，
                    % 那这一整组在当前量化强度下都会被截成 0。
                    for i = int32(0):(int32(group_size) - 1)
                        if idx + i <= buf_len
                            buf(idx + i) = uint32(0);
                        end
                    end
                else
                    if gtli > 0
                        for i = int32(0):(int32(group_size) - 1)
                            if idx + i > buf_len, break; end
                            pos = idx + i;
                            sign_val = bitand(uint32(buf(pos)), SBM);
                            % 这里先对 sign-magnitude 的“幅度部分”做量化，
                            % 最后再把原始符号位拼回去。
                            buf(pos) = bitand(uint32(jxs.internal.quant_ops.apply_dq(dq_type, buf(pos), gcli, int32(gtli))), jxs.internal.quant_ops.MAG_MASK);
                            buf(pos) = bitor(bitshift(buf(pos), int32(gtli)), sign_val);
                        end
                    end
                end
                idx = idx + int32(group_size);
            end
        end

        function buf = dequant(buf, ~, gclis, group_size, gtli, dq_type)
            % DEQUANT  Dequantize all coefficients in a precinct band line.
            %   Inverse of QUANT — reconstructs approximate magnitudes.
            %
            %   C reference: precinct_dequantize()  (quant.c:120)
            % dequant 不会恢复“编码前的真实系数”，而是恢复成
            % 当前量化器定义下的重建值，这也是有损编码的来源之一。
            buf_len = int32(length(buf));
            n_groups = idivide(buf_len + int32(group_size) - 1, int32(group_size), 'floor');
            idx = int32(1);
            for group = 1:n_groups
                gcli = int32(gclis(group));
                if gcli > int32(gtli)
                    if gtli > 0
                        for i = int32(0):(int32(group_size) - 1)
                            if idx + i > buf_len, break; end
                            buf(idx + i) = uint32(jxs.internal.quant_ops.apply_dq_inverse(dq_type, buf(idx + i), gcli, int32(gtli)));
                        end
                    end
                end
                idx = idx + int32(group_size);
            end
        end
    end
end
