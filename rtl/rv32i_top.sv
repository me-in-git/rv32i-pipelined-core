// rv32i_top: 5-stage pipelined RV32I core
module rv32i_top #(
    parameter int IMEM_ADDR_BITS = 10,
    parameter int DMEM_ADDR_BITS = 8
)(
    input  logic clk,
    input  logic rst_n,
    output logic halt
);

    // MEMORIES
    logic [31:0] inst, dmem_rdata;
    logic [31:0] dmem_addr, dmem_wdata;
    logic [2:0]  dmem_size;
    logic        dmem_read, dmem_write;

    instruction_memory #(.DEPTH_BITS(IMEM_ADDR_BITS)) imem (
        .clk(clk), .pc(pc), .inst(inst));

    data_memory #(.DEPTH_BITS(DMEM_ADDR_BITS)) dmem (
        .clk(clk), .mem_read(dmem_read), .mem_write(dmem_write),
        .mem_size(dmem_size), .addr(dmem_addr), .wdata(dmem_wdata),
        .rdata(dmem_rdata));

    // IF STAGE
    logic [31:0] pc, pc_plus4, next_pc;
    logic [31:0] branch_target, jump_target;

    assign pc_plus4 = pc + 32'd4;
    // Branch/jump resolved in EX: use the EX-stage instruction's own PC and
    // offset (exmem_* would be the previous instruction -> wrong target).
    assign branch_target = idex_pc + idex_imm;
    assign jump_target   = (idex_pc_src == 2'b11) ? idex_pc + idex_imm_u     // JAL
                                                : alu_result_out & ~32'h1;  // JALR

always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)                  pc <= 32'h0000_0000;
        else if (pc_stall_n && !halt_r) pc <= next_pc;
    end

    always_comb begin
        if (pc_taken)            next_pc = branch_target;
        else if (jump_taken)     next_pc = jump_target;
        else                     next_pc = pc_plus4;
    end

    logic branch_taken, jump_taken, pc_taken;

    // IF/ID REGISTER
    logic [31:0] if_id_pc, if_id_inst;

    // reset to NOP, otherwise instr 0 issues twice after reset
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            if_id_pc   <= 32'h0000_0000;
            if_id_inst <= 32'h0000_0013;
        end
        else if (if_write_en) begin
            if_id_pc   <= pc;
            if_id_inst <= (flush_if_id) ? 32'h0000_0013 : inst;
        end
    end

    logic [4:0] if_id_rs1, if_id_rs2;
    logic [4:0] if_id_rd;

    assign if_id_rs1 = if_id_inst[19:15];
    assign if_id_rs2 = if_id_inst[24:20];
    assign if_id_rd  = if_id_inst[11:7];

    // HAZARD DETECTION
    logic pc_stall_n, if_write_en, flush_if_id, bubble_ex;

