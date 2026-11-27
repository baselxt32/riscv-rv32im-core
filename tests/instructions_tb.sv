module instructions_tb;
    logic clk = 1'b0;
    logic rst = 1'b1;
    logic [31:0] trace_pc, trace_instr, trace_rd_value;
    logic [4:0] trace_rd;
    logic trace_valid, fault;
    always #5 clk = ~clk;
    core dut (
        .clk(clk), .rst(rst), .trace_pc(trace_pc),
        .trace_instr(trace_instr), .trace_valid(trace_valid),
        .trace_rd(trace_rd), .trace_rd_value(trace_rd_value), .fault(fault)
    );

    function automatic logic [31:0] ri(
        input integer imm, input logic [4:0] rs1, input logic [2:0] f3,
        input logic [4:0] rd, input logic [6:0] opcode
    );
        return {imm[11:0], rs1, f3, rd, opcode};
    endfunction
    function automatic logic [31:0] rr(
        input logic [6:0] f7, input logic [4:0] rs2,
        input logic [4:0] rs1, input logic [2:0] f3, input logic [4:0] rd
    );
        return {f7, rs2, rs1, f3, rd, 7'b0110011};
    endfunction
    function automatic logic [31:0] st(
        input integer imm, input logic [4:0] rs2,
        input logic [4:0] rs1, input logic [2:0] f3
    );
        return {imm[11:5], rs2, rs1, f3, imm[4:0], 7'b0100011};
    endfunction
    function automatic logic [31:0] br(
        input integer imm, input logic [4:0] rs2,
        input logic [4:0] rs1, input logic [2:0] f3
    );
        return {imm[12], imm[10:5], rs2, rs1, f3,
                imm[4:1], imm[11], 7'b1100011};
    endfunction

    initial begin
        #1;
        dut.imem0.words[0]  = ri(-1, 0, 3'b000, 1, 7'b0010011);
        dut.imem0.words[1]  = ri(1, 0, 3'b000, 2, 7'b0010011);
        dut.imem0.words[2]  = rr(0, 2, 1, 3'b010, 3); // slt
        dut.imem0.words[3]  = rr(0, 2, 1, 3'b011, 4); // sltu
        dut.imem0.words[4]  = ri(12'h401, 1, 3'b101, 5, 7'b0010011); // srai
        dut.imem0.words[5]  = ri(1, 1, 3'b101, 6, 7'b0010011); // srli
        dut.imem0.words[6]  = ri(5, 2, 3'b001, 7, 7'b0010011); // slli
        dut.imem0.words[7]  = rr(7'b0100000, 1, 2, 3'b000, 8); // sub
        dut.imem0.words[8]  = rr(0, 7, 1, 3'b111, 9); // and
        dut.imem0.words[9]  = rr(0, 7, 2, 3'b110, 10); // or
        dut.imem0.words[10] = rr(0, 7, 10, 3'b100, 11); // xor
        dut.imem0.words[11] = {20'h12345, 5'd12, 7'b0110111}; // lui
        dut.imem0.words[12] = {20'b0, 5'd13, 7'b0010111}; // auipc
        dut.imem0.words[13] = ri(128, 0, 3'b000, 14, 7'b0010011);
        dut.imem0.words[14] = st(0, 1, 14, 3'b000); // sb
        dut.imem0.words[15] = ri(0, 14, 3'b100, 15, 7'b0000011); // lbu
        dut.imem0.words[16] = ri(0, 14, 3'b000, 16, 7'b0000011); // lb
        dut.imem0.words[17] = st(2, 7, 14, 3'b001); // sh
        dut.imem0.words[18] = ri(2, 14, 3'b101, 17, 7'b0000011); // lhu
        dut.imem0.words[19] = ri(2, 14, 3'b001, 18, 7'b0000011); // lh
        dut.imem0.words[20] = ri(88, 0, 3'b000, 19, 7'b1100111); // jalr
        dut.imem0.words[21] = ri(99, 0, 3'b000, 20, 7'b0010011);
        dut.imem0.words[22] = br(8, 2, 1, 3'b001); // bne
        dut.imem0.words[23] = ri(99, 0, 3'b000, 21, 7'b0010011);
        dut.imem0.words[24] = ri(7, 0, 3'b000, 22, 7'b0010011);
        dut.imem0.words[25] = 32'h0000006f; // jal x0,0
        repeat (2) @(negedge clk);
        rst = 1'b0;
        repeat (30) @(posedge clk);
        #1;
        if (dut.rf.regs[1]  !== 32'hffffffff) $fatal(1, "x1");
        if (dut.rf.regs[3]  !== 32'd1) $fatal(1, "slt");
        if (dut.rf.regs[4]  !== 32'd0) $fatal(1, "sltu");
        if (dut.rf.regs[5]  !== 32'hffffffff) $fatal(1, "srai");
        if (dut.rf.regs[6]  !== 32'h7fffffff) $fatal(1, "srli");
        if (dut.rf.regs[7]  !== 32'd32) $fatal(1, "slli");
        if (dut.rf.regs[8]  !== 32'd2) $fatal(1, "sub");
        if (dut.rf.regs[9]  !== 32'd32) $fatal(1, "and");
        if (dut.rf.regs[10] !== 32'd33) $fatal(1, "or");
        if (dut.rf.regs[11] !== 32'd1) $fatal(1, "xor");
        if (dut.rf.regs[12] !== 32'h12345000) $fatal(1, "lui");
        if (dut.rf.regs[13] !== 32'd48) $fatal(1, "auipc");
        if (dut.rf.regs[15] !== 32'd255) $fatal(1, "lbu");
        if (dut.rf.regs[16] !== 32'hffffffff) $fatal(1, "lb");
        if (dut.rf.regs[17] !== 32'd32) $fatal(1, "lhu");
        if (dut.rf.regs[18] !== 32'd32) $fatal(1, "lh");
        if (dut.rf.regs[19] !== 32'd84) $fatal(1, "jalr link");
        if (dut.rf.regs[20] !== 32'd0) $fatal(1, "jalr skip");
        if (dut.rf.regs[21] !== 32'd0) $fatal(1, "bne skip");
        if (dut.rf.regs[22] !== 32'd7) $fatal(1, "final addi");
        if (fault) $fatal(1, "fault");
        $display("PASS instruction families");
        $finish;
    end
endmodule
