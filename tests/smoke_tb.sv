module smoke_tb;
    logic clk = 1'b0;
    logic rst = 1'b1;
    logic [31:0] trace_pc, trace_instr, trace_rd_value;
    logic [4:0] trace_rd;
    logic trace_valid, fault;
    int retired = 0;

    always #5 clk = ~clk;
    core dut (
        .clk(clk), .rst(rst), .trace_pc(trace_pc),
        .trace_instr(trace_instr), .trace_valid(trace_valid),
        .trace_rd(trace_rd), .trace_rd_value(trace_rd_value), .fault(fault)
    );

    function automatic logic [31:0] enc_i(
        input integer imm, input logic [4:0] rs1, input logic [2:0] f3,
        input logic [4:0] rd, input logic [6:0] opcode
    );
        return {imm[11:0], rs1, f3, rd, opcode};
    endfunction
    function automatic logic [31:0] enc_s(
        input integer imm, input logic [4:0] rs2, input logic [4:0] rs1,
        input logic [2:0] f3
    );
        return {imm[11:5], rs2, rs1, f3, imm[4:0], 7'b0100011};
    endfunction
    function automatic logic [31:0] enc_b(
        input integer imm, input logic [4:0] rs2, input logic [4:0] rs1,
        input logic [2:0] f3
    );
        return {imm[12], imm[10:5], rs2, rs1, f3,
                imm[4:1], imm[11], 7'b1100011};
    endfunction
    function automatic logic [31:0] enc_j(
        input integer imm, input logic [4:0] rd
    );
        return {imm[20], imm[10:1], imm[11], imm[19:12], rd, 7'b1101111};
    endfunction

    initial begin
        #1;
        dut.imem0.words[0] = enc_i(7, 0, 3'b000, 1, 7'b0010011); // addi x1,x0,7
        dut.imem0.words[1] = enc_i(5, 1, 3'b000, 2, 7'b0010011); // addi x2,x1,5
        dut.imem0.words[2] = enc_i(99, 2, 3'b000, 0, 7'b0010011); // x0 stays zero
        dut.imem0.words[3] = enc_i(-2, 2, 3'b000, 3, 7'b0010011);
        dut.imem0.words[4] = enc_s(0, 3, 0, 3'b010); // sw x3,0(x0)
        dut.imem0.words[5] = enc_i(0, 0, 3'b010, 4, 7'b0000011); // lw x4,0(x0)
        dut.imem0.words[6] = enc_b(8, 3, 4, 3'b000); // beq, skip x5 write
        dut.imem0.words[7] = enc_i(99, 0, 3'b000, 5, 7'b0010011);
        dut.imem0.words[8] = enc_j(8, 6); // jal, skip x7 write
        dut.imem0.words[9] = enc_i(99, 0, 3'b000, 7, 7'b0010011);
        dut.imem0.words[10] = enc_i(1, 6, 3'b000, 8, 7'b0010011);
        dut.imem0.words[11] = enc_j(0, 0); // loop
        repeat (2) @(negedge clk);
        rst = 1'b0;
        repeat (12) @(posedge clk);
        #1;
        if (dut.rf.regs[1] !== 32'd7) $fatal(1, "x1");
        if (dut.rf.regs[2] !== 32'd12) $fatal(1, "x2");
        if (dut.rf.regs[0] !== 32'd0) $fatal(1, "x0");
        if (dut.rf.regs[3] !== 32'd10) $fatal(1, "x3");
        if (dut.rf.regs[4] !== 32'd10) $fatal(1, "x4");
        if (dut.rf.regs[5] !== 32'd0) $fatal(1, "branch did not skip x5");
        if (dut.rf.regs[6] !== 32'd36) $fatal(1, "jal link x6");
        if (dut.rf.regs[7] !== 32'd0) $fatal(1, "jal did not skip x7");
        if (dut.rf.regs[8] !== 32'd37) $fatal(1, "x8");
        if (fault) $fatal(1, "fault");
        $display("PASS smoke: %0d instructions retired", retired);
        $finish;
    end

    always @(negedge clk) begin
        if (!rst && trace_valid) retired++;
    end
endmodule
