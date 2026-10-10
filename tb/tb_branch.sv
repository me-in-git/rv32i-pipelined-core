// tb_branch: taken branch flushes the wrong-path instruction
module tb_branch;

    logic clk = 0, rst_n = 0, halt;

    rv32i_top dut (.clk(clk), .rst_n(rst_n), .halt(halt));

    // [0] addi x1,x0,5  -> x1 = 5
    // [1] addi x2,x0,5  -> x2 = 5
    // [2] beq  x1,x2,+8 -> taken, skip next instruction
    // [3] addi x3,x0,99 -> should NOT execute (flushed)
    // [4] sw  x3,0(x0)  -> dmem[0] = 0
    // [5] ecall
    logic [31:0] IMG [0:5];
    initial begin
        IMG[0] = 32'h00500093;
        IMG[1] = 32'h00500113;
        IMG[2] = 32'h208463;     // beq x1,x2,+8
        IMG[3] = 32'h06300193;   // addi x3,x0,99
        IMG[4] = 32'h00302023;   // sw x3,0(x0)
        IMG[5] = 32'h00000073;   // ecall
    end

    always #5 clk = ~clk;

    integer i;
    initial begin
        for (i = 0; i < 6; i = i + 1) dut.imem.mem[i] = IMG[i];
        rst_n = 1'b0; #(40); rst_n = 1'b1;
        #(500);

        if (dut.rf.mem[3] === 32'd0)
            $display("PASS: x3=%0d (branch taken; dependent instr flushed)", dut.rf.mem[3]);
        else
            $display("FAIL: x3=%0d (expect 0) branch not taken(skip)", dut.rf.mem[3]);

        if (dut.dmem.data[0] === 32'd0)
            $display("PASS: dmem[0]=%0d (control hazard resolved)", dut.dmem.data[0]);
        else
            $display("FAIL: dmem[0]=%0d (expect 0)", dut.dmem.data[0]);

        if (dut.rf.mem[3] === 32'd0 && dut.dmem.data[0] === 32'd0)
            $display("=== BRANCH_TEST: ALL PASS ===");
        else
            $display("=== BRANCH_TEST: HAS FAILURES ===");

        $finish;
    end

endmodule