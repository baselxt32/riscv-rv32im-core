`timescale 1ns/1ps
module demo_top_tb;
    logic clk = 1'b0;
    logic rst = 1'b1;
    logic tx, fault;
    always #5 clk = ~clk;
    demo_top #(.CLK_HZ(4_000_000), .BAUD(1_000_000)) dut (
        .clk(clk), .rst(rst), .uart_tx_pin(tx), .fault_led(fault)
    );
    task automatic receive(input logic [7:0] expected_byte);
        begin
            @(negedge tx);
            #20;
            if (tx !== 1'b0) $fatal(1, "start bit");
            for (int bit_index = 0; bit_index < 8; bit_index++) begin
                #40;
                if (tx !== expected_byte[bit_index])
                    $fatal(1, "byte %02x bit %0d", expected_byte, bit_index);
            end
            #40;
            if (tx !== 1'b1) $fatal(1, "stop bit");
        end
    endtask
    initial begin
        repeat (2) @(negedge clk);
        rst = 1'b0;
        receive(8'h48); // H
        receive(8'h69); // i
        receive(8'h0a); // newline
        if (fault) $fatal(1, "CPU fault");
        $display("PASS ROM demo: CPU printed Hi over UART");
        $finish;
    end
    initial begin
        #10000;
        $fatal(1, "UART demo timed out");
    end
endmodule
