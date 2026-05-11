% sig_flags.m — significance flags 的生成与编码。
%
% 对应 C 参考实现：libjxs/src/sig_flags.c
% 标准位置：ISO/IEC 21122-1 Annex F.3.4
%
% 当某些 GCLI group 为零时，可以通过 significance flag
% 跳过一大段无效 residual，从而减少码流长度。
% (containing at least one non-zero) or "insignificant" (all zero).
% The flag vector is written to the bitstream; insignificant groups
% are then skipped during GCLI entropy coding, reducing bit cost.

classdef sig_flags < handle
    properties
        max_w               % Maximum supported buffer width
        min_group_width     % Minimum significance group width (S_s parameter)
        w                   % Current buffer width
        group_width         % Current group width (same as min_group_width)
        lvls        % int8 vector — per-group significance (0=insignificant, 1=significant)
        lvls_size           % Number of groups
        lvls_max_size       % Allocated size of lvls
        lvls_ptr            % Current read pointer (for decoder)
        lvls_zero_count     % Number of insignificant groups
        lvls_one_count      % Number of significant groups
        last_group_width    % Width of the last (possibly partial) group
    end

    methods (Static)
        function sz = nextlvl_size(w, g)
            % NEXTLVL_SIZE  Number of groups: ceil(w / g).
            % 一个 significance flag 覆盖 g 个 GCLI 项，
            % 所以 flag 总数就是把宽度按组宽做上取整。
            sz = idivide(int32(w) + int32(g) - 1, int32(g), 'floor');
        end

        function sz = last_group_size(w, g)
            % LAST_GROUP_SIZE  Width of the trailing group (may be < g).
            r = mod(int32(w), int32(g));
            if r ~= 0, sz = r; else, sz = int32(g); end
        end
    end

    methods
        function obj = sig_flags(max_w, min_group_width)
            % SIG_FLAGS  Construct significance flag buffer.
            %
            %   C reference: sigflags_alloc()  (sig_flags.c:14)
            obj.max_w = max_w;
            obj.min_group_width = min_group_width;
            obj.group_width = min_group_width;
            obj.lvls_size = 0;
            obj.lvls_ptr = 0;
            obj.lvls_max_size = jxs.internal.sig_flags.nextlvl_size(max_w, obj.group_width);
            obj.lvls = zeros(obj.lvls_max_size, 1, 'int8');
            obj.lvls_one_count = 0;
            obj.lvls_zero_count = 0;
        end

        function init(obj, input_buf, buf_len, group_width)
            % INIT  Compute significance flags from a residual vector (encoder).
            %   A group is significant if any element in that group is non-zero.
            %
            %   C reference: sigflags_init()  (sig_flags.c:30)
            assert(buf_len <= obj.max_w);
            assert(group_width >= obj.min_group_width);
            obj.w = buf_len;
            obj.lvls_zero_count = 0;
            obj.lvls_one_count = 0;
            % lvls_size 是 group 个数，不是元素个数。
            obj.lvls_size = jxs.internal.sig_flags.nextlvl_size(buf_len, obj.group_width);
            if obj.lvls_size > obj.lvls_max_size
                obj.lvls_max_size = obj.lvls_size;
                obj.lvls = zeros(obj.lvls_max_size, 1, 'int8');
            end
            obj.last_group_width = jxs.internal.sig_flags.last_group_size(buf_len, obj.group_width);
            obj.lvls(:) = 0;
            for i = 1:buf_len
                if input_buf(i) ~= 0
                    % 只要组内任意一个 residual 非零，这一整组就被标为 significant。
                    g = idivide(int32(i) - 1, int32(obj.group_width), 'floor') + 1;  % 1-based group index
                    obj.lvls(g) = int8(1);
                end
            end
            for i = 1:obj.lvls_size
                if obj.lvls(i) == 0
                    obj.lvls_zero_count = obj.lvls_zero_count + 1;
                else
                    obj.lvls_one_count = obj.lvls_one_count + 1;
                end
            end
        end

        function inclusion = inclusion_mask(obj)
            % INCLUSION_MASK  Expand group-level flags to per-element mask.
            %   Returns a uint8 vector of length W where each element is 1
            %   if its group is significant, 0 otherwise.
            inclusion = zeros(obj.w, 1, 'uint8');
            for i = 1:obj.w
                % 把 group 级别的 0/1 展开回逐元素 mask，
                % 方便后续直接按元素过滤 residual / predictor 向量。
                g = idivide(int32(i) - 1, int32(obj.group_width), 'floor') + 1;
                inclusion(i) = uint8(obj.lvls(g));
            end
        end

        function [buf_out, out_len] = filter_values(obj, buf_in)
            % FILTER_VALUES  Extract only values belonging to significant groups.
            %   [FILTERED, LEN] = filter_values(BUF_IN) compacts BUF_IN
            %   by discarding elements in insignificant groups.
            %
            %   C reference: sigflags_filter()  (sig_flags.c:62)
            buf_out = zeros(obj.w, 1, 'int8');
            out_len = int32(0);
            for i = 1:obj.w
                g = idivide(int32(i) - 1, int32(obj.group_width), 'floor') + 1;
                if obj.lvls(g) ~= 0
                    % 只有 significant group 的元素才会被压缩拷贝到输出前缀中；
                    % out_len 返回的就是这个“有效前缀”的长度。
                    buf_out(out_len + 1) = buf_in(i);
                    out_len = out_len + 1;
                end
            end
        end

        function bgt = budget(obj)
            % BUDGET  Bit cost of the significance flag vector (1 bit per group).
            % 当前实现里 flags 本身没有额外熵编码，
            % 所以成本就是“组数 = flag 位数”。
            bgt = obj.lvls_size;
        end

        function nbits = write(obj, bitstream)
            % WRITE  Encode significance flags to bitstream.
            %   Convention: significant=0, insignificant=1 (inverted).
            %
            %   C reference: sigflags_write()  (sig_flags.c:78)
            nbits = int32(0);
            for i = 1:obj.lvls_size
                % JPEG XS 这里的语义有一点反直觉：
                %   significant   -> 写 0
                %   insignificant -> 写 1
                % 所以这里先按位取反，再只保留最低 1 bit。
                val = bitcmp(uint64(obj.lvls(i)), 'uint64');
                nbits = nbits + bitstream.write(bitand(val, uint64(1)), 1);
            end
        end

        function nbits = read_flags(obj, bitstream, buf_len, group_width)
            % READ_FLAGS  Decode significance flags from bitstream (decoder).
            %   Convention: reads inverted flags (0=significant).
            %
            %   C reference: sigflags_read()  (sig_flags.c:92)
            nbits = int32(0);
            assert(group_width >= obj.min_group_width);
            if buf_len > obj.max_w
                obj.max_w = buf_len;
                obj.lvls_max_size = jxs.internal.sig_flags.nextlvl_size(buf_len, obj.group_width);
                obj.lvls = zeros(obj.lvls_max_size, 1, 'int8');
            end
            obj.w = buf_len;
            obj.lvls_zero_count = 0;
            obj.lvls_one_count = 0;
            obj.lvls_size = jxs.internal.sig_flags.nextlvl_size(buf_len, obj.group_width);
            obj.last_group_width = jxs.internal.sig_flags.last_group_size(buf_len, obj.group_width);
            for i = 1:obj.lvls_size
                [val, nb] = bitstream.read(1);
                nbits = nbits + nb;
                % 读回来后同样要再反一次，恢复成内部统一的
                % 0=insignificant, 1=significant 表示。
                val = bitcmp(val, 'uint64');
                obj.lvls(i) = int8(bitand(val, uint64(1)));
            end
        end
    end
end
