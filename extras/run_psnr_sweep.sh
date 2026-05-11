#!/bin/bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

DEFAULT_ENCODER="${REPO_ROOT}/.build/debug/bin/jxs_encoder"
DEFAULT_DECODER="${REPO_ROOT}/.build/debug/bin/jxs_decoder"
DEFAULT_INPUT_DIR="${REPO_ROOT}/originalPics_ppm"
DEFAULT_OUTPUT_DIR="${REPO_ROOT}/results/jpegxs_psnr_$(date +%Y%m%d_%H%M%S)"

ENCODER="${DEFAULT_ENCODER}"
DECODER="${DEFAULT_DECODER}"
INPUT_DIR="${DEFAULT_INPUT_DIR}"
OUTPUT_DIR="${DEFAULT_OUTPUT_DIR}"
KEEP_INTERMEDIATES=1
EXPORT_BMP=1
EXPORT_SOURCE_BMP=1

CONFIG_NAMES=()
CONFIG_VALUES=()

print_usage() {
  cat <<EOF
Usage:
  $(basename "$0") [options]

Options:
  -i <dir>   Input directory containing .ppm files
  -o <dir>   Output directory for csv/jxs/decoded images
  -e <path>  Path to jxs_encoder
  -d <path>  Path to jxs_decoder
  -c <spec>  Add test config in the form name=xs_config
  --no-bmp   Do not export decoded images to .bmp
  --no-source-bmp
             Do not export source .ppm images to .bmp
  --no-keep  Remove generated .jxs and decoded .ppm after statistics are written
  -h         Show this help

Default configs:
  r4=profile=Main444.12;rate=4
  r6=profile=Main444.12;rate=6
  r8=profile=Main444.12;rate=8
  r10=profile=Main444.12;rate=10
  r8_psnr=profile=Main444.12;rate=8;gains=psnr
  r8_visual=profile=Main444.12;rate=8;gains=visual

When BMP export is enabled, each decoded ppm is also written to:
  <output>/<config>/bmp/<image>_roundtrip.bmp

When source BMP export is enabled, original images are also written to:
  <output>/source_bmp/<image>.bmp

Example:
  $(basename "$0") -o "${REPO_ROOT}/results/manual_run"
EOF
}

add_config() {
  local entry="$1"
  local name="${entry%%=*}"
  local value="${entry#*=}"

  if [[ -z "${name}" || "${name}" == "${value}" ]]; then
    echo "Invalid config entry: ${entry}" >&2
    exit 1
  fi

  CONFIG_NAMES+=("${name}")
  CONFIG_VALUES+=("${value}")
}

add_default_configs() {
  add_config "r4=profile=Main444.12;rate=4"
  add_config "r6=profile=Main444.12;rate=6"
  add_config "r8=profile=Main444.12;rate=8"
  add_config "r10=profile=Main444.12;rate=10"
  add_config "r8_psnr=profile=Main444.12;rate=8;gains=psnr"
  add_config "r8_visual=profile=Main444.12;rate=8;gains=visual"
}

ensure_tooling() {
  if [[ ! -x "${ENCODER}" ]]; then
    echo "Encoder not found or not executable: ${ENCODER}" >&2
    exit 1
  fi
  if [[ ! -x "${DECODER}" ]]; then
    echo "Decoder not found or not executable: ${DECODER}" >&2
    exit 1
  fi
  if ! command -v compare >/dev/null 2>&1; then
    echo "ImageMagick 'compare' command not found" >&2
    exit 1
  fi
  if [[ "${EXPORT_BMP}" -eq 1 ]] && ! command -v magick >/dev/null 2>&1; then
    echo "ImageMagick 'magick' command not found" >&2
    exit 1
  fi
  if [[ ! -d "${INPUT_DIR}" ]]; then
    echo "Input directory not found: ${INPUT_DIR}" >&2
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -i)
      INPUT_DIR="$2"
      shift 2
      ;;
    -o)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    -e)
      ENCODER="$2"
      shift 2
      ;;
    -d)
      DECODER="$2"
      shift 2
      ;;
    -c)
      add_config "$2"
      shift 2
      ;;
    --no-bmp)
      EXPORT_BMP=0
      shift
      ;;
    --no-source-bmp)
      EXPORT_SOURCE_BMP=0
      shift
      ;;
    --no-keep)
      KEEP_INTERMEDIATES=0
      shift
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      print_usage >&2
      exit 1
      ;;
  esac
done

