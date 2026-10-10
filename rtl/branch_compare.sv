// branch_compare: branch condition
module branch_compare (
    input  logic [2:0]   branch_type, // funct3 from B-type
    input  logic [31:0]  a,           // rs1 (forwarded)
    input  logic [31:0]  b,           // rs2 (forwarded)
    output logic         branch_taken
);

    logic eq, ne, lt, ge, ltu, geu;

    assign eq  = (a == b);
    assign ne  = !eq;
    assign lt  = ($signed(a) < $signed(b));
    assign ge  = !lt;
    assign ltu = ($unsigned(a) < $unsigned(b));
    assign geu = !ltu;

    always_comb begin
        unique case (branch_type)
            3'b000: branch_taken = eq;   // BEQ
            3'b001: branch_taken = ne;   // BNE
            3'b100: branch_taken = lt;   // BLT
            3'b101: branch_taken = ge;   // BGE
            3'b110: branch_taken = ltu;  // BLTU
            3'b111: branch_taken = geu;  // BGEU
            default: branch_taken = 1'b0;
        endcase
    end

endmodule