% precinct.m — precinct 数据容器与访问接口。
%
% 对应 C 参考实现：libjxs/src/precinct.c / precinct.h
% 标准位置：ISO/IEC 21122-1 Annex B.3
%
% precinct 是 JPEG XS 编码/解码时最核心的工作单元：
%   “一列 band 数据” × “一个 precinct 高度”
%
% 这个类负责保存：
%   - sign-magnitude 系数
%   - 每组系数的 GCLI
%   - band / ypos / packet 与缓冲区之间的映射关系
%
% 也就是说，编码器/解码器几乎所有真正处理的数据，
% 最后都会先落到 precinct 对象里再继续往下走。

classdef precinct < handle
    properties
        sig_mag_data  % cell array of uint32 vectors (replaces sig_mag_data_mb)
        gclis_data    % cell array of int8 vectors (replaces gclis_mb)
        ids           % reference to ids_t
        group_size int32
        idx_from_level  % [MAX_PRECINCT_HEIGHT x MAX_PACKETS] mapping
        y_idx int32
        column int32
        is_last_column int32
    end

    methods (Static)
        function g = gcli(x)
            % GCLI  Greatest Coded Level Index of a sign-magnitude value.
            %   GCLI(x) = floor(log2(|x|)) + 1, or 0 if x == 0.
            %
            %   C reference: precinct_gcli()  (precinct.h macro)
            if x == 0
                g = int32(0);
            else
                % Use bit length: position of highest set bit + 1
                g = int32(floor(log2(double(x)))) + 1;
            end
        end

        function [reclen, out_buf] = compute_gcli_buf(in_data, len, out_buf, max_out_len, group_size)
            % COMPUTE_GCLI_BUF  Compute GCLIs for groups of samples.
            %   For each group of GROUP_SIZE samples, OR all magnitudes
            %   together and compute GCLI of the result.
            %
            %   C reference: compute_gcli_buf()  (precinct.c:36)
            % GCLI 是“按组”算的，所以输出长度 = ceil(len / group_size)。
            out_len = int32(idivide(int32(len) + group_size - 1, group_size, 'floor'));
            assert(out_len <= max_out_len);
            idx = int32(1);
            n_full = idivide(int32(len), group_size, 'floor');
            for i = 1:n_full
                % 先把一整组样本的幅度按位 OR 起来，
                % 再对 OR 结果取最高有效位位置，就等于这组的 GCLI。
                or_all = uint32(0);
                for j = 1:group_size
                    or_all = bitor(or_all, in_data(idx));
                    idx = idx + 1;
                end
                out_buf(i) = int8(jxs.internal.precinct.gcli(bitand(or_all, bitcmp(jxs.Constants.SIGN_BIT_MASK, 'uint32'))));
            end
            rem = mod(int32(len), group_size);
            if rem > 0
                or_all = uint32(0);
                for j = 1:rem
                    or_all = bitor(or_all, in_data(idx));
                    idx = idx + 1;
                end
                out_buf(out_len) = int8(jxs.internal.precinct.gcli(bitand(or_all, bitcmp(jxs.Constants.SIGN_BIT_MASK, 'uint32'))));
            end
            reclen = out_len;
        end
    end

    methods
        function obj = precinct()
            obj.sig_mag_data = {};
            obj.gclis_data = {};
            obj.group_size = int32(4);
            obj.idx_from_level = zeros(4, 79, 'int32');  % MAX_PRECINCT_HEIGHT=4, MAX_PACKETS=79
            obj.y_idx = int32(-1);
            obj.column = int32(0);
            obj.is_last_column = int32(0);
        end

        function open_column(obj, ids_ref, group_size, column)
            import jxs.Constants;
            obj.ids = ids_ref;
            obj.group_size = int32(group_size);
            obj.column = int32(column);
            obj.is_last_column = int32(column == ids_ref.npx - 1);
            obj.y_idx = int32(-1);
            obj.sig_mag_data = cell(1, ids_ref.npi);
            obj.gclis_data = cell(1, ids_ref.npi);
            obj.idx_from_level = zeros(4, Constants.MAX_PACKETS, 'int32');
            for idx = 1:ids_ref.npi
                band = ids_ref.pi(idx).b + 1;
                % pi(idx).y 是 packet inclusion 顺序里的 band 内行号；
                % l0(band) 是该 band 在 precinct 内的首有效行。
                % 两者相减后，才得到本地存储缓冲区里的 0-based ypos。
                y = ids_ref.pi(idx).y - ids_ref.l0(band);
                obj.idx_from_level(y + 1, band) = int32(idx);
                col_idx = int32(obj.is_last_column) + 1;
                % N_cg = 这一行在当前列里会被切成多少个 GCLI group。
                N_cg = int32(idivide(ids_ref.pwb(col_idx, band) + int32(group_size) - 1, int32(group_size), 'floor'));
                nb_coefficients = N_cg * int32(group_size);
                obj.sig_mag_data{idx} = zeros(nb_coefficients, 1, 'uint32');
                obj.gclis_data{idx} = zeros(N_cg, 1, 'int8');
            end
        end

        function close(obj)
            obj.sig_mag_data = {};
            obj.gclis_data = {};
        end

        function [ptr, x_inc, line_len] = ptr_for_line_of_band(obj, image, band_idx, in_band_ypos)
            % PTR_FOR_LINE_OF_BAND  Compute pointer into component array.
            %   [PTR, X_INC, LINE_LEN] = ptr_for_line_of_band(IMAGE, BAND, YPOS)
            %   Returns the start index (1-based), sample stride, and number
            %   of samples for one line of a given band within this precinct.
            %
            %   C reference: precinct_ptr_for_line_of_band()  (precinct.c:80)
            ids_ref = obj.ids;
            c = ids_ref.band_idx_to_c_and_b(band_idx + 1).c + 1;
            b = ids_ref.band_idx_to_c_and_b(band_idx + 1).b + 1;

            % 下面这段是在“平铺后的分量向量”里定位 band 某一行的起点。
            %
            % 组成这个地址的偏移一共有 5 部分：
            %   1. 该 band 自己的高频起始偏移（x/y）
            %   2. precinct 当前位于第几行（y_idx）
            %   3. 该行在 band 内的 ypos
            %   4. precinct 当前位于第几列（column）
            %   5. 分量本身是否有 subsampling（sx/sy）
            the_ptr = int32(1);
            % 1) 先补上 band 在 y 方向是否是高频带带来的起始偏移
            if ids_ref.band_is_high(b).y
                the_ptr = the_ptr + int32(bitshift(1, ids_ref.band_d(c, b).y - 1)) * ids_ref.comp_w(c);
            end
            % 2) 再补上 x 方向高频带的起始偏移
            if ids_ref.band_is_high(b).x
                the_ptr = the_ptr + int32(bitshift(1, ids_ref.band_d(c, b).x - 1));
            end
            % 3) 跳到当前 precinct 的起始行
            the_ptr = the_ptr + ids_ref.comp_w(c) * bitshift(ids_ref.ph, -(int32(image.sy(c)) - 1)) * obj.y_idx;
            % 4) 再跳到当前 precinct 内的第 in_band_ypos 行
            the_ptr = the_ptr + ids_ref.comp_w(c) * in_band_ypos * int32(bitshift(1, ids_ref.band_d(c, b).y));
            % 5) 最后再跳到当前列 precinct 的 x 起点
            the_ptr = the_ptr + bitshift(ids_ref.pw(1), -(int32(image.sx(c)) - 1)) * obj.column;

            % x_inc 是同一 band 行内，相邻两个有效样本在平铺数组里的间隔。
            x_inc = int32(bitshift(1, ids_ref.band_d(c, b).x));
            line_len = int32(ids_ref.pwb(obj.is_last_column + 1, band_idx + 1));
            ptr = int32(the_ptr);
        end

        function to_image(obj, target, Fq)
            % TO_IMAGE  Write precinct coefficients back to image buffer.
            %   Applies Fq scaling and sign reconstruction.
            %
            %   C reference: precinct_to_image()  (precinct.c:110)
            for band_idx = int32(0):(obj.ids.nbands - 1)
                height = obj.in_band_height_of(band_idx);
                for ypos = int32(0):(height - 1)
                    [dst_ptr, dst_inc, dst_len] = obj.ptr_for_line_of_band(target, band_idx, ypos);
                    src = obj.line_of(band_idx, ypos);
                    comp_idx = obj.ids.band_idx_to_c_and_b(band_idx + 1).c + 1;
                    dst = target.comps_array{comp_idx};
                    for i = 1:dst_len
                        val = src(i);
                        % precinct 内部存的是 sign-magnitude。
                        % 写回 image 时要恢复成 MATLAB/C 都使用的有符号整数值。
                        if bitand(val, jxs.Constants.SIGN_BIT_MASK) ~= 0
                            dst(dst_ptr) = int32(-int32(bitand(val, bitcmp(jxs.Constants.SIGN_BIT_MASK, 'uint32')))) * int32(bitshift(1, Fq));
                        else
                            dst(dst_ptr) = int32(val) * int32(bitshift(1, Fq));
                        end
                        dst_ptr = dst_ptr + dst_inc;
                    end
                    target.comps_array{comp_idx} = dst;
                end
            end
        end

        function from_image(obj, image, Fq)
            % FROM_IMAGE  Extract one precinct's coefficients from the image.
            %   Applies Fq inverse scaling and sign-magnitude conversion.
            %
            %   C reference: precinct_from_image()  (precinct.c:140)
            % Fq_r = 2^(Fq-1)，用于右移前的舍入补偿。
            Fq_r = int32(bitshift(int32(1), Fq) / 2);
            for band_idx = int32(0):(obj.ids.nbands - 1)
                height = obj.in_band_height_of(band_idx);
                for ypos = int32(0):(height - 1)
                    [src_ptr, src_inc, src_len] = obj.ptr_for_line_of_band(image, band_idx, ypos);
                    c_idx = obj.ids.band_idx_to_c_and_b(band_idx + 1).c + 1;
                    src = image.comps_array{c_idx};
                    dst = obj.line_of(band_idx, ypos);
                    dst(:) = uint32(0);
                    sp = int32(src_ptr);
                    for i = int32(1):src_len
                        if sp < 1 || sp > int32(length(src)), break; end
                        val = int32(src(sp));
                        % 从有符号整数恢复到 sign-magnitude 表示。
                        if val >= 0
                            dst(i) = uint32(bitshift(val + Fq_r, -Fq));
                        else
                            dst(i) = bitor(uint32(bitshift(-val + Fq_r, -Fq)), jxs.Constants.SIGN_BIT_MASK);
                        end
                        sp = sp + src_inc;
                    end
                    obj.set_line(band_idx, ypos, dst);
                end
            end
        end

        function n = bands_count(obj)
            n = obj.ids.nbands;
        end

        function buf = line_of(obj, band_index, ypos)
            idx = obj.idx_from_level(ypos + 1, band_index + 1);
            assert(idx >= 1);
            buf = obj.sig_mag_data{idx};
        end

        function set_line(obj, band_index, ypos, data)
            idx = obj.idx_from_level(ypos + 1, band_index + 1);
            assert(idx >= 1);
            obj.sig_mag_data{idx} = data;
        end

        function w = width_of(obj, band_index)
            idx = obj.idx_from_level(1, band_index + 1);
            assert(idx >= 1);
            w = int32(length(obj.sig_mag_data{idx}));
        end

        function buf = gcli_of(obj, band_index, ypos)
            idx = obj.idx_from_level(ypos + 1, band_index + 1);
            assert(idx >= 1);
            buf = obj.gclis_data{idx};
        end

        function set_gcli(obj, band_index, ypos, data)
            idx = obj.idx_from_level(ypos + 1, band_index + 1);
            assert(idx >= 1);
            obj.gclis_data{idx} = data;
        end

        function buf = gcli_top_of(obj, prec_top, band_index, ypos)
            if ypos == 0
                prec_above = prec_top;
                if ~isempty(prec_above)
                    ylast = prec_above.in_band_height_of(band_index) - 1;
                else
                    ylast = 0;
                end
            else
                prec_above = obj;
                ylast = ypos - 1;
            end
            if ~isempty(prec_above)
                buf = prec_above.gcli_of(band_index, ylast);
            else
                buf = [];
            end
        end

        function gs = get_gcli_group_size(obj)
            gs = obj.group_size;
        end

        function w = gcli_width_of(obj, band_index)
            idx = obj.idx_from_level(1, band_index + 1);
            assert(idx >= 1);
            w = int32(length(obj.gclis_data{idx}));
        end

        function update_gclis(obj)
            for band = int32(0):(obj.bands_count() - 1)
                height = obj.in_band_height_of(band);
                for ypos = int32(0):(height - 1)
                    in_data = obj.line_of(band, ypos);
                    dst = obj.gcli_of(band, ypos);
                    width = int32(obj.width_of(band));
                    gcli_count = int32(obj.gcli_width_of(band));
                    [~, dst] = jxs.internal.precinct.compute_gcli_buf(in_data, width, dst, gcli_count, obj.group_size);
                    obj.set_gcli(band, ypos, dst);
                end
            end
        end

        function quantize(obj, gtli, dq_type)
            for band = int32(0):(obj.bands_count() - 1)
                height = obj.in_band_height_of(band);
                for ypos = int32(0):(height - 1)
                    data = obj.line_of(band, ypos);
                    width = obj.width_of(band);
                    gclis = obj.gcli_of(band, ypos);
                    data = jxs.internal.quant_ops.quant(data, width, gclis, obj.group_size, gtli(band + 1), dq_type);
                    obj.set_line(band, ypos, data);
                end
            end
        end

        function dequantize(obj, gtli, dq_type)
            for band = int32(0):(obj.bands_count() - 1)
                height = obj.in_band_height_of(band);
                for ypos = int32(0):(height - 1)
                    data = obj.line_of(band, ypos);
                    width = obj.width_of(band);
                    gclis = obj.gcli_of(band, ypos);
                    data = jxs.internal.quant_ops.dequant(data, width, gclis, obj.group_size, gtli(band + 1), dq_type);
                    obj.set_line(band, ypos, data);
                end
            end
        end

        function set_y_idx(obj, y_idx)
            assert(y_idx >= 0 && y_idx < obj.ids.npy);
            obj.y_idx = int32(y_idx);
        end

        function tf = is_first_of_slice(obj, slice_height)
            tf = (mod(int32(obj.y_idx * obj.ids.ph), int32(slice_height)) == 0);
        end

        function tf = is_last_of_image(obj, im_height)
            im_h = int32(im_height);
            tf = (idivide(im_h + obj.ids.ph - 1, obj.ids.ph, 'floor') == obj.y_idx + 1);
        end

        function h = in_band_height_of(obj, band_index)
            is_last = (obj.y_idx < (obj.ids.npy - 1));
            li = jxs.Constants.iif(is_last, 1, 2);
            h = int32(obj.ids.l1(li, band_index + 1) - obj.ids.l0(band_index + 1));
        end

        function tf = use_long_headers(obj)
            tf = obj.ids.use_long_precinct_headers;
        end

        function b = band_index_of(obj, position)
            b = int32(obj.ids.pi(position + 1).b);
        end

        function y = ypos_of(obj, position)
            y = int32(obj.ids.pi(position + 1).y - obj.ids.l0(obj.ids.pi(position + 1).b + 1));
        end

        function s = subpkt_of(obj, position)
            s = int32(obj.ids.pi(position + 1).s);
        end

        function n = nb_subpkts(obj)
            n = int32(obj.ids.npc);
        end

        function p = position_of(obj, lvl, ypos)
            % Returns 0-based position index (like C)
            p = int32(obj.idx_from_level(ypos + 1, lvl + 1)) - 1;
        end

        function copy_gclis(obj, src)
            % Copy GCLIs from src precinct to this one
            for band = int32(0):(obj.bands_count() - 1)
                if obj.in_band_height_of(band) ~= src.in_band_height_of(band), continue; end
                for ypos = int32(0):(obj.in_band_height_of(band) - 1)
                    dst = obj.gcli_of(band, ypos);
                    src_data = src.gcli_of(band, ypos);
                    n = min(length(dst), length(src_data));
                    dst(1:n) = src_data(1:n);
                    obj.set_gcli(band, ypos, dst);
                end
            end
        end

        function copy_data(obj, src)
            % Copy sig_mag data from src precinct to this one
            for band = int32(0):(obj.bands_count() - 1)
                if obj.in_band_height_of(band) ~= src.in_band_height_of(band), continue; end
                for ypos = int32(0):(obj.in_band_height_of(band) - 1)
                    dst = obj.line_of(band, ypos);
                    src_data = src.line_of(band, ypos);
                    n = min(length(dst), length(src_data));
                    dst(1:n) = src_data(1:n);
                    obj.set_line(band, ypos, dst);
                end
            end
        end

        function precinct_copy(obj, src)
            obj.y_idx = src.y_idx;
            obj.copy_gclis(src);
            obj.copy_data(src);
        end

        function lines = spacial_lines_of(obj, im_height)
            precheight = obj.ids.ph;
            leftover = mod(int32(im_height), precheight);
            if ~obj.is_last_of_image(im_height) || leftover == 0
                lines = precheight;
            else
                lines = leftover;
            end
        end
    end
end