if [[ ${#CONFIG_NAMES[@]} -eq 0 ]]; then
  add_default_configs
fi

ensure_tooling

mkdir -p "${OUTPUT_DIR}"
DETAIL_CSV="${OUTPUT_DIR}/detail.csv"
SUMMARY_CSV="${OUTPUT_DIR}/final_summary.csv"
SOURCE_BMP_DIR="${OUTPUT_DIR}/source_bmp"

printf 'config,file,orig_bytes,jxs_bytes,ratio,psnr_db\n' > "${DETAIL_CSV}"
printf 'config,count,avg_psnr,avg_psnr_excl120,min_psnr,min_file,max_psnr,max_file,avg_jxs_bytes,avg_ratio\n' > "${SUMMARY_CSV}"

shopt -s nullglob
INPUT_FILES=("${INPUT_DIR}"/*.ppm)
shopt -u nullglob

if [[ ${#INPUT_FILES[@]} -eq 0 ]]; then
  echo "No .ppm files found in ${INPUT_DIR}" >&2
  exit 1
fi

if [[ "${EXPORT_BMP}" -eq 1 && "${EXPORT_SOURCE_BMP}" -eq 1 ]]; then
  mkdir -p "${SOURCE_BMP_DIR}"
  echo "[PREP] exporting source BMP files"
  for input_file in "${INPUT_FILES[@]}"; do
    base="$(basename "${input_file}" .ppm)"
    source_bmp_file="${SOURCE_BMP_DIR}/${base}.bmp"
    if ! magick "${input_file}" "${source_bmp_file}" >/dev/null 2>&1; then
      echo "Warning: failed to export source BMP for ${base}" >&2
    fi
  done
  echo
fi

echo "Input dir : ${INPUT_DIR}"
echo "Output dir: ${OUTPUT_DIR}"
echo "Images    : ${#INPUT_FILES[@]}"
echo

for idx in "${!CONFIG_NAMES[@]}"; do
  cfg_name="${CONFIG_NAMES[$idx]}"
  cfg_value="${CONFIG_VALUES[$idx]}"
  cfg_dir="${OUTPUT_DIR}/${cfg_name}"
  jxs_dir="${cfg_dir}/jxs"
  dec_dir="${cfg_dir}/decoded"
  bmp_dir="${cfg_dir}/bmp"
  log_dir="${cfg_dir}/logs"

  mkdir -p "${jxs_dir}" "${dec_dir}" "${log_dir}"
  if [[ "${EXPORT_BMP}" -eq 1 ]]; then
    mkdir -p "${bmp_dir}"
  fi

  echo "[RUN] ${cfg_name} => ${cfg_value}"

  for input_file in "${INPUT_FILES[@]}"; do
    base="$(basename "${input_file}" .ppm)"
    jxs_file="${jxs_dir}/${base}.jxs"
    decoded_file="${dec_dir}/${base}_roundtrip.ppm"
    bmp_file="${bmp_dir}/${base}_roundtrip.bmp"
    enc_log="${log_dir}/${base}.encode.log"
    dec_log="${log_dir}/${base}.decode.log"

    if ! "${ENCODER}" -c "${cfg_value}" "${input_file}" "${jxs_file}" >"${enc_log}" 2>&1; then
      printf '%s,%s,ENCODE_FAIL,,,\n' "${cfg_name}" "${base}" >> "${DETAIL_CSV}"
      continue
    fi

    if ! "${DECODER}" "${jxs_file}" "${decoded_file}" >"${dec_log}" 2>&1; then
      printf '%s,%s,DECODE_FAIL,,,\n' "${cfg_name}" "${base}" >> "${DETAIL_CSV}"
      continue
    fi

    if [[ "${EXPORT_BMP}" -eq 1 ]]; then
      if ! magick "${decoded_file}" "${bmp_file}" >>"${dec_log}" 2>&1; then
        echo "Warning: failed to export BMP for ${cfg_name}/${base}" >&2
      fi
    fi

    orig_bytes="$(stat -f %z "${input_file}")"
    jxs_bytes="$(stat -f %z "${jxs_file}")"
    ratio="$(awk -v o="${orig_bytes}" -v c="${jxs_bytes}" 'BEGIN{printf "%.4f", o/c}')"
    psnr_raw="$(compare -metric PSNR "${input_file}" "${decoded_file}" null: 2>&1 || true)"
    psnr_db="${psnr_raw%% *}"

    printf '%s,%s,%s,%s,%s,%s\n' \
      "${cfg_name}" "${base}" "${orig_bytes}" "${jxs_bytes}" "${ratio}" "${psnr_db}" \
      >> "${DETAIL_CSV}"
  done

  awk -F, -v target="${cfg_name}" '
    $1==target && $6!="" && $6!="ENCODE_FAIL" && $6!="DECODE_FAIL" {
      sum+=$6
      sumj+=$4
      sumr+=$5
      n++
      if ($6 < 120) {
        sum2+=$6
        n2++
      }
      if (n==1 || $6<min) {
        min=$6
        minf=$2
      }
      if (n==1 || $6>max) {
        max=$6
        maxf=$2
      }
    }
    END {
      if (n > 0) {
        excl = (n2 > 0) ? sum2 / n2 : 0
        printf "%s,%d,%.4f,%.4f,%.4f,%s,%.4f,%s,%.0f,%.4f\n", \
          target, n, sum / n, excl, min, minf, max, maxf, sumj / n, sumr / n
      }
    }
  ' "${DETAIL_CSV}" >> "${SUMMARY_CSV}"

  if [[ "${KEEP_INTERMEDIATES}" -eq 0 ]]; then
    rm -rf "${jxs_dir}" "${dec_dir}" "${bmp_dir}"
  fi

  echo "[DONE] ${cfg_name}"
  echo
done

echo "Wrote:"
echo "  ${DETAIL_CSV}"
echo "  ${SUMMARY_CSV}"
if [[ "${KEEP_INTERMEDIATES}" -eq 1 ]]; then
  echo "Saved outputs under:"
  if [[ "${EXPORT_BMP}" -eq 1 && "${EXPORT_SOURCE_BMP}" -eq 1 ]]; then
    echo "  ${OUTPUT_DIR}/source_bmp"
  fi
  echo "  ${OUTPUT_DIR}/<config>/jxs"
  echo "  ${OUTPUT_DIR}/<config>/decoded"
  if [[ "${EXPORT_BMP}" -eq 1 ]]; then
    echo "  ${OUTPUT_DIR}/<config>/bmp"
  fi
fi
