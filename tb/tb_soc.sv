// ============================================================================
// tb_soc.sv : drives the SoC and decodes the real UART TX serial line.
// ============================================================================
module tb_soc;
  localparam int DIV = 16;            // clocks per bit (CLK_FREQ/BAUD)

  logic clk = 0, rst_n = 0, uart_rx = 1, uart_tx, halt;
  always #5 clk = ~clk;

  soc_top #(.INIT_FILE("sim/program.hex"), .CLK_FREQ(16), .BAUD(1)) dut (
    .clk(clk), .rst_n(rst_n), .uart_rx(uart_rx), .uart_tx(uart_tx), .halt(halt)
  );

  // ---- synchronous 8N1 receive monitor ------------------------------------
  typedef enum logic [1:0] {IDLE, DATA, STOP} st_e;
  st_e        st = IDLE;
  int         cnt = 0, bit_i = 0;
  logic [7:0] shreg = 0;

  always @(posedge clk) begin
    if (!rst_n) st <= IDLE;
    else case (st)
      IDLE: if (uart_tx == 1'b0) begin
               cnt <= DIV + DIV/2 - 1;   // 1.5 bits -> middle of data bit 0
               bit_i <= 0; st <= DATA;
            end
      DATA: if (cnt == 0) begin
               shreg <= {uart_tx, shreg[7:1]};
               cnt <= DIV - 1;
               if (bit_i == 7) st <= STOP;
               else bit_i <= bit_i + 1;
            end else cnt <= cnt - 1;
      STOP: if (cnt == 0) begin           // wait out the stop bit, then print
               $write("%c", shreg); $fflush();
               st <= IDLE;
            end else cnt <= cnt - 1;
      default: st <= IDLE;
    endcase
  end

  // ---- reset + run control -------------------------------------------------
  initial begin rst_n = 0; repeat (8) @(posedge clk); rst_n = 1; end

  int cycles = 0;
  always @(posedge clk) begin
    cycles <= cycles + 1;
    if (halt) begin
      // let the last frame finish draining before stopping
      repeat (DIV*12) @(posedge clk);
      $display("\n[tb] CPU halted (ECALL) after %0d cycles", cycles);
      $finish;
    end
    if (cycles > 500000) begin $display("\n[tb] TIMEOUT"); $finish; end
  end
endmodule
