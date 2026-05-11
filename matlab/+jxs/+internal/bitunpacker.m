% bitunpacker.m — MSB-first 位流读取器。
%
% 对应 C 参考实现：libjxs/src/bitpacking.c (bit_unpacker_t)
%
% 它和 bitpacker 正好相反，负责：
%   - 按位读取 JPEG XS 码流中的字段
%   - 支持 peek / skip / align
%   - 读取 unary / bounded code 等熵编码值
% (signed, unsigned, bounded), alignment, and rewind.

classdef bitunpacker < handle
    properties
        buffer      % uint8 array — the raw byte buffer (big-endian uint64 words)
        ptr_cur     % current word index (1-based into uint64 words)
        cur         % current uint64 word (host byte order)
        bit_offset  % bits consumed from current word [0..63]
        max_size    % total bytes in buffer
        consumed    % uint64 — bits consumed from completed words
    end

    properties (Constant, Access = private)
        MAXB = 64
    end

    methods (Static)
        function w = betoh64(in_val)
            w = swapbytes(uint64(in_val));
        end

        function w = read_word_be(buf_bytes, word_idx)
            start_b = (word_idx - 1) * 8 + 1;
            word_bytes = buf_bytes(start_b:start_b + 7);
            w = swapbytes(typecast(word_bytes, 'uint64'));
        end
    end

    methods
        function obj = bitunpacker()
            obj.buffer = [];
            obj.ptr_cur = 0;
            obj.cur = uint64(0);
            obj.bit_offset = 0;
            obj.max_size = 0;
            obj.consumed = uint64(0);
        end

        function set_buffer(obj, ptr_bytes, max_size)
            % ptr_bytes is uint8 array. Pad to multiple of 8 bytes for uint64 word access.
            % 解码侧也按 64bit word 读，因此不足 8 byte 的尾部需要补零，
            % 否则 typecast 成 uint64 时无法稳定访问。
            padded_len = idivide(int64(max_size) + 7, int64(8), 'floor') * 8;
            obj.buffer = zeros(1, double(padded_len), 'uint8');
            obj.buffer(1:min(length(ptr_bytes), double(padded_len))) = ptr_bytes(1:min(length(ptr_bytes), double(padded_len)));
            obj.max_size = max_size;
            obj.reset();
        end

        function reset(obj)
            obj.ptr_cur = 1;
            if ~isempty(obj.buffer) && length(obj.buffer) >= 8
                obj.cur = jxs.internal.bitunpacker.read_word_be(obj.buffer, 1);
            else
                obj.cur = uint64(0);
            end
            obj.bit_offset = 0;
            obj.consumed = uint64(0);
        end

        function [val, n] = read(obj, nbits)
            % Read nbits MSB-first. Returns val and number of bits read.
            MAXB = obj.MAXB;
            available0 = MAXB - obj.bit_offset;
            if available0 >= nbits
                len0 = nbits;
                len1 = 0;
            else
                len0 = available0;
                len1 = nbits - len0;
            end

            val = uint64(0);

            if len0 > 0
                % 先从当前 word 的剩余高位区域取出 len0 bit。
                val = bitor(val, bitshift(bitshift(obj.cur, -(available0 - len0)), len1));
                obj.bit_offset = obj.bit_offset + len0;
            end

            if len1 > 0
                % 当前 word 不够时，切到下一个 word 继续读剩余 len1 bit。
                obj.consumed = obj.consumed + uint64(MAXB);
                obj.ptr_cur = obj.ptr_cur + 1;
                if (obj.ptr_cur) * 8 > obj.max_size
                    % 最后一个不满 8 byte 的尾 word，需要手工拼一个临时 8-byte 缓冲。
                    remaining_bytes = mod(obj.max_size, 8);
                    buffer_bytes = zeros(1, 8, 'uint8');
                    start_b = (obj.ptr_cur - 1) * 8 + 1;
                    for i = 1:min(remaining_bytes, length(obj.buffer) - start_b + 1)
                        if start_b + i - 1 <= length(obj.buffer)
                            buffer_bytes(i) = obj.buffer(start_b + i - 1);
                        end
                    end
                    obj.cur = swapbytes(typecast(buffer_bytes, 'uint64'));
                else
                    obj.cur = jxs.internal.bitunpacker.read_word_be(obj.buffer, obj.ptr_cur);
                end
                obj.bit_offset = 0;
                val = bitor(val, bitshift(obj.cur, -(MAXB - len1)));
                obj.bit_offset = obj.bit_offset + len1;
            end

            if nbits < 64
                % read() 返回的有效值永远落在低 nbits 位。
                val = bitand(val, bitshift(uint64(1), nbits) - uint64(1));
            end

            n = nbits;
        end

        function [val, n] = read_val(obj, nbits)
            % Convenience wrapper — delegates to read
            [val, n] = obj.read(nbits);
        end

        function [val, n] = peek(obj, nbits)
            % peek 的做法是“读一遍再把状态完整回滚”，
            % 这样不用额外维护一套并行读取逻辑。
            saved_cur = obj.cur;
            saved_offset = obj.bit_offset;
            saved_consumed = obj.consumed;
            saved_ptr = obj.ptr_cur;

            [val, n] = obj.read(nbits);

            obj.cur = saved_cur;
            obj.bit_offset = saved_offset;
            obj.consumed = saved_consumed;
            obj.ptr_cur = saved_ptr;
        end

        function [val, n] = read_unary_signed(obj, alphabet)
            % bitunpacker_read_unary_signed — mirrors C exactly, returns [val, nbits]
            import jxs.Constants;
            nbits_start = obj.consumed_bits();

            switch alphabet
                case Constants.UNARY_ALPHABET_FULL
                    % 先数前导 1 的长度，再按 full alphabet 的映射还原符号和值。
                    bit = uint64(1);
                    val = int8(-1);
                    while bit ~= 0 && val < 17
                        [bit, ~] = obj.read_val(1);
                        val = val + 1;
                    end
                    if val == 1
                        val = int8(-1);
                    elseif val == 2
                        val = int8(1);
                    elseif val == 3
                        val = int8(-2);
                    elseif val == 4
                        val = int8(2);
                    elseif val > 4
                        val = val - 2;
                        [bit, ~] = obj.read_val(1);
                        if bit ~= 0
                            val = -val;
                        end
                    end

                case Constants.UNARY_ALPHABET_4_CLIPPED
                    % 4-clipped 和 full 的区别主要在“较大绝对值”区域被截断到更短范围。
                    bit = uint64(1);
                    val = int8(-1);
                    while bit ~= 0 && val < 15
                        [bit, ~] = obj.read_val(1);
                        val = val + 1;
                    end
                    if val == 1
                        val = int8(-1);
                    elseif val == 2
                        val = int8(1);
                    elseif val == 3
                        val = int8(-2);
                    elseif val == 4
                        val = int8(2);
                    end
                    if val > 4
                        val = val - 2;
                        if val ~= 0 && val ~= Constants.MAX_UNARY - 2
                            [bit, ~] = obj.read_val(1);
                        end
                        if bit ~= 0
                            val = -val;
                        end
                    end

                case Constants.UNARY_ALPHABET_0
                    % alphabet_0 的符号位总是在长度段之后额外再读 1 bit
                    % （除了 0 和最大截断值这两种边界情况）。
                    bit = uint64(1);
                    val = int8(-1);
                    while bit ~= 0 && val < Constants.MAX_UNARY
                        [bit, ~] = obj.read_val(1);
                        val = val + 1;
                    end
                    if val ~= 0 && val ~= Constants.MAX_UNARY
                        [bit, ~] = obj.read_val(1);
                    end
                    if bit ~= 0
                        val = -val;
                    end

                otherwise
                    error('invalid alphabet specified');
            end

            n = int32(obj.consumed_bits() - nbits_start);
        end

        function [val, n] = read_unary_signed_val(obj, alphabet)
            [val, n] = obj.read_unary_signed(alphabet);
        end

        function [val, n] = read_unary_unsigned(obj)
            bit = uint64(1);
            val = int8(-1);
            % 连续读到第一个 0 为止，前面 1 的个数就是数值本身。
            while bit ~= 0
                [bit, ~] = obj.read_val(1);
                val = val + 1;
            end
            n = double(val) + 1;
        end

        function [val, n] = read_unary_unsigned_val(obj)
            [val, n] = obj.read_unary_unsigned();
        end

        function [val, n] = read_bounded_code(obj, min_allowed, max_allowed)
            % bitunpacker_read_bounded_code — returns [val, ~nbits]
            trigger = abs(int32(min_allowed));

            [tmp, n] = obj.read_unary_unsigned();
            tmp = int32(tmp);

            if tmp > 2 * trigger
                % 超过两侧交替区间后，编号直接映射到正方向尾部。
                val = tmp - trigger;
            else
                % 前半段按 0, -1, +1, -2, +2 ... 逆映射回来。
                val = idivide(tmp + 1, 2, 'floor');
                if mod(int32(tmp), 2) ~= 0
                    val = -val;
                end
            end
            val = int8(val);
        end

        function [val, n] = read_bounded_code_val(obj, min_allowed, max_allowed)
            [val, n] = obj.read_bounded_code(min_allowed, max_allowed);
        end

        function n = align(obj, nbits)
            if mod(obj.bit_offset, nbits) ~= 0
                % 对齐本质上就是把当前位置跳到下一个 nbits 边界。
                [~, n] = obj.read_val(nbits - mod(obj.bit_offset, nbits));
            else
                n = 0;
            end
        end

        function c = consumed_bytes(obj)
            c = double(idivide(obj.consumed + uint64(obj.bit_offset) + uint64(7), uint64(8), 'floor'));
        end

        function tf = consumed_all(obj)
            tf = (obj.consumed_bytes() == obj.max_size);
        end

        function b = consumed_bits(obj)
            b = double(obj.consumed + uint64(obj.bit_offset));
        end

        function n = skip(obj, nbits)
            for i = 1:64:nbits
                burst = min(64, nbits - i + 1);
                [~, ~] = obj.read_val(burst);
            end
            n = nbits;
        end

        function n = rewind(obj, nbits)
            MAXB = obj.MAXB;
            if obj.bit_offset >= nbits
                len0 = nbits;
                len1 = 0;
            else
                len0 = obj.bit_offset;
                len1 = nbits - len0;
            end

            if len0 > 0
                obj.bit_offset = obj.bit_offset - len0;
            end

            for i = 1:MAXB:len1
                burst = min(MAXB, len1 - i + 1);
                % 回退跨 word 时，需要把“已经完成消费”的 word 计数撤销，
                % 再重新装回上一个 word。
                obj.consumed = obj.consumed - uint64(MAXB);
                obj.ptr_cur = obj.ptr_cur - 1;
                obj.cur = jxs.internal.bitunpacker.read_word_be(obj.buffer, obj.ptr_cur);
                obj.bit_offset = MAXB;
                obj.bit_offset = obj.bit_offset - burst;
            end
            n = 0;
        end

        function delete(~)
        end
    end
end
