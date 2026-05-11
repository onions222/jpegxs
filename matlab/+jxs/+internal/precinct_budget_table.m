% precinct_budget_table.m — precinct 预算表存储层。
%
% 对应 C 参考实现：libjxs/src/precinct_budget_table.c/h
%
% 这个类本身不做复杂决策，主要负责把
%   (method, position, gtli) -> 预算值
% 这种三维索引关系平铺保存起来。
% vector of length (MAX_GCLI+1) giving the bit cost at that GTLI.
% Four tables: significance flags, GCLI, data, and sign.

classdef precinct_budget_table < handle
    properties
        position_count
        method_count
        sigf_budget_table   % method_count*position_count cell of (MAX_GCLI+1) uint32 vectors
        gcli_budget_table   % same
        data_budget_table   % position_count cell of (MAX_GCLI+1) uint32 vectors
        sign_budget_table   % same
    end

    methods (Static)
        function v = align_to_bits(value, nbits)
            % ALIGN_TO_BITS  Round VALUE up to the next multiple of NBITS.
            %   Used to byte/nibble-align sub-packet sizes.
            % 这是经典的“向上对齐”位运算写法：
            %   1. 先加上 nbits-1
            %   2. 再把低位掩掉
            % 例如对齐到 8 bit 时，相当于向上取整到最近的 byte。
            v = bitor(int32(value + nbits - 1), int32(0));
            v = bitand(v, bitcmp(int32(nbits - 1), 'int32'));
        end
    end

    methods
        function obj = precinct_budget_table()
            obj.position_count = int32(0);
            obj.method_count = int32(0);
            obj.sigf_budget_table = {};
            obj.gcli_budget_table = {};
            obj.data_budget_table = {};
            obj.sign_budget_table = {};
        end

        function open(obj, position_count, method_count)
            % OPEN  Allocate all budget arrays for the given precinct geometry.
            %
            %   C reference: precinct_budget_table_open()  (precinct_budget_table.c:14)
            import jxs.Constants;
            obj.position_count = int32(position_count);
            obj.method_count = int32(method_count);
            gcli_entries = Constants.MAX_GCLI + 1;
            % 对 GCLI/SIGF 来说，预算不仅依赖 position，还依赖 method，
            % 所以表大小是 method_count * position_count。
            total_method_positions = obj.method_count * obj.position_count;
            obj.sigf_budget_table = cell(1, total_method_positions);
            obj.gcli_budget_table = cell(1, total_method_positions);
            for i = 1:total_method_positions
                % 每个 cell 内部再放一个长度为 MAX_GCLI+1 的向量，
                % 下标 gtli+1 处记录“该 GTLI 下的 bit 成本”。
                obj.sigf_budget_table{i} = zeros(1, gcli_entries, 'uint32');
                obj.gcli_budget_table{i} = zeros(1, gcli_entries, 'uint32');
            end
            obj.data_budget_table = cell(1, obj.position_count);
            obj.sign_budget_table = cell(1, obj.position_count);
            for i = 1:obj.position_count
                obj.data_budget_table{i} = zeros(1, gcli_entries, 'uint32');
                obj.sign_budget_table{i} = zeros(1, gcli_entries, 'uint32');
            end
        end

        function buf = sigf_bgt_of(obj, gcli_method, position)
            % 二维索引 (method, position) 被摊平成一维：
            % idx = method * position_count + position
            % 这里 method/position 都按 C 端习惯从 0 开始，因此最后再 +1 适配 MATLAB。
            idx = int32(gcli_method) * obj.position_count + int32(position) + 1;
            if idx < 1 || idx > length(obj.sigf_budget_table)
                buf = []; return;
            end
            buf = obj.sigf_budget_table{idx};
        end

        function buf = gcli_bgt_of(obj, gcli_method, position)
            idx = int32(gcli_method) * obj.position_count + int32(position) + 1;
            if idx < 1 || idx > length(obj.gcli_budget_table)
                buf = []; return;
            end
            buf = obj.gcli_budget_table{idx};
        end

        function buf = data_bgt_of(obj, position)
            % DATA/SIGN 不区分 GCLI method，所以只需要按 position 索引。
            idx = int32(position) + 1;
            if idx < 1 || idx > length(obj.data_budget_table)
                buf = []; return;
            end
            buf = obj.data_budget_table{idx};
        end

        function buf = sign_bgt_of(obj, position)
            idx = int32(position) + 1;
            if idx < 1 || idx > length(obj.sign_budget_table)
                buf = []; return;
            end
            buf = obj.sign_budget_table{idx};
        end

        function set_sigf_bgt_of(obj, gcli_method, position, buf)
            idx = int32(gcli_method) * obj.position_count + int32(position) + 1;
            obj.sigf_budget_table{idx} = buf;
        end

        function set_gcli_bgt_of(obj, gcli_method, position, buf)
            idx = int32(gcli_method) * obj.position_count + int32(position) + 1;
            obj.gcli_budget_table{idx} = buf;
        end

        function set_data_bgt_of(obj, position, buf)
            idx = int32(position) + 1;
            obj.data_budget_table{idx} = buf;
        end

        function set_sign_bgt_of(obj, position, buf)
            idx = int32(position) + 1;
            obj.sign_budget_table{idx} = buf;
        end
    end
end
