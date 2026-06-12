// ============================================================================
// uart.sv : memory-mapped 8N1 UART
//
//   Register map (word offsets within the UART region):
//     0x0  DATA    : write -> transmit a byte (low 8 bits)
//                    read  -> received byte; reading clears RX_VALID
//     0x4  STATUS  : bit0 = TX_BUSY (1 while a frame is being sent)
//                    bit1 = RX_VALID (1 when an unread byte is waiting)
//                    bit2 = RX_OVERRUN
//     0x8  DIV     : clocks-per-bit divisor (write to change baud at runtime)
//
//   Frame: 1 start bit (0), 8 data bits LSB-first, 1 stop bit (1).
//
//   TX_BUSY is asserted on the same clock edge that accepts a DATA write, so a
//   polling CPU that writes then immediately re-reads STATUS observes BUSY and
//   will not clobber the in-flight frame.
// ============================================================================
module uart #(
  parameter int CLK_FREQ = 50_000_000,
  parameter int BAUD     = 115200
)(
  input  logic        clk,
  input  logic        rst_n,
  input  logic        sel,
  input  logic [3:0]  addr,
  input  logic        we,
  input  logic [31:0] wdata,
  output logic [31:0] rdata,
  input  logic        rx,
  output logic        tx
);
  localparam int DIVW    = 16;
  localparam int DIV_RST = (CLK_FREQ / BAUD) > 0 ? (CLK_FREQ / BAUD) : 1;

  logic [DIVW-1:0] div;

  wire wr_data = sel && we && (addr[3:2] == 2'b00);   // write to DATA
  wire wr_div  = sel && we && (addr[3:2] == 2'b10);   // write to DIV
  wire rd_data = sel && !we && (addr[3:2] == 2'b00);  // read DATA (clears VALID)

  // ----------------------------------------------------------------- TX ----
  logic            tx_busy;
  logic [9:0]      tx_shift;
  logic [3:0]      tx_idx;
  logic [DIVW-1:0] tx_cnt;

  assign tx = tx_busy ? tx_shift[0] : 1'b1;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      tx_busy  <= 1'b0;
      tx_shift <= 10'h3FF;
      tx_idx   <= 4'd0;
      tx_cnt   <= '0;
    end else if (!tx_busy) begin
      if (wr_data) begin                          // accept + start in one edge
        tx_shift <= {1'b1, wdata[7:0], 1'b0};     // stop | data | start
        tx_busy  <= 1'b1;
        tx_idx   <= 4'd0;
        tx_cnt   <= div - 1'b1;
      end
    end else begin
      if (tx_cnt == 0) begin
        tx_cnt <= div - 1'b1;
        if (tx_idx == 4'd9) begin
          tx_busy <= 1'b0;
        end else begin
          tx_shift <= {1'b1, tx_shift[9:1]};
          tx_idx   <= tx_idx + 1'b1;
        end
      end else begin
        tx_cnt <= tx_cnt - 1'b1;
      end
    end
  end

  // ----------------------------------------------------------------- RX ----
  logic            rx_busy;
  logic [7:0]      rx_shift;
  logic [3:0]      rx_idx;
  logic [DIVW-1:0] rx_cnt;
  logic [7:0]      rx_data;
  logic            rx_valid;
  logic            rx_overrun;
  logic            rx_complete;

  logic rx_m, rx_s;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin rx_m <= 1'b1; rx_s <= 1'b1; end
    else        begin rx_m <= rx;   rx_s <= rx_m; end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rx_busy <= 1'b0; rx_idx <= 4'd0; rx_cnt <= '0;
      rx_shift <= 8'd0; rx_complete <= 1'b0;
    end else begin
      rx_complete <= 1'b0;
      if (!rx_busy) begin
        if (rx_s == 1'b0) begin
          rx_busy <= 1'b1; rx_idx <= 4'd0;
          rx_cnt  <= div + (div >> 1) - 1'b1;     // sample mid-bit0
        end
      end else if (rx_cnt == 0) begin
        rx_cnt   <= div - 1'b1;
        rx_shift <= {rx_s, rx_shift[7:1]};
        if (rx_idx == 4'd7) begin
          rx_busy <= 1'b0; rx_complete <= 1'b1;
        end else begin
          rx_idx <= rx_idx + 1'b1;
        end
      end else begin
        rx_cnt <= rx_cnt - 1'b1;
      end
    end
  end

  // -------------------------------------------------- config + rx status ----
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      div <= DIV_RST[DIVW-1:0]; rx_data <= 8'd0;
      rx_valid <= 1'b0; rx_overrun <= 1'b0;
    end else begin
      if (wr_div) div <= wdata[DIVW-1:0];
      if (rx_complete) begin
        rx_data <= rx_shift;
        if (rx_valid) rx_overrun <= 1'b1;
        rx_valid <= 1'b1;
      end else if (rd_data) begin
        rx_valid <= 1'b0;
      end
    end
  end

  always_comb begin
    rdata = 32'd0;
    if (sel) begin
      unique case (addr[3:2])
        2'b00: rdata = {24'd0, rx_data};
        2'b01: rdata = {29'd0, rx_overrun, rx_valid, tx_busy};
        2'b10: rdata = {{(32-DIVW){1'b0}}, div};
        default: rdata = 32'd0;
      endcase
    end
  end
endmodule
