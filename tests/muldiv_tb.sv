module muldiv_tb;
    logic clk = 1'b0;
    logic rst = 1'b1;
    logic start = 1'b0;
    logic [2:0] funct3;
    logic [31:0] a, b, result;
    logic busy, done;
    integer cycles;
    always #5 clk = ~clk;

    muldiv dut (
        .clk(clk), .rst(rst), .start(start), .funct3(funct3),
        .a(a), .b(b), .busy(busy), .done(done), .result(result)
    );

    task automatic check(
        input logic [2:0] op,
        input logic [31:0] lhs,
        input logic [31:0] rhs,
        input logic [31:0] expected
    );
        @(negedge clk);
        funct3 = op;
        a = lhs;
        b = rhs;
        start = 1'b1;
        @(posedge clk);
        #1;
        start = 1'b0;
        cycles = 0;
        while (!done && cycles < 34) begin
            @(posedge clk);
            #1;
            cycles = cycles + 1;
        end
        if (!done || result !== expected)
            $fatal(1, "op %0d: %08x / %08x expected %08x, got %08x after %0d cycles",
                   op, lhs, rhs, expected, result, cycles);
        if (op[2] && rhs != 0 &&
            !(lhs == 32'h80000000 && rhs == 32'hffffffff && !op[0]) &&
            cycles != 32)
            $fatal(1, "divider did not take 32 cycles");
    endtask

    initial begin
        repeat (2) @(negedge clk);
        rst = 1'b0;
        check(3'b000, -3, 7, -21);
        check(3'b001, 32'h80000000, 32'h80000000, 32'h40000000);
        check(3'b010, 32'hffffffff, 32'hffffffff, 32'hffffffff);
        check(3'b011, 32'hffffffff, 32'hffffffff, 32'hfffffffe);
        check(3'b100, -20, 3, -6);
        check(3'b101, 20, 3, 6);
        check(3'b110, -20, 3, -2);
        check(3'b111, 20, 3, 2);
        check(3'b100, 32'h80000000, 32'hffffffff, 32'h80000000);
        check(3'b110, 32'h80000000, 32'hffffffff, 0);
        check(3'b100, 42, 0, 32'hffffffff);
        check(3'b110, 42, 0, 42);
        check(3'b101, 42, 0, 32'hffffffff);
        check(3'b111, 42, 0, 42);
        check(3'b101, 32'hffffffff, 2, 32'h7fffffff);
        check(3'b111, 32'hffffffff, 2, 1);
        $display("PASS RV32M multiply and iterative divide edge cases");
        $finish;
    end
endmodule
