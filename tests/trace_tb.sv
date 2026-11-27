module trace_tb;
    logic clk = 1'b0;
    logic rst = 1'b1;
    logic trace_valid, trace_mem_write, stall, flush, m_stall, fault;
    logic [31:0] trace_pc, trace_instr, trace_rd_value;
    logic [31:0] trace_mem_addr, trace_mem_wdata;
    logic [4:0] trace_rd;
    integer max_retire, retired = 0;
    integer stalls = 0, flushes = 0, m_stalls = 0, cycles = 0;
    string program_file;
    always #5 clk = ~clk;
    pipeline_core dut (
        .clk(clk), .rst(rst), .trace_valid(trace_valid),
        .trace_pc(trace_pc), .trace_instr(trace_instr),
        .trace_rd(trace_rd), .trace_rd_value(trace_rd_value),
        .trace_mem_write(trace_mem_write), .trace_mem_addr(trace_mem_addr),
        .trace_mem_wdata(trace_mem_wdata),
        .debug_load_use_stall(stall), .debug_control_flush(flush),
        .debug_m_stall(m_stall), .fault(fault)
    );
    initial begin
        if (!$value$plusargs("program=%s", program_file)) $fatal(1, "missing +program");
        if (!$value$plusargs("max_retire=%d", max_retire)) $fatal(1, "missing +max_retire");
        #1;
        $readmemh(program_file, dut.imem0.words);
        repeat (2) @(negedge clk);
        rst = 1'b0;
        repeat (10000) @(posedge clk);
        $fatal(1, "timeout after %0d retirements", retired);
    end
    always @(negedge clk) begin
        if (!rst) begin
            if (fault) $fatal(1, "core fault after %0d retirements", retired);
            if (trace_valid) begin
                $display("TRACE %08x %08x %02x %08x %1x %08x %08x",
                         trace_pc, trace_instr, trace_rd, trace_rd_value,
                         trace_mem_write, trace_mem_addr, trace_mem_wdata);
                retired = retired + 1;
                if (retired == max_retire) begin
                    $display("COVERAGE stalls=%0d flushes=%0d m_stalls=%0d cycles=%0d",
                             stalls, flushes, m_stalls, cycles);
                    $finish;
                end
            end
        end
    end
    always @(posedge clk) begin
        if (!rst) begin
            cycles = cycles + 1;
            if (stall) stalls = stalls + 1;
            if (flush) flushes = flushes + 1;
            if (m_stall) m_stalls = m_stalls + 1;
        end
    end
endmodule
