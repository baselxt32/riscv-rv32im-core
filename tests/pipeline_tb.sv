module pipeline_tb;
    logic clk = 1'b0;
    logic rst = 1'b1;
    logic trace_valid, trace_mem_write, stall, flush, fault;
    logic [31:0] trace_pc, trace_instr, trace_rd_value;
    logic [31:0] trace_mem_addr, trace_mem_wdata;
    logic [4:0] trace_rd;
    integer stall_count = 0;
    integer flush_count = 0;
    integer retired_count = 0;
    integer store_count = 0;

    always #5 clk = ~clk;
    pipeline_core dut (
        .clk(clk), .rst(rst), .trace_valid(trace_valid),
        .trace_pc(trace_pc), .trace_instr(trace_instr),
        .trace_rd(trace_rd), .trace_rd_value(trace_rd_value),
        .trace_mem_write(trace_mem_write), .trace_mem_addr(trace_mem_addr),
        .trace_mem_wdata(trace_mem_wdata),
        .debug_load_use_stall(stall), .debug_control_flush(flush), .fault(fault)
    );

    function automatic logic [31:0] ri(
        input integer imm, input logic [4:0] rs1, input logic [2:0] f3,
        input logic [4:0] rd, input logic [6:0] opcode
    );
        return {imm[11:0], rs1, f3, rd, opcode};
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
    function automatic logic [31:0] jmp(
        input integer imm, input logic [4:0] rd
    );
        return {imm[20], imm[10:1], imm[11], imm[19:12], rd, 7'b1101111};
    endfunction

    initial begin
        #1;
        dut.imem0.words[0]  = ri(5, 0, 3'b000, 1, 7'b0010011);
        dut.imem0.words[1]  = ri(7, 1, 3'b000, 2, 7'b0010011); // EX forwarding
        dut.imem0.words[2]  = ri(1, 2, 3'b000, 3, 7'b0010011); // EX forwarding
        dut.imem0.words[3]  = st(0, 3, 0, 3'b010); // forwarded store data
        dut.imem0.words[4]  = ri(0, 0, 3'b010, 4, 7'b0000011);
        dut.imem0.words[5]  = ri(2, 4, 3'b000, 5, 7'b0010011); // load-use stall
        dut.imem0.words[6]  = br(8, 3, 5, 3'b001); // taken, forwarded branch operand
        dut.imem0.words[7]  = ri(99, 0, 3'b000, 6, 7'b0010011); // flushed
        dut.imem0.words[8]  = ri(1, 5, 3'b000, 7, 7'b0010011);
        dut.imem0.words[9]  = jmp(8, 8); // taken jump
        dut.imem0.words[10] = ri(99, 0, 3'b000, 9, 7'b0010011); // flushed
        dut.imem0.words[11] = ri(1, 8, 3'b000, 10, 7'b0010011);
        dut.imem0.words[12] = jmp(0, 0); // park
        repeat (2) @(negedge clk);
        rst = 1'b0;
        repeat (40) @(posedge clk);
        #1;
        if (fault) $fatal(1, "pipeline fault");
        if (dut.rf.regs[1] !== 32'd5) $fatal(1, "x1");
        if (dut.rf.regs[2] !== 32'd12) $fatal(1, "EX forwarding x2");
        if (dut.rf.regs[3] !== 32'd13) $fatal(1, "EX forwarding x3");
        if (dut.rf.regs[4] !== 32'd13) $fatal(1, "load x4");
        if (dut.rf.regs[5] !== 32'd15) $fatal(1, "load-use x5");
        if (dut.rf.regs[6] !== 32'd0) $fatal(1, "branch flush x6");
        if (dut.rf.regs[7] !== 32'd16) $fatal(1, "x7");
        if (dut.rf.regs[8] !== 32'd40) $fatal(1, "jump link x8");
        if (dut.rf.regs[9] !== 32'd0) $fatal(1, "jump flush x9");
        if (dut.rf.regs[10] !== 32'd41) $fatal(1, "x10");
        if (stall_count != 1) $fatal(1, "expected one load-use stall, saw %0d", stall_count);
        if (flush_count < 2) $fatal(1, "expected branch and jump flushes");
        if (store_count != 1) $fatal(1, "expected one retired store");
        $display("PASS pipeline hazards: %0d stalls, %0d redirects, %0d retired",
                 stall_count, flush_count, retired_count);
        $finish;
    end
    always @(posedge clk) begin
        if (!rst) begin
            if (stall) stall_count = stall_count + 1;
            if (flush) flush_count = flush_count + 1;
        end
    end
    always @(negedge clk) begin
        if (!rst && trace_valid) begin
            if (retired_count < 11) begin
                case (retired_count)
                    0: if (trace_pc !== 32'd0) $fatal(1, "retire order 0");
                    1: if (trace_pc !== 32'd4) $fatal(1, "retire order 1");
                    2: if (trace_pc !== 32'd8) $fatal(1, "retire order 2");
                    3: if (trace_pc !== 32'd12) $fatal(1, "retire order 3");
                    4: if (trace_pc !== 32'd16) $fatal(1, "retire order 4");
                    5: if (trace_pc !== 32'd20) $fatal(1, "retire order 5");
                    6: if (trace_pc !== 32'd24) $fatal(1, "retire order 6");
                    7: if (trace_pc !== 32'd32) $fatal(1, "retire order 7");
                    8: if (trace_pc !== 32'd36) $fatal(1, "retire order 8");
                    9: if (trace_pc !== 32'd44) $fatal(1, "retire order 9");
                    10: if (trace_pc !== 32'd48) $fatal(1, "retire order 10");
                endcase
                if (trace_instr !== dut.imem0.words[trace_pc >> 2])
                    $fatal(1, "retirement instruction mismatch");
            end
            retired_count = retired_count + 1;
            if (trace_pc == 32'd28 || trace_pc == 32'd40)
                $fatal(1, "flushed instruction retired at PC %0d", trace_pc);
            if (trace_mem_write) begin
                store_count = store_count + 1;
                if (trace_mem_addr !== 32'd0 || trace_mem_wdata !== 32'd13)
                    $fatal(1, "store retirement trace");
            end
        end
    end
endmodule
