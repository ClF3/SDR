#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FPGA_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUT_DIR="${FPGA_DIR}/reports/verilator_cosim"

mkdir -p "${OUT_DIR}"

RTL_FILES=()
while IFS= read -r file; do
  RTL_FILES+=("${file}")
done < <(find "${FPGA_DIR}/rtl" -name '*.v' | sort)

verilator -Wall --cc --exe --build \
  -Wno-DECLFILENAME \
  -Wno-UNUSEDPARAM \
  -Wno-UNUSEDSIGNAL \
  -Wno-WIDTH \
  -Wno-BLKSEQ \
  --Mdir "${OUT_DIR}/obj_sdr_pl_core" \
  --top-module sdr_pl_core \
  "${RTL_FILES[@]}" \
  "${FPGA_DIR}/sim/verilator/sdr_cosim_server.cpp"

"${OUT_DIR}/obj_sdr_pl_core/Vsdr_pl_core" "$@"
