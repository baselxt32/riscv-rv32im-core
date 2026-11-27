module pipeline_system_tb;
    logic clk = 1'b0;
    logic rst = 1'b1;
    logic fault, trace_valid;
    logic [31:0] trace_pc, trace_instr;
    integer mret_count = 0;
    always #5 clk = ~clk;

    pipeline_core dut (
        .clk(clk), .rst(rst), .fault(fault),
        .trace_valid(trace_valid), .trace_pc(trace_pc),
        .trace_instr(trace_instr)
    );

    function automatic logic [31:0] addi(
        input integer imm, input logic [4:0] rs1, input logic [4:0] rd
    );
        return {imm[11:0], rs1, 3'b000, rd, 7'b0010011};
    endfunction
    function automatic logic [31:0] csrop(
        input logic [11:0] addr, input logic [4:0] rs1,
        input logic [2:0] op, input logic [4:0] rd
    );
        return {addr, rs1, op, rd, 7'b1110011};
    endfunction
    function automatic logic [31:0] sw(
        input logic [4:0] rs2, input logic [4:0] rs1
    );
        return {7'b0, rs2, rs1, 3'b010, 5'b0, 7'b0100011};
    endfunction

    initial begin
        #1;
        dut.imem0.words[0] = addi(256, 0, 1);
        dut.imem0.words[1] = csrop(12'h305, 1, 3'b001, 0);
        dut.imem0.words[2] = addi(0, 0, 13);
        dut.imem0.words[3] = csrop(12'hc00, 0, 3'b010, 2);
        dut.imem0.words[4] = csrop(12'hc02, 0, 3'b010, 3);
        dut.imem0.words[5] = 32'hffffffff;
        dut.imem0.words[6] = 32'h00100073;
        dut.imem0.words[7] = 32'h00000073;
        dut.imem0.words[8] = 32'h0ff0000f;
        dut.imem0.words[9] = addi(7, 0, 4);
        dut.imem0.words[10] = 32'h0000006f;
        dut.imem0.words[64] = csrop(12'h342, 0, 3'b010, 10);
        dut.imem0.words[65] = csrop(12'h341, 0, 3'b010, 11);
        dut.imem0.words[66] = sw(10, 13);
        dut.imem0.words[67] = addi(4, 13, 13);
        dut.imem0.words[68] = addi(4, 11, 11);
        dut.imem0.words[69] = csrop(12'h341, 11, 3'b001, 0);
        dut.imem0.words[70] = 32'h30200073;
        repeat (2) @(negedge clk);
        rst = 1'b0;
        repeat (500) @(posedge clk);
        #1;
        if (fault) $fatal(1, "system fault");
        if (dut.rf.regs[4] !== 32'd7) $fatal(1, "trap return did not reach main program");
        if (dut.rf.regs[2] == 0 || dut.rf.regs[3] == 0)
            $fatal(1, "cycle or instret did not advance");
        if (dut.dmem0.bytes[0] !== 8'd2 ||
            dut.dmem0.bytes[4] !== 8'd3 ||
            dut.dmem0.bytes[8] !== 8'd11)
            $fatal(1, "trap causes were not stored in order");
        if (dut.csrs.mepc !== 32'd32) $fatal(1, "mepc after final trap");
        if (mret_count != 3) $fatal(1, "mret did not retire three times");
        $display("PASS CSRs, illegal/EBREAK/ECALL traps, MRET, FENCE");
        $finish;
    end

    always @(negedge clk) begin
        if (!rst && trace_valid) begin
            if (trace_pc == 32'd20 || trace_pc == 32'd24 || trace_pc == 32'd28)
                $fatal(1, "trapping instruction retired");
            if (trace_instr == 32'h30200073) mret_count = mret_count + 1;
        end
    end
endmodule
