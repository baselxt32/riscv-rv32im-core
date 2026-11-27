module misaligned_target_tb;
    logic clk = 1'b0;
    logic rst = 1'b1;
    logic fault, rvfi_valid, rvfi_trap;
    logic [31:0] rvfi_pc_rdata, rvfi_pc_wdata;
    logic [4:0] rvfi_rd_addr;
    integer trap_count = 0;
    integer held_branch = 0;
    logic [31:0] trap_pc, trap_next;
    logic [4:0] trap_rd;
    always #5 clk = ~clk;

    pipeline_core dut (
        .clk(clk), .rst(rst), .fault(fault),
        .rvfi_valid(rvfi_valid), .rvfi_trap(rvfi_trap),
        .rvfi_pc_rdata(rvfi_pc_rdata), .rvfi_pc_wdata(rvfi_pc_wdata),
        .rvfi_rd_addr(rvfi_rd_addr)
    );

    function automatic logic [31:0] addi(input integer imm, input logic [4:0] rs1, rd);
        return {imm[11:0], rs1, 3'b000, rd, 7'h13};
    endfunction
    function automatic logic [31:0] branch(input integer imm,
                                            input logic [4:0] rs2, rs1,
                                            input logic [2:0] funct3);
        return {imm[12], imm[10:5], rs2, rs1, funct3,
                imm[4:1], imm[11], 7'h63};
    endfunction
    function automatic logic [31:0] jal(input integer imm, input logic [4:0] rd);
        return {imm[20], imm[10:1], imm[11], imm[19:12], rd, 7'h6f};
    endfunction
    function automatic logic [31:0] jalr(input integer imm,
                                          input logic [4:0] rs1, rd);
        return {imm[11:0], rs1, 3'b000, rd, 7'h67};
    endfunction
    function automatic logic [31:0] sw(input logic [4:0] rs2, rs1);
        return {7'b0, rs2, rs1, 3'b010, 5'b0, 7'h23};
    endfunction

    task automatic prepare;
        rst = 1'b1;
        trap_count = 0;
        held_branch = 0;
        trap_pc = 0;
        trap_next = 0;
        trap_rd = 0;
        #1;
        for (integer i = 0; i < 70; i++) dut.imem0.words[i] = 32'h00000013;
        dut.imem0.words[64] = jal(0, 0);
    endtask
    task automatic run_case;
        repeat (2) @(negedge clk);
        rst = 1'b0;
        repeat (24) @(negedge clk);
        if (fault) $fatal(1, "core fault");
    endtask
    task automatic check_trap(input logic [31:0] epc, target);
        if (trap_count != 1 || trap_pc !== epc || trap_next !== 32'h100 ||
            trap_rd !== 0 || dut.csrs.mcause !== 0 ||
            dut.csrs.mepc !== epc || dut.csrs.mtval !== target)
            $fatal(1, "bad trap epc=%h target=%h count=%0d pc=%h next=%h rd=%0d cause=%h mepc=%h mtval=%h",
                   epc, target, trap_count, trap_pc, trap_next, trap_rd,
                   dut.csrs.mcause, dut.csrs.mepc, dut.csrs.mtval);
    endtask

    initial begin
        prepare();
        dut.imem0.words[0] = branch(2, 0, 0, 3'b000);
        dut.imem0.words[1] = addi(99, 0, 3);
        run_case();
        check_trap(0, 2);
        if (dut.rf.regs[3] !== 0) $fatal(1, "BEQ did not flush younger instruction");

        prepare();
        dut.imem0.words[0] = addi(1, 0, 1);
        dut.imem0.words[1] = branch(2, 0, 1, 3'b001);
        dut.imem0.words[2] = addi(99, 0, 3);
        run_case();
        check_trap(4, 6);
        if (dut.rf.regs[3] !== 0) $fatal(1, "BNE did not flush younger instruction");

        prepare();
        dut.imem0.words[0] = branch(2, 0, 0, 3'b001);
        dut.imem0.words[1] = addi(7, 0, 4);
        dut.imem0.words[2] = jal(0, 0);
        run_case();
        if (trap_count != 0 || dut.rf.regs[4] !== 7)
            $fatal(1, "not-taken branch trapped or failed to fall through");

        prepare();
        dut.imem0.words[0] = jal(2, 5);
        dut.imem0.words[1] = addi(99, 0, 3);
        run_case();
        check_trap(0, 2);
        if (dut.rf.regs[5] !== 0 || dut.rf.regs[3] !== 0)
            $fatal(1, "trapping JAL wrote a register");

        prepare();
        dut.imem0.words[0] = addi(6, 0, 1);
        dut.imem0.words[1] = jalr(0, 1, 5);
        dut.imem0.words[2] = addi(99, 0, 3);
        run_case();
        check_trap(4, 6);
        if (dut.rf.regs[5] !== 0 || dut.rf.regs[3] !== 0)
            $fatal(1, "trapping JALR wrote a register");

        prepare();
        dut.imem0.words[0] = addi(13, 0, 1);
        dut.imem0.words[1] = jalr(0, 1, 5);
        dut.imem0.words[2] = addi(99, 0, 7);
        dut.imem0.words[3] = addi(7, 0, 6);
        dut.imem0.words[4] = jal(0, 0);
        run_case();
        if (trap_count != 0 || dut.rf.regs[5] !== 8 ||
            dut.rf.regs[6] !== 7 || dut.rf.regs[7] !== 0)
            $fatal(1, "JALR bit-zero clearing or link failed");

        prepare();
        dut.imem0.words[0] = 32'h100000b7;
        dut.imem0.words[1] = addi(65, 0, 2);
        dut.imem0.words[2] = sw(2, 1);
        dut.imem0.words[3] = sw(2, 1);
        dut.imem0.words[4] = branch(2, 0, 0, 3'b000);
        dut.imem0.words[5] = addi(99, 0, 3);
        repeat (2) @(negedge clk);
        rst = 1'b0;
        repeat (220) @(negedge clk);
        if (held_branch == 0) $fatal(1, "UART did not hold the branch");
        check_trap(16, 18);
        if (dut.rf.regs[3] !== 0) $fatal(1, "held branch did not flush younger instruction");
        $display("PASS misaligned branch and jump targets");
        $finish;
    end

    always @(negedge clk) begin
        if (!rst && rvfi_valid && rvfi_trap) begin
            trap_count = trap_count + 1;
            trap_pc = rvfi_pc_rdata;
            trap_next = rvfi_pc_wdata;
            trap_rd = rvfi_rd_addr;
        end
        if (!rst && dut.uart_stall && dut.ex_misaligned) begin
            held_branch = held_branch + 1;
            if (dut.csrs.mtval !== 0)
                $fatal(1, "trap committed while an older UART store was stalled");
        end
    end
endmodule
