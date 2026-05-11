% test_bitpacker.m — Unit tests for bitpacker/bitunpacker bit-exactness
% Tests: basic write/read, all 3 unary alphabets, bounded codes, alignment, padding

function all_pass = test_bitpacker()
    all_pass = true;
    import jxs.Constants;

    fprintf('=== Testing bitpacker/bitunpacker ===\n');

    % Test 1: Basic write/read roundtrip
    passed = test_basic_write_read();
    all_pass = all_pass && passed;
    fprintf('  Basic write/read: %s\n', ternary(passed, 'PASS', 'FAIL'));

    % Test 2: Cross-word boundary write/read
    passed = test_cross_boundary();
    all_pass = all_pass && passed;
    fprintf('  Cross-word boundary: %s\n', ternary(passed, 'PASS', 'FAIL'));

    % Test 3: Unary alphabet 0 signed roundtrip
    passed = test_unary_alphabet_0();
    all_pass = all_pass && passed;
    fprintf('  Unary alphabet 0: %s\n', ternary(passed, 'PASS', 'FAIL'));

    % Test 4: Unary alphabet 4-clipped signed roundtrip
    passed = test_unary_alphabet_4_clipped();
    all_pass = all_pass && passed;
    fprintf('  Unary alphabet 4-clipped: %s\n', ternary(passed, 'PASS', 'FAIL'));

    % Test 5: Unary alphabet full signed roundtrip
    passed = test_unary_alphabet_full();
    all_pass = all_pass && passed;
    fprintf('  Unary alphabet full: %s\n', ternary(passed, 'PASS', 'FAIL'));

    % Test 6: Unary unsigned roundtrip
    passed = test_unary_unsigned();
    all_pass = all_pass && passed;
    fprintf('  Unary unsigned: %s\n', ternary(passed, 'PASS', 'FAIL'));

    % Test 7: Bounded code roundtrip
    passed = test_bounded_code();
    all_pass = all_pass && passed;
    fprintf('  Bounded code: %s\n', ternary(passed, 'PASS', 'FAIL'));

    % Test 8: Alignment
    passed = test_alignment();
    all_pass = all_pass && passed;
    fprintf('  Alignment: %s\n', ternary(passed, 'PASS', 'FAIL'));

    % Test 9: Padding
    passed = test_padding();
    all_pass = all_pass && passed;
    fprintf('  Padding: %s\n', ternary(passed, 'PASS', 'FAIL'));

    % Test 10: Skip and rewind
    passed = test_skip_rewind();
    all_pass = all_pass && passed;
    fprintf('  Skip/Rewind: %s\n', ternary(passed, 'PASS', 'FAIL'));

    % Test 11: Flush and get_bytes
    passed = test_flush_bytes();
    all_pass = all_pass && passed;
    fprintf('  Flush/get_bytes: %s\n', ternary(passed, 'PASS', 'FAIL'));

    fprintf('=== Overall: %s ===\n', ternary(all_pass, 'ALL PASS', 'SOME FAILED'));
end

function s = ternary(cond, t, f)
    if cond, s = t; else, s = f; end
end

function pass = test_basic_write_read()
    import jxs.internal.bitpacker;
    import jxs.internal.bitunpacker;

    buf_size = 1024;
    buf = zeros(1, buf_size, 'uint8');

    p = bitpacker();
    p.set_buffer(buf, buf_size);

    % Write some values
    p.write(uint64(0xAB), 8);
    p.write(uint64(0xCD), 8);
    p.write(uint64(0x1234), 16);

    bytes = p.get_bytes();

    u = bitunpacker();
    u.set_buffer(bytes, length(bytes));

    [v1, ~] = u.read_val(8);
    [v2, ~] = u.read_val(8);
    [v3, ~] = u.read_val(16);

    pass = (v1 == 0xAB) && (v2 == 0xCD) && (v3 == 0x1234);
end

function pass = test_cross_boundary()
    import jxs.internal.bitpacker;
    import jxs.internal.bitunpacker;

    buf_size = 1024;
    buf = zeros(1, buf_size, 'uint8');

    p = bitpacker();
    p.set_buffer(buf, buf_size);

    % Write values that cross the 64-bit boundary
    values = uint64([0xDEADBEEFCAFEBABE, 0x0123456789ABCDEF, 0xFEEDFACEDEADBEEF]);
    mask48 = uint64(hex2dec('FFFFFFFFFFFF'));
    total_bits = 0;
    for i = 1:length(values)
        p.write(values(i), 48);
        total_bits = total_bits + 48;
    end

    bytes = p.get_bytes();

    u = bitunpacker();
    u.set_buffer(bytes, length(bytes));

    for i = 1:length(values)
        [v, ~] = u.read_val(48);
        if v ~= bitand(values(i), mask48)
            pass = false;
            return;
        end
    end
    pass = true;
