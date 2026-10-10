// tb_sort: bubble sort on the pipeline
module tb_sort;

    logic clk = 0;
    logic rst_n = 1;
    logic halt;

    // 0x400 needs byte-word index 256 -> bump DMEM depth to 11 bits (2048 words)
    rv32i_top #(.DMEM_ADDR_BITS(11)) dut (.clk(clk), .rst_n(rst_n), .halt(halt));

    // bubble sort:
    // x8  = base address (0x400)
    // x9  = outer index i          x14 = n-1 (=7)
    // x10 = inner index j          x11 = limit (n-1-i)
    // x12 = &a[j]                  x13 = a[j]  x6 = a[j+1]  x7 = scratch
    logic [31:0] IMG [0:21];
    initial begin
        IMG[0]  = 32'h40000413;   // addi x8,  x0,  1024    # base = 0x400
        IMG[1]  = 32'h00000493;   // addi x9,  x0,  0       # i = 0
        IMG[2]  = 32'h00700713;   // addi x14, x0,  7       # n-1 = 7
        IMG[3]  = 32'h04E48463;   // beq  x9,  x14, +?      # if i == n-1: done
        IMG[4]  = 32'h00000513;   // addi x10, x0,  0       # j = 0
        IMG[5]  = 32'h409705B3;   // sub  x11, x14, x9      # lim = (n-1)-i
        IMG[6]  = 32'h02B50A63;   // beq  x10, x11, +?      # if j == lim: end inner
        IMG[7]  = 32'h009573B3;   // and  x7,  x10, x9      # scratch AND
        IMG[8]  = 32'h00A3E3B3;   // or   x7,  x7,  x10     # scratch OR
        IMG[9]  = 32'h00251613;   // slli x12, x10, 2       # off = 4*j
        IMG[10] = 32'h00860633;   // add  x12, x12, x8      # &a[j]
        IMG[11] = 32'h00062683;   // lw   x13, 0(x12)       # a  = a[j]
        IMG[12] = 32'h00462303;   // lw   x6,  4(x12)       # b  = a[j+1]
        IMG[13] = 32'h00D323B3;   // slt  x7,  x6,  x13     # x7 = (b < a)
        IMG[14] = 32'h00038663;   // beq  x7,  x0,  +?      # if !(b<a) skip swap
        IMG[15] = 32'h00662023;   // sw   x6,  0(x12)       # a[j]   = b
        IMG[16] = 32'h00D62223;   // sw   x13, 4(x12)       # a[j+1] = a
        IMG[17] = 32'h00150513;   // addi x10, x10, 1       # j++
        IMG[18] = 32'hFC0008E3;   // beq  x0,  x0,  LOOP_J  # -> inner loop
        IMG[19] = 32'h00148493;   // addi x9,  x9,  1       # i++
        IMG[20] = 32'hFA000EE3;   // beq  x0,  x0,  LOOP_I  # -> outer loop
        IMG[21] = 32'h00000073;   // ecall                  # done
    end

    always #5 clk = ~clk;

    // Golden sorted result (verified independently by a software model of the
    // same algorithm).
    logic [31:0] golden [0:7];
    initial begin
        golden[0] = 32'd1;  golden[1] = 32'd2;  golden[2] = 32'd3;  golden[3] = 32'd5;
        golden[4] = 32'd6;  golden[5] = 32'd7;  golden[6] = 32'd8;  golden[7] = 32'd9;
    end

    integer cycles = 0;
    logic run = 1'b0;
    always @(posedge clk) begin
        if (run) cycles = cycles + 1;
    end

    integer w;
    integer failures = 0;
    initial begin
        integer load_i;
        // 1) load program
        for (load_i = 0; load_i < 22; load_i = load_i + 1)
            dut.imem.mem[load_i] = IMG[load_i];

        // 2) load unsorted data array at byte address 0x400 (word 256)
        dut.dmem.data[256+0] = 32'd9;
        dut.dmem.data[256+1] = 32'd5;
        dut.dmem.data[256+2] = 32'd3;
        dut.dmem.data[256+3] = 32'd8;
        dut.dmem.data[256+4] = 32'd1;
        dut.dmem.data[256+5] = 32'd7;
        dut.dmem.data[256+6] = 32'd2;
        dut.dmem.data[256+7] = 32'd6;
        $display("Input  array: 9 5 3 8 1 7 2 6   (base 0x400, word 256)");

        // 3) reset and run
        rst_n = 1'b0;
        #(30);
        rst_n = 1'b1;
        run = 1'b1;

        // 4) wait for halt (generous time-out for 8-element bubble sort)
        while (halt !== 1'b1 && cycles < 2000) @(posedge clk);
        run = 1'b0;

        if (halt !== 1'b1) begin
            $display("FAIL: core did not halt within 2000 cycles");
            failures = failures + 1;
        end else begin
            $display("PASS: core halted at ECALL after %0d cycles", cycles);
        end
        #(50);   // PC is frozen; let the older instructions drain through WB

        // 5) per-word automatic golden comparison
        for (w = 0; w < 8; w = w + 1) begin
            if (dut.dmem.data[256+w] !== golden[w]) begin
                $display("FAIL: a[%0d]=%0d expect %0d (not sorted / wrong value)",
                         w, dut.dmem.data[256+w], golden[w]);
                failures = failures + 1;
            end else begin
                $display("PASS: a[%0d]=%0d", w, dut.dmem.data[256+w]);
            end
        end

        // 6) monotonicity + loop-variable checks
        for (w = 0; w < 7; w = w + 1) begin
            if ($signed(dut.dmem.data[256+w]) > $signed(dut.dmem.data[256+w+1])) begin
                $display("FAIL: array not monotonic at a[%0d]: %0d > %0d",
                         w, dut.dmem.data[256+w], dut.dmem.data[256+w+1]);
                failures = failures + 1;
            end
        end
        if (dut.rf.mem[8] !== 32'd1024) begin
            $display("FAIL: base register x8=%0d expect 1024", dut.rf.mem[8]);
            failures = failures + 1;
        end else begin
            $display("PASS: x8 (base)=%0d", dut.rf.mem[8]);
        end
        if (dut.rf.mem[14] !== 32'd7) begin
            $display("FAIL: n-1 register x14=%0d expect 7", dut.rf.mem[14]);
            failures = failures + 1;
        end else begin
            $display("PASS: x14 (n-1)=%0d", dut.rf.mem[14]);
        end

        if (failures === 0)
            $display("=== SORT_TEST: ALL PASS (8-element bubble sort) ===");
        else
            $display("=== SORT_TEST: %0d FAILURES ===", failures);
        $finish;
    end

endmodule