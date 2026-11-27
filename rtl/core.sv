module core (
    input  logic        clk,
    input  logic        rst,
    output logic [31:0] trace_pc,
    output logic [31:0] trace_instr,
    output logic        trace_valid,
    output logic [4:0]  trace_rd,
    output logic [31:0] trace_rd_value,
    output logic        fault
);
    logic [31:0] pc, instr, next_pc;
    logic [31:0] rs1_value, rs2_value, alu_a, alu_b, alu_result;
    logic [31:0] imm_i, imm_s, imm_b, imm_u, imm_j, selected_imm;
    logic [31:0] load_data, writeback;
    logic reg_write, mem_write, mem_read, alu_src_imm, alu_src_pc;
    logic [1:0] wb_sel;
    logic branch_enable, jal, jalr, illegal, branch_taken;
    logic [2:0] branch_type;
    logic [3:0] alu_op;
    logic access_fault, misaligned;

    imem imem0 (.addr(pc), .instr(instr));
    regfile rf (
        .clk(clk), .rst(rst), .rs1(instr[19:15]), .rs2(instr[24:20]),
        .rd(instr[11:7]), .write_data(writeback),
        .write_enable(reg_write && !fault),
        .read1(rs1_value), .read2(rs2_value)
    );
    imm_gen ig (
        .instr(instr), .imm_i(imm_i), .imm_s(imm_s),
        .imm_b(imm_b), .imm_u(imm_u), .imm_j(imm_j)
    );
    control ctl (
        .instr(instr), .reg_write(reg_write), .mem_write(mem_write),
        .mem_read(mem_read), .alu_src_imm(alu_src_imm),
        .alu_src_pc(alu_src_pc), .wb_sel(wb_sel),
        .branch_enable(branch_enable), .branch_type(branch_type),
        .jal(jal), .jalr(jalr), .alu_op(alu_op), .illegal(illegal)
    );

    always_comb begin
        selected_imm = (instr[6:0] == 7'b0100011) ? imm_s : imm_i;
        if (instr[6:0] == 7'b0010111) selected_imm = imm_u;
        alu_a = alu_src_pc ? pc : rs1_value;
        alu_b = alu_src_imm ? selected_imm : rs2_value;
    end
    alu alu0 (.a(alu_a), .b(alu_b), .op(alu_op), .result(alu_result));
    dmem dmem0 (
        .clk(clk), .rst(rst), .read_enable(mem_read),
        .write_enable(mem_write && !illegal && !(|pc[1:0])),
        .funct3(instr[14:12]),
        .addr(alu_result), .write_data(rs2_value), .read_data(load_data),
        .access_fault(access_fault), .misaligned(misaligned)
    );

    always_comb begin
        branch_taken = 1'b0;
        if (branch_enable) begin
            case (branch_type)
                3'b000: branch_taken = (rs1_value == rs2_value);
                3'b001: branch_taken = (rs1_value != rs2_value);
                3'b100: branch_taken = ($signed(rs1_value) < $signed(rs2_value));
                3'b101: branch_taken = ($signed(rs1_value) >= $signed(rs2_value));
                3'b110: branch_taken = (rs1_value < rs2_value);
                3'b111: branch_taken = (rs1_value >= rs2_value);
                default: branch_taken = 1'b0;
            endcase
        end
        next_pc = pc + 32'd4;
        if (branch_taken) next_pc = pc + imm_b;
        if (jal) next_pc = pc + imm_j;
        if (jalr) next_pc = (rs1_value + imm_i) & 32'hfffffffe;
        case (wb_sel)
            2'd0: writeback = alu_result;
            2'd1: writeback = load_data;
            2'd2: writeback = pc + 32'd4;
            default: writeback = imm_u;
        endcase
        fault = illegal || access_fault || misaligned || |pc[1:0];
    end
    always_ff @(posedge clk) begin
        if (rst) begin
            pc <= 32'b0;
            trace_valid <= 1'b0;
            trace_pc <= 32'b0;
            trace_instr <= 32'b0;
            trace_rd <= 5'b0;
            trace_rd_value <= 32'b0;
        end else if (!fault) begin
            pc <= next_pc;
            trace_valid <= 1'b1;
            trace_pc <= pc;
            trace_instr <= instr;
            trace_rd <= reg_write ? instr[11:7] : 5'b0;
            trace_rd_value <= writeback;
        end else begin
            trace_valid <= 1'b0;
        end
    end
endmodule
