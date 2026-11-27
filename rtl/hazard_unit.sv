module hazard_unit (
    input  logic        ifid_valid,
    input  logic [31:0] ifid_instr,
    input  logic        idex_valid,
    input  logic        idex_mem_read,
    input  logic [4:0]  idex_rd,
    output logic        load_use_stall
);
    logic uses_rs1, uses_rs2;
    logic [6:0] opcode;

    assign opcode = ifid_instr[6:0];
    assign uses_rs1 = opcode == 7'b0110011 || opcode == 7'b0010011 ||
                      opcode == 7'b0000011 || opcode == 7'b0100011 ||
                      opcode == 7'b1100011 || opcode == 7'b1100111;
    assign uses_rs2 = opcode == 7'b0110011 || opcode == 7'b0100011 ||
                      opcode == 7'b1100011;
    assign load_use_stall = ifid_valid && idex_valid && idex_mem_read &&
                            idex_rd != 5'd0 &&
                            ((uses_rs1 && ifid_instr[19:15] == idex_rd) ||
                             (uses_rs2 && ifid_instr[24:20] == idex_rd));
endmodule
