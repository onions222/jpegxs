cd('/Users/silas/Desktop/code/VideoCompress/jpegxs/matlab');
addpath(genpath(cd));

fprintf('=== Cross-boundary test ===\n');

p = jxs.internal.bitpacker();
buf = zeros(1, 1024, 'uint8');
p.set_buffer(buf, 1024);

% Write two 48-bit values
v1 = uint64(hex2dec('DEADBEEFCAFE'));
v2 = uint64(hex2dec('BABE01234567'));
% Actually use values that fit in 48 bits exactly
v1_48 = bitand(v1, bitshift(uint64(1), 48) - 1);
v2_48 = bitand(v2, bitshift(uint64(1), 48) - 1);
fprintf('v1 = 0x%012X\n', v1_48);
fprintf('v2 = 0x%012X\n', v2_48);

p.write(v1_48, 48);
fprintf('After 1st write: ptr_cur=%d, bit_offset=%d, cur=0x%016X\n', p.ptr_cur, p.bit_offset, p.cur_word);

p.write(v2_48, 48);
fprintf('After 2nd write: ptr_cur=%d, bit_offset=%d, cur=0x%016X\n', p.ptr_cur, p.bit_offset, p.cur_word);

bytes = p.get_bytes();
fprintf('Buffer bytes: [%s]\n', sprintf('%02X ', bytes));

% Read back
u = jxs.internal.bitunpacker();
u.set_buffer(bytes, length(bytes));
fprintf('Unpacker set: cur=0x%016X, bit_offset=%d\n', u.cur, u.bit_offset);

[vr1, ~] = u.read(48);
fprintf('Read 48b: 0x%012X, expected 0x%012X -> %s\n', vr1, v1_48, pasf(vr1==v1_48));

[vr2, ~] = u.read(48);
fprintf('Read 48b: 0x%012X, expected 0x%012X -> %s\n', vr2, v2_48, pasf(vr2==v2_48));

function s = pasf(cond)
    if cond, s = 'PASS'; else, s = 'FAIL'; end
end
