// register_file: 32x32, 2 read / 1 write (negedge)
module register_file #(
    parameter int ADDR_WIDTH = 5,
    parameter int DATA_WIDTH = 32
)(
    input  logic                    clk,
    input  logic                    rst_n,
    input  logic                    we3,          // write enable (valid in WB)
    input  logic [ADDR_WIDTH-1:0]   a3,           // write address (rd)
    input  logic [DATA_WIDTH-1:0]   wd3,          // write data
    input  logic [ADDR_WIDTH-1:0]   a1,           // read addr 1 (rs1)
    input  logic [ADDR_WIDTH-1:0]   a2,           // read addr 2 (rs2)
    output logic [DATA_WIDTH-1:0]   rd1,
    output logic [DATA_WIDTH-1:0]   rd2
);

    logic [DATA_WIDTH-1:0] mem [0:2**ADDR_WIDTH-1];

    always_comb begin
        rd1 = (a1 == 5'd0) ? 32'b0 : mem[a1];
        rd2 = (a2 == 5'd0) ? 32'b0 : mem[a2];
    end

    // Synchronous write on the falling edge
    always_ff @(negedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < 2**ADDR_WIDTH; i++)
                mem[i] <= '0;
        end else if (we3 && (a3 != 5'd0)) begin
            mem[a3] <= wd3;
        end
    end

endmodule