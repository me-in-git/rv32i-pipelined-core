// tb_rv32i_seq: single-cycle core vs golden model after every instruction
module tb_rv32i_seq;

    logic clk = 1;         // first edge is a negedge (t=5): inst0's write-back
                           // commits at t=5 while pc=0, then pc advances at t=10
    logic rst_n = 1;       // start high, then drive a real negedge
    logic halt;

    rv32i_sequential dut (.clk(clk), .rst_n(rst_n), .halt(halt));

    // program:
    // [0] addi x1, x0, 7
    // [1] addi x2, x0, 3
    // [2] sub  x3, x1, x2   -> x3 = 4
    // [3] and  x4, x1, x2   -> x4 = 3
    // [4] or   x5, x1, x4   -> x5 = 7
    // [5] sw   x5, 0(x0)    -> dmem[0] = 7
    // [6] lw   x6, 0(x0)    -> x6 = 7
    // [7] addi x6, x6, 1    -> x6 = 8
    // [8] sw   x6, 4(x0)    -> dmem[1] = 8
    // [9] beq  x1, x1, +8   -> taken, skip [10]
    // [10] addi x7, x0, 99   -> must NOT execute (x7 stays 0)
    // [11] addi x8, x0, 5    -> x8 = 5
    // [12] ecall             -> halt
    logic [31:0] IMG [0:12];
    initial begin
        IMG[0]  = 32'h00700093;   // addi x1, x0, 7
        IMG[1]  = 32'h00300113;   // addi x2, x0, 3
        IMG[2]  = 32'h402081B3;   // sub  x3, x1, x2
        IMG[3]  = 32'h0020F233;   // and  x4, x1, x2
        IMG[4]  = 32'h0040E2B3;   // or   x5, x1, x4
        IMG[5]  = 32'h00502023;   // sw   x5, 0(x0)
        IMG[6]  = 32'h00002303;   // lw   x6, 0(x0)
        IMG[7]  = 32'h00130313;   // addi x6, x6, 1
        IMG[8]  = 32'h00602223;   // sw   x6, 4(x0)
        IMG[9]  = 32'h00108463;   // beq  x1, x1, +8
        IMG[10] = 32'h06300393;   // addi x7, x0, 99
        IMG[11] = 32'h00500413;   // addi x8, x0, 5
        IMG[12] = 32'h00000073;   // ecall
    end

    always #5 clk = ~clk;

    // Golden architectural model
    logic [31:0] gpr [0:31];
    logic [31:0] gdm [0:1];        // used data words only (rest is don't care)
    logic [31:0] exp_pc;
    integer      cur_idx;
    integer      exec_cnt;
    logic        watch;
    logic        done;
    integer      failures;

    initial begin
        foreach (gpr[i]) gpr[i] = 32'h0000_0000;
        foreach (gdm[i]) gdm[i] = 32'h0000_0000;
        exp_pc    = 32'h0000_0000;
        cur_idx   = 0;
        exec_cnt  = 0;
        watch     = 1'b0;
        done      = 1'b0;
        failures  = 0;
    end

    // Advance the golden model by exactly one executed instruction.
    task automatic apply_golden(input logic [31:0] pc);
        begin
            case (pc[31:2])
                0:  gpr[1] = 32'd7;                              // addi x1
                1:  gpr[2] = 32'd3;                              // addi x2
                2:  gpr[3] = gpr[1] - gpr[2];                    // sub  x3
                3:  gpr[4] = gpr[1] & gpr[2];                    // and  x4
                4:  gpr[5] = gpr[1] | gpr[4];                    // or   x5
                5:  gdm[0] = gpr[5];                             // sw  -> dmem[0]
                6:  gpr[6] = gdm[0];                             // lw  -> x6
                7:  gpr[6] = gpr[6] + 32'd1;                     // addi x6
                8:  gdm[1] = gpr[6];                             // sw  -> dmem[1]
                9:  ;                                            // beq  (control only)
                10: begin                                        // must never run
                        $display("FAIL: branch missed, instr 10 executed");
                        failures = failures + 1;
                    end
                11: gpr[8] = 32'd5;                              // addi x8
                12: ;                                            // ecall
                default: ;
            endcase
        end
    endtask

    // after each negedge (reg write), step the golden model and compare
    integer i;
    always @(negedge clk) begin
        #1;
        if (watch && !done) begin
            if (dut.pc !== exp_pc) begin
                $display("FAIL[pc mismatch] @inst%0d: pc=%0h expect %0h",
                         exec_cnt, dut.pc, exp_pc);
                failures = failures + 1;
            end
            if (dut.pc[31:2] == 10) begin
                $display("FAIL: beq was not taken (pc=0x%08h)", dut.pc);
                failures = failures + 1;
            end
            apply_golden(dut.pc);
            exec_cnt = exec_cnt + 1;

            // compare all 32 registers
            for (i = 0; i < 32; i = i + 1) begin
                if (dut.rf.mem[i] !== gpr[i]) begin
                    $display("FAIL[inst %0d]: x%0d=%0h expect %0h",
                             dut.pc[31:2], i, dut.rf.mem[i], gpr[i]);
                    failures = failures + 1;
                end
            end
            // ---- compare data words (skip the store's own cycle: the
            // synchronous RAM commit happens on the next posedge) ----
            if (!(dut.pc[31:2] == 5 || dut.pc[31:2] == 8)) begin
                for (i = 0; i < 2; i = i + 1) begin
                    if (dut.dmem.data[i] !== gdm[i]) begin
                        $display("FAIL[inst %0d]: dmem[%0d]=%0h expect %0h",
                                 dut.pc[31:2], i, dut.dmem.data[i], gdm[i]);
                        failures = failures + 1;
                    end
                end
            end

            // expected next PC (beq at inst 9 skips inst 10)
            case (dut.pc[31:2])
                9:  exp_pc = 32'd44;                             // skip [10]
                12: begin exp_pc = 32'd48; done = 1'b1; end      // ecall
                default: exp_pc = exp_pc + 32'd4;
            endcase
        end
    end

    initial begin
        integer load_i;
        for (load_i = 0; load_i < 13; load_i = load_i + 1)
            dut.imem.mem[load_i] = IMG[load_i];

        // data memory has no reset: prime the words the program touches so the
        // golden compares are deterministic
        dut.dmem.data[0] = 32'h0000_0000;
        dut.dmem.data[1] = 32'h0000_0000;

        rst_n = 1'b0;                // real negedge: async reset fires
        #3;
        rst_n = 1'b1;                // release before first negedge (t=5)
        watch = 1'b1;                // first negedge commit (t=5) = inst 0

        // Let the program run through the ECALL and beyond the halt point.
        #(300);
        #10;

        // final checks
        if (halt !== 1'b1) begin
            $display("FAIL: core did not halt");
            failures = failures + 1;
        end else begin
            $display("PASS: core halted at ECALL");
        end
        if (dut.rf.mem[1] !== 32'd7) begin
            $display("FAIL: final x1=%0d expect 7", dut.rf.mem[1]);
            failures = failures + 1;
        end
        if (dut.rf.mem[7] !== 32'd0) begin
            $display("FAIL: x7=%0d expect 0 (branch must skip instr 10)",
                     dut.rf.mem[7]);
            failures = failures + 1;
        end else begin
            $display("PASS: branch skipped instr 10 (x7=%0d)", dut.rf.mem[7]);
        end
        if (dut.rf.mem[8] !== 32'd5) begin
            $display("FAIL: x8=%0d expect 5", dut.rf.mem[8]);
            failures = failures + 1;
        end
        if (dut.dmem.data[0] !== 32'd7 || dut.dmem.data[1] !== 32'd8) begin
            $display("FAIL: dmem word0=%0d word1=%0d (expect 7, 8)",
                     dut.dmem.data[0], dut.dmem.data[1]);
            failures = failures + 1;
        end

        $display("Sequential core executed %0d instructions (PC 0 -> 0x%08h).",
                 exec_cnt, dut.pc);

        if (failures === 0)
            $display("=== SEQUENTIAL_TEST: ALL PASS ===");
        else
            $display("=== SEQUENTIAL_TEST: %0d FAILURES ===", failures);
        $finish;
    end

endmodule