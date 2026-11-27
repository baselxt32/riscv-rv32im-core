module pipeline_forward_tb;
    logic clk = 1'b0;
    logic rst = 1'b1;
    logic trace_valid, trace_mem_write, stall, flush, fault;
    logic [31:0] trace_pc, trace_instr, trace_rd_value;
    logic [31:0] trace_mem_addr, trace_mem_wdata;
    logic [4:0] trace_rd;
    integer stalls = 0;
    always #5 clk = ~clk;
    pipeline_core dut (
        .clk(clk), .rst(rst), .trace_valid(trace_valid),
        .trace_pc(trace_pc), .trace_instr(trace_instr),
        .trace_rd(trace_rd), .trace_rd_value(trace_rd_value),
        .trace_mem_write(trace_mem_write), .trace_mem_addr(trace_mem_addr),
        .trace_mem_wdata(trace_mem_wdata),
        .debug_load_use_stall(stall), .debug_control_flush(flush), .fault(fault)
    );
    function automatic logic [31:0] addi(
        input integer imm, input logic [4:0] rs1, input logic [4:0] rd
    );
        return {imm[11:0], rs1, 3'b000, rd, 7'b0010011};
    endfunction
    initial begin
        #1;
        dut.imem0.words[0] = addi(9, 0, 1);
        dut.imem0.words[1] = addi(1, 0, 2);
        dut.imem0.words[2] = addi(2, 1, 3); // WB-to-EX forwarding
        dut.imem0.words[3] = addi(3, 1, 4); // WB-to-ID bypass
        dut.imem0.words[4] = addi(1, 3, 5); // WB-to-EX forwarding
        dut.imem0.words[5] = 32'h0000006f;
        repeat (2) @(negedge clk);
        rst = 1'b0;
        repeat (20) @(posedge clk);
        #1;
        if (fault) $fatal(1, "fault");
        if (dut.rf.regs[3] !== 32'd11) $fatal(1, "WB-to-EX x3");
        if (dut.rf.regs[4] !== 32'd12) $fatal(1, "WB-to-ID x4");
        if (dut.rf.regs[5] !== 32'd12) $fatal(1, "WB-to-EX x5");
        if (stalls != 0) $fatal(1, "false load-use stall");
        $display("PASS pipeline WB forwarding and decode bypass");
        $finish;
    end
    always @(posedge clk) if (!rst && stall) stalls = stalls + 1;
endmodule
