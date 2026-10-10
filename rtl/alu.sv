// alu: RV32I ALU
module alu #(
    parameter int DWIDTH = 32
)(
    input  logic [DWIDTH-1:0] src_a,
    input  logic [DWIDTH-1:0] src_b,
    input  logic [3:0]        alu_ctrl,
    output logic [DWIDTH-1:0] alu_result,
    output logic              zero,
    output logic              lt,       // result < 0 (for branch/jump compare)
    output logic              lt_unsigned
);

    logic [DWIDTH-1:0] shift_left;
    logic [DWIDTH-1:0] shift_right_arith;
    logic [DWIDTH-1:0] shift_right_logic;

    assign shift_left        = src_a << src_b[4:0];
    assign shift_right_arith = $signed(src_a) >>> src_b[4:0];
    assign shift_right_logic = src_a >> src_b[4:0];

    always_comb begin
        case (alu_ctrl)
            4'b0000: alu_result = src_a + src_b;         // ADD
            4'b0001: alu_result = src_a - src_b;         // SUB
            4'b0010: alu_result = src_a & src_b;         // AND
            4'b0011: alu_result = src_a | src_b;         // OR
            4'b0100: alu_result = src_a ^ src_b;         // XOR
            4'b0101: alu_result = shift_left;            // SLL
            4'b0110: alu_result = shift_right_logic;     // SRL
            4'b0111: alu_result = shift_right_arith;     // SRA
            4'b1000: alu_result = (src_a < src_b) ? 32'b1 : 32'b0;            // SLT (signed)
            4'b1001: alu_result = ($unsigned(src_a) < $unsigned(src_b)) ? 32'b1 : 32'b0; // SLTU
            default: alu_result = 32'b0;
        endcase
    end

    assign zero         = (alu_result == 32'b0);
    assign lt           = ($signed(src_a) < $signed(src_b));
    assign lt_unsigned  = ($unsigned(src_a) < $unsigned(src_b));

endmodule