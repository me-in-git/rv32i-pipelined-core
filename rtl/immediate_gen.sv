// immediate_gen: I/S/B/U/J immediates
module immediate_gen #(
    parameter int DWIDTH = 32
)(
    input  logic [DWIDTH-1:0] instruction,
    output logic [DWIDTH-1:0] imm,
    output logic [DWIDTH-1:0] imm_u_j     // U-type / J-type (upper or target)
);

    logic [31:0] inst;
    assign inst = instruction;

    always_comb begin
        unique case (inst[6:0])
            7'b0000011, 7'b0010011, 7'b1101111, 7'b0000111, 7'b0100111,
            7'b0000111, 7'b1100111 :                         // I-type, JAL, JALR, LUI/loads fp
                imm = {{20{inst[31]}}, inst[31:20]};
            7'b0100011 :                                    // S-type (store)
                imm = {{20{inst[31]}}, inst[31:25], inst[11:7]};
            7'b1100011 :                                    // B-type (branch)
                imm = {{20{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0};
            7'b0110111, 7'b0010111 :                        // U-type: LUI/AUIPC
                imm = {inst[31:12], 12'b0};
            default: imm = 32'b0;
        endcase
    end

    // Sign-extended 21-bit B/J target combining for jump target computation
    always_comb begin
        unique case (inst[6:0])
            7'b1101111 :                                    // JAL
                imm_u_j = { {12{inst[31]}}, inst[19:12], inst[20],
                             inst[30:21], 1'b0 };
            7'b0110111, 7'b0110011, 7'b0000011, 7'b0010011,
            7'b1100011 :                                    // non-jump -> keep immutable
                imm_u_j = imm;
            default : imm_u_j = imm;
        endcase
    end

endmodule