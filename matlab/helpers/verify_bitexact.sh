#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
preset="${1:-input}"

c_bin_dir="${repo_root}/.build/debug/bin"

case "${preset}" in
  input)
    input_ppm="${repo_root}/samples/input.ppm"
    c_config='profile=Main444.12;size=1103754'
    c_encode_jxs="/private/tmp/c_encoder_output_size1103754_verify.jxs"
    c_encode_ppm="/private/tmp/c_encoder_output_size1103754_verify.ppm"
    matlab_jxs="${repo_root}/samples/matlab_encoder_output_size1103754.jxs"
    matlab_report="/private/tmp/matlab_verify_bitexact_report.txt"
    sample_jxs=""
    ;;
  debug_input)
    input_ppm="${repo_root}/samples/debug_input.ppm"
    c_config='profile=Main444.12;level=1k-1;sublevel=9bpp;size=4096'
    c_encode_jxs="/private/tmp/debug_input_c_4096_verify.jxs"
    c_encode_ppm="/private/tmp/debug_input_c_4096_verify.ppm"
    matlab_jxs="/private/tmp/debug_input_matlab_4096_verify.jxs"
    matlab_report="/private/tmp/matlab_verify_bitexact_debug_input_report.txt"
    sample_jxs="${repo_root}/samples/debug_output.jxs"
    ;;
  *)
    echo "Unknown preset: ${preset}" >&2
    echo "Usage: $0 [input|debug_input]" >&2
    exit 2
    ;;
esac

echo "[1/5] Building C reference binaries"
cmake --build "${repo_root}/.build/debug" -j4

echo "[2/5] Generating fresh C reference outputs for preset=${preset}"
"${c_bin_dir}/jxs_encoder" -c "${c_config}" "${input_ppm}" "${c_encode_jxs}"
"${c_bin_dir}/jxs_decoder" "${c_encode_jxs}" "${c_encode_ppm}"
if [[ -n "${sample_jxs}" ]]; then
  cmp -s "${sample_jxs}" "${c_encode_jxs}"
fi

echo "[3/5] Running MATLAB verification flow"
matlab -batch "try; cd('${repo_root}/matlab/tests'); verify_bitexact('${preset}'); exit(0); catch ME; disp(getReport(ME, 'extended')); exit(1); end"

echo "[4/5] Comparing MATLAB outputs against C reference"
cmp -s "${matlab_jxs}" "${c_encode_jxs}"
rg -q "VERIFY_BITEXACT_OK" "${matlab_report}"

echo "[5/5] SHA1 summary"
shasum \
    "${matlab_jxs}" \
    "${c_encode_jxs}" \
    "${c_encode_ppm}"
if [[ -n "${sample_jxs}" ]]; then
  shasum "${sample_jxs}"
fi

echo "BIT-EXACT VERIFIED"
echo "  preset: ${preset}"
echo "  MATLAB report: ${matlab_report}"
