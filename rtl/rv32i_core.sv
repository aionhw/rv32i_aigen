// ============================================================================
// rv32i_core.sv : 3-stage RV32I pipeline
//
//   Stage 1  IF  : PC -> instruction-memory address (registered/sync read,
//                  so the instruction word arrives in the EX stage).
//   Stage 2  EX  : decode, register read, ALU, branch/jump resolution,
//                  data-memory address issue (load/store).
//   Stage 3  MEM : data-memory read data returns, sub-word extension,
//                  write-back to the register file.
//
//   Hazards:
//     * Control : branch/jump resolved in EX -> exactly one bubble on taken.
//     * Data    : single forward path MEM->EX.  Because the data memory has a
//                 registered output, a load's result is already stable at the
//                 start of the following cycle, so the dependent instruction in
//                 EX can consume it via the same forward path -- no load-use
//                 stall is required for this memory model.
//
//   The data side is driven combinationally from EX and the result is consumed
//   in MEM (i_drdata is expected to be valid in the MEM cycle).
// ============================================================================
module rv32i_core
  import rv32i_pkg::*;
#(
  parameter logic [31:0] RESET_PC = 32'h0000_0000
)(
  input  logic        clk,
  input  logic        rst_n,
  // instruction fetch port
  output logic [31:0] o_iaddr,
  input  logic [31:0] i_irdata,
  // data / MMIO port (driven in EX, data consumed in MEM)
  output logic [31:0] o_daddr,
  output logic        o_dreq,    // any load or store this cycle
  output logic        o_dwe,     // store
  output logic [3:0]  o_dbe,     // byte enables for store
  output logic [31:0] o_dwdata,
  input  logic [31:0] i_drdata,  // valid in MEM
  output logic        o_halt     // ECALL/EBREAK reached
);

  // =========================================================================
  // Stage 1 : Fetch
  // =========================================================================
  logic [31:0] f_pc;
  logic [31:0] x_pc;       // PC of the instruction currently in EX
  logic        ex_valid;   // EX instruction is real (not a reset/branch bubble)

  logic        take_branch;
  logic [31:0] branch_target;

  assign o_iaddr = f_pc;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      f_pc     <= RESET_PC;
      x_pc     <= RESET_PC;
      ex_valid <= 1'b0;                 // first EX after reset is a bubble
    end else begin
      x_pc     <= f_pc;
      ex_valid <= ~take_branch;         // squash wrongly-fetched delay slot
      f_pc     <= take_branch ? branch_target : (f_pc + 32'd4);
    end
  end

  // =========================================================================
  // Stage 2 : Decode / Execute
  // =========================================================================
  logic [31:0] instr;
  assign instr = i_irdata;

  wire [6:0] opcode = instr[6:0];
  wire [4:0] rd     = instr[11:7];
  wire [2:0] funct3 = instr[14:12];
  wire [4:0] rs1    = instr[19:15];
  wire [4:0] rs2    = instr[24:20];
  wire [6:0] funct7 = instr[31:25];

  // ---- immediates ----------------------------------------------------------
  wire [31:0] imm_i = {{20{instr[31]}}, instr[31:20]};
  wire [31:0] imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};
  wire [31:0] imm_b = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
  wire [31:0] imm_u = {instr[31:12], 12'd0};
  wire [31:0] imm_j = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};

  // ---- register read + forwarding -----------------------------------------
  logic [31:0] rf_rdata1, rf_rdata2;

  // MEM-stage write-back value (declared in MEM section, used here to forward)
  logic        m_valid;
  logic        m_reg_write;
  logic [4:0]  m_rd;
  logic [31:0] m_wb_value;

  wire fwd_a = m_valid & m_reg_write & (m_rd != 5'd0) & (m_rd == rs1);
  wire fwd_b = m_valid & m_reg_write & (m_rd != 5'd0) & (m_rd == rs2);

  wire [31:0] rs1_val = fwd_a ? m_wb_value : rf_rdata1;
  wire [31:0] rs2_val = fwd_b ? m_wb_value : rf_rdata2;

  // ---- main control --------------------------------------------------------
  logic        reg_write;
  logic        mem_read;
  logic        mem_write;
  logic [3:0]  alu_op;
  logic        alu_a_pc;     // ALU A = PC (AUIPC)
  logic        alu_b_imm;    // ALU B = immediate
  logic [31:0] imm_sel;      // selected immediate for ALU B
  logic        wb_pc4;       // write-back value is PC+4 (JAL/JALR)
  logic        is_branch;
  logic        is_jal;
  logic        is_jalr;
  logic        is_system;

  always_comb begin
    reg_write = 1'b0;
    mem_read  = 1'b0;
    mem_write = 1'b0;
    alu_op    = ALU_ADD;
    alu_a_pc  = 1'b0;
    alu_b_imm = 1'b1;
    imm_sel   = imm_i;
    wb_pc4    = 1'b0;
    is_branch = 1'b0;
    is_jal    = 1'b0;
    is_jalr   = 1'b0;
    is_system = 1'b0;

    unique case (opcode)
      OP_LUI: begin
        reg_write = 1'b1; alu_op = ALU_PASSB; imm_sel = imm_u;
      end
      OP_AUIPC: begin
        reg_write = 1'b1; alu_op = ALU_ADD; alu_a_pc = 1'b1; imm_sel = imm_u;
      end
      OP_JAL: begin
        reg_write = 1'b1; is_jal = 1'b1; wb_pc4 = 1'b1;
      end
      OP_JALR: begin
        reg_write = 1'b1; is_jalr = 1'b1; wb_pc4 = 1'b1; imm_sel = imm_i;
      end
      OP_BRANCH: begin
        is_branch = 1'b1; alu_b_imm = 1'b0;
      end
      OP_LOAD: begin
        reg_write = 1'b1; mem_read = 1'b1; alu_op = ALU_ADD; imm_sel = imm_i;
      end
      OP_STORE: begin
        mem_write = 1'b1; alu_op = ALU_ADD; imm_sel = imm_s;
      end
      OP_IMM: begin
        reg_write = 1'b1; imm_sel = imm_i;
        unique case (funct3)
          3'b000: alu_op = ALU_ADD;                              // ADDI
          3'b010: alu_op = ALU_SLT;                              // SLTI
          3'b011: alu_op = ALU_SLTU;                             // SLTIU
          3'b100: alu_op = ALU_XOR;                              // XORI
          3'b110: alu_op = ALU_OR;                               // ORI
          3'b111: alu_op = ALU_AND;                              // ANDI
          3'b001: alu_op = ALU_SLL;                              // SLLI
          3'b101: alu_op = instr[30] ? ALU_SRA : ALU_SRL;        // SRAI/SRLI
          default: alu_op = ALU_ADD;
        endcase
      end
      OP_REG: begin
        reg_write = 1'b1; alu_b_imm = 1'b0;
        unique case (funct3)
          3'b000: alu_op = instr[30] ? ALU_SUB : ALU_ADD;        // SUB/ADD
          3'b001: alu_op = ALU_SLL;
          3'b010: alu_op = ALU_SLT;
          3'b011: alu_op = ALU_SLTU;
          3'b100: alu_op = ALU_XOR;
          3'b101: alu_op = instr[30] ? ALU_SRA : ALU_SRL;        // SRA/SRL
          3'b110: alu_op = ALU_OR;
          3'b111: alu_op = ALU_AND;
          default: alu_op = ALU_ADD;
        endcase
      end
      OP_FENCE: begin /* treated as NOP */ end
      OP_SYSTEM: begin
        // ECALL / EBREAK -> halt; CSR ops are treated as NOP in this minimal core
        if (funct3 == 3'b000) is_system = 1'b1;
      end
      default: ;
    endcase
  end

  // ---- ALU -----------------------------------------------------------------
  wire [31:0] alu_a = alu_a_pc ? x_pc : rs1_val;
  wire [31:0] alu_b = alu_b_imm ? imm_sel : rs2_val;
  logic [31:0] alu_y;

  alu u_alu (.op(alu_op), .a(alu_a), .b(alu_b), .y(alu_y));

  // ---- branch comparison ---------------------------------------------------
  logic branch_taken;
  always_comb begin
    unique case (funct3)
      3'b000: branch_taken = (rs1_val == rs2_val);                       // BEQ
      3'b001: branch_taken = (rs1_val != rs2_val);                       // BNE
      3'b100: branch_taken = ($signed(rs1_val) <  $signed(rs2_val));     // BLT
      3'b101: branch_taken = ($signed(rs1_val) >= $signed(rs2_val));     // BGE
      3'b110: branch_taken = (rs1_val <  rs2_val);                       // BLTU
      3'b111: branch_taken = (rs1_val >= rs2_val);                       // BGEU
      default: branch_taken = 1'b0;
    endcase
  end

  wire [31:0] target_b    = x_pc + imm_b;
  wire [31:0] target_jal  = x_pc + imm_j;
  wire [31:0] target_jalr = (rs1_val + imm_i) & ~32'd1;

  always_comb begin
    take_branch   = 1'b0;
    branch_target = 32'd0;
    if (ex_valid) begin
      if (is_jal) begin
        take_branch = 1'b1; branch_target = target_jal;
      end else if (is_jalr) begin
        take_branch = 1'b1; branch_target = target_jalr;
      end else if (is_branch && branch_taken) begin
        take_branch = 1'b1; branch_target = target_b;
      end
    end
  end

  assign o_halt = ex_valid & is_system;

  // ---- data-memory address / store formatting ------------------------------
  wire [31:0] mem_addr = alu_y;          // for load/store, ALU computes rs1+imm
  wire [1:0]  addr_lo  = mem_addr[1:0];

  logic [3:0]  store_be;
  logic [31:0] store_wdata;
  always_comb begin
    store_be    = 4'b0000;
    store_wdata = rs2_val;
    unique case (funct3)
      3'b000: begin                                    // SB
        store_be    = 4'b0001 << addr_lo;
        store_wdata = {4{rs2_val[7:0]}};
      end
      3'b001: begin                                    // SH
        store_be    = addr_lo[1] ? 4'b1100 : 4'b0011;
        store_wdata = {2{rs2_val[15:0]}};
      end
      3'b010: begin                                    // SW
        store_be    = 4'b1111;
        store_wdata = rs2_val;
      end
      default: ;
    endcase
  end

  assign o_daddr  = mem_addr;
  assign o_dreq   = ex_valid & (mem_read | mem_write);
  assign o_dwe    = ex_valid & mem_write;
  assign o_dbe    = store_be;
  assign o_dwdata = store_wdata;

  // ---- non-load write-back value (known in EX) -----------------------------
  wire [31:0] ex_result = wb_pc4 ? (x_pc + 32'd4) : alu_y;

  // =========================================================================
  // EX -> MEM pipeline register
  // =========================================================================
  logic [2:0]  m_funct3;
  logic [1:0]  m_addr_lo;
  logic        m_is_load;
  logic [31:0] m_result;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      m_valid     <= 1'b0;
      m_reg_write <= 1'b0;
      m_rd        <= 5'd0;
      m_is_load   <= 1'b0;
      m_funct3    <= 3'd0;
      m_addr_lo   <= 2'd0;
      m_result    <= 32'd0;
    end else begin
      m_valid     <= ex_valid;
      m_reg_write <= ex_valid & reg_write;
      m_rd        <= rd;
      m_is_load   <= ex_valid & mem_read;
      m_funct3    <= funct3;
      m_addr_lo   <= addr_lo;
      m_result    <= ex_result;
    end
  end

  // =========================================================================
  // Stage 3 : Memory / Write-back
  // =========================================================================
  // sub-word load extraction from the (registered) read data
  logic [7:0]  ld_byte;
  logic [15:0] ld_half;
  always_comb begin
    unique case (m_addr_lo)
      2'b00: ld_byte = i_drdata[ 7: 0];
      2'b01: ld_byte = i_drdata[15: 8];
      2'b10: ld_byte = i_drdata[23:16];
      2'b11: ld_byte = i_drdata[31:24];
      default: ld_byte = 8'd0;
    endcase
    ld_half = m_addr_lo[1] ? i_drdata[31:16] : i_drdata[15:0];
  end

  logic [31:0] load_data;
  always_comb begin
    unique case (m_funct3)
      3'b000: load_data = {{24{ld_byte[7]}},  ld_byte};   // LB
      3'b001: load_data = {{16{ld_half[15]}}, ld_half};   // LH
      3'b010: load_data = i_drdata;                       // LW
      3'b100: load_data = {24'd0, ld_byte};               // LBU
      3'b101: load_data = {16'd0, ld_half};               // LHU
      default: load_data = i_drdata;
    endcase
  end

  assign m_wb_value = m_is_load ? load_data : m_result;

  regfile u_rf (
    .clk    (clk),
    .we     (m_valid & m_reg_write & (m_rd != 5'd0)),
    .waddr  (m_rd),
    .wdata  (m_wb_value),
    .raddr1 (rs1),
    .raddr2 (rs2),
    .rdata1 (rf_rdata1),
    .rdata2 (rf_rdata2)
  );

endmodule
