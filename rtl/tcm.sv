// ============================================================================
// tcm.sv : 128 KB tightly-coupled memory
//   - dual port: port I = instruction read (read-only)
//                port D = data read / byte-write
//   - synchronous (registered) read on BOTH ports: address presented in
//     cycle N, read data valid in cycle N+1.  This 1-cycle latency is what
//     the core's pipeline is built around.
//   - read-first behaviour on the data port (a store does not affect the
//     value returned by a simultaneous load to the same word).
// ============================================================================
module tcm #(
  parameter int    BYTES     = 128 * 1024,
  parameter string INIT_FILE = ""
)(
  input  logic        clk,
  // instruction port (read only)
  input  logic [31:0] i_addr,
  output logic [31:0] i_rdata,
  // data port (read / byte-write)
  input  logic [31:0] d_addr,
  input  logic        d_we,
  input  logic [3:0]  d_be,
  input  logic [31:0] d_wdata,
  output logic [31:0] d_rdata
);
  localparam int WORDS = BYTES / 4;
  localparam int AW    = $clog2(WORDS);   // word-index width

  logic [31:0] mem [0:WORDS-1];

  // byte address -> word index
  wire [AW-1:0] i_idx = i_addr[AW+1:2];
  wire [AW-1:0] d_idx = d_addr[AW+1:2];

  initial begin
    integer k;
    for (k = 0; k < WORDS; k = k + 1) mem[k] = 32'd0;
    if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
  end

  // instruction read port
  always_ff @(posedge clk)
    i_rdata <= mem[i_idx];

  // data read/write port (read-first)
  always_ff @(posedge clk) begin
    d_rdata <= mem[d_idx];
    if (d_we) begin
      if (d_be[0]) mem[d_idx][ 7: 0] <= d_wdata[ 7: 0];
      if (d_be[1]) mem[d_idx][15: 8] <= d_wdata[15: 8];
      if (d_be[2]) mem[d_idx][23:16] <= d_wdata[23:16];
      if (d_be[3]) mem[d_idx][31:24] <= d_wdata[31:24];
    end
  end
endmodule
