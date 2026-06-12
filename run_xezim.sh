#!/usr/bin/env bash
# Run the RV32I SoC testbench under xezim.
# Paths are relative to this script's directory (rv32i/).
set -euo pipefail

cd "$(dirname "$0")"

XEZIM="${XEZIM:-../xezim/target/release/xezim}"

exec "$XEZIM" --simulate -s tb_soc -Irtl --max-time 200000000 \
  rtl/rv32i_pkg.sv \
  rtl/alu.sv \
  rtl/regfile.sv \
  rtl/tcm.sv \
  rtl/uart.sv \
  rtl/rv32i_core.sv \
  rtl/soc_top.sv \
  tb/tb_soc.sv \
  "$@"
