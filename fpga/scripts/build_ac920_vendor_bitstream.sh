#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FPGA_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_DIR="$(cd "${FPGA_DIR}/.." && pwd)"

PROJECT="${AC920_PROJECT:-${FPGA_DIR}/build/ac920_vendor_sdr/CM3432_DualChannel_TCP.xpr}"
VIVADO_BIN="${VIVADO:-vivado}"
JOBS="${VIVADO_JOBS:-1}"

if [[ ! -f "${PROJECT}" ]]; then
  echo "Vivado project not found: ${PROJECT}" >&2
  exit 1
fi

if ! command -v "${VIVADO_BIN}" >/dev/null 2>&1; then
  echo "Vivado not found: ${VIVADO_BIN}" >&2
  exit 1
fi

BUILD_DIR="$(cd "$(dirname "${PROJECT}")" && pwd)"
VIVADO_LOG="${BUILD_DIR}/ac920_bitstream_vivado.log"
VIVADO_JOURNAL="${BUILD_DIR}/ac920_bitstream_vivado.jou"

export AC920_PROJECT="${PROJECT}"
export SDR_REPO_DIR="${REPO_DIR}"
export VIVADO_JOBS="${JOBS}"
export PWD="${REPO_DIR}"

(
  cd "${REPO_DIR}"
  "${VIVADO_BIN}" -mode batch -source "${SCRIPT_DIR}/vivado_ac920_build_bitstream.tcl" \
    -log "${VIVADO_LOG}" \
    -journal "${VIVADO_JOURNAL}"
)

if [[ ! -f "${VIVADO_LOG}" ]] || ! grep -q 'AC920 bitstream complete\.' "${VIVADO_LOG}"; then
  echo "Vivado did not complete bitstream generation. See log: ${VIVADO_LOG}" >&2
  exit 1
fi

echo
echo "Generated AC920 SDR bitstream:"
echo "  ${BUILD_DIR}/CM3432_DualChannel_TCP.runs/impl_1/top.bit"
