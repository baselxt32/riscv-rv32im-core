module forwarding_unit (
    input  logic [4:0]  ifid_rs1,
    input  logic [4:0]  ifid_rs2,
    input  logic [31:0] rf_rs1,
    input  logic [31:0] rf_rs2,
    input  logic [4:0]  idex_rs1,
    input  logic [4:0]  idex_rs2,
    input  logic [31:0] idex_rs1_data,
    input  logic [31:0] idex_rs2_data,
    input  logic        exmem_valid,
    input  logic        exmem_reg_write,
    input  logic        exmem_mem_read,
    input  logic [4:0]  exmem_rd,
    input  logic [31:0] exmem_value,
    input  logic        memwb_valid,
    input  logic        memwb_reg_write,
    input  logic [4:0]  memwb_rd,
    input  logic [31:0] memwb_value,
    output logic [31:0] dec_rs1,
    output logic [31:0] dec_rs2,
    output logic [31:0] ex_rs1,
    output logic [31:0] ex_rs2
);
    always_comb begin
        dec_rs1 = rf_rs1;
        dec_rs2 = rf_rs2;
        if (memwb_valid && memwb_reg_write && memwb_rd != 5'd0) begin
            if (ifid_rs1 == memwb_rd) dec_rs1 = memwb_value;
            if (ifid_rs2 == memwb_rd) dec_rs2 = memwb_value;
        end

        ex_rs1 = idex_rs1_data;
        ex_rs2 = idex_rs2_data;
        if (memwb_valid && memwb_reg_write && memwb_rd != 5'd0) begin
            if (idex_rs1 == memwb_rd) ex_rs1 = memwb_value;
            if (idex_rs2 == memwb_rd) ex_rs2 = memwb_value;
        end
        if (exmem_valid && exmem_reg_write && !exmem_mem_read &&
            exmem_rd != 5'd0) begin
            if (idex_rs1 == exmem_rd) ex_rs1 = exmem_value;
            if (idex_rs2 == exmem_rd) ex_rs2 = exmem_value;
        end
    end
endmodule
