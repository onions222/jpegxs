% bitpacker.m — MSB-first 位流写入器。
%
% 对应 C 参考实现：libjxs/src/bitpacking.c (bit_packer_t)
%
% JPEG XS 码流不是按字节整齐写的，而是大量按 bit 字段拼出来的。
% 这个类负责：
%   - 把不同长度的字段按 MSB-first 顺序写进缓存
%   - 处理对齐、padding、unary code 等底层细节
%   - 最终导出 uint8 码流
% data (markers, headers, entropy codes, data planes) is written
% through this class.
%
% Also provides static methods for bounded-code range computation
% and unary lookup tables.

classdef bitpacker < handle
    properties
        buffer      % uint8 array — the raw byte buffer (big-endian uint64 words)
        ptr_cur     % current word index (1-based into uint64 words)
        ptr_max     % max word index
        cur_word    % current uint64 word being assembled (host byte order)
        bit_offset  % bits used in current word [0..63]
        flushed     % logical
    end

    properties (Constant, Access = private)
        MAXB = 64
    end

    properties (Constant)
        UNARY_LUP = jxs.internal.bitpacker.build_unary_lup()
        UNARY_LUP_VER4CLIP = jxs.internal.bitpacker.build_unary_lup_ver4clip()
        UNARY_LUP_FULL = jxs.internal.bitpacker.build_unary_lup_full()
    end

    methods (Static)
        function out = htobe64(in_val)
            % 主机字节序与码流字节序可能不同，
            % 这里统一把 MATLAB 内部 uint64 转成 big-endian 表示。
            out = swapbytes(uint64(in_val));
        end

        function out = betoh64(in_val)
            out = swapbytes(uint64(in_val));
        end

        function w = read_word_be(buf_bytes, word_idx)
            % Read 8 bytes starting at (word_idx-1)*8+1 as big-endian uint64
            start_b = (word_idx - 1) * 8 + 1;
            word_bytes = buf_bytes(start_b:start_b + 7);
            w = swapbytes(typecast(word_bytes, 'uint64'));
        end

        function buf_bytes = write_word_be(buf_bytes, word_idx, val)
            % Write uint64 val as big-endian 8 bytes
            start_b = (word_idx - 1) * 8 + 1;
            word_bytes = typecast(swapbytes(uint64(val)), 'uint8');
            buf_bytes(start_b:start_b + 7) = word_bytes;
        end

        function lup = build_unary_lup()
            vals = int32([65535 65533 32765 16381 8189 4093 2045 1021 509 253 125 61 29 13 5 0 4 12 28 60 124 252 508 1020 2044 4092 8188 16380 32764 65532 65534]);
            nbits = int32([16 16 15 14 13 12 11 10 9 8 7 6 5 4 3 1 3 4 5 6 7 8 9 10 11 12 13 14 15 16 16]);
            lup = struct('val', num2cell(vals), 'nbits', num2cell(nbits));
        end

        function lup = build_unary_lup_ver4clip()
            vals = int32([65535 65535 65535 65533 32765 16381 8189 4093 2045 1021 509 253 125 14 2 0 6 30 124 252 508 1020 2044 4092 8188 16380 32764 65532 65534 65534 65534]);
            nbits = int32([16 16 16 16 15 14 13 12 11 10 9 8 7 4 2 1 3 5 7 8 9 10 11 12 13 14 15 16 16 16 16]);
            lup = struct('val', num2cell(vals), 'nbits', num2cell(nbits));
        end

        function lup = build_unary_lup_full()
            vals = int32([524285 262141 131069 65533 32765 16381 8189 4093 2045 1021 509 253 125 14 2 0 6 30 124 252 508 1020 2044 4092 8188 16380 32764 65532 131068 262140 524285]);
            nbits = int32([19 18 17 16 15 14 13 12 11 10 9 8 7 4 2 1 3 5 7 8 9 10 11 12 13 14 15 16 17 18 19]);
            lup = struct('val', num2cell(vals), 'nbits', num2cell(nbits));
        end
    end

    methods
        function obj = bitpacker()
            obj.buffer = [];
            obj.ptr_cur = 0;
            obj.ptr_max = 0;
            obj.cur_word = uint64(0);
            obj.bit_offset = 0;
            obj.flushed = false;
        end

        function set_buffer(obj, ptr_bytes, max_size)
            % ptr_bytes is uint8 array. Buffer stores big-endian uint64 words.
            nwords = floor(max_size / 8);
            nbytes = nwords * 8;
            % 以 64bit word 为基本写出单元，因此底层 buffer 也按 8 byte 对齐。
            if length(ptr_bytes) < nbytes
                obj.buffer = zeros(1, nbytes, 'uint8');
                obj.buffer(1:length(ptr_bytes)) = ptr_bytes(:)';
            else
                obj.buffer = ptr_bytes(1:nbytes);
            end
            obj.ptr_max = nwords;
            obj.reset();
        end

        function reset(obj)
            % 当前 word 从空开始，后续字段会按 MSB-first 逐步 OR 进去。
            obj.buffer(:) = 0;
            obj.ptr_cur = 1;
            obj.cur_word = uint64(0);
            obj.bit_offset = 0;
            obj.flushed = false;
        end

        function n = write(obj, val, nbits)
            % WRITE  Append NBITS from VAL (MSB-first) to the bitstream.
            %   Returns the number of bits written (always == NBITS).
            %
            %   C reference: bitpacker_write()  (bitpacking.c:65)
            MAXB = obj.MAXB;
            available0 = MAXB - obj.bit_offset;
            if available0 >= nbits
                len0 = nbits;
                len1 = 0;
            else
                len0 = available0;
                len1 = nbits - len0;
            end

            val = uint64(val);
            if nbits < 64
                % 只保留本次需要写入的低 nbits 位。
                val = bitand(val, bitshift(uint64(intmax('uint64')), -(64 - nbits)));
            end

            if len0 > 0
                % 先把字段能放进当前 word 的那一段写进去。
                % 因为是 MSB-first，所以目标位置总是剩余空位的高位端。
                shift_amt = available0 - len0;
                shifted = bitshift(val, -len1);
                obj.cur_word = bitor(obj.cur_word, bitshift(shifted, shift_amt));
                obj.bit_offset = obj.bit_offset + len0;
            end

            if len1 > 0
                % Flush current word to buffer in big-endian
                if obj.ptr_cur <= obj.ptr_max
                    obj.buffer = jxs.internal.bitpacker.write_word_be(obj.buffer, obj.ptr_cur, obj.cur_word);
                    obj.ptr_cur = obj.ptr_cur + 1;
                    obj.bit_offset = 0;
                    % 跨 word 的剩余位重新放到下一个 word 的最高位区域。
                    obj.cur_word = bitshift(val, MAXB - len1);
                    obj.bit_offset = len1;
                else
                    error('bitpacker reached end of buffer!');
                end
            end
            n = nbits;
        end

        function n = write_unary_signed(obj, val, alphabet)
            import jxs.Constants;
            c = jxs.internal.bitpacker;
            % 负值/正值统一平移到非负区间后查 LUT，减少运行时分支。
            idx = int32(val) + int32(Constants.MAX_UNARY) + 1;
            switch alphabet
                case Constants.UNARY_ALPHABET_FULL
                    n = obj.write(c.UNARY_LUP_FULL(idx).val, c.UNARY_LUP_FULL(idx).nbits);
                case Constants.UNARY_ALPHABET_4_CLIPPED
                    assert(abs(val) <= Constants.MAX_UNARY_CLIPPED);
                    n = obj.write(c.UNARY_LUP_VER4CLIP(idx).val, c.UNARY_LUP_VER4CLIP(idx).nbits);
                case Constants.UNARY_ALPHABET_0
                    n = obj.write(c.UNARY_LUP(idx).val, c.UNARY_LUP(idx).nbits);
                otherwise
                    error('unsupported alphabet specified');
            end
        end

        function n = write_unary_unsigned(obj, val)
            val_u = uint64(val);
            % unsigned unary: V -> V 个前导 1，再跟一个结束 0。
            code = bitshift(uint64(1), val_u + 1) - uint64(2);
            n = obj.write(code, double(val_u) + 1);
        end

        function n = align(obj, nbits)
            % ALIGN  Pad with zero bits until bit_offset is a multiple of NBITS.
            %
            %   C reference: bitpacker_align()  (bitpacking.c:110)
            if mod(obj.bit_offset, nbits) ~= 0
                n = obj.write(uint64(0), nbits - mod(obj.bit_offset, nbits));
            else
                n = 0;
            end
        end

        function len = get_len(obj)
            len = int32(obj.ptr_cur - 1) * 64 + obj.bit_offset;
        end

        function n = add_padding(obj, nbits)
            % padding 统一补 0；分块写只是为了不超过单次 64bit 写入窗口。
            for i = 1:64:nbits
                burst = min(64, nbits - i + 1);
                r = obj.write(uint64(0), burst);
                if r < 0, n = -1; return; end
            end
            n = nbits;
        end

        function flush(obj)
            if ~obj.flushed && obj.bit_offset > 0
                % 只需把最后一个未满的 word 刷回 buffer。
                obj.buffer = jxs.internal.bitpacker.write_word_be(obj.buffer, obj.ptr_cur, obj.cur_word);
            end
            obj.flushed = true;
        end

        function buf = get_bytes(obj)
            % GET_BYTES  Flush and return the codestream as a uint8 vector.
            %   Length = ceil(total_bits / 8), matching C's calculation.
            %
            %   C reference: bitpacker_get_bytes()  (bitpacking.c:140)
            % Compute total bytes from total bits, matching C:
            %   codestream_byte_size = (get_len + 7) / 8
            obj.flush();
            total_bits = (obj.ptr_cur - 1) * 64 + obj.bit_offset;
            total_bytes = idivide(int64(total_bits) + 7, int64(8), 'floor');
            total_bytes = double(total_bytes);
            if total_bytes > 0 && ~isempty(obj.buffer)
                if total_bytes <= length(obj.buffer)
                    buf = obj.buffer(1:total_bytes);
                else
                    buf = obj.buffer;
                end
            else
                buf = zeros(1, 0, 'uint8');
            end
        end

        function delete(obj)
            obj.flush();
        end
    end

    methods (Static)
        function [min_allowed, max_allowed] = bounded_code_get_min_max(predictor, gtli)
            % BOUNDED_CODE_GET_MIN_MAX  Compute valid range for bounded coding.
            %   min_allowed = -max(predictor - gtli, 0)
            %   max_allowed = max(MAX_GCLI - max(predictor, gtli), 0)
            %
            %   C reference: bounded_code_get_min_max()  (bitpacking.c:180)
            import jxs.Constants;
            p = int32(predictor); g = int32(gtli);
            % predictor 越高，允许的负 residual 区间越宽；
            % predictor/gtli 越接近 MAX_GCLI，允许的正 residual 区间越窄。
            min_allowed = -jxs.Constants.MAX(p - g, int32(0));
            max_allowed = jxs.Constants.MAX(Constants.MAX_GCLI - jxs.Constants.MAX(p, g), int32(0));
        end

        function code = bounded_code_get_unary_code(val, min_allowed, max_allowed)
            % BOUNDED_CODE_GET_UNARY_CODE  Map residual to bounded unary code.
            %   Values near zero get short codes; the mapping folds
            %   negative values into odd indices.
            %
            %   C reference: bounded_code_get_unary_code()  (bitpacking.c:192)
            assert(min_allowed <= 0);
            aval = abs(int32(val));
            trigger = abs(int32(min_allowed));
            if aval <= trigger
                % 靠近 0 的 residual 采用交替折叠顺序：
                % 0, -1, +1, -2, +2, ...
                if val < 0
                    code = 2 * aval - 1;
                else
                    code = 2 * aval;
                end
            else
                % 超过 trigger 后切换到单调递增编号。
                code = trigger + aval;
            end
        end
    end
end
