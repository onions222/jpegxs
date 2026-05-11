% xs_markers.m — JPEG XS 码流 marker 的读写器。
%
% 对应 C 参考实现：libjxs/src/xs_markers.c
% 标准位置：ISO/IEC 21122-1 Annex A
%
% 作用：
%   负责码流头和 slice header 的语法层封装/解析。
%
% 这里处理的 marker 包括：
%   SOC, EOC, PIH, CDT, WGT, NLT, CWD, CTS, CRG, SLH, CAP, COM
%
% 可以把这个文件理解成：
%   “编码器/解码器和 JPEG XS 语法规范之间的翻译层”

classdef xs_markers
    properties (Constant)
        XS_MARKER_SOC = uint16(hex2dec('ff10'))
        XS_MARKER_EOC = uint16(hex2dec('ff11'))
        XS_MARKER_PIH = uint16(hex2dec('ff12'))
        XS_MARKER_CDT = uint16(hex2dec('ff13'))
        XS_MARKER_WGT = uint16(hex2dec('ff14'))
        XS_MARKER_COM = uint16(hex2dec('ff15'))
        XS_MARKER_NLT = uint16(hex2dec('ff16'))
        XS_MARKER_CWD = uint16(hex2dec('ff17'))
        XS_MARKER_CTS = uint16(hex2dec('ff18'))
        XS_MARKER_CRG = uint16(hex2dec('ff19'))
        XS_MARKER_SLH = uint16(hex2dec('ff20'))
        XS_MARKER_CAP = uint16(hex2dec('ff50'))
        XS_MARKER_NBITS = int32(16)
    end

    methods (Static)
        % ---- WRITE functions ----
        function nbits = write_picture_header(bitstream, im, cfg)
            % WRITE_PICTURE_HEADER  Emit the PIH marker segment.
            %   Contains codec profile, level, image dimensions, and
            %   all coding parameters (N_g, S_s, Bw, Fq, etc.).
            %
            %   C reference: xs_write_picture_header()  (xs_markers.c:40)
            import jxs.internal.xs_markers;
            nbits = int32(0);
            nbits = nbits + bitstream.write(xs_markers.XS_MARKER_PIH, xs_markers.XS_MARKER_NBITS);
            % PIH marker 的 length 字段固定为 26 byte，
            % 这是 JPEG XS 规范定义的固定大小 header，不随图像内容变化。
            nbits = nbits + bitstream.write(uint64(26), xs_markers.XS_MARKER_NBITS);
            if cfg.bitstream_size_in_bytes == intmax('uint64')
                % 约定 0 表示“不显式限制最终码流大小”，即无限 budget 模式。
                nbits = nbits + bitstream.write(uint64(0), 32);
            else
                nbits = nbits + bitstream.write(cfg.bitstream_size_in_bytes, 32);
            end
            % level 和 sublevel 在码流中被打包到同一个 16bit 字段：
            % 高 8 位是 level，低 8 位是 sublevel。
            nbits = nbits + bitstream.write(uint64(cfg.profile), 16);
            nbits = nbits + bitstream.write(bitor(bitshift(uint16(cfg.level), 8), uint16(cfg.sublevel)), 16);
            nbits = nbits + bitstream.write(uint64(im.width), 16);
            nbits = nbits + bitstream.write(uint64(im.height), 16);
            nbits = nbits + bitstream.write(uint64(cfg.p.Cw), 16);
            % PIH 中 slice height 存的不是像素行数，而是“按最低分辨率子带归一化后”的高度。
            % 解码时要再乘回 2^NLy 才能恢复真实 slice 高度。
            nbits = nbits + bitstream.write(uint64(idivide(int32(cfg.p.slice_height), int32(bitshift(1, cfg.p.NLy)), 'floor')), 16);
            nbits = nbits + bitstream.write(uint64(im.ncomps), 8);
            nbits = nbits + bitstream.write(uint64(cfg.p.N_g), 8);
            nbits = nbits + bitstream.write(uint64(cfg.p.S_s), 8);
            nbits = nbits + bitstream.write(uint64(cfg.p.Bw), 8);
            nbits = nbits + bitstream.write(uint64(cfg.p.Fq), 4);
            nbits = nbits + bitstream.write(uint64(cfg.p.B_r), 4);
            nbits = nbits + bitstream.write(uint64(cfg.p.Fslc), 1);
            nbits = nbits + bitstream.write(uint64(cfg.p.Ppoc), 3);
            nbits = nbits + bitstream.write(uint64(bitand(int32(cfg.p.color_transform), 15)), 4);
            nbits = nbits + bitstream.write(uint64(cfg.p.NLx), 4);
            nbits = nbits + bitstream.write(uint64(cfg.p.NLy), 4);
            nbits = nbits + bitstream.write(uint64(cfg.p.Lh), 1);
            nbits = nbits + bitstream.write(uint64(cfg.p.Rl), 1);
            nbits = nbits + bitstream.write(uint64(cfg.p.Qpih), 2);
            nbits = nbits + bitstream.write(uint64(cfg.p.Fs), 2);
            nbits = nbits + bitstream.write(uint64(cfg.p.Rm), 2);
        end

        function nbits = write_component_table(bitstream, im)
            import jxs.internal.xs_markers;
            nbits = int32(0);
            nbits = nbits + bitstream.write(xs_markers.XS_MARKER_CDT, xs_markers.XS_MARKER_NBITS);
            % CDT 段长度 = 每个分量 2 byte(depth + sx/sy) + 自身 length 字段 2 byte。
            nbits = nbits + bitstream.write(uint64(2 * im.ncomps + 2), xs_markers.XS_MARKER_NBITS);
            for comp = 1:im.ncomps
                nbits = nbits + bitstream.write(uint64(im.depth), 8);
                nbits = nbits + bitstream.write(uint64(im.sx(comp)), 4);
                nbits = nbits + bitstream.write(uint64(im.sy(comp)), 4);
            end
        end

        function nbits = write_weights_table(bitstream, cfg)
            import jxs.internal.xs_markers; import jxs.Constants;
            % 权重表后面用 255 作为“终止哨兵”，这里只统计真正有效的 band 数 Nl。
            Nl = 0; while Nl < Constants.MAX_NBANDS && cfg.p.lvl_gains(Nl + 1) ~= 255, Nl = Nl + 1; end
            nbits = int32(0);
            nbits = nbits + bitstream.write(xs_markers.XS_MARKER_WGT, xs_markers.XS_MARKER_NBITS);
            nbits = nbits + bitstream.write(uint64(2 * Nl + 2), xs_markers.XS_MARKER_NBITS);
            for lvl = 1:Nl
                nbits = nbits + bitstream.write(uint64(cfg.p.lvl_gains(lvl)), 8);
                nbits = nbits + bitstream.write(uint64(cfg.p.lvl_priorities(lvl)), 8);
            end
        end

        function nbits = write_nlt(bitstream, cfg)
            import jxs.internal.xs_markers; import jxs.Constants;
            nbits = int32(0);
            if cfg.p.Tnlt == Constants.XS_NLT_QUADRATIC
                nbits = nbits + bitstream.write(xs_markers.XS_MARKER_NLT, xs_markers.XS_MARKER_NBITS);
                nbits = nbits + bitstream.write(uint64(5), xs_markers.XS_MARKER_NBITS);
                nbits = nbits + bitstream.write(uint64(1), 8);
                nbits = nbits + bitstream.write(uint64(cfg.p.Tnlt_params.quadratic.sigma), 1);
                nbits = nbits + bitstream.write(uint64(cfg.p.Tnlt_params.quadratic.alpha), 15);
            elseif cfg.p.Tnlt == Constants.XS_NLT_EXTENDED
                nbits = nbits + bitstream.write(xs_markers.XS_MARKER_NLT, xs_markers.XS_MARKER_NBITS);
                nbits = nbits + bitstream.write(uint64(12), xs_markers.XS_MARKER_NBITS);
                nbits = nbits + bitstream.write(uint64(2), 8);
                nbits = nbits + bitstream.write(uint64(cfg.p.Tnlt_params.extended.T1), 32);
                nbits = nbits + bitstream.write(uint64(cfg.p.Tnlt_params.extended.T2), 32);
                nbits = nbits + bitstream.write(uint64(cfg.p.Tnlt_params.extended.E), 8);
            end
        end

        function nbits = write_com_encoder_identification(bitstream)
            import jxs.internal.xs_markers;
            id = 'ISO-21122-5-2.0.2-ED2';
            nbits = int32(0);
            nbits = nbits + bitstream.write(xs_markers.XS_MARKER_COM, xs_markers.XS_MARKER_NBITS);
            % COM 的长度需要把：
            % 1. registration value(2 byte)
            % 2. ASCII 字符串
            % 3. 末尾的 NUL
            % 一起算进去，所以是 strlength + 5。
            nbits = nbits + bitstream.write(uint64(strlength(id) + 5), xs_markers.XS_MARKER_NBITS);
            nbits = nbits + bitstream.write(uint64(0), xs_markers.XS_MARKER_NBITS);
            for i = 1:strlength(id)
                nbits = nbits + bitstream.write(uint64(uint8(char(extractBetween(id, i, i)))), 8);
            end
            nbits = nbits + bitstream.write(uint64(0), 8);
        end

        function nbits = write_head(bitstream, im, cfg)
            % WRITE_HEAD  Emit the complete codestream header.
            %   Order: SOC, CAP, PIH, CDT, WGT, [NLT], COM.
            %
            %   C reference: xs_write_head()  (xs_markers.c:200)
            import jxs.internal.xs_markers; import jxs.Constants;
            nbits = int32(0);
            nbits = nbits + bitstream.write(xs_markers.XS_MARKER_SOC, xs_markers.XS_MARKER_NBITS);
            % CAP marker 在这里始终写出，即使 capability bits 为 0 也不省略。
            % 这样能保持与 C 参考实现完全一致，也避免某些解析器要求 CAP 必须出现。
            nbits = nbits + bitstream.write(xs_markers.XS_MARKER_CAP, xs_markers.XS_MARKER_NBITS);
            nbits = nbits + bitstream.write(uint64(2), xs_markers.XS_MARKER_NBITS);
            nbits = nbits + xs_markers.write_picture_header(bitstream, im, cfg);
            nbits = nbits + xs_markers.write_component_table(bitstream, im);
            nbits = nbits + xs_markers.write_weights_table(bitstream, cfg);
            if cfg.p.Tnlt ~= Constants.XS_NLT_NONE
                nbits = nbits + xs_markers.write_nlt(bitstream, cfg);
            end
            nbits = nbits + xs_markers.write_com_encoder_identification(bitstream);
        end

        function nbits = write_tail(bitstream)
            import jxs.internal.xs_markers;
            nbits = bitstream.write(xs_markers.XS_MARKER_EOC, xs_markers.XS_MARKER_NBITS);
        end

        function nbits = write_slice_header(bitstream, slice_idx)
            import jxs.internal.xs_markers;
            nbits = int32(0);
            nbits = nbits + bitstream.write(xs_markers.XS_MARKER_SLH, xs_markers.XS_MARKER_NBITS);
            % SLH 的长度字段固定为 4 byte：2 byte length + 2 byte slice index。
            nbits = nbits + bitstream.write(uint64(4), xs_markers.XS_MARKER_NBITS);
            nbits = nbits + bitstream.write(uint64(slice_idx), 16);
        end

        % ---- PARSE functions (all return [ok, cfg] for pass-by-value safety) ----
        function [ok, cfg] = parse_head(bitstream, im, cfg)
            % PARSE_HEAD  Read and dispatch all header markers until SLH.
            %
            %   C reference: xs_parse_head()  (xs_markers.c:250)
            import jxs.internal.xs_markers;
            [val, ~] = bitstream.read(xs_markers.XS_MARKER_NBITS);
            if val ~= xs_markers.XS_MARKER_SOC, ok = false; return; end
            while true
                [marker, ~] = bitstream.peek(16);
                if marker == xs_markers.XS_MARKER_SLH, ok = true; return; end
                if ~isempty(cfg)
                    [ok, cfg] = xs_markers.dispatch_parse(bitstream, im, cfg, marker);
                    if ~ok, return; end
                else
                    % cfg 为空时退化成“跳过未知 marker”的模式：
                    % 先读 marker，再 peek 它的段长度，然后整段跳过。
                    [~, ~] = bitstream.read(xs_markers.XS_MARKER_NBITS);
                    [sz, ~] = bitstream.peek(xs_markers.XS_MARKER_NBITS);
                    bitstream.skip(int32(sz) * 8);
                end
            end
        end

        function [ok, cfg] = dispatch_parse(bitstream, im, cfg, marker)
            import jxs.internal.xs_markers;
            switch marker
                case xs_markers.XS_MARKER_PIH
                    [ok, cfg] = xs_markers.parse_picture_header(bitstream, im, cfg);
                case xs_markers.XS_MARKER_CDT
                    ok = xs_markers.parse_component_table(bitstream, im);
                case xs_markers.XS_MARKER_WGT
                    [ok, cfg] = xs_markers.parse_weights_table(bitstream, cfg);
                case xs_markers.XS_MARKER_CAP
                    [ok, cfg] = xs_markers.parse_capabilities(bitstream, cfg);
                case xs_markers.XS_MARKER_NLT
                    [ok, cfg] = xs_markers.parse_nlt_marker(bitstream, cfg);
                case xs_markers.XS_MARKER_CWD
                    [ok, cfg] = xs_markers.parse_cwd_marker(bitstream, cfg);
                case xs_markers.XS_MARKER_COM
                    ok = xs_markers.parse_com_marker(bitstream);
                case xs_markers.XS_MARKER_CTS
                    [ok, cfg] = xs_markers.parse_cts_marker(bitstream, cfg);
                case xs_markers.XS_MARKER_CRG
                    [ok, cfg] = xs_markers.parse_crg_marker(bitstream, im, cfg);
                otherwise
                    ok = false;
            end
        end

        function [ok, cfg] = parse_picture_header(bitstream, im, cfg)
            % PARSE_PICTURE_HEADER  Read the PIH marker segment.
            %   Populates im (width, height, ncomps) and cfg.p fields.
            %
            %   C reference: xs_parse_picture_header()  (xs_markers.c:280)
            import jxs.internal.xs_markers;
            [v, ~] = bitstream.read(xs_markers.XS_MARKER_NBITS); if v ~= xs_markers.XS_MARKER_PIH, ok=false; return; end
            [v, ~] = bitstream.read(xs_markers.XS_MARKER_NBITS); if v ~= 26, ok=false; return; end
            [v, ~] = bitstream.read(32); cfg.bitstream_size_in_bytes = uint64(v);
            [v, ~] = bitstream.read(16); cfg.profile = int32(v);
            [v, ~] = bitstream.read(16); cfg.level = int32(bitshift(v, -8)); cfg.sublevel = int32(bitand(v, 255));
            [v, ~] = bitstream.read(16); im.width = int32(v);
            [v, ~] = bitstream.read(16); im.height = int32(v);
            [v, ~] = bitstream.read(16); cfg.p.Cw = int32(v);
            [v, ~] = bitstream.read(16); cfg.p.slice_height = int32(v);
            [v, ~] = bitstream.read(8); im.ncomps = int32(v);
            [v, ~] = bitstream.read(8); cfg.p.N_g = int32(v);
            [v, ~] = bitstream.read(8); cfg.p.S_s = int32(v);
            [v, ~] = bitstream.read(8); cfg.p.Bw = int32(v);
            [v, ~] = bitstream.read(4); cfg.p.Fq = int32(v);
            [v, ~] = bitstream.read(4); cfg.p.B_r = int32(v);
            [v, ~] = bitstream.read(1); cfg.p.Fslc = int32(v);
            [v, ~] = bitstream.read(3); cfg.p.Ppoc = int32(v);
            [v, ~] = bitstream.read(4); cfg.p.color_transform = int32(v);
            [v, ~] = bitstream.read(4); cfg.p.NLx = int32(v);
            [v, ~] = bitstream.read(4); cfg.p.NLy = int32(v);
            % 写入时做过 2^NLy 归一化，这里要乘回来恢复真实 slice_height。
            cfg.p.slice_height = cfg.p.slice_height * int32(bitshift(1, cfg.p.NLy));
            [v, ~] = bitstream.read(1); cfg.p.Lh = int32(v);
            [v, ~] = bitstream.read(1); cfg.p.Rl = int32(v);
            [v, ~] = bitstream.read(2); cfg.p.Qpih = int32(v);
            [v, ~] = bitstream.read(2); cfg.p.Fs = int32(v);
            [v, ~] = bitstream.read(2); cfg.p.Rm = int32(v);
            ok = true;
        end

        function ok = parse_component_table(bitstream, im)
            import jxs.internal.xs_markers;
            [v, ~] = bitstream.read(xs_markers.XS_MARKER_NBITS); if v ~= xs_markers.XS_MARKER_CDT, ok=false; return; end
            [v, ~] = bitstream.read(xs_markers.XS_MARKER_NBITS);
            for comp = 1:im.ncomps
                [v, ~] = bitstream.read(8); im.depth = int32(v);
                [v, ~] = bitstream.read(4); im.sx(comp) = int32(v);
                [v, ~] = bitstream.read(4); im.sy(comp) = int32(v);
            end
            ok = true;
        end

        function [ok, cfg] = parse_weights_table(bitstream, cfg)
            import jxs.internal.xs_markers; import jxs.Constants;
            [v, ~] = bitstream.read(xs_markers.XS_MARKER_NBITS); if v ~= xs_markers.XS_MARKER_WGT, ok=false; return; end
            [v, ~] = bitstream.read(xs_markers.XS_MARKER_NBITS);
            Nl = int32((double(v) - 2) / 2);
            % marker 长度里减掉 2 byte 自身长度字段后，每个 band 恰好占 2 byte：
            % 1 byte gain + 1 byte priority。
            for lvl = 1:Nl
                [v, ~] = bitstream.read(8); cfg.p.lvl_gains(lvl) = int32(v);
                [v, ~] = bitstream.read(8); cfg.p.lvl_priorities(lvl) = int32(v);
            end
            % 解析完成后显式补上 255 哨兵，方便后续 MATLAB 端沿用同一套“到 255 为止”的逻辑。
            cfg.p.lvl_gains(Nl + 1) = int32(255);
            cfg.p.lvl_priorities(Nl + 1) = int32(255);
            cfg.p.lvl_gains(Constants.MAX_NBANDS + 1) = int32(255);
            cfg.p.lvl_priorities(Constants.MAX_NBANDS + 1) = int32(255);
            ok = true;
        end

        function [ok, cfg] = parse_capabilities(bitstream, cfg)
            import jxs.internal.xs_markers;
            [v, ~] = bitstream.read(xs_markers.XS_MARKER_NBITS); if v ~= xs_markers.XS_MARKER_CAP, ok=false; return; end
            [v, ~] = bitstream.read(xs_markers.XS_MARKER_NBITS);
            % CAP marker 允许 8bit 或 16bit capability bitmap。
            % v==2 表示空 capability；v==3/4 分别表示后面跟 1 或 2 个字节。
            if v == 3, [v, ~] = bitstream.read(8); v = bitshift(v, 8);
            elseif v == 4, [v, ~] = bitstream.read(16); end
            cfg.cap_bits = int32(v); ok = true;
        end

        function [ok, cfg] = parse_nlt_marker(bitstream, cfg)
            import jxs.internal.xs_markers; import jxs.Constants;
            [v, ~] = bitstream.read(xs_markers.XS_MARKER_NBITS); if v ~= xs_markers.XS_MARKER_NLT, ok=false; return; end
            [v, ~] = bitstream.read(xs_markers.XS_MARKER_NBITS);
            [v, ~] = bitstream.read(8);
            if v == 1
                cfg.p.Tnlt = Constants.XS_NLT_QUADRATIC;
                [v, ~] = bitstream.read(1); cfg.p.Tnlt_params.quadratic.sigma = int32(v);
                [v, ~] = bitstream.read(15); cfg.p.Tnlt_params.quadratic.alpha = int32(v);
            elseif v == 2
                cfg.p.Tnlt = Constants.XS_NLT_EXTENDED;
                [v, ~] = bitstream.read(32); cfg.p.Tnlt_params.extended.T1 = int32(v);
                [v, ~] = bitstream.read(32); cfg.p.Tnlt_params.extended.T2 = int32(v);
                [v, ~] = bitstream.read(8); cfg.p.Tnlt_params.extended.E = int32(v);
            else, ok = false; return;
            end
            ok = true;
        end

        function [ok, cfg] = parse_cwd_marker(bitstream, cfg)
            import jxs.internal.xs_markers;
            [v, ~] = bitstream.read(xs_markers.XS_MARKER_NBITS); if v ~= xs_markers.XS_MARKER_CWD, ok=false; return; end
            [v, ~] = bitstream.read(xs_markers.XS_MARKER_NBITS);
            [v, ~] = bitstream.read(8); cfg.p.Sd = int32(v); ok = true;
        end

        function [ok, cfg] = parse_cts_marker(bitstream, cfg)
            import jxs.internal.xs_markers;
            [v, ~] = bitstream.read(xs_markers.XS_MARKER_NBITS); if v ~= xs_markers.XS_MARKER_CTS, ok=false; return; end
            [v, ~] = bitstream.read(xs_markers.XS_MARKER_NBITS);
            [~, ~] = bitstream.read(4); [v, ~] = bitstream.read(4);
            cfg.p.tetrix_params.Cf = int32(v);
            [v, ~] = bitstream.read(4); cfg.p.tetrix_params.e1 = int32(v);
            [v, ~] = bitstream.read(4); cfg.p.tetrix_params.e2 = int32(v);
            ok = true;
        end

        function [ok, cfg] = parse_crg_marker(bitstream, im, cfg)
            import jxs.internal.xs_markers;
            [v, ~] = bitstream.read(xs_markers.XS_MARKER_NBITS); if v ~= xs_markers.XS_MARKER_CRG, ok=false; return; end
            [v, ~] = bitstream.read(xs_markers.XS_MARKER_NBITS);
            % 当前 MATLAB 端只需要把 CRG 段整体消费掉，
            % 不依赖每个分量的 registration 值，所以这里只读不落地。
            for c = 1:4
                [~, ~] = bitstream.read(16); [~, ~] = bitstream.read(16);
            end
            cfg.p.cfa_pattern = int32(0); ok = true;
        end

        function ok = parse_com_marker(bitstream)
            import jxs.internal.xs_markers;
            [v, ~] = bitstream.read(xs_markers.XS_MARKER_NBITS); if v ~= xs_markers.XS_MARKER_COM, ok=false; return; end
            [sz, ~] = bitstream.read(xs_markers.XS_MARKER_NBITS);
            while sz > 2, [~, ~] = bitstream.read(8); sz = sz - 1; end
            ok = true;
        end

        function ok = parse_tail(bitstream)
            import jxs.internal.xs_markers;
            [v, ~] = bitstream.read(xs_markers.XS_MARKER_NBITS);
            ok = (v == xs_markers.XS_MARKER_EOC);
        end

        function [ok, slice_idx] = parse_slice_header(bitstream)
            import jxs.internal.xs_markers;
            [v, ~] = bitstream.read(xs_markers.XS_MARKER_NBITS);
            if v ~= xs_markers.XS_MARKER_SLH, ok = false; slice_idx = 0; return; end
            [v, ~] = bitstream.read(xs_markers.XS_MARKER_NBITS);
            [v, ~] = bitstream.read(16);
            ok = true; slice_idx = int32(v);
        end
    end
end
