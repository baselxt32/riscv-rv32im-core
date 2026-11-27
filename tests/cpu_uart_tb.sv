`timescale 1ns/1ps
module cpu_uart_tb;
    logic clk = 1'b0;
    logic rst = 1'b1;
    logic trace_valid, trace_mem_write, load_stall, flush, uart_stall, tx, fault;
    logic [31:0] trace_pc, trace_instr, trace_rd_value;
    logic [31:0] trace_mem_addr, trace_mem_wdata;
    logic [4:0] trace_rd;
    integer uart_stall_cycles = 0;
    integer uart_store_count = 0;
    always #5 clk = ~clk;
    pipeline_core #(.UART_CLOCKS_PER_BIT(4)) dut (
        .clk(clk), .rst(rst), .trace_valid(trace_valid),
        .trace_pc(trace_pc), .trace_instr(trace_instr),
        .trace_rd(trace_rd), .trace_rd_value(trace_rd_value),
        .trace_mem_write(trace_mem_write), .trace_mem_addr(trace_mem_addr),
        .trace_mem_wdata(trace_mem_wdata),
        .debug_load_use_stall(load_stall), .debug_control_flush(flush),
        .debug_uart_stall(uart_stall), .uart_tx_pin(tx), .fault(fault)
    );
    function automatic logic [31:0] addi(
        input integer imm, input logic [4:0] rs1, input logic [4:0] rd
    );
        return {imm[11:0], rs1, 3'b000, rd, 7'b0010011};
    endfunction
    function automatic logic [31:0] sb(
        input logic [4:0] rs2, input logic [4:0] rs1
    );
        return {7'b0, rs2, rs1, 3'b000, 5'b0, 7'b0100011};
    endfunction
    task automatic receive(input logic [7:0] expected_byte);
        begin
            @(negedge tx);
            #20;
            if (tx !== 1'b0) $fatal(1, "UART start bit");
            for (int bit_index = 0; bit_index < 8; bit_index++) begin
                #40;
                if (tx !== expected_byte[bit_index])
                    $fatal(1, "UART byte %02x bit %0d", expected_byte, bit_index);
            end
            #40;
            if (tx !== 1'b1) $fatal(1, "UART stop bit");
        end
    endtask
    initial begin
        #1;
        dut.imem0.words[0] = {20'h10000, 5'd1, 7'b0110111};
        dut.imem0.words[1] = addi(65, 0, 2);
        dut.imem0.words[2] = sb(2, 1);
        dut.imem0.words[3] = addi(66, 0, 2);
        dut.imem0.words[4] = sb(2, 1);
        dut.imem0.words[5] = addi(7, 0, 3);
        dut.imem0.words[6] = 32'h0000006f;
        repeat (2) @(negedge clk);
        rst = 1'b0;
        receive(8'h41); // A
        receive(8'h42); // B
        repeat (12) @(posedge clk);
        #1;
        if (fault) $fatal(1, "CPU fault");
        if (dut.rf.regs[3] !== 32'd7) $fatal(1, "CPU did not resume after UART wait");
        if (uart_stall_cycles == 0) $fatal(1, "busy UART did not stall pipeline");
        if (uart_store_count != 2) $fatal(1, "expected two retired UART stores");
        $display("PASS CPU UART: sent AB, waited %0d cycles for TX", uart_stall_cycles);
        $finish;
    end
    always @(posedge clk) if (!rst && uart_stall) uart_stall_cycles = uart_stall_cycles + 1;
    always @(negedge clk) begin
        if (!rst && trace_valid && trace_mem_write) begin
            if (trace_mem_addr !== 32'h10000000) $fatal(1, "UART store address");
            if (uart_store_count == 0 && trace_mem_wdata[7:0] !== 8'h41)
                $fatal(1, "first UART store");
            if (uart_store_count == 1 && trace_mem_wdata[7:0] !== 8'h42)
                $fatal(1, "second UART store");
            uart_store_count = uart_store_count + 1;
        end
    end
endmodule
