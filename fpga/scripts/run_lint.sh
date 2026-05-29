#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FPGA_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

RTL_FILES=()
while IFS= read -r file; do
  RTL_FILES+=("${file}")
done < <(find "${FPGA_DIR}/rtl" -name '*.v' | sort)

verilator --lint-only --timing -Wall \
  -Wno-DECLFILENAME \
  -Wno-UNUSEDPARAM \
  -Wno-UNUSEDSIGNAL \
  -Wno-WIDTH \
  -Wno-BLKSEQ \
  "${RTL_FILES[@]}" \
  --top-module sdr_top
