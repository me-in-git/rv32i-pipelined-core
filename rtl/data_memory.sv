// data_memory: data RAM with byte/half/word writes
module data_memory #(
    parameter int DEPTH_BITS = 8,
    parameter int DEPTH       = (1<<DEPTH_BITS)
)(
    input  logic        clk,
    input  logic        mem_read,
    input  logic        mem_write,
    input  logic [2:0]  mem_size,        // 000=B, 001=H, 010=W
    input  logic [31:0] addr,
    input  logic [31:0] wdata,
    output logic [31:0] rdata
);

    logic [31:0] data [DEPTH-1:0];
    logic [3:0]  byte_en;
    logic [31:0] word_out;

    // Per-byte lane mask from {mem_size, addr[1:0]}
    always_comb begin
        byte_en = 4'b0000;
        case (mem_size)
            3'b000: byte_en = 4'b0001 << addr[1:0];
            3'b001: byte_en = (addr[1] == 1'b0) ? 4'b0011 : 4'b1100;
            3'b010: byte_en = 4'b1111;
            default: byte_en = 4'b0000;
        endcase
    end

    // store data moved into its byte lane, then merged into the word
    logic [31:0] wdata_lane;
    assign wdata_lane = wdata << {addr[1:0], 3'b000};

    always_comb begin
        word_out = data[addr[31:2]];
        if (byte_en[0]) word_out[7:0]   = wdata_lane[7:0];
        if (byte_en[1]) word_out[15:8]  = wdata_lane[15:8];
        if (byte_en[2]) word_out[23:16] = wdata_lane[23:16];
        if (byte_en[3]) word_out[31:24] = wdata_lane[31:24];
    end

    // Asynchronous read (combinationally available to WB)
    // LB/LH sign-extend, LBU/LHU zero-extend
    logic [31:0] word_r, load_val;
    logic [7:0]  byte_r;
    logic [15:0] half_r;
    assign word_r = data[addr[31:2]];
    assign byte_r = word_r >> {addr[1:0], 3'b000};
    assign half_r = addr[1] ? word_r[31:16] : word_r[15:0];

    always_comb begin
        case (mem_size)
            3'b000:  load_val = {{24{byte_r[7]}}, byte_r};   // LB
            3'b001:  load_val = {{16{half_r[15]}}, half_r};  // LH
            3'b100:  load_val = {24'b0, byte_r};             // LBU
            3'b101:  load_val = {16'b0, half_r};             // LHU
            default: load_val = word_r;                      // LW
        endcase
    end

    assign rdata = mem_read ? load_val : 32'b0;

    // Synchronous write
    always_ff @(posedge clk) begin
        if (mem_write)
            data[addr[31:2]] <= word_out;
    end

endmodule