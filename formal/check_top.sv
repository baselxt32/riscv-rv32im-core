`include "rvfi_macros.vh"
`ifndef FORMAL_CHECK_CYCLE
`define FORMAL_CHECK_CYCLE 9
`endif

module rvfi_testbench (input clock);
    reg reset = 1'b1;
    reg [7:0] cycle = 0;
    always @(posedge clock) begin
        reset <= 1'b0;
        cycle <= cycle + 8'd1;
    end

    `RVFI_WIRES

    rvfi_wrapper wrapper (
        .clock(clock), .reset(reset),
        `RVFI_CONN32
    );

`ifdef FORMAL_REG_CHECK
    rvfi_reg_check check_inst (
        .clock(clock), .reset(reset), .check(cycle == 8'd12),
        `RVFI_CONN32
    );
`else
    rvfi_insn_check check_inst (
        .clock(clock), .reset(reset), .check(cycle == `FORMAL_CHECK_CYCLE),
        `RVFI_CONN32
    );
`endif
endmodule
