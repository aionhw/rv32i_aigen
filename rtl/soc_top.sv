// ============================================================================
// soc_top.sv : core + 128 KB TCM + UART
//
//   Memory map:
//     0x0000_0000 .. 0x0001_FFFF : TCM  (128 KB)
//     0x1000_0000 .. 0x1000_000F : UART registers
//
//   The data side is issued in EX and consumed in MEM.  The TCM data port is
//   already registered (valid in MEM).  The UART read is combinational, so its
//   result and select are registered here to line up with the MEM stage.
// ============================================================================
module soc_top #(
  parameter string INIT_FILE = "",
  parameter int    CLK_FREQ  = 50_000_000,
  parameter int    BAUD      = 115200
)(
  input  logic clk,
  input  logic rst_n,
  input  logic uart_rx,
  output logic uart_tx,
  output logic halt
);
  localparam logic [31:0] UART_BASE = 32'h1000_0000;

  // ---- core <-> bus --------------------------------------------------------
  logic [31:0] iaddr, irdata;
  logic [31:0] daddr, dwdata, drdata;
  logic        dreq, dwe;
  logic [3:0]  dbe;

  rv32i_core u_core (
    .clk(clk), .rst_n(rst_n),
    .o_iaddr(iaddr),  .i_irdata(irdata),
    .o_daddr(daddr),  .o_dreq(dreq), .o_dwe(dwe),
    .o_dbe(dbe),      .o_dwdata(dwdata),
    .i_drdata(drdata),
    .o_halt(halt)
  );

  // ---- address decode (EX stage) ------------------------------------------
  wire sel_uart = dreq & (daddr[31:16] == UART_BASE[31:16]);
  wire sel_tcm  = dreq & ~sel_uart;

  // ---- TCM ----------------------------------------------------------------
  logic [31:0] tcm_drdata;
  tcm #(.BYTES(128*1024), .INIT_FILE(INIT_FILE)) u_tcm (
    .clk(clk),
    .i_addr(iaddr), .i_rdata(irdata),
    .d_addr(daddr), .d_we(dwe & sel_tcm), .d_be(dbe), .d_wdata(dwdata),
    .d_rdata(tcm_drdata)
  );

  // ---- UART ---------------------------------------------------------------
  logic [31:0] uart_rdata;
  uart #(.CLK_FREQ(CLK_FREQ), .BAUD(BAUD)) u_uart (
    .clk(clk), .rst_n(rst_n),
    .sel(sel_uart), .addr(daddr[3:0]), .we(dwe), .wdata(dwdata),
    .rdata(uart_rdata),
    .rx(uart_rx), .tx(uart_tx)
  );

  // ---- align bus read data to the MEM stage --------------------------------
  logic        sel_uart_m;
  logic [31:0] uart_rdata_m;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      sel_uart_m   <= 1'b0;
      uart_rdata_m <= 32'd0;
    end else begin
      sel_uart_m   <= sel_uart;
      uart_rdata_m <= uart_rdata;
    end
  end

  assign drdata = sel_uart_m ? uart_rdata_m : tcm_drdata;
endmodule
