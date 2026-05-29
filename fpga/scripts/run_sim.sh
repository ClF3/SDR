#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FPGA_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUT_DIR="${FPGA_DIR}/reports/sim"

mkdir -p "${OUT_DIR}"

RTL_FILES=()
while IFS= read -r file; do
  RTL_FILES+=("${file}")
done < <(find "${FPGA_DIR}/rtl" "${FPGA_DIR}/sim/models" -name '*.v' | sort)

TBS=(
  tb_nco
  tb_adc_level_monitor
  tb_iq_packetizer
  tb_ddc_core
  tb_sdr_pl_core
)

for tb in "${TBS[@]}"; do
  echo "[SIM] ${tb}"
  iverilog -g2012 -Wall -o "${OUT_DIR}/${tb}.vvp" -s "${tb}" "${RTL_FILES[@]}" "${FPGA_DIR}/sim/tb/${tb}.v"
  vvp "${OUT_DIR}/${tb}.vvp" | tee "${OUT_DIR}/${tb}.log"
done

echo "[SIM] all testbenches passed"
