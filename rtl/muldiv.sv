module muldiv (
    input  logic        clk,
    input  logic        rst,
    input  logic        start,
    input  logic [2:0]  funct3,
    input  logic [31:0] a,
    input  logic [31:0] b,
    output logic        busy,
    output logic        done,
    output logic [31:0] result
);
    logic [63:0] product_uu;
    logic signed [63:0] product_ss, product_su;
    logic [31:0] dividend, divisor, quotient;
    logic [32:0] remainder, trial, next_remainder;
    logic [31:0] next_quotient;
    logic [5:0] count;
    logic neg_quotient, neg_remainder, return_remainder;
    logic special;
    logic [31:0] special_value;
    logic subtract;
`ifdef RISCV_FORMAL_ALTOPS
    logic [31:0] alt_result;

    always_comb begin
        case (funct3)
            3'b000: alt_result = (a + b) ^ 32'h5876063e;
            3'b001: alt_result = (a + b) ^ 32'hf6583fb7;
            3'b010: alt_result = (a - b) ^ 32'hecfbe137;
            3'b011: alt_result = (a + b) ^ 32'h949ce5e8;
            3'b100: alt_result = (a - b) ^ 32'h7f8529ec;
            3'b101: alt_result = (a - b) ^ 32'h10e8fd70;
            3'b110: alt_result = (a - b) ^ 32'h8da68fa5;
            default: alt_result = (a - b) ^ 32'h3138d0e1;
        endcase
    end
`endif

    assign product_uu = a * b;
    assign product_ss = $signed(a) * $signed(b);
    assign product_su = $signed({{32{a[31]}}, a}) * $signed({32'b0, b});
    assign trial = {remainder[31:0], dividend[31]};
    assign subtract = trial >= {1'b0, divisor};
    assign next_remainder = subtract ? trial - {1'b0, divisor} : trial;
    assign next_quotient = {quotient[30:0], subtract};

    always_ff @(posedge clk) begin
        if (rst) begin
            busy <= 1'b0;
            done <= 1'b0;
            result <= 32'b0;
            dividend <= 32'b0;
            divisor <= 32'b0;
            quotient <= 32'b0;
            remainder <= 33'b0;
            count <= 6'b0;
            neg_quotient <= 1'b0;
            neg_remainder <= 1'b0;
            return_remainder <= 1'b0;
            special <= 1'b0;
            special_value <= 32'b0;
        end else begin
            done <= 1'b0;
            if (start && !busy) begin
`ifdef RISCV_FORMAL_ALTOPS
                result <= alt_result;
                done <= 1'b1;
`else
                if (!funct3[2]) begin
                    case (funct3)
                        3'b000: result <= product_uu[31:0];
                        3'b001: result <= product_ss[63:32];
                        3'b010: result <= product_su[63:32];
                        default: result <= product_uu[63:32];
                    endcase
                    done <= 1'b1;
                end else begin
                    busy <= 1'b1;
                    count <= 6'd32;
                    dividend <= (!funct3[0] && a[31]) ? -a : a;
                    divisor <= (!funct3[0] && b[31]) ? -b : b;
                    quotient <= 32'b0;
                    remainder <= 33'b0;
                    neg_quotient <= !funct3[0] && (a[31] ^ b[31]);
                    neg_remainder <= !funct3[0] && a[31];
                    return_remainder <= funct3[1];
                    special <= b == 32'b0 ||
                               (!funct3[0] && a == 32'h80000000 && b == 32'hffffffff);
                    if (b == 32'b0)
                        special_value <= funct3[1] ? a : 32'hffffffff;
                    else
                        special_value <= funct3[1] ? 32'b0 : a;
                end
`endif
            end else if (busy) begin
                if (special) begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    result <= special_value;
                end else begin
                    dividend <= {dividend[30:0], 1'b0};
                    quotient <= next_quotient;
                    remainder <= next_remainder;
                    count <= count - 1'b1;
                    if (count == 6'd1) begin
                        busy <= 1'b0;
                        done <= 1'b1;
                        if (return_remainder)
                            result <= neg_remainder ? -next_remainder[31:0] :
                                                      next_remainder[31:0];
                        else
                            result <= neg_quotient ? -next_quotient : next_quotient;
                    end
                end
            end
        end
    end
endmodule
