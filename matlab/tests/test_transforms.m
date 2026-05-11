% test_transforms.m — Verify NLT → MCT → DWT roundtrip is bit-exact
cd('/Users/silas/Desktop/code/VideoCompress/jpegxs/matlab');
addpath(genpath(cd));
import jxs.*;
import jxs.internal.*;

fprintf('=== Transform Roundtrip Tests ===\n');

% Create small test image
w = int32(16); h = int32(16);
im = image();
im.ncomps = int32(3); im.width = w; im.height = h; im.depth = int32(10);
im.sx(1:3) = int32([1 1 1]); im.sy(1:3) = int32([1 1 1]);
im.allocate(true);

% Fill with test pattern
for c = 1:im.ncomps
    for y = 0:(h-1)
        for x = 0:(w-1)
            idx = y * w + x + 1;
            im.comps_array{c}(idx) = int32(mod((x + y * 13 + c * 37) * 17, 512));
        end
    end
end

im_orig = cell(1, im.ncomps);
for c = 1:im.ncomps
    im_orig{c} = im.comps_array{c};
end

cfg = xs_config.default_config();
[~, cfg] = xs_config.resolve_auto_values(cfg, im);
Bw = int32(cfg.p.Bw);

% Forward transforms
fprintf('Forward NLT (linear, Bw=%d) ... ', Bw);
nlt.forward_linear(im, Bw);
fprintf('done\n');

fprintf('Forward RCT ... ');
mct.forward_rct(im);
fprintf('done\n');

ids_obj = ids();
ids_obj.construct(im, cfg.p.NLx, cfg.p.NLy, cfg.p.Sd, cfg.p.Cw, cfg.p.Lh);
fprintf('Forward DWT (NLx=%d, NLy=%d) ... ', ids_obj.nlxy.x, ids_obj.nlxy.y);
dwt.forward_transform(ids_obj, im);
fprintf('done\n');

% Inverse transforms
fprintf('Inverse DWT ... ');
dwt.inverse_transform(ids_obj, im);
fprintf('done\n');

fprintf('Inverse RCT ... ');
mct.inverse_rct(im);
fprintf('done\n');

fprintf('Inverse NLT ... ');
nlt.inverse_linear(im, Bw);
fprintf('done\n');

% Compare
all_pass = true;
for c = 1:im.ncomps
    diff = im_orig{c} - im.comps_array{c};
    max_abs = max(abs(double(diff)));
    if max_abs > 0
        fprintf('  Component %d: MISMATCH max_diff=%d\n', c, max_abs);
        all_pass = false;
        % Show first few differences
        bad = find(diff ~= 0);
        for i = 1:min(5, length(bad))
            fprintf('    idx=%d: orig=%d, roundtrip=%d\n', bad(i), im_orig{c}(bad(i)), im.comps_array{c}(bad(i)));
        end
    else
        fprintf('  Component %d: bit-exact match\n', c);
    end
end

if all_pass
    fprintf('\n=== ALL TRANSFORMS BIT-EXACT ===\n');
else
    fprintf('\n=== SOME MISMATCHES DETECTED ===\n');
end
