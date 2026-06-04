#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FPGA_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_DIR="$(cd "${FPGA_DIR}/.." && pwd)"

VENDOR_DIR="${1:-${AC920_VENDOR_DIR:-${HOME}/Downloads/AC920_CM3432_DualChannel_TCP}}"
WORK_DIR="${AC920_WORK_DIR:-${FPGA_DIR}/build/ac920_vendor_sdr}"
PROJECT_NAME="CM3432_DualChannel_TCP.xpr"
VIVADO_BIN="${VIVADO:-vivado}"

if [[ ! -f "${VENDOR_DIR}/${PROJECT_NAME}" ]]; then
  echo "Vendor project not found: ${VENDOR_DIR}/${PROJECT_NAME}" >&2
  echo "Usage: $0 /path/to/AC920_CM3432_DualChannel_TCP" >&2
  exit 1
fi

if ! command -v "${VIVADO_BIN}" >/dev/null 2>&1; then
  echo "Vivado not found: ${VIVADO_BIN}" >&2
  echo "Run this from a Vivado shell, source settings64.sh, or set VIVADO=/path/to/vivado." >&2
  exit 1
fi

mkdir -p "$(dirname "${WORK_DIR}")"
rm -rf "${WORK_DIR}"
rsync -a --exclude '.DS_Store' "${VENDOR_DIR}/" "${WORK_DIR}/"

PATCHED_ADC_CTRL="${FPGA_DIR}/rtl/vendor/acfl3432/ACFL3432_ctrl.v"
VENDOR_ADC_CTRL="${WORK_DIR}/CM3432_DualChannel_TCP.srcs/sources_1/new/3432/ACFL3432_ctrl.v"
if [[ -f "${PATCHED_ADC_CTRL}" ]]; then
  if [[ ! -d "$(dirname "${VENDOR_ADC_CTRL}")" ]]; then
    echo "Copied vendor project is missing the ACFL3432 source directory: $(dirname "${VENDOR_ADC_CTRL}")" >&2
    exit 1
  fi
  cp "${PATCHED_ADC_CTRL}" "${VENDOR_ADC_CTRL}"
  echo "Applied patched ACFL3432_ctrl.v:"
  echo "  ${VENDOR_ADC_CTRL}"
fi

export AC920_PROJECT="${WORK_DIR}/${PROJECT_NAME}"
export SDR_REPO_DIR="${REPO_DIR}"
export PWD="${REPO_DIR}"

VIVADO_LOG="${WORK_DIR}/ac920_overlay_vivado.log"
VIVADO_JOURNAL="${WORK_DIR}/ac920_overlay_vivado.jou"

(
  cd "${REPO_DIR}"
  "${VIVADO_BIN}" -mode batch -source "${SCRIPT_DIR}/vivado_ac920_vendor_overlay.tcl" \
    -log "${VIVADO_LOG}" \
    -journal "${VIVADO_JOURNAL}"
)

if [[ ! -f "${VIVADO_LOG}" ]] || ! grep -q 'AC920 vendor overlay complete\.' "${VIVADO_LOG}"; then
  echo "Vivado did not complete the AC920 overlay. See log: ${VIVADO_LOG}" >&2
  exit 1
fi

echo
echo "Prepared AC920 SDR Vivado project:"
echo "  ${AC920_PROJECT}"
echo
echo "Open it with:"
echo "  vivado ${AC920_PROJECT}"
