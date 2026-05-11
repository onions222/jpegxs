% sigbuffer.m — significance flag 缓冲区。
%
% 对应 C 参考实现：libjxs/src/sigbuffer.c
%
% 解码时先把某个 precinct 的 significance flags 读出来，
% 后续解 GCLI residual 时再查这个缓冲区判断哪些 group 需要真正读取。
% used to skip zero-valued groups during entropy decoding.
%
% Indexed by (ypos, band) → cell index → int8 vector.

classdef sigbuffer < handle
    properties
        sig_values      % {1 x n_lines} int8 vectors — significance flags
        sig_preds       % {1 x n_lines} int8 vectors — predictor values
        widths          % {1 x n_lines} int32 scalars — GCLI width per line
        idx_from_level  % [MAX_PRECINCT_HEIGHT x MAX_NBANDS] mapping
        n_lines int32   % Total number of band-lines in the precinct
    end

    methods
        function obj = sigbuffer(prec)
            % SIGBUFFER  Allocate significance buffers matching precinct geometry.
            %
            %   C reference: sigbuffer_open()  (sigbuffer.c:12)
            obj.n_lines = prec.ids.npi;
            n_bands = prec.bands_count();
            obj.sig_values = cell(1, obj.n_lines);
            obj.sig_preds = cell(1, obj.n_lines);
            obj.widths = cell(1, obj.n_lines);
            obj.idx_from_level = zeros(4, 79, 'int32');
            idx = int32(1);
            for lvl = int32(0):(n_bands - 1)
                height = prec.in_band_height_of(lvl);
                for ypos = int32(0):(height - 1)
                    w = prec.gcli_width_of(lvl);
                    % sig_values/sig_preds 都按“每条 band-line 一个向量”保存，
                    % 与 packing/unpacking 逐行处理 GCLI 的方式保持一致。
                    obj.sig_values{idx} = zeros(w, 1, 'int8');
                    obj.sig_preds{idx} = zeros(w, 1, 'int8');
                    obj.widths{idx} = w;
                    obj.idx_from_level(ypos + 1, lvl + 1) = idx;
                    idx = idx + 1;
                end
            end
        end

        function v = values(obj, lvl, ypos)
            % VALUES  Get significance flags for (lvl, ypos).
            %   lvl and ypos are 0-based (C convention).
            idx = obj.idx_from_level(ypos + 1, lvl + 1);
            % 返回的是该行“逐 group/逐元素展开后”的 significance 向量。
            v = obj.sig_values{idx};
        end

        function p = predictors(obj, lvl, ypos)
            % PREDICTORS  Get predictor values for (lvl, ypos).
            idx = obj.idx_from_level(ypos + 1, lvl + 1);
            p = obj.sig_preds{idx};
        end

        function w = width(obj, lvl, ypos)
            % WIDTH  Get GCLI width for (lvl, ypos).
            idx = obj.idx_from_level(ypos + 1, lvl + 1);
            w = obj.widths{idx};
        end
    end
end
