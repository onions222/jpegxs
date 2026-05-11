% msbpack.m — MSB nibble packing 优化逻辑。
%
% 对应 C 参考实现：libjxs/src/msbpack.c
%
% 某些模式下，最高位平面可以被折叠成更紧凑的 nibble 表示，
% 这里就是这套优化编码/解码规则的 MATLAB 实现。
% matches one of the predefined short-code templates.  This can
% reduce the cost of the MSB plane by ~1 bit per group.

classdef msbpack
    properties (Constant)
        MSB_CODES = uint32([0 6 4 10 2 14 9 12 0 11 14 13 8 13 12 15])
        THRESHOLD_TABLE = uint16([...
            hex2dec('6db6'), hex2dec('7777'), hex2dec('7bde'), hex2dec('7df7'), ...
            hex2dec('7efd'), hex2dec('7f7f'), hex2dec('7fbf'), hex2dec('7fdf'), ...
            hex2dec('7fef'), hex2dec('7ff7'), hex2dec('7ffb'), hex2dec('7ffd')])
    end

    methods (Static)
        function v = get_config_value(sign_packing)
            % 当前这版实现里，是否启用 msbpack 直接复用了 sign_packing 开关。
            % 这样做是为了与移植时参考的 C 路径保持一致。
            if sign_packing, v = int32(1); else, v = int32(0); end
        end

        function tf = enabled(sign_packing)
            tf = jxs.internal.msbpack.get_config_value(sign_packing) ~= 0;
        end

        function tf = test_range(gcli, gtli, sign_packing)
            nbits = int32(gcli) - gtli;
            mbits = jxs.internal.msbpack.get_config_value(sign_packing);
            % 只有当剩余 bit-plane 数落在可优化的短范围内时，
            % 才值得尝试用 nibble 模板去折叠最高位平面。
            tf = (mbits > 0) && (nbits > 1) && (nbits <= mbits);
        end

        function update = update_cost_of_msb_nibble(datas_buf, data_len, group_size, group, gcli, gtli, dq_type)
            import jxs.Constants;
            nibble = uint8(0);
            idx = group * group_size;
            bp = gcli - 1;
            if gcli - gtli - 2 >= 0 && gcli - gtli - 2 < 12
                threshold = bitshift(jxs.internal.msbpack.THRESHOLD_TABLE(gcli - gtli - 1), -(Constants.MAX_GCLI - gcli + 1));
            else
                threshold = uint16(0);
            end
            for i = 0:(group_size - 1)
                if idx + i + 1 > data_len, break; end
                if dq_type ~= 0 && gtli > 0
                    % 某些量化模式下，不是简单看原始 MSB，而是看样本是否超过当前阈值。
                    magnitude = bitand(datas_buf(idx + i + 1), bitcmp(Constants.SIGN_BIT_MASK, 'uint32'));
                    bit_val = jxs.Constants.iif(magnitude > uint32(threshold), 1, 0);
                else
                    bit_val = bitand(bitshift(datas_buf(idx + i + 1), -bp), uint32(1));
                end
                nibble = bitor(nibble, uint8(bitshift(bit_val, group_size - i - 1)));
            end
            if Constants.msbp_is_short_code(nibble), update = int32(-1);
            elseif Constants.msbp_is_rot0(nibble) || Constants.msbp_is_rot1(nibble), update = int32(1);
            else, update = int32(0);
            % 返回值表示“与普通逐 bit 编码相比，成本变化了多少 bit”：
            %   -1 更省
            %    0 持平
            %   +1 更贵
        end
        end

        function code = msbp_code(nibble)
            code = jxs.internal.msbpack.MSB_CODES(nibble + 1);
        end

        function result = msbp_decode(nibble, buf, buf_len, idx, bp)
            import jxs.Constants;
            result = jxs.internal.msbpack.msbp_decode_cd(nibble, buf, buf_len, idx, bp);
        end

        function result = msbp_decode_cd(nibble, buf, buf_len, idx, bp)
            import jxs.Constants;
            A = {[1 0 0 0], [1 1 0 0], [1 1 1 0], [1 0 1 0], [1 1 1 1]};
            nibble_val = double(nibble);
            n = int32(4);
            for i = 0:3
                if n == 4 && bitand(bitshift(nibble_val, -(3-i)), 1) == 0
                    n = int32(i);
                end
            end
            rot = int32(0); fsgn = int32(0); frot = int32(0);
            switch n
                case 0
                    % n=0 是最特殊的一类模板：除了 bit-plane 模式外，还带了额外 sign 信息。
                    rot = bitshift(bitand(bitshift(nibble_val, -2), 1), 1) + bitand(bitshift(nibble_val, -1), 1);
                    fsgn = rot;
                    if idx + rot + 1 <= buf_len
                        buf(idx + rot + 1) = bitor(buf(idx + rot + 1), bitshift(uint32(bitand(bitshift(nibble_val, 0), 1)), Constants.SIGN_BIT_POSITION));
                    end
                case 1
                    rot = bitshift(bitand(bitshift(nibble_val, -1), 1), 1) + bitand(bitshift(nibble_val, 0), 1);
                case 2
                    rot = bitshift(bitand(nibble_val, 1), 1);
                    frot = int32(1);
                case 3
                    rot = int32(0); frot = int32(1);
                otherwise
                    rot = int32(0);
            end
            for i = 0:3
                j = mod(i - rot, 4);
                if j < 0, j = j + 4; end
                if idx + i + 1 <= buf_len
                    % A{n+1} 给出模板 bit-plane 的 4 元模式，
                    % rot 则决定它在组内循环旋转多少位。
                    buf(idx + i + 1) = bitor(buf(idx + i + 1), bitshift(uint32(A{n + 1}(j + 1)), bp));
                end
            end
            result = bitshift(fsgn, 1) + frot;
        end

        function rotr_bitplane(buf, buf_len, group_size, bp)
            mask = bitshift(uint32(1), bp);
            last_val = uint32(0);
            if group_size <= buf_len, last_val = buf(group_size); end
            % 这里对单个 bit-plane 做环形右旋，
            % 用于匹配某些 msbpack 模板对应的旋转表示。
            for i = min(buf_len, group_size):-1:2
                if bitand(buf(i), mask) ~= bitand(buf(i - 1), mask)
                    buf(i) = bitxor(buf(i), mask);
                end
            end
            if group_size > 1 && bitand(buf(1), mask) ~= bitand(last_val, mask)
                buf(1) = bitxor(buf(1), mask);
            end
        end
    end
end
