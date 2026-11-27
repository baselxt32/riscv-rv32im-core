module alu_imm_tb;
    logic [31:0] a, b, result, instr;
    logic [3:0] op;
    logic [31:0] imm_i, imm_s, imm_b, imm_u, imm_j;
    alu alu0 (.a(a), .b(b), .op(op), .result(result));
    imm_gen ig (
        .instr(instr), .imm_i(imm_i), .imm_s(imm_s),
        .imm_b(imm_b), .imm_u(imm_u), .imm_j(imm_j)
    );
    initial begin
        a = 32'h80000000; b = 32'd1; op = 4'd8; #1;
        if (result !== 32'd1) $fatal(1, "signed slt");
        op = 4'd9; #1;
        if (result !== 32'd0) $fatal(1, "unsigned sltu");
        op = 4'd7; #1;
        if (result !== 32'hc0000000) $fatal(1, "sra");
        op = 4'd6; #1;
        if (result !== 32'h40000000) $fatal(1, "srl");
        instr = 32'hfff00013; #1;
        if (imm_i !== 32'hffffffff) $fatal(1, "negative I immediate");
        instr = 32'h80000063; #1;
        if (imm_b !== 32'hfffff000) $fatal(1, "negative B immediate");
        instr = 32'h8000006f; #1;
        if (imm_j !== 32'hfff00000) $fatal(1, "negative J immediate");
        $display("PASS ALU and immediate edge cases");
        $finish;
    end
endmodule
