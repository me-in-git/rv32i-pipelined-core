// tb_isa: every implemented instruction on both cores, final state vs a Python reference model
module tb_isa;

    logic clk = 0;
    logic rst_n = 0;
    logic halt_p, halt_r;

    rv32i_top        pipe (.clk(clk), .rst_n(rst_n), .halt(halt_p));
    rv32i_sequential refc (.clk(clk), .rst_n(rst_n), .halt(halt_r));

    always #5 clk = ~clk;

    `include "isa_prog.svh"

    int errors = 0;

    task automatic check_core(input string name, input int is_pipe);
        int bad = 0;
        logic [31:0] got;
        for (int i = 1; i < 32; i++) begin
            got = is_pipe ? pipe.rf.mem[i] : refc.rf.mem[i];
            if (got !== exp_r[i]) begin
                $display("FAIL: %0s x%0d = %h, expected %h", name, i, got, exp_r[i]);
                bad++;
            end
        end
        for (int i = 0; i < 4; i++) begin
            got = is_pipe ? pipe.dmem.data[i] : refc.dmem.data[i];
            if (got !== exp_m[i]) begin
                $display("FAIL: %0s mem[%0d] = %h, expected %h", name, i, got, exp_m[i]);
                bad++;
            end
        end
        if (bad == 0) $display("PASS: %0s: 31 registers + 4 memory words match", name);
        errors += bad;
    endtask

    initial begin
        isa_program;
        isa_expected;
        for (int k = 0; k < ISA_LEN; k++) begin
            pipe.imem.mem[k] = prog[k];
            refc.imem.mem[k] = prog[k];
        end
        for (int k = 0; k < 4; k++) begin
            pipe.dmem.data[k] = 0;
            refc.dmem.data[k] = 0;
        end

        repeat (2) @(posedge clk);
        #2 rst_n = 1;
        for (int c = 0; c < 500 && !(halt_p === 1'b1 && halt_r === 1'b1); c++) @(posedge clk);
        repeat (5) @(posedge clk);          // let the pipeline drain

        if (halt_p !== 1'b1 || halt_r !== 1'b1) begin
            $display("FAIL: did not halt (pipe=%b ref=%b)", halt_p, halt_r);
            errors++;
        end
        check_core("pipeline", 1);
        check_core("single-cycle", 0);

        if (errors == 0) $display("=== ISA_TEST: ALL PASS (%0d instructions) ===", ISA_LEN);
        else             $display("=== ISA_TEST: %0d errors ===", errors);
        $finish;
    end

endmodule
