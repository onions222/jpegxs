% xs_config.m — JPEG XS 配置默认值与自动推导逻辑。
%
% 对应 C 参考实现：libjxs/src/xs_config.c
%
% 这个模块负责两类事情：
%   1. 给出一套“可运行”的默认配置
%   2. 把 AUTO 字段解析成最终编码/解码要用的确定值
%
% 典型会自动决定的字段包括：
%   - color transform（是否用 RCT）
%   - level / sublevel
%   - capability bits
%   - 默认 gains / priorities 权重表
% (profile constraints, weights table, bitstream size) from the user-
% specified settings.  All p.* fields use int32 for consistent arithmetic.

classdef xs_config
    methods (Static)
        function cfg = default_config()
            c = jxs.Constants;
            cfg = struct();
            % bitstream_size_in_bytes 用 uint64 的最大值表示“无限预算”。
            % 这和 C 侧用 (size_t)-1 的语义一致：即不做码率上限约束。
            cfg.bitstream_size_in_bytes = uint64(intmax('uint64'));
            cfg.verbose = int32(0);
            cfg.gains_mode = c.XS_GAINS_OPT_PSNR;
            cfg.profile = int32(c.XS_PROFILE_MAIN_444_12);
            cfg.budget_report_lines = single(jxs.internal.xs_config.profile_budget_report_lines(cfg.profile));
            cfg.level = int32(c.XS_LEVEL_AUTO);
            cfg.sublevel = int32(c.XS_SUBLEVEL_AUTO);
            cfg.cap_bits = int32(c.XS_CAP_AUTO);

            cfg.p = struct();
            % p.* 字段基本都直接对应 PIH marker 中的编码参数。
            % 其中 AUTO 值表示“先占位，后面 resolve_auto_values() 再补最终值”。
            cfg.p.color_transform = c.XS_CPIH_AUTO;
            cfg.p.Cw = int32(0);
            cfg.p.slice_height = int32(16);
            cfg.p.N_g = int32(4);
            cfg.p.S_s = int32(8);
            cfg.p.Bw = int32(20);
            cfg.p.Fq = int32(8);
            cfg.p.B_r = int32(4);
            cfg.p.Fslc = int32(0);
            cfg.p.Ppoc = int32(0);
            cfg.p.NLx = int32(5);
            cfg.p.NLy = int32(1);
            cfg.p.Lh = int32(0);
            cfg.p.Rl = int32(0);
            cfg.p.Qpih = int32(1);
            cfg.p.Fs = int32(0);
            cfg.p.Rm = int32(1);
            cfg.p.Sd = int32(0);
            % 255 是 WGT 表的终止哨兵，不是实际权重值。
            % 这里先全部填 255，后面 select_default_weights() 会覆盖真实表项。
            cfg.p.lvl_gains = int32(255) * ones(1, c.MAX_NBANDS + 1, 'int32');
            cfg.p.lvl_priorities = int32(255) * ones(1, c.MAX_NBANDS + 1, 'int32');
            cfg.p.Tnlt = c.XS_NLT_NONE;
            cfg.p.Tnlt_params = struct();
            cfg.p.Tnlt_params.quadratic = struct('sigma', int32(1), 'alpha', int32(15));
            cfg.p.Tnlt_params.extended = struct('T1', int32(0), 'T2', int32(0), 'E', int32(0));
            cfg.p.tetrix_params = struct('Cf', int32(0), 'e1', int32(0), 'e2', int32(0));
            cfg.p.cfa_pattern = c.XS_CFA_NONE;
        end

        function [ok, cfg] = resolve_auto_values(cfg, im)
            c = jxs.Constants;
            % resolve 的顺序很重要：
            %   profile -> color transform -> level/sublevel -> cap bits -> weights
            % 因为后面的很多自动推导会依赖前一步的结果。
            if cfg.profile == c.XS_PROFILE_AUTO
                cfg.profile = c.XS_PROFILE_MAIN_444_12;
            end
            if cfg.p.color_transform == c.XS_CPIH_AUTO
                cfg.p.color_transform = jxs.internal.xs_config.resolve_color_transform(cfg, im);
            end
            if cfg.level == c.XS_LEVEL_AUTO
                cfg.level = jxs.internal.xs_config.resolve_level(im);
            end
            if cfg.sublevel == c.XS_SUBLEVEL_AUTO
                cfg.sublevel = jxs.internal.xs_config.resolve_sublevel(cfg, im);
            end
            if cfg.budget_report_lines == 0
                cfg.budget_report_lines = single(jxs.internal.xs_config.profile_budget_report_lines(cfg.profile));
            end
            % 某些字段在 C 里允许“保留值”表达默认行为，这里在 MATLAB 里显式落地。
            if cfg.p.Bw == 255, cfg.p.Bw = int32(20); end
            if cfg.p.slice_height == 0, cfg.p.slice_height = int32(16); end
            if cfg.cap_bits == c.XS_CAP_AUTO
                cfg.cap_bits = jxs.internal.xs_config.calculate_cap_bits(cfg, im);
            end
            cfg = jxs.internal.xs_config.select_default_weights(cfg, im);
            ok = true;
        end

        function ok = validate(cfg, im)
            ok = true;
        end

        function cap_bits = calculate_cap_bits(cfg, im)
            c = jxs.Constants;
            using_sy = false;
            for comp = 1:double(im.ncomps)
                using_sy = using_sy || (im.sy(comp) > 1);
            end
            cap_bits = int32(0);
            % CAP marker 本质上是一个能力位掩码：
            % 哪些“非基本配置”被用到了，就把对应 bit 置 1。
            if cfg.p.color_transform == c.XS_CPIH_TETRIX
                cap_bits = bitor(cap_bits, c.XS_CAP_STAR_TETRIX);
            end
            if cfg.p.Tnlt == c.XS_NLT_QUADRATIC
                cap_bits = bitor(cap_bits, c.XS_CAP_NLT_Q);
            elseif cfg.p.Tnlt == c.XS_NLT_EXTENDED
                cap_bits = bitor(cap_bits, c.XS_CAP_NLT_E);
            end
            if using_sy
                cap_bits = bitor(cap_bits, c.XS_CAP_SY);
            end
            if cfg.p.Sd > 0
                cap_bits = bitor(cap_bits, c.XS_CAP_SD);
            end
            % MLS 位的语义和 C 保持一致：
            %   - unrestricted + Fq=0
            %   - 或无限预算模式
            if cfg.profile == c.XS_PROFILE_UNRESTRICTED && cfg.p.Fq == 0
                cap_bits = bitor(cap_bits, c.XS_CAP_MLS);
            end
            if cfg.bitstream_size_in_bytes == uint64(intmax('uint64'))
                cap_bits = bitor(cap_bits, c.XS_CAP_MLS);
            end
            if cfg.p.Rl ~= 0
                cap_bits = bitor(cap_bits, c.XS_CAP_RAW_PER_PKT);
            end
        end

        function cpih = resolve_color_transform(cfg, im)
            c = jxs.Constants;
            cpih = c.XS_CPIH_NONE;
            % 当前自动规则非常保守：
            % 只有 Main444.12 且图像是 3 分量 4:4:4 时，才自动启用 RCT。
            % 这和 C 参考实现保持一致，目的是避免把 subsampled / 特殊输入
            % 错误地当成可做 RCT 的标准 RGB 图像。
            if cfg.profile == c.XS_PROFILE_MAIN_444_12 && ...
               im.ncomps >= 3 && im.sx(1) == 1 && im.sx(2) == 1 && im.sx(3) == 1 && ...
               im.sy(1) == 1 && im.sy(2) == 1 && im.sy(3) == 1
                cpih = c.XS_CPIH_RCT;
            end
        end

        function level = resolve_level(im)
            c = jxs.Constants;
            samples = double(im.width) * double(im.height);
            % 这里不是简单看宽高，而是同时受：
            %   1. 最大宽度
            %   2. 最大高度
            %   3. 最大总样本数
            % 三个约束控制。只要有一项超限，就需要升到更高 level。
            level_table = [ ...
                double(c.XS_LEVEL_1K_1), 1280, 5120, 26214400; ...
                double(c.XS_LEVEL_2K_1), 2048, 8192, 4194304; ...
                double(c.XS_LEVEL_4K_1), 4096, 16384, 8912896; ...
                double(c.XS_LEVEL_UNRESTRICTED), 65535, 65535, 4294967295];
            level = c.XS_LEVEL_UNRESTRICTED;
            for i = 1:size(level_table, 1)
                if double(im.width) <= level_table(i, 2) && ...
                   double(im.height) <= level_table(i, 3) && ...
                   samples <= level_table(i, 4)
                    level = int32(level_table(i, 1));
                    return;
                end
            end
        end

        function sublevel = resolve_sublevel(cfg, im)
            c = jxs.Constants;
            if cfg.bitstream_size_in_bytes == uint64(intmax('uint64'))
                sublevel = c.XS_SUBLEVEL_UNRESTRICTED;
                return;
            end
            % 这里的 bitrate 是“每像素平均多少 bit”，不是每秒码率：
            %
            %   bitrate = bitstream_total_bits / (width * height)
            %
            % 如果走 Tetrix，C 参考实现按 2bit 单位折算；否则按普通 8bit 字节折算。
            bitrate = double(cfg.bitstream_size_in_bytes) * ...
                double(jxs.Constants.iif(cfg.p.color_transform == c.XS_CPIH_TETRIX, 2, 8)) / ...
                max(1e-4, double(im.width) * double(im.height));
            % 注意这里“超过 12bpp -> unrestricted”是和 C 对齐后的行为。
            % 之前如果写成 FULL，会导致码流头 sublevel 只差 1 个字段，
            % 图像结果一样，但 .jxs 无法逐字节对齐。
            if bitrate <= 2
                sublevel = c.XS_SUBLEVEL_2_BPP;
            elseif bitrate <= 3
                sublevel = c.XS_SUBLEVEL_3_BPP;
            elseif bitrate <= 6
                sublevel = c.XS_SUBLEVEL_6_BPP;
            elseif bitrate <= 9
                sublevel = c.XS_SUBLEVEL_9_BPP;
            elseif bitrate <= 12
                sublevel = c.XS_SUBLEVEL_12_BPP;
            else
                % libjxs resolves auto sublevel above 12 bpp to unrestricted.
                sublevel = c.XS_SUBLEVEL_UNRESTRICTED;
            end
        end

        function cfg = select_default_weights(cfg, im)
            c = jxs.Constants;
            if cfg.gains_mode == c.XS_GAINS_OPT_EXPLICIT
                return;
            end
            if cfg.p.lvl_gains(1) ~= 255 || cfg.p.lvl_priorities(1) ~= 255
                % 说明调用方已经显式给了权重表，就不要再自动覆盖。
                return;
            end

            % 这张表不是“算出来”的，而是直接移植自 C 参考实现内建 LUT。
            % 前提条件必须精确匹配：RGB 4:4:4 + RCT + NLx=5 + NLy=1 + PSNR 模式。
            if cfg.gains_mode == c.XS_GAINS_OPT_PSNR && ...
               cfg.p.NLx == 5 && cfg.p.NLy == 1 && ...
               cfg.p.color_transform == c.XS_CPIH_RCT && ...
               im.ncomps == 3 && im.sx(1) == 1 && im.sx(2) == 1 && im.sx(3) == 1 && ...
               im.sy(1) == 1 && im.sy(2) == 1 && im.sy(3) == 1
                gains = int32([4 2 2 3 2 2 2 1 1 2 1 1 1 0 0 1 0 0 1 0 0 1 0 0]);
                prios = int32([21 1 0 15 19 18 5 9 8 14 17 16 2 4 3 7 13 11 6 12 10 20 23 22]);
                n = length(gains);
                cfg.p.lvl_gains(1:n) = gains;
                cfg.p.lvl_priorities(1:n) = prios;
                cfg.p.lvl_gains(n + 1) = int32(255);
                cfg.p.lvl_priorities(n + 1) = int32(255);
                return;
            end

            % 这里保留了 NLy=2 的旧表，主要用于更深的垂直分解配置。
            if cfg.gains_mode == c.XS_GAINS_OPT_PSNR && ...
               cfg.p.NLx == 5 && cfg.p.NLy == 2 && ...
               cfg.p.color_transform == c.XS_CPIH_RCT && ...
               im.ncomps == 3 && im.sx(1) == 1 && im.sx(2) == 1 && im.sx(3) == 1 && ...
               im.sy(1) == 1 && im.sy(2) == 1 && im.sy(3) == 1
                gains = int32([4 3 3 3 2 2 3 2 2 2 1 1 2 1 1 2 1 1 1 0 0 1 0 0 1 0 0 1 0 0]);
                prios = int32([12 15 14 3 11 10 24 26 27 0 4 5 18 21 20 19 23 22 13 16 17 2 9 6 1 7 8 25 28 29]);
                n = length(gains);
                cfg.p.lvl_gains(1:n) = gains;
                cfg.p.lvl_priorities(1:n) = prios;
                cfg.p.lvl_gains(n + 1) = int32(255);
                cfg.p.lvl_priorities(n + 1) = int32(255);
                return;
            end

            error('No built-in gains/priorities defined for the given configuration');
        end

        function lines = profile_budget_report_lines(profile)
            c = jxs.Constants;
            switch int32(profile)
                case int32(c.XS_PROFILE_UNRESTRICTED)
                    lines = single(20);
                case int32(c.XS_PROFILE_MAIN_444_12)
                    lines = single(6);
                otherwise
                    lines = single(0);
            end
        end
    end
end
