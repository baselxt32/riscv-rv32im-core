module csr_ops_tb;
    logic clk = 1'b0;
    logic rst = 1'b1;
    logic fault, trace_valid;
    logic [31:0] trace_pc;
    always #5 clk = ~clk;

    pipeline_core dut (
        .clk(clk), .rst(rst), .fault(fault),
        .trace_valid(trace_valid), .trace_pc(trace_pc)
    );

    function automatic logic [31:0] csrop(
        input logic [11:0] addr, input logic [4:0] rs1,
        input logic [2:0] op, input logic [4:0] rd
    );
        return {addr, rs1, op, rd, 7'b1110011};
    endfunction

    initial begin
        #1;
        dut.imem0.words[0] = csrop(12'h342, 5'd5, 3'b101, 2);
        dut.imem0.words[1] = csrop(12'h342, 5'd2, 3'b110, 3);
        dut.imem0.words[2] = csrop(12'h342, 5'd1, 3'b111, 4);
        dut.imem0.words[3] = csrop(12'h342, 5'd0, 3'b010, 5);
        dut.imem0.words[4] = csrop(12'hc00, 5'd0, 3'b010, 6);
        dut.imem0.words[5] = csrop(12'hc00, 5'd0, 3'b011, 8);
        dut.imem0.words[6] = csrop(12'hc00, 5'd0, 3'b110, 9);
        dut.imem0.words[7] = csrop(12'hc00, 5'd1, 3'b101, 7);
        dut.imem0.words[8] = 32'h0000006f;
        dut.imem0.words[64] = csrop(12'h342, 5'd0, 3'b010, 10);
        dut.imem0.words[65] = csrop(12'h341, 5'd0, 3'b010, 11);
        dut.imem0.words[66] = 32'h0000006f;
        repeat (2) @(negedge clk);
        rst = 1'b0;
        repeat (130) @(posedge clk);
        #1;
        if (fault) $fatal(1, "CSR test fault");
        if (dut.rf.regs[2] !== 0 || dut.rf.regs[3] !== 5 ||
            dut.rf.regs[4] !== 7 || dut.rf.regs[5] !== 6)
            $fatal(1, "CSR immediate read-modify-write");
        if (dut.rf.regs[6] == 0 || dut.rf.regs[8] == 0 ||
            dut.rf.regs[9] == 0) $fatal(1, "read-only counter read");
        if (dut.rf.regs[7] !== 0) $fatal(1, "illegal CSR write retired");
        if (dut.rf.regs[10] !== 2 || dut.rf.regs[11] !== 28)
            $fatal(1, "read-only CSR write did not trap");
        $display("PASS CSR set/clear and read-only write trap");
        $finish;
    end

    always @(negedge clk) begin
        if (!rst && trace_valid && trace_pc == 32'd28)
            $fatal(1, "illegal CSR write retired");
    end
endmodule
