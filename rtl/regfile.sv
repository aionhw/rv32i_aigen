// ============================================================================
// regfile.sv : 32 x 32-bit register file
//   - two combinational read ports, one synchronous write port
//   - x0 hardwired to zero
// ============================================================================
module regfile (
  input  logic        clk,
  input  logic        we,
  input  logic [4:0]  waddr,
  input  logic [31:0] wdata,
  input  logic [4:0]  raddr1,
  input  logic [4:0]  raddr2,
  output logic [31:0] rdata1,
  output logic [31:0] rdata2
);
  logic [31:0] regs [0:31];

  // zero-initialise so simulation starts from a known state
  integer i;
  initial for (i = 0; i < 32; i = i + 1) regs[i] = 32'd0;

  always_ff @(posedge clk)
    if (we && waddr != 5'd0)
      regs[waddr] <= wdata;

  assign rdata1 = (raddr1 == 5'd0) ? 32'd0 : regs[raddr1];
  assign rdata2 = (raddr2 == 5'd0) ? 32'd0 : regs[raddr2];
endmodule
