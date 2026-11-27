module rvfi_wrapper (
    input clock,
    input reset,
    `RVFI_OUTPUTS
);
    pipeline_core #(.IMEM_WORDS(16), .DMEM_BYTES(64)) core (
        .clk(clock), .rst(reset),
        `RVFI_CONN32
    );
endmodule
