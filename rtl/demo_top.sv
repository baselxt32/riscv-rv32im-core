module demo_top #(
    parameter int CLK_HZ = 100_000_000,
    parameter int BAUD = 115_200,
    parameter PROGRAM_HEX = "software/hello.hex",
    parameter int PROGRAM_WORDS = 8
) (
    input  logic clk,
    input  logic rst,
    output logic uart_tx_pin,
    output logic fault_led
);
    localparam int CLOCKS_PER_BIT = (CLK_HZ + BAUD / 2) / BAUD;
    pipeline_core #(
        .UART_CLOCKS_PER_BIT(CLOCKS_PER_BIT),
        .PROGRAM_HEX(PROGRAM_HEX), .PROGRAM_WORDS(PROGRAM_WORDS)
    ) cpu (
        .clk(clk), .rst(rst), .uart_tx_pin(uart_tx_pin), .fault(fault_led)
    );
endmodule
