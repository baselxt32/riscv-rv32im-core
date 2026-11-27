module dmem #(
    parameter int BYTES = 4096,
    parameter logic [31:0] BASE_ADDR = 32'b0,
    parameter bit ALLOW_MISALIGNED = 1'b0
) (
    input  logic        clk,
    input  logic        rst,
    input  logic        read_enable,
    input  logic        write_enable,
    input  logic [2:0]  funct3,
    input  logic [31:0] addr,
    input  logic [31:0] write_data,
    output logic [31:0] read_data,
    output logic        access_fault,
    output logic        misaligned
);
    logic [7:0] bytes [0:BYTES-1];
    logic [31:0] raw;
    logic [31:0] offset;
    logic [2:0] size_bytes;
    integer i;
    assign offset = addr - BASE_ADDR;
    always_comb begin
        case (funct3[1:0])
            2'b00: size_bytes = 3'd1;
            2'b01: size_bytes = 3'd2;
            default: size_bytes = 3'd4;
        endcase
        misaligned = !ALLOW_MISALIGNED && (read_enable || write_enable) &&
                     ((size_bytes == 3'd2 && addr[0]) ||
                      (size_bytes == 3'd4 && |addr[1:0]));
        access_fault = (read_enable || write_enable) &&
                       (addr < BASE_ADDR || offset > BYTES - size_bytes);
        raw = 32'b0;
        if (!access_fault && !misaligned && read_enable) begin
            raw[7:0] = bytes[offset];
            if (size_bytes >= 3'd2) raw[15:8] = bytes[offset + 1];
            if (size_bytes == 3'd4) begin
                raw[23:16] = bytes[offset + 2];
                raw[31:24] = bytes[offset + 3];
            end
        end
        case (funct3)
            3'b000: read_data = {{24{raw[7]}}, raw[7:0]};
            3'b001: read_data = {{16{raw[15]}}, raw[15:0]};
            3'b010: read_data = raw;
            3'b100: read_data = {24'b0, raw[7:0]};
            3'b101: read_data = {16'b0, raw[15:0]};
            default: read_data = 32'b0;
        endcase
    end
    always_ff @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < BYTES; i = i + 1) bytes[i] <= 8'b0;
        end else if (write_enable && !access_fault && !misaligned) begin
            bytes[offset] <= write_data[7:0];
            if (size_bytes >= 3'd2) bytes[offset + 1] <= write_data[15:8];
            if (size_bytes == 3'd4) begin
                bytes[offset + 2] <= write_data[23:16];
                bytes[offset + 3] <= write_data[31:24];
            end
        end
    end
endmodule
