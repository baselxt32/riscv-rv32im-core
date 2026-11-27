module muldiv_random_tb;
    logic clk = 1'b0;
    logic rst = 1'b1;
    logic start = 1'b0;
    logic [2:0] funct3;
    logic [31:0] a, b, result;
    logic busy, done;
    logic [31:0] seed = 32'h4d5a6b7c;
    logic [31:0] edges [0:7];
    integer checks = 0;

    always #5 clk = ~clk;

    muldiv dut (
        .clk(clk), .rst(rst), .start(start), .funct3(funct3),
        .a(a), .b(b), .busy(busy), .done(done), .result(result)
    );

    function automatic logic [31:0] next_random(input logic [31:0] value);
        logic [31:0] x;
        x = value ^ (value << 13);
        x = x ^ (x >> 17);
        return x ^ (x << 5);
    endfunction

    function automatic logic [31:0] reference(
        input logic [2:0] op,
        input logic [31:0] lhs,
        input logic [31:0] rhs
    );
        logic [63:0] unsigned_product;
        logic signed [63:0] signed_product, mixed_product;
        unsigned_product = {32'b0, lhs} * {32'b0, rhs};
        signed_product = $signed({{32{lhs[31]}}, lhs}) *
                         $signed({{32{rhs[31]}}, rhs});
        mixed_product = $signed({{32{lhs[31]}}, lhs}) *
                        $signed({32'b0, rhs});
        case (op)
            3'b000: reference = unsigned_product[31:0];
            3'b001: reference = signed_product[63:32];
            3'b010: reference = mixed_product[63:32];
            3'b011: reference = unsigned_product[63:32];
            3'b100: begin
                if (rhs == 0) reference = 32'hffffffff;
                else if (lhs == 32'h80000000 && rhs == 32'hffffffff)
                    reference = lhs;
                else reference = $signed(lhs) / $signed(rhs);
            end
            3'b101: reference = rhs == 0 ? 32'hffffffff : lhs / rhs;
            3'b110: begin
                if (rhs == 0) reference = lhs;
                else if (lhs == 32'h80000000 && rhs == 32'hffffffff)
                    reference = 0;
                else reference = $signed(lhs) % $signed(rhs);
            end
            default: reference = rhs == 0 ? lhs : lhs % rhs;
        endcase
    endfunction

    task automatic check(
        input logic [2:0] op,
        input logic [31:0] lhs,
        input logic [31:0] rhs
    );
        logic [31:0] expected;
        integer cycles;
        expected = reference(op, lhs, rhs);
        @(negedge clk);
        if (busy || done)
            $fatal(1, "unit not idle before op %0d", op);
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
            $fatal(1, "op=%0d a=%08x b=%08x expected=%08x got=%08x cycles=%0d",
                   op, lhs, rhs, expected, result, cycles);
        if (op[2] && rhs != 0 &&
            !(lhs == 32'h80000000 && rhs == 32'hffffffff && !op[0]) &&
            cycles != 32)
            $fatal(1, "divider latency op=%0d a=%08x b=%08x cycles=%0d",
                   op, lhs, rhs, cycles);
        checks = checks + 1;
        @(negedge clk);
    endtask

    initial begin
        edges[0] = 32'h00000000;
        edges[1] = 32'h00000001;
        edges[2] = 32'hffffffff;
        edges[3] = 32'h80000000;
        edges[4] = 32'h7fffffff;
        edges[5] = 32'h80000001;
        edges[6] = 32'h55555555;
        edges[7] = 32'haaaaaaaa;
        repeat (2) @(negedge clk);
        rst = 1'b0;
        for (integer i = 0; i < 8; i++)
            for (integer j = 0; j < 8; j++)
                for (integer op = 0; op < 8; op++)
                    check(op[2:0], edges[i], edges[j]);
        for (integer i = 0; i < 1000; i++) begin
            logic [31:0] lhs, rhs;
            seed = next_random(seed);
            lhs = seed;
            seed = next_random(seed);
            rhs = seed;
            for (integer op = 0; op < 8; op++)
                check(op[2:0], lhs, rhs);
        end
        $display("PASS M random: %0d operations (512 edge, 8000 random)", checks);
        $finish;
    end
endmodule
