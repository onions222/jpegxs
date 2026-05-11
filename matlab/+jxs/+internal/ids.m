% ids.m — Image Decomposition Structure（图像分解结构）。
%
% 对应 C 参考实现：libjxs/src/ids.c / ids.h
% 标准位置：ISO/IEC 21122-1 Annex B
%
% 这个模块决定“图像在 JPEG XS 里被怎么切开”：
%   - 每个分量有多少级分解
%   - 每个 band 的尺寸、位置、低高频属性
%   - 每个 precinct / packet / line 的映射关系
%
% 可以把 IDS 看成整个编解码流程的“几何坐标系统”。
% into sub-bands (via the DWT), how sub-bands map to precincts and
% packets, and the geometry (width, height, stride) at every level.
%
% Key concepts:
%   - nb     : total filter types = 2*NLy + NLx + 1
%   - nbands : count of active sub-bands across all components
%   - pi     : packet inclusion order (Annex B, Table B.2)
%   - pwb    : precinct width in each sub-band
%   - l0/l1  : vertical line range per band within a precinct

classdef ids < handle
    properties
        ncomps int32
        w int32
        h int32
        comp_w
        comp_h
        nbands int32
        sd int32
        nb int32
        nlxy             % struct with .x .y
        nlxyp            % array of structs per component
        band_idx         % [MAX_NCOMPS x MAX_NFILTER_TYPES] int8
        band_idx_to_c_and_b  % [MAX_NBANDS] struct with .c .b
        band_d           % [MAX_NCOMPS x MAX_NFILTER_TYPES] struct with .x .y
        band_is_high     % [MAX_NFILTER_TYPES] struct with .x .y
        band_dim         % [MAX_NCOMPS x MAX_NFILTER_TYPES] struct with .w .h
        band_max_width int32
        cs int32
        npx int32
        npy int32
        np int32
        pw               % [1 x 2]
        ph int32
        pwb              % [2 x MAX_NBANDS]
        l0               % [1 x MAX_NBANDS]
        l1               % [2 x MAX_NBANDS]
        pi                % [MAX_PACKETS] struct with .b .y .s
        npc int32
        npi int32
        use_long_precinct_headers logical
    end

    methods
        function obj = ids()
            import jxs.Constants;
            obj.ncomps = int32(0);
            obj.w = int32(0); obj.h = int32(0);
            obj.comp_w = zeros(1, Constants.MAX_NCOMPS, 'int32');
            obj.comp_h = zeros(1, Constants.MAX_NCOMPS, 'int32');
            obj.nbands = int32(0); obj.sd = int32(0); obj.nb = int32(0);
            obj.nlxy = struct('x', int32(0), 'y', int32(0));
            obj.nlxyp = repmat(struct('x', int32(0), 'y', int32(0)), 1, Constants.MAX_NCOMPS);
            obj.band_idx = zeros(Constants.MAX_NCOMPS, Constants.MAX_NFILTER_TYPES, 'int8');
            obj.band_idx_to_c_and_b = repmat(struct('c', int8(0), 'b', int8(0)), 1, Constants.MAX_NBANDS);
            obj.band_d = repmat(struct('x', int32(0), 'y', int32(0)), Constants.MAX_NCOMPS, Constants.MAX_NFILTER_TYPES);
            obj.band_is_high = repmat(struct('x', false, 'y', false), 1, Constants.MAX_NFILTER_TYPES);
            obj.band_dim = repmat(struct('w', int32(0), 'h', int32(0)), Constants.MAX_NCOMPS, Constants.MAX_NFILTER_TYPES);
            obj.band_max_width = int32(0);
            obj.cs = int32(0); obj.npx = int32(0); obj.npy = int32(0); obj.np = int32(0);
            obj.pw = zeros(1, 2, 'int32'); obj.ph = int32(0);
            obj.pwb = zeros(2, Constants.MAX_NBANDS, 'int32');
            obj.l0 = zeros(1, Constants.MAX_NBANDS, 'int32');
            obj.l1 = zeros(2, Constants.MAX_NBANDS, 'int32');
            obj.pi = repmat(struct('b', int32(0), 'y', int32(0), 's', int32(0)), 1, Constants.MAX_PACKETS);
            obj.npc = int32(0); obj.npi = int32(0);
            obj.use_long_precinct_headers = false;
        end

        function construct(obj, im, ndecomp_h, ndecomp_v, sd, cw, lh)
            % CONSTRUCT  Build the full IDS from image parameters.
            %   construct(IM, NLx, NLy, Sd, Cw, Lh)
            %   Populates band indexing, band dimensions, precinct
            %   geometry, and packet inclusion tables.
            %
            %   C reference: ids_construct()  (ids.c:62)
            import jxs.Constants;
            assert(im.ncomps > 0 && im.ncomps <= Constants.MAX_NCOMPS);
            assert(ndecomp_v <= ndecomp_h && ndecomp_h > 0 && ndecomp_v >= 0);
            assert(lh == 0 || lh == 1);
            assert(sd >= 0 && sd <= im.ncomps);

            obj.ncomps = int32(im.ncomps);
            obj.w = int32(im.width);
            obj.h = int32(im.height);
            obj.sd = int32(sd);
            obj.nlxy.x = int32(ndecomp_h);
            obj.nlxy.y = int32(ndecomp_v);
            % nb = 当前分解配置下“滤波器类型槽位”的总数。
            % 对 JPEG XS 而言：
            %   - 水平-only band 数和 NLx 有关
            %   - 混合 H/V band 数和 NLy 有关
            % 最后组合成 2*NLy + NLx + 1
            obj.nb = int32(2 * ndecomp_v + ndecomp_h + 1);
            obj.use_long_precinct_headers = ~((obj.w * obj.ncomps < 32752) && (lh == 0));

            % band_is_high 描述每个滤波器槽位在 x / y 方向上是否是高频。
            % 后面 band 尺寸计算、指针定位都会依赖这个标志。
            for b = int32(2):int32(obj.nlxy.x - obj.nlxy.y + 1)
                obj.band_is_high(b).x = true;
            end
            for b = int32(obj.nlxy.x - obj.nlxy.y + 2):3:obj.nb
                obj.band_is_high(b).x = true;     % HL
                obj.band_is_high(b+1).y = true;    % LH
                obj.band_is_high(b+2).x = true;    % HH
                obj.band_is_high(b+2).y = true;
            end

            for c = 1:obj.ncomps
                obj.comp_w(c) = idivide(obj.w, im.sx(c), 'floor');
                obj.comp_h(c) = idivide(obj.h, im.sy(c), 'floor');
                if c <= obj.ncomps - obj.sd
                    obj.nlxyp(c).x = obj.nlxy.x;
                    obj.nlxyp(c).y = obj.nlxy.y - bitshift(im.sy(c), -1);
                end
                % 先建立“这个分量有哪些 band 存在”的粗表。
                % 对某些分量 / 分解层，部分 band 会被标成不存在（-1）。
                obj.band_idx(c, 1) = int8(1);
                obj.band_d(c, 1).x = obj.nlxyp(c).x;
                obj.band_d(c, 1).y = obj.nlxyp(c).y;
                for b = int32(2):int32(obj.nlxyp(c).x - obj.nlxyp(c).y + 1)
                    obj.band_idx(c, b) = int8(1);
                    % 这里的 band_d 表示“距离最终低频 LL 还剩多少层分解”。
                    % 因为 MATLAB 下标从 1 开始，所以比 C 的公式多一个 +1 偏移。
                    obj.band_d(c, b).x = obj.nlxyp(c).x + 2 - b;
                    obj.band_d(c, b).y = obj.nlxyp(c).y;
                end
                start_b = obj.nlxyp(c).x - obj.nlxyp(c).y + 2;
                end_b = obj.nb - 3 * obj.nlxyp(c).y;
                for b = start_b:end_b
                    obj.band_idx(c, b) = int8(-1);
                    obj.band_d(c, b).x = int32(-1);
                    obj.band_d(c, b).y = int32(-1);
                end
                for i = 3 * obj.nlxyp(c).y:-1:1
                    b = obj.nb - i + 1;
                    d = idivide(i + 2, int32(3), 'floor');
                    obj.band_idx(c, b) = int8(1);
                    obj.band_d(c, b).x = d;
                    obj.band_d(c, b).y = d;
                end
            end

            % 第二步把“存在的 band”重新编号成连续的 0-based band index，
            % 这样后面的 precinct / packet 表都能统一引用它们。
            nbands = int32(0);
            for b = 1:obj.nb
                for c = 1:(obj.ncomps - obj.sd)
                    if obj.band_idx(c, b) == int8(1)
                        obj.band_idx(c, b) = int8(nbands);  % 0-based band index (like C)
                        nbands = nbands + 1;
                        obj.band_idx_to_c_and_b(nbands).c = int8(c - 1);
                        obj.band_idx_to_c_and_b(nbands).b = int8(b - 1);
                    end
                end
            end
            for c = (obj.ncomps - obj.sd + 1):obj.ncomps
                if obj.band_idx(c, 1) == int8(1)
                    obj.band_idx(c, 1) = int8(nbands);  % 0-based band index
                    nbands = nbands + 1;
                    obj.band_idx_to_c_and_b(nbands).c = int8(c - 1);
                    obj.band_idx_to_c_and_b(nbands).b = int8(0);
                end
            end
            obj.nbands = nbands;

            % 计算每个 band 的实际宽高。
            %
            % 低频 band 的尺寸相当于 ceil(comp_size / 2^d)
            % 高频 band 的尺寸相当于 ceil(comp_size / 2^(d-1)) / 2
            %
            % 这正是 lifting 分解后高低频子带尺寸不同的来源。
            for c = 1:obj.ncomps
                comp_w = int32(obj.comp_w(c));
                comp_h = int32(obj.comp_h(c));
                for b = 1:obj.nb
                    if obj.band_idx(c, b) < 0, continue; end
                    if obj.band_is_high(b).x
                        d = int32(bitshift(1, obj.band_d(c, b).x - 1));
                        obj.band_dim(c, b).w = idivide(comp_w + d - 1, d * 2, 'floor');
                    else
                        d = int32(bitshift(1, obj.band_d(c, b).x));
                        obj.band_dim(c, b).w = idivide(comp_w + d - 1, d, 'floor');
                    end
                    if obj.band_is_high(b).y
                        d = int32(bitshift(1, obj.band_d(c, b).y - 1));
                        obj.band_dim(c, b).h = idivide(comp_h + d - 1, d * 2, 'floor');
                    else
                        d = int32(bitshift(1, obj.band_d(c, b).y));
                        obj.band_dim(c, b).h = idivide(comp_h + d - 1, d, 'floor');
                    end
                    if obj.band_max_width < obj.band_dim(c, b).w
                        obj.band_max_width = obj.band_dim(c, b).w;
                    end
                end
            end

            % precinct 几何参数：
            %   cs  —— 一列 precinct 在原图里的宽度
            %   ph  —— 一个 precinct 在原图里的高度 (= 2^NLy)
            %   npx —— 水平方向有多少列 precinct
            %   npy —— 垂直方向有多少行 precinct
            obj.cs = jxs.internal.ids.calculate_cs(im, ndecomp_h, cw);
            obj.ph = int32(bitshift(1, obj.nlxy.y));
            obj.npx = idivide(obj.w + obj.cs - 1, obj.cs, 'floor');
            obj.npy = idivide(obj.h + obj.ph - 1, obj.ph, 'floor');
            obj.np = obj.npx * obj.npy;
            obj.pw(1) = obj.cs;
            obj.pw(2) = mod(int32(obj.w - 1), obj.cs) + 1;
            for b = 1:obj.nbands
                i2cft = obj.band_idx_to_c_and_b(b);
                cidx = i2cft.c + 1; bidx = i2cft.b + 1;
                sx = int32(im.sx(cidx)) - 1;
                % pw_in_b_* 先把 precinct 在原图中的宽度，换算到当前分量采样网格。
                % 如果有 subsampling（sx>1），这里相当于先除以 sx。
                pw_in_b_0 = bitshift(obj.pw(1) + sx, -sx);
                pw_in_b_1 = bitshift(obj.pw(2) + sx, -sx);
                if obj.band_is_high(bidx).x
                    d = int32(bitshift(1, obj.band_d(cidx, bidx).x - 1));
                    obj.pwb(1, b) = idivide(pw_in_b_0 + d - 1, d * 2, 'floor');
                    obj.pwb(2, b) = idivide(pw_in_b_1 + d - 1, d * 2, 'floor');
                else
                    d = int32(bitshift(1, obj.band_d(cidx, bidx).x));
                    obj.pwb(1, b) = idivide(pw_in_b_0 + d - 1, d, 'floor');
                    obj.pwb(2, b) = idivide(pw_in_b_1 + d - 1, d, 'floor');
                end
                if b <= obj.nbands - obj.sd
                    % l0 / l1 描述一个 precinct 内，每个 band 真正覆盖哪些行。
                    % 因为高频 band 的垂直采样间距和低频 band 不一样，
                    % 所以同一个 precinct 在不同 band 内的“有效行数”也不同。
                    tmp = bitshift(int32(1), jxs.Constants.MAX(obj.nlxyp(cidx).y - obj.band_d(cidx, bidx).y, 0));
                    obj.l0(b) = tmp * int32(obj.band_is_high(bidx).y);
                    obj.l1(1, b) = int32(obj.l0(b) + tmp);
                    obj.l1(2, b) = int32(obj.l0(b) + (obj.band_dim(cidx, bidx).h - (obj.npy - 1) * tmp));
                else
                    obj.l0(b) = int32(0);
                    obj.l1(1, b) = obj.ph;
                    obj.l1(2, b) = mod(int32(obj.band_dim(cidx, bidx).h + obj.ph - 1), obj.ph) + 1;
                end
            end
            obj.compute_packet_inclusion();
        end

        function compute_packet_inclusion(obj)
            % COMPUTE_PACKET_INCLUSION  Build the packet scanning order.
            %   Populates obj.pi with {band, ypos, subpacket} triples
            %   that define the order in which band-lines are packed
            %   into sub-packets within each precinct.
            %
            %   C reference: ids_compute_packet_inclusion_()  (ids.c:180)
            % pi 是一个线性扫描表，定义“precinct 内 band-line 被打包的顺序”。
            % 后面的 packing / unpacking 都按这个顺序走，所以它本质上是语法顺序表。
            idx = int32(1);
            s = int32(0);
            beta1 = obj.nlxy.x - obj.nlxy.y + 1;
            for beta = int32(0):(beta1 - 1)
                for i = 1:(obj.ncomps - obj.sd)
                    b = obj.band_idx(i, beta + 1);
                    assert(b >= 0);
                    obj.pi(idx).b = int32(b);
                    obj.pi(idx).y = int32(0);
                    obj.pi(idx).s = s;
                    idx = idx + 1;
                end
            end
            for beta0 = int32(beta1):int32(3):(obj.nb - 1)
                nlines = bitshift(int32(1), obj.nlxy.y - obj.band_d(1, beta0 + 1).y);
                for lambda = int32(0):(nlines - 1)
                    for beta = beta0:min(beta0 + 2, obj.nb - 1)
                        r = int32(1);
                        for i = 1:(obj.ncomps - obj.sd)
                            b = obj.band_idx(i, beta + 1);
                            if b >= 0
                                if obj.l0(b + 1) + lambda < obj.l1(1, b + 1)
                                    % s 表示 subpacket 编号。对于同一个 precinct，
                                    % 某些 band-line 会被划到不同 subpacket 中，
                                    % 以满足 JPEG XS 的分包结构。
                                    s = s + r;
                                    obj.pi(idx).b = int32(b);
                                    obj.pi(idx).y = int32(obj.l0(b + 1) + lambda);
                                    obj.pi(idx).s = s;
                                    r = int32(0);
                                    idx = idx + 1;
                                end
                            end
                        end
                    end
                end
            end
            for lambda = int32(0):(obj.ph - 1)
                for i = (obj.ncomps - obj.sd + 1):obj.ncomps
                    b = obj.band_idx(i, 1);
                    if obj.l0(b + 1) + lambda < obj.l1(1, b + 1)
                        s = s + 1;
                        obj.pi(idx).b = int32(b);
                        obj.pi(idx).y = int32(obj.l0(b + 1) + lambda);
                        obj.pi(idx).s = s;
                        idx = idx + 1;
                    end
                end
            end
            obj.npi = idx - 1;
            obj.npc = s + 1;
            assert(obj.npi <= jxs.Constants.MAX_PACKETS);
        end
    end

    methods (Static)
        function cs = calculate_cs(im, ndecomp_h, cw)
            % CALCULATE_CS  Compute precinct column stride from Cw parameter.
            %   cs = 8 * Cw * max_sx * 2^NLx  when Cw > 0,
            %   cs = image_width              when Cw == 0 (single column).
            %
            %   C reference: ids_calculate_cs()  (ids.c:32)
            if cw > 0
                max_sx = int32(0);
                for c = 1:im.ncomps
                    if max_sx < im.sx(c), max_sx = im.sx(c); end
                end
                cs = int32(8 * cw * max_sx * bitshift(1, ndecomp_h));
            else
                cs = int32(im.width);
            end
        end
    end
end
