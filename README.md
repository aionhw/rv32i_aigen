# RV32I 3-stage core + 128 KB TCM + UART

Synthesizable SystemVerilog. Simulated and passing under Verilator 5.020.

## Pipeline (3 stages)
- **IF**: PC drives the instruction-side TCM address. TCM read is *registered*, so the
  fetched word lands in EX.
- **EX**: decode, regfile read, ALU, branch/jump resolution, data-address issue.
- **MEM**: data read-data returns, sub-word sign/zero extend, write-back.

Branches/jumps resolve in EX -> exactly **one bubble** on taken (the wrongly-fetched
delay slot is squashed via `ex_valid <= ~take_branch`). Single forward path MEM->EX.
Because both TCM ports are registered, a load result is stable at the start of the next
cycle, so the dependent op consumes it through that same forward path - **no load-use
stall** is needed for this memory model. No stalls anywhere; 1 instr/cycle throughput.

## Memory map
- TCM  `0x0000_0000 .. 0x0001_FFFF`  (128 KB, dual-port: I read-only, D read/byte-write)
- UART `0x1000_0000 .. 0x1000_000F`
  - `0x0` DATA   (write = TX byte; read = RX byte, clears RX_VALID)
  - `0x4` STATUS (bit0 TX_BUSY, bit1 RX_VALID, bit2 RX_OVERRUN)
  - `0x8` DIV    (clocks-per-bit)

## Files
    rtl/rv32i_pkg.sv   opcode + ALU-op localparams
    rtl/regfile.sv     32x32, 2 comb read / 1 sync write, x0=0
    rtl/alu.sv         combinational ALU
    rtl/tcm.sv         128 KB dual-port, both ports registered-read, $readmemh init
    rtl/uart.sv        8N1 MMIO UART (TX shift FSM, RX 2-FF sync + oversample)
    rtl/rv32i_core.sv  the 3-stage pipeline (full RV32I base integer)
    rtl/soc_top.sv     core + tcm + uart, address decode, UART-read alignment
    tb/tb_soc.sv       drives SoC, decodes the real uart_tx serial line, $finish on halt
    tb/tb_probe.sv     bus-probe TB (prints DATA writes; isolates CPU from serial decode)
    sim/asm.py         mini-assembler -> program.hex ("Hello, RV32I 3-stage!\n" via UART)
    sim/program.hex    prebuilt TCM image

## Build & run (Verilator)
Package must be compiled first.

    python3 sim/asm.py sim/program.hex     # regenerate the TCM image (optional)

    verilator --binary --timing \
      -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-UNOPTFLAT \
      --top-module tb_soc -Irtl \
      rtl/rv32i_pkg.sv rtl/alu.sv rtl/regfile.sv rtl/tcm.sv rtl/uart.sv \
      rtl/rv32i_core.sv rtl/soc_top.sv tb/tb_soc.sv -o sim_soc

    ./obj_dir/sim_soc

Expected output:

    Hello, RV32I 3-stage!
    [tb] CPU halted (ECALL) after 3480 cycles

## Build & run (xezim)
xezim simulates the design directly from the SystemVerilog sources (no separate
compile step). Use `-s` to select the top module:

    xezim --simulate -s tb_soc -Irtl \
      rtl/rv32i_pkg.sv rtl/alu.sv rtl/regfile.sv rtl/tcm.sv rtl/uart.sv \
      rtl/rv32i_core.sv rtl/soc_top.sv tb/tb_soc.sv

Or use the bundled helper script (paths are relative to its location; set the
`XEZIM` env var to override the binary path):

    ./run_xezim.sh

Produces the same output as Verilator (`Hello, RV32I 3-stage!` + ECALL halt).

## Notes / not implemented
CSRs, traps/interrupts, and timers are stubbed (FENCE and CSR ops decode as NOP;
ECALL/EBREAK halt the core). RESET_PC is a parameter. The demo program polls
STATUS.TX_BUSY before each byte; the UART accepts a DATA write and raises TX_BUSY on
the same store edge, so back-to-back polled writes serialize correctly.
