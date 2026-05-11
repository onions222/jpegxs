% test_cross_decode.m — Decode C-generated .jxs with MATLAB
cd('/Users/silas/Desktop/code/VideoCompress/jpegxs/matlab');
addpath(genpath(cd));
import jxs.*;
import jxs.internal.*;

fprintf('=== Cross-reference: MATLAB decode C-encoded bitstream ===\n');

% Read C-encoded bitstream
fid = fopen('/tmp/test_c.jxs', 'rb');
if fid < 0, error('Cannot open /tmp/test_c.jxs'); end
bytes = fread(fid, inf, 'uint8=>uint8')';
fclose(fid);
fprintf('Read %d bytes\n', length(bytes));

% Decode with MATLAB
fprintf('Decoding...\n');
try
    im_out = jpegxs_decode(bytes);
    fprintf('Decoded: %dx%d, ncomps=%d, depth=%d\n', im_out.width, im_out.height, im_out.ncomps, im_out.depth);
catch e
    fprintf('Decode error: %s\n', e.message);
    disp(getReport(e));
end
