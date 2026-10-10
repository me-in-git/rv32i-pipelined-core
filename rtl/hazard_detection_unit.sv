// hazard_detection_unit: load-use stall
module hazard_detection_unit (
    input  logic        id_mem_read,   // EX-stage instruction is a load
    input  logic [4:0]  id_ex_rd,      // rd of the load in EX stage
    input  logic [4:0]  if_id_rs1,     // rs1 being read in IF/ID
    input  logic [4:0]  if_id_rs2,     // rs2 being read in IF/ID
    output logic        pc_write,      // 0 -> freeze PC
    output logic        if_write,      // 0 -> freeze IF/ID register
    output logic        bubble         // 1 -> force EX stage control to NOP
);

    logic load_use_match;
    assign load_use_match = (id_mem_read) &&
                            ((if_id_rs1 == id_ex_rd) || (if_id_rs2 == id_ex_rd)) &&
                            (id_ex_rd != 5'd0);

    assign pc_write = ~load_use_match;
    assign if_write = ~load_use_match;
    assign bubble   =  load_use_match;

endmodule