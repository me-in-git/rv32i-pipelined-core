// forwarding_unit: EX operand forwarding
module forwarding_unit (
    input  logic [4:0]  id_rs1,      // source regs read during ID/EX
    input  logic [4:0]  id_rs2,
    input  logic        ex_reg_write,
    input  logic [4:0]  ex_rd,
    input  logic        mem_reg_write,
    input  logic [4:0]  mem_rd,
    output logic [1:0]  forward_a,
    output logic [1:0]  forward_b
);

    always_comb begin
        // Default: register file value
        forward_a = 2'b00;
        forward_b = 2'b00;

        // rs1 forwarding (highest priority: nearest producer)
        if (ex_reg_write && (ex_rd != 5'd0) && (ex_rd == id_rs1))
            forward_a = 2'b01;                       // from MEM stage (ALU result)
        else if (mem_reg_write && (mem_rd != 5'd0) && (mem_rd == id_rs1))
            forward_a = 2'b10;                       // from WB stage

        // rs2 forwarding
        if (ex_reg_write && (ex_rd != 5'd0) && (ex_rd == id_rs2))
            forward_b = 2'b01;
        else if (mem_reg_write && (mem_rd != 5'd0) && (mem_rd == id_rs2))
            forward_b = 2'b10;
    end

endmodule