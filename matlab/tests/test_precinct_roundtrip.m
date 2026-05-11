% test_precinct_roundtrip.m — Verify precinct from/to image and pack/unpack
cd('/Users/silas/Desktop/code/VideoCompress/jpegxs/matlab');
addpath(genpath(cd));
import jxs.*;
import jxs.internal.*;

fprintf('=== Precinct & Packing Roundtrip Tests ===\n');

w = int32(16); h = int32(16);
im = image();
im.ncomps = int32(3); im.width = w; im.height = h; im.depth = int32(10);
im.sx(1:3) = int32([1 1 1]); im.sy(1:3) = int32([1 1 1]);
im.allocate(true);
for c = 1:im.ncomps
    for y = 0:(h-1)
        for x = 0:(w-1)
            idx = y * w + x + 1;
            im.comps_array{c}(idx) = int32(mod((x + y*13 + c*37)*17, 512));
        end
    end
end

% Transform
cfg = xs_config.default_config();
[~, cfg] = xs_config.resolve_auto_values(cfg, im);
nlt.forward_linear(im, cfg.p.Bw);
mct.forward_rct(im);
ids_obj = ids();
ids_obj.construct(im, cfg.p.NLx, cfg.p.NLy, cfg.p.Sd, cfg.p.Cw, cfg.p.Lh);
dwt.forward_transform(ids_obj, im);

% Save transformed image
im_xform = cell(1, im.ncomps);
for c = 1:im.ncomps
    im_xform{c} = im.comps_array{c};
end

% Extract precinct
prec = precinct();
prec.open_column(ids_obj, cfg.p.N_g, 0);
prec.set_y_idx(0);
prec.from_image(im, cfg.p.Fq);
prec.update_gclis();

% Check GCLI values
fprintf('GCLIs computed for %d bands\n', prec.bands_count());

% Quantize with gtli=0 (lossless)
gtli = zeros(1, prec.bands_count(), 'int32');
prec.quantize(gtli, cfg.p.Qpih);

% Write back to image
im2 = image();
im2.ncomps = im.ncomps; im2.width = w; im2.height = h; im2.depth = im.depth;
im2.sx = im.sx; im2.sy = im.sy;
im2.allocate(true);
prec.to_image(im2, cfg.p.Fq);

% Check precinct roundtrip (quantized domain)
for c = 1:im.ncomps
    diff = double(im_xform{c}) - double(im2.comps_array{c});
    max_abs = max(abs(diff(:)));
    if max_abs > 0
        nz = sum(diff(:) ~= 0);
        fprintf('  Component %d: precinct RT max_diff=%d (%d non-zero)\n', c, max_abs, nz);
    else
        fprintf('  Component %d: precinct RT bit-exact\n', c);
    end
end

% Test pack/unpack roundtrip
fprintf('\n--- Pack/Unpack roundtrip ---\n');
bp = bitpacker();
buf = zeros(1, 65536, 'uint8');
bp.set_buffer(buf, 65536);

% Create simple rc_results for packing
rc = rate_control();
rc.open(cfg, ids_obj, 0);
rc.init(int32(100000), int32(10000));
rc_results = rc.process_precinct(prec);

pack_ctx = packing.packer_open(cfg, prec);
packing.pack_precinct(pack_ctx, bp, prec, rc_results);
packed_bytes = bp.get_bytes();
fprintf('Packed %d bytes\n', length(packed_bytes));

% Unpack
bu = bitunpacker();
bu.set_buffer(packed_bytes, length(packed_bytes));
unpack_ctx = packing.unpacker_open(cfg, prec);
prec3 = precinct();
prec3.open_column(ids_obj, cfg.p.N_g, 0);
prec3.set_y_idx(0);

info_out = struct('data_len', zeros(1, 79, 'int32'), ...
    'gcli_len', zeros(1, 79, 'int32'), 'sign_len', zeros(1, 79, 'int32'), ...
    'gtli_table_data', zeros(1, 79, 'int32'), 'gtli_table_gcli', zeros(1, 79, 'int32'));
gtli_top = zeros(1, 79, 'int32');
[gtli_data, gtli_gcli] = packing.unpack_precinct(unpack_ctx, bu, prec3, [], gtli_top, info_out);

% Dequantize and compare
prec3.dequantize(gtli_data, cfg.p.Qpih);
im3 = image();
im3.ncomps = im.ncomps; im3.width = w; im3.height = h; im3.depth = im.depth;
im3.sx = im.sx; im3.sy = im.sy;
im3.allocate(true);
prec3.to_image(im3, cfg.p.Fq);

for c = 1:im.ncomps
    diff = double(im2.comps_array{c}) - double(im3.comps_array{c});
    max_abs = max(abs(diff(:)));
    if max_abs > 0
        fprintf('  Component %d: pack-RT max_diff=%d\n', c, max_abs);
    else
        fprintf('  Component %d: pack-RT bit-exact\n', c);
    end
end

fprintf('\n=== DONE ===\n');