end

function pass = test_unary_alphabet_0()
    import jxs.internal.bitpacker;
    import jxs.internal.bitunpacker;
    import jxs.Constants;

    buf_size = 4096;
    buf = zeros(1, buf_size, 'uint8');

    p = bitpacker();
    p.set_buffer(buf, buf_size);

    % Test all values in range [-15, 15]
    test_vals = int8(-15:15);
    for i = 1:length(test_vals)
        p.write_unary_signed(test_vals(i), Constants.UNARY_ALPHABET_0);
    end

    bytes = p.get_bytes();

    u = bitunpacker();
    u.set_buffer(bytes, length(bytes));

    for i = 1:length(test_vals)
        [v, ~] = u.read_unary_signed_val(Constants.UNARY_ALPHABET_0);
        if v ~= test_vals(i)
            fprintf('    Mismatch at %d: wrote %d, read %d\n', i, test_vals(i), v);
            pass = false;
            return;
        end
    end
    pass = true;
end

function pass = test_unary_alphabet_4_clipped()
    import jxs.internal.bitpacker;
    import jxs.internal.bitunpacker;
    import jxs.Constants;

    buf_size = 4096;
    buf = zeros(1, buf_size, 'uint8');

    p = bitpacker();
    p.set_buffer(buf, buf_size);

    test_vals = int8(-13:13);
    for i = 1:length(test_vals)
        p.write_unary_signed(test_vals(i), Constants.UNARY_ALPHABET_4_CLIPPED);
    end

    bytes = p.get_bytes();

    u = bitunpacker();
    u.set_buffer(bytes, length(bytes));

    for i = 1:length(test_vals)
        [v, ~] = u.read_unary_signed_val(Constants.UNARY_ALPHABET_4_CLIPPED);
        if v ~= test_vals(i)
            fprintf('    Mismatch at %d: wrote %d, read %d\n', i, test_vals(i), v);
            pass = false;
            return;
        end
    end
    pass = true;
end

function pass = test_unary_alphabet_full()
    import jxs.internal.bitpacker;
    import jxs.internal.bitunpacker;
    import jxs.Constants;

    buf_size = 4096;
    buf = zeros(1, buf_size, 'uint8');

    p = bitpacker();
    p.set_buffer(buf, buf_size);

    % libjxs decodes the final codeword to -15, so the full alphabet is not
    % a strict roundtrip for +15. Match the C reference behavior here.
    test_vals = int8(-15:15);
    expected_vals = test_vals;
    expected_vals(end) = int8(-15);
    for i = 1:length(test_vals)
        p.write_unary_signed(test_vals(i), Constants.UNARY_ALPHABET_FULL);
    end

    bytes = p.get_bytes();

    u = bitunpacker();
    u.set_buffer(bytes, length(bytes));

    for i = 1:length(test_vals)
        [v, ~] = u.read_unary_signed_val(Constants.UNARY_ALPHABET_FULL);
        if v ~= expected_vals(i)
            fprintf('    Mismatch at %d: wrote %d, expected %d, read %d\n', i, test_vals(i), expected_vals(i), v);
            pass = false;
            return;
        end
    end
    pass = true;
end

function pass = test_unary_unsigned()
    import jxs.internal.bitpacker;
    import jxs.internal.bitunpacker;

    buf_size = 4096;
    buf = zeros(1, buf_size, 'uint8');

    p = bitpacker();
    p.set_buffer(buf, buf_size);

    test_vals = int8(0:15);
    for i = 1:length(test_vals)
        p.write_unary_unsigned(test_vals(i));
    end

    bytes = p.get_bytes();

    u = bitunpacker();
    u.set_buffer(bytes, length(bytes));

    for i = 1:length(test_vals)
        [v, ~] = u.read_unary_unsigned_val();
        if v ~= test_vals(i)
            fprintf('    Mismatch at %d: wrote %d, read %d\n', i, test_vals(i), v);
            pass = false;
            return;
        end
    end
    pass = true;
end

