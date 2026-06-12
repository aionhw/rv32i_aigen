// ============================================================================
// alu.sv : combinational ALU
// ============================================================================
module alu
  import rv32i_pkg::*;
(
  input  logic [3:0]  op,
  input  logic [31:0] a,
  input  logic [31:0] b,
  output logic [31:0] y
);
  logic [4:0] shamt;
  assign shamt = b[4:0];

  always_comb begin
    unique case (op)
      ALU_ADD  : y = a + b;
      ALU_SUB  : y = a - b;
      ALU_SLL  : y = a << shamt;
      ALU_SLT  : y = ($signed(a) <  $signed(b)) ? 32'd1 : 32'd0;
      ALU_SLTU : y = (a < b)                    ? 32'd1 : 32'd0;
      ALU_XOR  : y = a ^ b;
      ALU_SRL  : y = a >> shamt;
      ALU_SRA  : y = $signed(a) >>> shamt;
      ALU_OR   : y = a | b;
      ALU_AND  : y = a & b;
      ALU_PASSB: y = b;
      default  : y = a + b;
    endcase
  end
endmodule