hazard_detection_unit hdu (
        .id_mem_read(idex_mem_read),      // load sitting in ID/EX (EX stage)
        .id_ex_rd   (idex_rd),
        .if_id_rs1  (if_id_rs1),
        .if_id_rs2  (if_id_rs2),
        .pc_write   (pc_stall_n),        // 0 -> freeze PC
        .if_write   (if_write_en),       // 0 -> freeze IF/ID
        .bubble     (bubble_ex));

    assign flush_if_id = pc_taken | jump_taken;

    // ID STAGE
    logic [31:0] rd1, rd2;
    logic [31:0] id_imm, id_imm_u;

    register_file rf (
        .clk(clk), .rst_n(rst_n),
        .we3(wb_reg_write), .a3(wb_rd), .wd3(wb_result),
        .a1(if_id_rs1), .a2(if_id_rs2),
        .rd1(rd1), .rd2(rd2));

    immediate_gen immgen (.instruction(if_id_inst),
                          .imm(id_imm), .imm_u_j(id_imm_u));

    logic        cu_reg_w, cu_mem_to_reg, cu_mem_write, cu_mem_read, cu_pc_alu_a;
    logic [1:0]  cu_alu_src_b, cu_pc_src;
    logic [3:0]  cu_alu_ctrl;
    logic [2:0]  cu_branch_type, cu_mem_size;

    control_unit cu (
        .opcode(if_id_inst[6:0]),
        .funct3(if_id_inst[14:12]),
        .funct7(if_id_inst[31:25]),
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

    // ID/EX REGISTER
    logic [31:0] idex_pc, idex_rs1, idex_rs2, idex_imm, idex_imm_u;
    logic [4:0]  idex_rs1a, idex_rs2a, idex_rd;
    logic        idex_reg_w, idex_mem_to_reg, idex_mem_write, idex_mem_read;
    logic        idex_pc_alu_a, idex_jump;
    logic [1:0]  idex_alu_src_b, idex_pc_src;
    logic [3:0]  idex_alu_ctrl;
    logic [2:0]  idex_branch_type, idex_mem_size;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            idex_reg_w       <= 1'b0;
            idex_mem_to_reg  <= 1'b0;
            idex_mem_write   <= 1'b0;
            idex_mem_read    <= 1'b0;
            idex_pc_alu_a    <= 1'b0;
            idex_jump        <= 1'b0;
            idex_alu_src_b   <= 2'b00;
            idex_pc_src      <= 2'b00;
            idex_alu_ctrl    <= 4'b0000;
            idex_branch_type <= 3'b000;
            idex_mem_size    <= 3'b000;
        end else begin
            idex_reg_w       <= (bubble_ex | flush_if_id) ? 1'b0 : cu_reg_w;
            idex_mem_to_reg  <= (bubble_ex | flush_if_id) ? 1'b0 : cu_mem_to_reg;
            idex_mem_write   <= (bubble_ex | flush_if_id) ? 1'b0 : cu_mem_write;
            idex_mem_read    <= (bubble_ex | flush_if_id) ? 1'b0 : cu_mem_read;
            idex_pc_alu_a    <= (bubble_ex | flush_if_id) ? 1'b0 : cu_pc_alu_a;
            idex_jump        <= (bubble_ex | flush_if_id) ? 1'b0 : (cu_pc_src[1]);
            idex_alu_src_b   <= (bubble_ex | flush_if_id) ? 2'b00 : cu_alu_src_b;
            idex_pc_src      <= (bubble_ex | flush_if_id) ? 2'b00 : cu_pc_src;
            idex_alu_ctrl    <= (bubble_ex | flush_if_id) ? 4'b0000 : cu_alu_ctrl;
            idex_branch_type <= (bubble_ex | flush_if_id) ? 3'b000 : cu_branch_type;
            idex_mem_size    <= (bubble_ex | flush_if_id) ? 3'b000 : cu_mem_size;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            idex_pc <= 32'd0; idex_rs1 <= 32'd0; idex_rs2 <= 32'd0;
            idex_imm <= 32'd0; idex_imm_u <= 32'd0;
            idex_rs1a <= 5'd0; idex_rs2a <= 5'd0; idex_rd <= 5'd0;
        end else begin
            idex_pc    <= if_id_pc;
            idex_rs1   <= rd1;
            idex_rs2   <= rd2;
            idex_imm   <= id_imm;
            idex_imm_u <= id_imm_u;
            idex_rs1a  <= if_id_rs1;
            idex_rs2a  <= if_id_rs2;
            idex_rd    <= if_id_rd;
        end
    end

    // EX STAGE  (forwarding + ALU + branch evaluate)
    logic [1:0]  fwd_a, fwd_b;
    logic [31:0] alu_a, alu_b, alu_result;
    logic [31:0] rs1_fwd, rs2_fwd;   // forwarded register operands
    logic        br_taken;

    forwarding_unit fwd (
        .id_rs1(idex_rs1a), .id_rs2(idex_rs2a),
        .ex_reg_write(exmem_reg_w), .ex_rd(exmem_rd),
        .mem_reg_write(memwb_reg_w), .mem_rd(memwb_rd),
        .forward_a(fwd_a), .forward_b(fwd_b));

    // Forwarded register-operand values (used for ALU inputs AND store data)
    always_comb begin
        case (fwd_a)
            2'b01: rs1_fwd = exmem_alu_out;
            2'b10: rs1_fwd = wb_result;
            default: rs1_fwd = idex_rs1;
        endcase
    end
    always_comb begin
        case (fwd_b)
            2'b01: rs2_fwd = exmem_alu_out;
            2'b10: rs2_fwd = wb_result;
            default: rs2_fwd = idex_rs2;
        endcase
    end

    // ALU src A   (AUIPC overrides with PC)
    assign alu_a = idex_pc_alu_a ? idex_pc : rs1_fwd;

    // ALU src B (forwarding reg or immediate)
    always_comb begin
        case (idex_alu_src_b)
            2'b00: alu_b = rs2_fwd;
            2'b01: alu_b = idex_imm;
            2'b10: alu_b = idex_imm_u;
            default: alu_b = rs2_fwd;
        endcase
    end

    alu ex_alu (
        .src_a(alu_a), .src_b(alu_b),
        .alu_ctrl(idex_alu_ctrl), .alu_result(alu_result_out));

    branch_compare bcmp (
        .branch_type(idex_branch_type), .a(alu_a), .b(alu_b),
        .branch_taken(br_taken));

    assign pc_taken   = br_taken && (idex_pc_src == 2'b01);
    assign jump_taken = idex_jump;

    // EX/MEM REGISTER
    logic [31:0] alu_result_out;
    logic [31:0] exmem_alu_out, exmem_rs2, exmem_pc_out, exmem_branch_imm;
    logic [4:0]  exmem_rd;
    logic        exmem_reg_w, exmem_mem_to_reg, exmem_mem_write, exmem_mem_read;
    logic [2:0]  exmem_mem_size;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            exmem_reg_w <= 1'b0; exmem_mem_to_reg <= 1'b0;
            exmem_mem_write <= 1'b0; exmem_mem_read <= 1'b0;
            exmem_mem_size <= 3'b000;
        end else begin
            exmem_reg_w      <= idex_reg_w;
            exmem_mem_to_reg <= idex_mem_to_reg;
            exmem_mem_write  <= idex_mem_write;
            exmem_mem_read   <= idex_mem_read;
            exmem_mem_size   <= idex_mem_size;
        end
    end
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            exmem_alu_out <= 32'd0; exmem_rs2 <= 32'd0; exmem_pc_out <= 32'd0;
            exmem_branch_imm <= 32'd0; exmem_rd <= 5'd0;
        end else begin
            exmem_alu_out    <= idex_jump ? idex_pc + 32'd4 : alu_result_out;  // link for JAL/JALR
            exmem_rs2        <= rs2_fwd;
            exmem_pc_out     <= idex_pc;
            exmem_branch_imm <= idex_imm;
            exmem_rd         <= idex_rd;
        end
    end

    // MEM STAGE
    assign dmem_addr  = exmem_alu_out;
    assign dmem_write = exmem_mem_write;
    assign dmem_read  = exmem_mem_read;
    assign dmem_size  = exmem_mem_size;
    assign dmem_wdata = exmem_rs2;

    // MEM/WB REGISTER
    logic [31:0] memwb_alu_out, memwb_rdata;
    logic [4:0]  memwb_rd;
    logic        memwb_reg_w, memwb_mem_to_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            memwb_reg_w <= 1'b0; memwb_mem_to_reg <= 1'b0;
            memwb_rd <= 5'd0; memwb_alu_out <= 32'd0; memwb_rdata <= 32'd0;
        end else begin
            memwb_reg_w      <= exmem_reg_w;
            memwb_mem_to_reg <= exmem_mem_to_reg;
            memwb_alu_out    <= exmem_alu_out;
            memwb_rdata      <= dmem_rdata;
            memwb_rd         <= exmem_rd;
        end
    end

    // WB STAGE
    logic [31:0] wb_result;
    logic        wb_reg_write;
    logic [4:0]  wb_rd;

    assign wb_result      = memwb_mem_to_reg ? memwb_rdata : memwb_alu_out;
    assign wb_reg_write   = memwb_reg_w;
    assign wb_rd          = memwb_rd;

    // halt on ECALL in ID (ignored if it's being flushed)
    logic halt_r;
    logic ecall;
    assign ecall = (if_id_inst[6:0] == 7'b1110011) && (if_id_inst[14:12] == 3'b000)
                   && (if_id_inst[31:20] == 12'h000) && !flush_if_id;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) halt_r <= 1'b0;
        else if (ecall) halt_r <= 1'b1;
    end
    assign halt = halt_r;

endmodule