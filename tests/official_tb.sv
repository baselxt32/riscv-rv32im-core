module official_tb;
    logic clk = 1'b0;
    logic rst = 1'b1;
    logic fault, trace_valid, trace_mem_write;
    logic [31:0] trace_pc, trace_instr, trace_mem_addr, trace_mem_wdata;
    logic [31:0] tohost;
    string imem_file, dmem_file;
    integer cycles = 0;
    integer retired = 0;
    always #5 clk = ~clk;

    pipeline_core #(
        .RESET_PC(32'h80000000), .IMEM_BASE(32'h80000000),
        .IMEM_WORDS(2048), .DMEM_BASE(32'h80000000), .DMEM_BYTES(16384),
        .ALLOW_MISALIGNED(1'b1)
    ) dut (
        .clk(clk), .rst(rst), .fault(fault),
        .trace_valid(trace_valid), .trace_pc(trace_pc),
        .trace_instr(trace_instr), .trace_mem_write(trace_mem_write),
        .trace_mem_addr(trace_mem_addr), .trace_mem_wdata(trace_mem_wdata)
    );

    initial begin
        if (!$value$plusargs("imem=%s", imem_file) ||
            !$value$plusargs("dmem=%s", dmem_file) ||
            !$value$plusargs("tohost=%h", tohost))
            $fatal(1, "missing official-test arguments");
        repeat (2) @(negedge clk);
        rst = 1'b0;
        $readmemh(imem_file, dut.imem0.words);
        $readmemh(dmem_file, dut.dmem0.bytes);
        repeat (100000) @(posedge clk);
        $fatal(1, "official test timeout after %0d cycles, pc=%08x", cycles, dut.pc);
    end

    always @(negedge clk) begin
        if (!rst) begin
            cycles = cycles + 1;
            if (fault)
                $fatal(1, "official test core fault pc=%08x instr=%08x",
                       dut.exmem_pc, dut.exmem_instr);
            if (trace_valid) begin
                retired = retired + 1;
                if ($test$plusargs("trace") && retired <= 120)
                    $display("TRACE %08x %08x", trace_pc, trace_instr);
            end
            if (trace_valid && trace_mem_write &&
                trace_mem_addr == tohost && trace_mem_wdata != 0) begin
                if (trace_mem_wdata != 32'd1)
                    $fatal(1, "official test fail code=%0d pc=%08x",
                           trace_mem_wdata, trace_pc);
                $display("OFFICIAL PASS cycles=%0d", cycles);
                $finish;
            end
        end
    end
endmodule
