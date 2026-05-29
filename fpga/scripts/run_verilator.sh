#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FPGA_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUT_DIR="${FPGA_DIR}/reports/verilator"

mkdir -p "${OUT_DIR}"

verilator --lint-only -Wall \
  -Wno-DECLFILENAME \
  -Wno-UNUSEDPARAM \
  -Wno-UNUSEDSIGNAL \
  -Wno-WIDTH \
  -Wno-BLKSEQ \
  --top-module axis_async_fifo \
  "${FPGA_DIR}/rtl/stream/axis_async_fifo.v"

verilator -Wall --cc --exe --build \
  -Wno-DECLFILENAME \
  -Wno-UNUSEDPARAM \
  -Wno-UNUSEDSIGNAL \
  -Wno-WIDTH \
  -Wno-BLKSEQ \
  --Mdir "${OUT_DIR}/obj_axis_async_fifo" \
  --top-module axis_async_fifo \
  "${FPGA_DIR}/rtl/stream/axis_async_fifo.v" \
  "${FPGA_DIR}/sim/verilator/tb_axis_async_fifo.cpp"

"${OUT_DIR}/obj_axis_async_fifo/Vaxis_async_fifo"
