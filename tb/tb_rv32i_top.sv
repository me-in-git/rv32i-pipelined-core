// tb_rv32i_top: forwarding and load-use stall test
module tb_rv32i_top;

    logic clk = 0;
    logic rst_n = 0;
    logic halt;

    rv32i_top dut (.clk(clk), .rst_n(rst_n), .halt(halt));

    // program:
    // [0] addi x1, x0, 7   -> x1 = 7
    // [1] addi x2, x0, 3   -> x2 = 3
    // [2] add  x3, x1, x2  -> x3 = 10   (forwarding)
    // [3] sw   x3, 0(x0)   -> dmem[0] = 10
    // [4] lw   x4, 0(x0)   -> x4 = 10
    // [5] addi x5, x4, 1   -> x5 = 11   (load-use hazard -> stall)
    // [6] sw   x5, 4(x0)   -> dmem[1] = 11
    // [7] ecall            -> halt
    logic [31:0] IMG [0:7];
    initial begin
        IMG[0] = 32'h00700093;
        IMG[1] = 32'h00300113;
        IMG[2] = 32'h002081B3;   // add x3, x1, x2
        IMG[3] = 32'h00302023;   // sw x3, 0(x0)
        IMG[4] = 32'h00002203;   // lw x4, 0(x0)
        IMG[5] = 32'h00120293;   // addi x5, x4, 1
        IMG[6] = 32'h00502223;   // sw x5, 4(x0)
        IMG[7] = 32'h00000073;   // ecall
    end

    always #5 clk = ~clk;

    integer i;
    initial begin
        for (i = 0; i < 8; i = i + 1)
            dut.imem.mem[i] = IMG[i];
        rst_n = 1'b0;
        #(40);
        rst_n = 1'b1;

        // Wait for halt with a hard timeout to avoid infinite simulation
        #(600);
        if (halt !== 1'b1)
            $display("WARN: core did not halt in time (halt=%b). Dumping state anyway.", halt);

        #(30);

        // Checks
        if (dut.rf.mem[3] !== 32'd10)
            $display("FAIL: x3=%0d (expect 10) [forwarding]", dut.rf.mem[3]);
        else
            $display("PASS: x3=%0d (forwarding OK)", dut.rf.mem[3]);

        if (dut.rf.mem[4] !== 32'd10)
            $display("FAIL: x4=%0d (expect 10) [load]", dut.rf.mem[4]);
        else
            $display("PASS: x4=%0d (load OK)", dut.rf.mem[4]);

        if (dut.rf.mem[5] !== 32'd11)
            $display("FAIL: x5=%0d (expect 11) [load-use stall]", dut.rf.mem[5]);
        else
            $display("PASS: x5=%0d (load-use stall OK)", dut.rf.mem[5]);

        if (dut.dmem.data[0] !== 32'd10)
            $display("FAIL: dmem[0]=%0d (expect 10)", dut.dmem.data[0]);
        else
            $display("PASS: dmem[0]=%0d", dut.dmem.data[0]);

        if (dut.dmem.data[1] !== 32'd11)
            $display("FAIL: dmem[1]=%0d (expect 11)", dut.dmem.data[1]);
        else
            $display("PASS: dmem[1]=%0d", dut.dmem.data[1]);

        if (dut.rf.mem[3] === 32'd10 && dut.rf.mem[4] === 32'd10 &&
            dut.rf.mem[5] === 32'd11 && dut.dmem.data[0] === 32'd10 &&
            dut.dmem.data[1] === 32'd11)
            $display("=== RV32I_TEST: ALL PASS ===");
        else
            $display("=== RV32I_TEST: HAS FAILURES ===");

        $finish;
    end

endmodule