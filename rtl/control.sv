module control #(
    parameter bit SUPPORT_M = 1'b0,
    parameter bit SUPPORT_SYSTEM = 1'b0
) (
    input  logic [31:0] instr,
    output logic        reg_write,
    output logic        mem_write,
    output logic        mem_read,
    output logic        alu_src_imm,
    output logic        alu_src_pc,
    output logic [1:0]  wb_sel,
    output logic        branch_enable,
    output logic [2:0]  branch_type,
    output logic        jal,
    output logic        jalr,
    output logic [3:0]  alu_op,
    output logic        illegal
);
    logic [6:0] opcode;
    logic [2:0] funct3;
    logic [6:0] funct7;
    assign opcode = instr[6:0];
    assign funct3 = instr[14:12];
    assign funct7 = instr[31:25];

    always_comb begin
        reg_write = 1'b0;
        mem_write = 1'b0;
        mem_read = 1'b0;
        alu_src_imm = 1'b0;
        alu_src_pc = 1'b0;
        wb_sel = 2'd0; // 0 ALU, 1 memory, 2 PC+4, 3 U immediate
        branch_enable = 1'b0;
        branch_type = 3'd0;
        jal = 1'b0;
        jalr = 1'b0;
        alu_op = 4'd0;
        illegal = 1'b0;
        case (opcode)
            7'b0110111: begin // LUI
                reg_write = 1'b1;
                wb_sel = 2'd3;
            end
            7'b0010111: begin // AUIPC
                reg_write = 1'b1;
                alu_src_pc = 1'b1;
                alu_src_imm = 1'b1;
            end
            7'b1101111: begin // JAL
                reg_write = 1'b1;
                wb_sel = 2'd2;
                jal = 1'b1;
            end
            7'b1100111: begin // JALR
                reg_write = 1'b1;
                wb_sel = 2'd2;
                jalr = 1'b1;
                if (funct3 != 3'b000) illegal = 1'b1;
            end
            7'b1100011: begin // Branches
                branch_enable = 1'b1;
                branch_type = funct3;
                if (!(funct3 == 3'b000 || funct3 == 3'b001 ||
                      funct3 == 3'b100 || funct3 == 3'b101 ||
                      funct3 == 3'b110 || funct3 == 3'b111)) illegal = 1'b1;
            end
            7'b0000011: begin // Loads
                reg_write = 1'b1;
                mem_read = 1'b1;
                alu_src_imm = 1'b1;
                wb_sel = 2'd1;
                if (!(funct3 == 3'b000 || funct3 == 3'b001 ||
                      funct3 == 3'b010 || funct3 == 3'b100 ||
                      funct3 == 3'b101)) illegal = 1'b1;
            end
            7'b0100011: begin // Stores
                mem_write = 1'b1;
                alu_src_imm = 1'b1;
                if (!(funct3 == 3'b000 || funct3 == 3'b001 ||
                      funct3 == 3'b010)) illegal = 1'b1;
            end
            7'b0010011, 7'b0110011: begin // Integer ALU
                reg_write = 1'b1;
                alu_src_imm = (opcode == 7'b0010011);
                case (funct3)
                    3'b000: alu_op = (opcode == 7'b0110011 && funct7 == 7'b0100000) ? 4'd1 : 4'd0;
                    3'b001: alu_op = 4'd5;
                    3'b010: alu_op = 4'd8;
                    3'b011: alu_op = 4'd9;
                    3'b100: alu_op = 4'd4;
                    3'b101: alu_op = (funct7 == 7'b0100000) ? 4'd7 : 4'd6;
                    3'b110: alu_op = 4'd3;
                    3'b111: alu_op = 4'd2;
                    default: illegal = 1'b1;
                endcase
                if (opcode == 7'b0110011) begin
                    if (!(funct7 == 7'b0000001 && SUPPORT_M)) begin
                        if (funct3 == 3'b000 || funct3 == 3'b101) begin
                            if (!(funct7 == 7'b0000000 || funct7 == 7'b0100000)) illegal = 1'b1;
                        end else if (funct7 != 7'b0000000) illegal = 1'b1;
                    end
                end else if (funct3 == 3'b001 || funct3 == 3'b101) begin
                    if (funct3 == 3'b001 && funct7 != 7'b0000000) illegal = 1'b1;
                    if (funct3 == 3'b101 && !(funct7 == 7'b0000000 || funct7 == 7'b0100000)) illegal = 1'b1;
                end
            end
            7'b0001111: begin // FENCE: no-op for this simple memory system
                if (funct3 != 3'b000) illegal = 1'b1;
            end
            7'b1110011: begin
                if (!SUPPORT_SYSTEM) illegal = 1'b1;
                else if (funct3 == 3'b000) begin
                    if (!(instr == 32'h00000073 || instr == 32'h00100073 ||
                          instr == 32'h30200073)) illegal = 1'b1;
                end else if (funct3 == 3'b001 || funct3 == 3'b010 ||
                             funct3 == 3'b011 || funct3 == 3'b101 ||
                             funct3 == 3'b110 || funct3 == 3'b111) begin
                    reg_write = 1'b1;
                end else illegal = 1'b1;
            end
            default: illegal = 1'b1;
        endcase
        if (illegal) begin
            reg_write = 1'b0;
            mem_write = 1'b0;
            mem_read = 1'b0;
            jal = 1'b0;
            jalr = 1'b0;
            branch_type = 3'd0;
            branch_enable = 1'b0;
        end
    end
endmodule
