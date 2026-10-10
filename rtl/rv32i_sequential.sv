// rv32i_sequential: single-cycle RV32I core (reference)
module rv32i_sequential #(
    parameter int IMEM_ADDR_BITS = 10,
    parameter int DMEM_ADDR_BITS = 8
)(
    input  logic clk,
    input  logic rst_n,
    output logic halt
);

    // PROGRAM COUNTER + INSTRUCTION MEMORY
    logic [31:0] pc, pc_plus4, next_pc;
    logic [31:0] inst;

    assign pc_plus4 = pc + 32'd4;

    instruction_memory #(.DEPTH_BITS(IMEM_ADDR_BITS)) imem (
        .clk(clk), .pc(pc), .inst(inst));

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)            pc <= 32'h0000_0000;
        else if (!halt_r)      pc <= next_pc;
    end

    // ECALL (0x00000073) halts execution; keep PC parked on the ECALL.
    logic ecall;
    assign ecall = (inst[6:0] == 7'b1110011) && (inst[14:12] == 3'b000) &&
                   (inst[31:20] == 12'h000);

    logic halt_r;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) halt_r <= 1'b0;
        else if (ecall) halt_r <= 1'b1;
    end
    assign halt = halt_r;

    // ID : register file read, immediate, control decode
    logic [4:0]  rs1, rs2, rd;
    logic [31:0] rd1, rd2, imm, imm_u;

    assign rs1 = inst[19:15];
    assign rs2 = inst[24:20];
    assign rd  = inst[11:7];

    register_file rf (
        .clk(clk), .rst_n(rst_n),
        .we3(reg_we), .a3(rd), .wd3(reg_wd),
        .a1(rs1), .a2(rs2), .rd1(rd1), .rd2(rd2));

    immediate_gen immgen (.instruction(inst), .imm(imm), .imm_u_j(imm_u));

    logic        cu_reg_w, cu_mem_to_reg, cu_mem_write, cu_mem_read, cu_pc_alu_a;
    logic [1:0]  cu_alu_src_b, cu_pc_src;
    logic [3:0]  cu_alu_ctrl;
    logic [2:0]  cu_branch_type, cu_mem_size;

    control_unit cu (
        .opcode(inst[6:0]),
        .funct3(inst[14:12]),
        .funct7(inst[31:25]),
        .reg_write    (cu_reg_w),
        .mem_to_reg   (cu_mem_to_reg),
        .alu_src_b    (cu_alu_src_b),
        .pc_src       (cu_pc_src),
        .mem_write    (cu_mem_write),
        .mem_read     (cu_mem_read),
        .alu_ctrl     (cu_alu_ctrl),
        .branch_type  (cu_branch_type),
        .mem_size     (cu_mem_size),
        .pc_alu_src_a (cu_pc_alu_a));

    // EX : ALU + branch compare
    logic [31:0] alu_a, alu_b, alu_result;
    logic        alu_zero, alu_lt, alu_ltu;
    logic        branch_taken;

    // ALU src A: AUIPC uses PC, otherwise rs1
    assign alu_a = cu_pc_alu_a ? pc : rd1;
    // ALU src B: immediate for I/S/U-type, otherwise rs2
    assign alu_b = (cu_alu_src_b != 2'b00) ? imm : rd2;

    alu ex_alu (
        .src_a(alu_a), .src_b(alu_b), .alu_ctrl(cu_alu_ctrl),
        .alu_result(alu_result),
        .zero(alu_zero), .lt(alu_lt), .lt_unsigned(alu_ltu));

    branch_compare bcmp (
        .branch_type(cu_branch_type), .a(rd1), .b(rd2),
        .branch_taken(branch_taken));

    // MEM : data memory access (word / half / byte lane)
    logic [31:0] dmem_rdata;

    data_memory #(.DEPTH_BITS(DMEM_ADDR_BITS)) dmem (
        .clk(clk),
        .mem_read(cu_mem_read), .mem_write(cu_mem_write),
        .mem_size(cu_mem_size), .addr(alu_result),
        .wdata(rd2), .rdata(dmem_rdata));

    // WB : falling-edge register write (load data, link, or ALU result)
    logic        is_link;
    logic [31:0] reg_wd;
    logic        reg_we;

    assign is_link = (cu_pc_src == 2'b10) | (cu_pc_src == 2'b11); // JALR/JAL

    always_comb begin
        if (cu_mem_to_reg)   reg_wd = dmem_rdata;   // load
        else if (is_link)    reg_wd = pc_plus4;     // JAL/JALR link
        else                 reg_wd = alu_result;   // ALU / LUI / AUIPC
    end

    assign reg_we = cu_reg_w && !halt_r;

    // NEXT-PC MUX
    always_comb begin
        if (ecall || halt_r)
            next_pc = pc;                                    // ECALL -> park
        else if (branch_taken && (cu_pc_src == 2'b01))
            next_pc = pc + imm;                              // B-type taken
        else if (cu_pc_src == 2'b11)
            next_pc = pc + imm_u;                            // JAL
        else if (cu_pc_src == 2'b10)
            next_pc = alu_result & ~32'h1;                   // JALR (bit0 cleared)
        else
            next_pc = pc_plus4;
    end

endmodule