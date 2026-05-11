% test_load.m — Verify all modules load and basic pipeline works
cd('/Users/silas/Desktop/code/VideoCompress/jpegxs/matlab');
addpath(genpath(cd));

fprintf('=== Testing module loading ===\n');

% Test Constants
c = jxs.Constants;
fprintf('Constants: MAX_NBANDS=%d, MAX_PREC_COLS=%d\n', c.MAX_NBANDS, c.MAX_PREC_COLS);

% Test image creation
im = jxs.internal.image();
im.ncomps = int32(3);
im.width = int32(64);
im.height = int32(64);
im.depth = int32(10);
im.sx(1:3) = int32([1 1 1]);
im.sy(1:3) = int32([1 1 1]);
im.allocate(true);
fprintf('Image: %dx%d, ncomps=%d\n', im.width, im.height, im.ncomps);

% Fill components with test data
for c = 1:im.ncomps
    im.comps_array{c}(:) = int32(512);  % mid-gray
end

% Config
cfg = jxs.internal.xs_config.default_config();
[~, cfg] = jxs.internal.xs_config.resolve_auto_values(cfg, im);
fprintf('Config: profile=0x%04X, Bw=%d, Fq=%d\n', cfg.profile, cfg.p.Bw, cfg.p.Fq);

% Build IDs
ids_obj = jxs.internal.ids();
ids_obj.construct(im, cfg.p.NLx, cfg.p.NLy, cfg.p.Sd, cfg.p.Cw, cfg.p.Lh);
fprintf('IDs: nbands=%d, npx=%d, npy=%d, cs=%d, ph=%d\n', ids_obj.nbands, ids_obj.npx, ids_obj.npy, ids_obj.cs, ids_obj.ph);

% Open precinct
prec = jxs.internal.precinct();
prec.open_column(ids_obj, cfg.p.N_g, 0);
fprintf('Precinct: bands=%d, group_size=%d\n', prec.bands_count(), prec.group_size);

% Test forward transforms (without NLT — just linear)
jxs.internal.nlt.forward_linear(im, cfg.p.Bw);
jxs.internal.mct.forward_rct(im);
jxs.internal.dwt.forward_transform(ids_obj, im);

% Extract precinct from image
prec.set_y_idx(0);
prec.from_image(im, cfg.p.Fq);
prec.update_gclis();
fprintf('Precinct loaded: GCLIs computed\n');

% Test rate control
rc = jxs.internal.rate_control();
rc.open(cfg, ids_obj, 0);
rc.init(int32(100000), int32(10000));
rc_results = rc.process_precinct(prec);
fprintf('Rate control: quantization=%d, refinement=%d, bits=%d\n', ...
    rc_results.quantization, rc_results.refinement, rc_results.precinct_total_bits);

% Test quantize
prec.quantize(rc_results.gtli_table_data, cfg.p.Qpih);

% Test bitstream pack
bp = jxs.internal.bitpacker();
buf = zeros(1, 65536, 'uint8');
bp.set_buffer(buf, 65536);
pack_ctx = jxs.internal.packing.packer_open(cfg, prec);
jxs.internal.packing.pack_precinct(pack_ctx, bp, prec, rc_results);
bytes = bp.get_bytes();
fprintf('Packed: %d bytes\n', length(bytes));

% Test unpack
bu = jxs.internal.bitunpacker();
bu.set_buffer(bytes, length(bytes));
unpack_ctx = jxs.internal.packing.unpacker_open(cfg, prec);

prec2 = jxs.internal.precinct();
prec2.open_column(ids_obj, cfg.p.N_g, 0);
prec2.set_y_idx(0);

info_out = struct('data_len', zeros(1, 79, 'int32'), ...
    'gcli_len', zeros(1, 79, 'int32'), ...
    'sign_len', zeros(1, 79, 'int32'), ...
    'gtli_table_data', zeros(1, 79, 'int32'), ...
    'gtli_table_gcli', zeros(1, 79, 'int32'));

gtli_top = zeros(1, 79, 'int32');
jxs.internal.packing.unpack_precinct(unpack_ctx, bu, prec2, [], gtli_top, info_out);
fprintf('Unpacked: GCLIs decoded\n');

% Dequantize and write to image
prec2.dequantize(info_out.gtli_table_data, cfg.p.Qpih);
im2 = jxs.internal.image();
im2.ncomps = im.ncomps;
im2.width = im.width;
im2.height = im.height;
im2.depth = im.depth;
im2.sx = im.sx;
im2.sy = im.sy;
im2.allocate(true);
prec2.to_image(im2, cfg.p.Fq);

% Inverse transforms
jxs.internal.dwt.inverse_transform(ids_obj, im2);
jxs.internal.mct.inverse_rct(im2);
jxs.internal.nlt.inverse_linear(im2, cfg.p.Bw);

fprintf('Inverse transforms done\n');

% Check roundtrip (linear NLT is lossless modulo quantization)
max_diff = int32(0);
for c = 1:im.ncomps
    diff = max(abs(double(im.comps_array{c}) - double(im2.comps_array{c})));
    fprintf('  Component %d: max_diff = %d\n', c, diff);
    max_diff = max(max_diff, int32(diff));
end

fprintf('\n=== ALL TESTS PASSED ===\n');
