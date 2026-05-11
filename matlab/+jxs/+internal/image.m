% image.m — JPEG XS 图像容器。
%
% 对应 C 参考实现：libjxs/src/image.c
%
% 这里的图像不是 MATLAB 常见的 HxWxC 三维数组，而是：
%   每个分量一个平铺后的 int32 列向量
%
% 这样做的目的，是尽量贴近 C 参考实现里 xs_data_in_t* 的内存布局，
% 方便把 JPEG XS 的指针式访问逻辑一一映射过来。
% all index arithmetic (DWT strides, precinct extraction, etc.)
% translates 1:1 from the C reference.
%
% See also: jxs.Constants.MAX_NCOMPS

classdef image < handle
    properties
        ncomps int32          % Number of colour components (1–4)
        width  int32          % Image width  in pixels
        height int32          % Image height in pixels
        sx (1,:) int32        % Horizontal sub-sampling factor per component (1 or 2)
        sy (1,:) int32        % Vertical   sub-sampling factor per component (1 or 2)
        depth  int32          % Bit depth per sample (e.g. 8, 10, 12)
        comps_array cell      % {1 x ncomps} int32 column vectors — flat row-major pixel data
    end

    methods
        function obj = image()
            % IMAGE  Construct an empty image with default sub-sampling.
            import jxs.Constants;
            obj.sx = ones(1, Constants.MAX_NCOMPS, 'int32');
            obj.sy = ones(1, Constants.MAX_NCOMPS, 'int32');
            obj.comps_array = cell(1, Constants.MAX_NCOMPS);
        end

        function ok = allocate(obj, set_zero)
            % ALLOCATE  Reserve sample buffers for every component.
            %   ok = allocate(SET_ZERO) allocates flat int32 vectors sized
            %   (width/sx) * (height/sy) for each component.  SET_ZERO is
            %   accepted for API compatibility with the C reference but both
            %   branches currently zero-fill.
            %
            %   C reference: xs_allocate_image()  (image.c:30)
            for c = 1:obj.ncomps
                assert(isempty(obj.comps_array{c}), 'component already allocated');
                assert(obj.sx(c) == 1 || obj.sx(c) == 2);
                assert(obj.sy(c) == 1 || obj.sy(c) == 2);
                % 每个分量自己的采样平面尺寸是 (width/sx) x (height/sy)。
                % 例如 4:2:2 / 4:2:0 时，色度分量会比亮度分量更小。
                sample_count = int64(obj.width / obj.sx(c)) * int64(obj.height / obj.sy(c));
                if set_zero
                    obj.comps_array{c} = zeros(sample_count, 1, 'int32');
                else
                    obj.comps_array{c} = zeros(sample_count, 1, 'int32');
                end
            end
            ok = true;
        end

        function free(obj)
            % FREE  Release all component buffers.
            %
            %   C reference: xs_free_image()  (image.c:56)
            for c = 1:obj.ncomps
                % 这里直接清空 cell 内容即可，MATLAB 会自行回收底层数组。
                obj.comps_array{c} = [];
            end
        end
    end
end
