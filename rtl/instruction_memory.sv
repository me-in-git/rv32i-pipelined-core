// instruction_memory: instruction ROM, async read
module instruction_memory #(
    parameter int DEPTH_BITS = 10,     // word-units address width (1024 words)
    parameter int DEPTH       = (1<<DEPTH_BITS)
)(
    input  logic        clk,
    input  logic [31:0] pc,
    output logic [31:0] inst
);

    logic [31:0] mem [DEPTH-1:0];

    // default to NOP so fetches past the program never decode X
    initial for (int i = 0; i < DEPTH; i++) mem[i] = 32'h0000_0013;

    // Asynchronous (combinational) read: instruction appears in the same
    // cycle as the PC, making IF/ID sampling deterministic on the edge.
    assign inst = mem[pc[31:2]];

endmodule