`timescale 1ns/1ps
module uart_tx_tb;
    logic clk = 1'b0;
    logic rst = 1'b1;
    logic valid = 1'b0;
    logic [7:0] data = 8'b0;
    logic ready, tx;
    always #5 clk = ~clk;
    uart_tx #(.CLOCKS_PER_BIT(4)) dut (
        .clk(clk), .rst(rst), .valid(valid), .data(data),
        .ready(ready), .tx(tx)
    );

    task automatic send_and_check(input logic [7:0] value);
        logic expected;
        begin
            @(negedge clk);
            data = value;
            valid = 1'b1;
            @(posedge clk);
            #1;
            valid = 1'b0;
            if (ready || tx) $fatal(1, "UART did not start");
            #19; // Midpoint of the start bit.
            if (tx !== 1'b0) $fatal(1, "start bit");
            for (int bit_index = 0; bit_index < 8; bit_index++) begin
                #40;
                expected = value[bit_index];
                if (tx !== expected)
                    $fatal(1, "data bit %0d: expected %b, got %b",
                           bit_index, expected, tx);
            end
            #40;
            if (tx !== 1'b1) $fatal(1, "stop bit");
            #40;
            if (!ready || tx !== 1'b1) $fatal(1, "UART did not return idle");
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        if (tx !== 1'b1 || ready !== 1'b1) $fatal(1, "idle state");
        send_and_check(8'hA5);
        send_and_check(8'h00);
        send_and_check(8'hFF);
        $display("PASS UART TX 8N1 framing for A5, 00, FF");
        $finish;
    end
endmodule
