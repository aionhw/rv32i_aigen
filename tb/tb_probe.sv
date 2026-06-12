// Direct bus-probe testbench: prints the byte the CPU writes to UART DATA.
module tb_probe;
  logic clk = 0, rst_n = 0, uart_rx = 1, uart_tx, halt;
  always #5 clk = ~clk;

  soc_top #(.INIT_FILE("sim/program.hex"), .CLK_FREQ(16), .BAUD(1)) dut (
    .clk(clk), .rst_n(rst_n), .uart_rx(uart_rx), .uart_tx(uart_tx), .halt(halt)
  );

  initial begin rst_n = 0; repeat (8) @(posedge clk); rst_n = 1; end

  int cycles = 0;
  always @(posedge clk) begin
    cycles <= cycles + 1;
    // probe the data-bus write to UART DATA register
    if (rst_n && dut.sel_uart && dut.dwe && dut.daddr[3:2]==2'b00) begin
      $write("%c", dut.dwdata[7:0]); $fflush();
    end
    if (halt) begin $display("\n[probe] halted after %0d cycles", cycles); $finish; end
    if (cycles > 200000) begin $display("\n[probe] TIMEOUT"); $finish; end
  end
endmodule
