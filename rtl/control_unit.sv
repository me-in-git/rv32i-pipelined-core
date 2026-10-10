// control_unit: RV32I decoder
module control_unit #(
    parameter int DWIDTH = 32
)(
    input  logic [6:0]  opcode,
    input  logic [2:0]  funct3,
    input  logic [6:0]  funct7,

    output logic        reg_write,     // register write enable (WB stage)
    output logic        mem_to_reg,    // dmem -> register file select
    output logic [1:0]  alu_src_b,     // 0: rs2, 1: I/S-imm, 2: U-imm, 3: 0
    output logic [1:0]  pc_src,        // 0: +4, 1: branch, 2: JALR, 3: JAL
    output logic        mem_write,
    output logic        mem_read,
    output logic [3:0]  alu_ctrl,
    output logic [2:0]  branch_type,   // branch compare encoding
    output logic [2:0]  mem_size,      // {byte,half,word} lane sizing
    output logic        pc_alu_src_a   // 1 -> ALU src A = PC (AUIPC)
);

    always_comb begin
        reg_write    = 1'b0;
        mem_to_reg   = 1'b0;
        alu_src_b    = 2'b00;
        pc_src       = 2'b00;
        mem_write    = 1'b0;
        mem_read     = 1'b0;
        alu_ctrl     = 4'b0000;
        branch_type  = 3'b000;
        mem_size     = 3'b000;
        pc_alu_src_a = 1'b0;

        case (opcode)
            7'b0110011: begin // R-type
                reg_write = 1'b1;
                case ({funct7, funct3})
                    10'b0000000_000: alu_ctrl = 4'b0000; // ADD
                    10'b0100000_000: alu_ctrl = 4'b0001; // SUB
                    10'b0000000_111: alu_ctrl = 4'b0010; // AND
                    10'b0000000_110: alu_ctrl = 4'b0011; // OR
                    10'b0000000_100: alu_ctrl = 4'b0100; // XOR
                    10'b0000000_001: alu_ctrl = 4'b0101; // SLL
                    10'b0000000_101: alu_ctrl = 4'b0110; // SRL
                    10'b0100000_101: alu_ctrl = 4'b0111; // SRA
                    10'b0000000_010: alu_ctrl = 4'b1000; // SLT
                    10'b0000000_011: alu_ctrl = 4'b1001; // SLTU
                    default:         alu_ctrl = 4'b0000;
                endcase
            end
            7'b0010011: begin // I-type (ALU + shift)
                reg_write = 1'b1;
                alu_src_b = 2'b01;
                case (funct3)
                    3'b000: alu_ctrl = 4'b0000;              // ADDI
                    3'b010: alu_ctrl = 4'b1000;              // SLTI
                    3'b011: alu_ctrl = 4'b1001;              // SLTIU
                    3'b100: alu_ctrl = 4'b0100;              // XORI
                    3'b110: alu_ctrl = 4'b0011;              // ORI
                    3'b111: alu_ctrl = 4'b0010;              // ANDI
                    3'b001: alu_ctrl = 4'b0101;              // SLLI
                    3'b101: alu_ctrl = funct7[5] ? 4'b0111   // SRAI
                                                : 4'b0110;   // SRLI
                    default: alu_ctrl = 4'b0000;
                endcase
            end
            7'b0000011: begin // Loads
                alu_src_b  = 2'b01;
                alu_ctrl   = 4'b0000;
                mem_read   = 1'b1;
                mem_to_reg = 1'b1;
                reg_write  = 1'b1;
                mem_size   = funct3;
            end
            7'b0100011: begin // S-type store
                alu_src_b = 2'b01;
                alu_ctrl  = 4'b0000;
                mem_write = 1'b1;
                mem_size  = funct3;
            end
            7'b1100011: begin // B-type branch
                pc_src      = 2'b01;
                branch_type = funct3;
            end
            7'b1100111: begin // JALR
                pc_src      = 2'b10;
                reg_write   = 1'b1;
                alu_src_b   = 2'b01;
                alu_ctrl    = 4'b0000;
            end
            7'b1101111: begin // JAL
                pc_src      = 2'b11;
                reg_write   = 1'b1;
            end
            7'b0110111: begin // LUI
                reg_write = 1'b1;
                alu_src_b = 2'b10;
            end
            7'b0010111: begin // AUIPC
                reg_write    = 1'b1;
                alu_src_b    = 2'b10;
                pc_alu_src_a = 1'b1;
            end
            default: ; // illegal -> treated as NOP
        endcase
    end

endmodule