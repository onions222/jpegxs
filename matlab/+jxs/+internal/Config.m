% Config.m — 配置结构体的 handle 封装。
%
% 对应 C 里的 xs_config_t。
%
% 这个类的主要作用是把本来按值传递的配置，包装成 handle 对象，
% 方便在 MATLAB 里跨函数共享与更新，而不必每次手动接回返回值。
% pipeline (matching C's pointer semantics).

classdef Config < handle
    properties
        bitstream_size_in_bytes
        budget_report_lines
        verbose
        gains_mode
        profile
        level
        sublevel
        cap_bits
        p  % struct: xs_config_parameters_t
    end

    methods
        function obj = Config()
            c = jxs.Constants;
            % 这里先给一组“能工作”的默认值，
            % 后面再由 xs_config.resolve_* 系列函数按 profile / 图像尺寸 / 目标码率细化。
            obj.bitstream_size_in_bytes = uint64(intmax('uint64'));
            obj.budget_report_lines = single(0);
            obj.verbose = int32(0);
            obj.gains_mode = c.XS_GAINS_OPT_PSNR;
            obj.profile = int32(c.XS_PROFILE_MAIN_444_12);
            obj.level = int32(c.XS_LEVEL_4K_1);
            obj.sublevel = int32(c.XS_SUBLEVEL_FULL);
            obj.cap_bits = int32(c.XS_CAP_AUTO);

            obj.p = struct();
            % p 对应 C 里的 xs_config_parameters_t，
            % 基本上所有真正写进 PIH / marker 的编码参数都在这里。
            obj.p.color_transform = c.XS_CPIH_RCT;
            obj.p.Cw = int32(0);
            obj.p.slice_height = int32(16);
            obj.p.N_g = int32(4);
            obj.p.S_s = int32(8);
            obj.p.Bw = int32(18);
            obj.p.Fq = int32(8);
            obj.p.B_r = int32(4);
            obj.p.Fslc = int32(0);
            obj.p.Ppoc = int32(0);
            obj.p.NLx = int32(5);
            obj.p.NLy = int32(2);
            obj.p.Lh = int32(0);
            obj.p.Rl = int32(0);
            obj.p.Qpih = int32(0);
            obj.p.Fs = int32(1);
            obj.p.Rm = int32(0);
            obj.p.Sd = int32(0);
            obj.p.lvl_gains = int32(255) * ones(1, c.MAX_NBANDS + 1, 'int32');
            obj.p.lvl_priorities = int32(255) * ones(1, c.MAX_NBANDS + 1, 'int32');
            % gain/priority 用 255 作为“尚未解析/尚未填表”的哨兵值。
            obj.p.Tnlt = c.XS_NLT_NONE;
            obj.p.Tnlt_params = struct();
            obj.p.Tnlt_params.quadratic = struct('sigma', int32(1), 'alpha', int32(15));
            obj.p.Tnlt_params.extended = struct('T1', int32(0), 'T2', int32(0), 'E', int32(0));
            obj.p.tetrix_params = struct('Cf', int32(0), 'e1', int32(0), 'e2', int32(0));
            obj.p.cfa_pattern = c.XS_CFA_NONE;
        end

        function resolve_auto(obj, im)
            c = jxs.Constants;
            % 这里只做最薄的一层兜底，真正完整的 AUTO 解析逻辑在 xs_config.m。
            if obj.profile == c.XS_PROFILE_AUTO, obj.profile = c.XS_PROFILE_MAIN_444_12; end
            if obj.p.Bw == 255, obj.p.Bw = int32(18); end
            if obj.p.slice_height == 0, obj.p.slice_height = int32(16); end
        end
    end
end
