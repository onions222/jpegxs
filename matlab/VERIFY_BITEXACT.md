# MATLAB Bit-Exact Verification

This repository uses **C reference parity** as the definition of bit-exactness.

For JPEG XS here, **bit-exact does not mean roundtrip-to-input**.
Many test cases are intentionally **lossy**, so:

- `input -> encode -> decode == input` is **not** the validation criterion
- `MATLAB == C reference` **is** the validation criterion

## Correct Criteria

A case is considered bit-exact only when all applicable checks pass:

1. MATLAB encoded codestream matches the C encoded codestream **byte-for-byte**
2. MATLAB decoding of the C codestream matches C decoding **pixel-for-pixel**
3. If a checked sample codestream is already present in `samples/`, it must also match a fresh C encode when the case expects that

For lossy profiles, `roundtrip_equals_input=0` can still be a **correct** result.

## One-Command Verification

From the repository root:

```bash
./matlab/helpers/verify_bitexact.sh input
./matlab/helpers/verify_bitexact.sh debug_input
```

## Supported Presets

### `input`

Uses:

- input: [/Users/silas/Desktop/code/VideoCompress/jpegxs/samples/input.ppm](/Users/silas/Desktop/code/VideoCompress/jpegxs/samples/input.ppm)
- config: `profile=Main444.12;size=1103754`

Checks:

- MATLAB encode vs fresh C encode
- MATLAB decode of fresh C codestream vs C decode output

### `debug_input`

Uses:

- input: [/Users/silas/Desktop/code/VideoCompress/jpegxs/samples/debug_input.ppm](/Users/silas/Desktop/code/VideoCompress/jpegxs/samples/debug_input.ppm)
- sample codestream: [/Users/silas/Desktop/code/VideoCompress/jpegxs/samples/debug_output.jxs](/Users/silas/Desktop/code/VideoCompress/jpegxs/samples/debug_output.jxs)
- config: `profile=Main444.12;level=1k-1;sublevel=9bpp;size=4096`

Checks:

- MATLAB encode vs fresh C encode
- `samples/debug_output.jxs` vs fresh C encode
- MATLAB decode of fresh C codestream vs C decode output
- MATLAB decode of `samples/debug_output.jxs` vs C decode output

Important:

- `debug_input` is a **lossy** case
- so `roundtrip_equals_input=0` is expected and does **not** indicate failure

## Output Reports

The MATLAB-side detailed reports are written to:

- `input`: [/private/tmp/matlab_verify_bitexact_report.txt](/private/tmp/matlab_verify_bitexact_report.txt)
- `debug_input`: [/private/tmp/matlab_verify_bitexact_debug_input_report.txt](/private/tmp/matlab_verify_bitexact_debug_input_report.txt)

These reports explicitly print the verification criteria so other agents do not confuse:

- “matches original input”
with
- “matches C reference”

## Common Wrong Method

The following is **not** a valid bit-exact check for lossy JPEG XS cases:

1. Encode with MATLAB
2. Decode with MATLAB or C
3. Compare decoded image directly against the original input

That only tests whether the configuration is lossless.
It does **not** test whether the MATLAB port matches the C reference implementation.