function pass = test_bounded_code()
    import jxs.internal.bitpacker;
    import jxs.internal.bitunpacker;
    import jxs.Constants;

    % Test bounded_code_get_min_max
    [mn, mx] = jxs.internal.bitpacker.bounded_code_get_min_max(3, 0);
    pass = (mn == -3) && (mx == 12);
    if ~pass
        fprintf('    get_min_max(3,0) = [%d,%d], expected [-3,12]\n', mn, mx);
        return;
    end

    % Test bounded_code_get_unary_code encoding
    code1 = jxs.internal.bitpacker.bounded_code_get_unary_code(int8(-2), int8(-3), int8(12));
    pass = (code1 == 3);  % 2*2 - 1 = 3
    if ~pass
        fprintf('    get_unary_code(-2, -3, 12) = %d, expected 3\n', code1);
        return;
    end

    code2 = jxs.internal.bitpacker.bounded_code_get_unary_code(int8(5), int8(-3), int8(12));
    pass = (code2 == 8);  % trigger(3) + 5 = 8
    if ~pass
        fprintf('    get_unary_code(5, -3, 12) = %d, expected 8\n', code2);
        return;
    end

    % Test read_bounded_code roundtrip
    buf_size = 4096;
    buf = zeros(1, buf_size, 'uint8');

    p = bitpacker();
    p.set_buffer(buf, buf_size);

    % Write a sequence of bounded codes
    [mn, mx] = jxs.internal.bitpacker.bounded_code_get_min_max(5, 2);
    test_vals = int8([-3, 0, 2, 5, 8, -1, 10]);
    codes_to_write = zeros(1, length(test_vals));
    for i = 1:length(test_vals)
        codes_to_write(i) = jxs.internal.bitpacker.bounded_code_get_unary_code(test_vals(i), mn, mx);
        p.write_unary_unsigned(int8(codes_to_write(i)));
    end

    bytes = p.get_bytes();

    u = bitunpacker();
    u.set_buffer(bytes, length(bytes));

    for i = 1:length(test_vals)
        [v, ~] = u.read_bounded_code_val(mn, mx);
        if v ~= test_vals(i)
            fprintf('    Bounded code mismatch at %d: wrote %d, read %d\n', i, test_vals(i), v);
            pass = false;
            return;
        end
    end
    pass = true;
end

function pass = test_alignment()
    import jxs.internal.bitpacker;
    import jxs.internal.bitunpacker;

    buf_size = 1024;
    buf = zeros(1, buf_size, 'uint8');

    p = bitpacker();
    p.set_buffer(buf, buf_size);

    % Write non-aligned bits, then align
    p.write(uint64(0xFF), 4);  % 4 bits
    p.align(8);                 % align to byte

    % After alignment, should be at bit 8
    len = p.get_len();
    pass = (len == 8);
    if ~pass
        fprintf('    Expected len=8 after align, got %d\n', len);
        return;
    end

    bytes = p.get_bytes();

    u = bitunpacker();
    u.set_buffer(bytes, length(bytes));

    [v, ~] = u.read_val(4);
    pass = (v == 0xF);
    if ~pass, return; end

    u.align(8);
    pass = true;
end

function pass = test_padding()
    import jxs.internal.bitpacker;

    buf_size = 1024;
    buf = zeros(1, buf_size, 'uint8');

    p = bitpacker();
    p.set_buffer(buf, buf_size);

    p.write(uint64(0xFF), 8);
    p.add_padding(128);  % add 128 zero bits

    len = p.get_len();
    pass = (len == 136);  % 8 + 128
    if ~pass
        fprintf('    Expected len=136 after padding, got %d\n', len);
    end
end

function pass = test_skip_rewind()
    import jxs.internal.bitpacker;
    import jxs.internal.bitunpacker;

    buf_size = 1024;
    buf = zeros(1, buf_size, 'uint8');

    p = bitpacker();
    p.set_buffer(buf, buf_size);
    p.write(uint64(0xABCDEF0123456789), 64);
    p.write(uint64(0xDEADBEEFCAFEBABE), 64);
    bytes = p.get_bytes();

    u = bitunpacker();
    u.set_buffer(bytes, length(bytes));

    [v1, ~] = u.read_val(16);
    u.skip(32);
    [v2, ~] = u.read_val(16);
    u.rewind(64);
    [v1b, ~] = u.read_val(64);

    pass = (v1 == bitshift(uint64(0xABCDEF0123456789), -48)) && ...
           (v1b == uint64(0xABCDEF0123456789));
end

function pass = test_flush_bytes()
    import jxs.internal.bitpacker;

    buf_size = 1024;
    buf = zeros(1, buf_size, 'uint8');

    p = bitpacker();
    p.set_buffer(buf, buf_size);

    % Write exactly 64 bits = 8 bytes
    p.write(uint64(0x0102030405060708), 64);
    bytes = p.get_bytes();

    % The byte array should be exactly 8 bytes with the value in big-endian
    pass = (length(bytes) == 8);
    if ~pass
        fprintf('    Expected 8 bytes, got %d\n', length(bytes));
        return;
    end

    % Read back as big-endian uint64
    expected = uint64(0x0102030405060708);
    actual = swapbytes(typecast(bytes, 'uint64'));
    pass = (actual == expected);
    if ~pass
        fprintf('    Expected 0x%016x, got 0x%016x\n', expected, actual);
    end
end
