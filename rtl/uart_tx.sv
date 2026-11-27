module uart_tx #(
    parameter int CLOCKS_PER_BIT = 16
) (
    input  logic       clk,
    input  logic       rst,
    input  logic       valid,
    input  logic [7:0] data,
    output logic       ready,
    output logic       tx
);
    localparam int COUNT_BITS = (CLOCKS_PER_BIT < 2) ? 1 : $clog2(CLOCKS_PER_BIT);
    logic busy;
    logic [COUNT_BITS-1:0] ticks_left;
    logic [3:0] bits_sent;
    logic [9:0] shift;

    assign ready = !busy;
    assign tx = busy ? shift[0] : 1'b1;

    always_ff @(posedge clk) begin
        if (rst) begin
            busy <= 1'b0;
            ticks_left <= '0;
            bits_sent <= 4'd0;
            shift <= 10'h3ff;
        end else if (!busy) begin
            if (valid) begin
                busy <= 1'b1;
                ticks_left <= CLOCKS_PER_BIT - 1;
                bits_sent <= 4'd0;
                shift <= {1'b1, data, 1'b0}; // 8N1, least significant bit first
            end
        end else if (ticks_left == 0) begin
            ticks_left <= CLOCKS_PER_BIT - 1;
            if (bits_sent == 4'd9) begin
                busy <= 1'b0;
            end else begin
                bits_sent <= bits_sent + 4'd1;
                shift <= {1'b1, shift[9:1]};
            end
        end else begin
            ticks_left <= ticks_left - 1'b1;
        end
    end
endmodule
