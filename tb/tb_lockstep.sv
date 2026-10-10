// tb_lockstep: pipeline vs single-cycle core, compares every committed reg write / store
module tb_lockstep;

    localparam int DMEM_BITS = 11;            // 2048 words: sort data lives at 0x400
    localparam int MAXLOG    = 4096;

    logic clk = 0;
    logic rst_n = 0;
    logic halt_p, halt_r;

    rv32i_top        #(.DMEM_ADDR_BITS(DMEM_BITS)) pipe (.clk(clk), .rst_n(rst_n), .halt(halt_p));
    rv32i_sequential #(.DMEM_ADDR_BITS(DMEM_BITS)) refc (.clk(clk), .rst_n(rst_n), .halt(halt_r));

    always #5 clk = ~clk;

    // commit logs
    // kind 0 = register write (a = rd, d = value)
    // kind {size,1} = store (a = byte address, d = store data, size = LB/LH/LW code)
    logic [3:0]  p_kind [MAXLOG];  logic [31:0] p_a [MAXLOG];  logic [31:0] p_d [MAXLOG];
    logic [3:0]  r_kind [MAXLOG];  logic [31:0] r_a [MAXLOG];  logic [31:0] r_d [MAXLOG];
    int p_n, r_n;
    logic logging = 0;

    always @(negedge clk) if (logging && rst_n === 1'b1) begin
        if (pipe.wb_reg_write === 1'b1 && pipe.wb_rd != 5'd0) begin
            p_kind[p_n] = 0; p_a[p_n] = pipe.wb_rd; p_d[p_n] = pipe.wb_result; p_n++;
        end
        if (pipe.dmem_write === 1'b1) begin
            p_kind[p_n] = {pipe.dmem_size, 1'b1}; p_a[p_n] = pipe.dmem_addr; p_d[p_n] = pipe.dmem_wdata; p_n++;
        end
        if (refc.reg_we === 1'b1 && refc.rd != 5'd0) begin
            r_kind[r_n] = 0; r_a[r_n] = refc.rd; r_d[r_n] = refc.reg_wd; r_n++;
        end
        if (refc.cu_mem_write === 1'b1 && !halt_r) begin
            r_kind[r_n] = {refc.cu_mem_size, 1'b1}; r_a[r_n] = refc.alu_result; r_d[r_n] = refc.rd2; r_n++;
        end
    end

    // helpers
    logic [31:0] prog [64];
    int          prog_len;
    int          total_commits = 0;
    int          errors = 0;

    task automatic load_and_run(input string name, input int max_cycles);
        int cyc_p, cyc_r, k, mism;
        // memories: same program, cleared data, on both cores
        for (k = 0; k < (1 << 10); k++) begin
            pipe.imem.mem[k] = (k < prog_len) ? prog[k] : 32'h0000_0013;
            refc.imem.mem[k] = (k < prog_len) ? prog[k] : 32'h0000_0013;
        end
        for (k = 0; k < (1 << DMEM_BITS); k++) begin
            pipe.dmem.data[k] = 32'd0;
            refc.dmem.data[k] = 32'd0;
        end
        if (name == "bubble_sort") begin
            // unsorted array at byte 0x400 (word 256), same as tb_sort
            pipe.dmem.data[256] = 9; pipe.dmem.data[257] = 5; pipe.dmem.data[258] = 3; pipe.dmem.data[259] = 8;
            pipe.dmem.data[260] = 1; pipe.dmem.data[261] = 7; pipe.dmem.data[262] = 2; pipe.dmem.data[263] = 6;
            for (k = 256; k < 264; k++) refc.dmem.data[k] = pipe.dmem.data[k];
        end

        p_n = 0; r_n = 0;
        rst_n = 0;
        logging = 1;                          // monitor ignores cycles in reset
        repeat (2) @(posedge clk);
        #2 rst_n = 1;                         // release mid-cycle, away from both edges

        cyc_p = 0; cyc_r = 0;
        while ((halt_p !== 1'b1 || halt_r !== 1'b1) && cyc_p < max_cycles) begin
            @(posedge clk);
            if (halt_p !== 1'b1) cyc_p++;
            if (halt_r !== 1'b1) cyc_r++;
        end
        repeat (5) @(posedge clk);            // pipeline drains older instructions
        @(negedge clk) logging = 0;

        if (halt_p !== 1'b1 || halt_r !== 1'b1) begin
            $display("FAIL: %0s did not halt (pipe=%b ref=%b)", name, halt_p, halt_r);
            errors++;
            disable load_and_run;
        end

        // 1) commit streams identical
        mism = 0;
        if (p_n != r_n) begin
            $display("FAIL: %0s commit count pipe=%0d ref=%0d", name, p_n, r_n);
            mism++;
        end
        for (k = 0; k < p_n && k < r_n; k++) begin
            if (p_kind[k] !== r_kind[k] || p_a[k] !== r_a[k] || p_d[k] !== r_d[k]) begin
                if (mism < 5)
                    $display("FAIL: %0s commit #%0d differs: pipe {%h,%h,%h} ref {%h,%h,%h}",
                             name, k, p_kind[k], p_a[k], p_d[k], r_kind[k], r_a[k], r_d[k]);
                mism++;
            end
        end
        // 2) final architectural state identical
        for (k = 1; k < 32; k++)
            if (pipe.rf.mem[k] !== refc.rf.mem[k]) begin
                $display("FAIL: %0s final x%0d pipe=%h ref=%h", name, k, pipe.rf.mem[k], refc.rf.mem[k]);
                mism++;
            end
        for (k = 0; k < (1 << DMEM_BITS); k++)
            if (pipe.dmem.data[k] !== refc.dmem.data[k]) begin
                $display("FAIL: %0s final dmem[%0d] pipe=%h ref=%h", name, k, pipe.dmem.data[k], refc.dmem.data[k]);
                mism++;
            end

        if (mism == 0)
            $display("PASS: %0s: %0d commits identical (pipeline %0d cycles, single-cycle %0d cycles)",
                     name, p_n, cyc_p, cyc_r);
        errors += mism;
        total_commits += p_n;
    endtask

    // programs
    initial begin
        // A) forwarding + load-use (tb_rv32i_top)
        prog[0] = 32'h00700093;  // addi x1, x0, 7
        prog[1] = 32'h00300113;  // addi x2, x0, 3
        prog[2] = 32'h002081B3;  // add  x3, x1, x2
        prog[3] = 32'h00302023;  // sw   x3, 0(x0)
        prog[4] = 32'h00002203;  // lw   x4, 0(x0)
        prog[5] = 32'h00120293;  // addi x5, x4, 1    (load-use)
        prog[6] = 32'h00502223;  // sw   x5, 4(x0)
        prog[7] = 32'h00000073;  // ecall
        prog_len = 8;
        load_and_run("forward_loaduse", 200);

        // B) ALU / load-store / taken branch (tb_rv32i_seq)
        prog[0]  = 32'h00700093; // addi x1, x0, 7
        prog[1]  = 32'h00300113; // addi x2, x0, 3
        prog[2]  = 32'h402081B3; // sub  x3, x1, x2
        prog[3]  = 32'h0020F233; // and  x4, x1, x2
        prog[4]  = 32'h0040E2B3; // or   x5, x1, x4
        prog[5]  = 32'h00502023; // sw   x5, 0(x0)
        prog[6]  = 32'h00002303; // lw   x6, 0(x0)
        prog[7]  = 32'h00130313; // addi x6, x6, 1
        prog[8]  = 32'h00602223; // sw   x6, 4(x0)
        prog[9]  = 32'h00108463; // beq  x1, x1, +8
        prog[10] = 32'h06300393; // addi x7, x0, 99   (skipped)
        prog[11] = 32'h00500413; // addi x8, x0, 5
        prog[12] = 32'h00000073; // ecall
        prog_len = 13;
        load_and_run("alu_mem_branch", 200);

        // C) 8-element bubble sort (tb_sort)
        prog[0]  = 32'h40000413; prog[1]  = 32'h00000493; prog[2]  = 32'h00700713;
        prog[3]  = 32'h04E48463; prog[4]  = 32'h00000513; prog[5]  = 32'h409705B3;
        prog[6]  = 32'h02B50A63; prog[7]  = 32'h009573B3; prog[8]  = 32'h00A3E3B3;
        prog[9]  = 32'h00251613; prog[10] = 32'h00860633; prog[11] = 32'h00062683;
        prog[12] = 32'h00462303; prog[13] = 32'h00D323B3; prog[14] = 32'h00038663;
        prog[15] = 32'h00662023; prog[16] = 32'h00D62223; prog[17] = 32'h00150513;
        prog[18] = 32'hFC0008E3; prog[19] = 32'h00148493; prog[20] = 32'hFA000EE3;
        prog[21] = 32'h00000073;
        prog_len = 22;
        load_and_run("bubble_sort", 2000);

        if (errors == 0)
            $display("=== LOCKSTEP_TEST: ALL PASS (3 programs, %0d commits compared) ===", total_commits);
        else
            $display("=== LOCKSTEP_TEST: %0d mismatches ===", errors);
        $finish;
    end

endmodule
