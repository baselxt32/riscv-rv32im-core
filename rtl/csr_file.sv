module csr_file (
    input  logic        clk,
    input  logic        rst,
    input  logic [11:0] addr,
    output logic [31:0] rdata,
    output logic        valid,
    output logic        writable,
    input  logic        write_en,
    input  logic [31:0] wdata,
    input  logic        trap_en,
    input  logic [31:0] trap_pc,
    input  logic [31:0] trap_cause,
    input  logic [31:0] trap_tval,
    input  logic        retire,
    output logic [31:0] trap_vector,
    output logic [31:0] epc
);
    logic [63:0] cycle_count, instret_count;
    logic [31:0] mtvec, mepc, mcause, mtval, mstatus, mie, medeleg, mideleg;
    logic [31:0] pmpaddr0, pmpcfg0, mnstatus;

    assign trap_vector = mtvec;
    assign epc = mepc;

    always_comb begin
        rdata = 32'b0;
        valid = 1'b1;
        writable = 1'b0;
        case (addr)
            12'h180: begin rdata = 32'b0; writable = 1'b1; end
            12'h300: begin rdata = mstatus; writable = 1'b1; end
            12'h301: rdata = 32'h40001100;
            12'h302: begin rdata = medeleg; writable = 1'b1; end
            12'h303: begin rdata = mideleg; writable = 1'b1; end
            12'h304: begin rdata = mie; writable = 1'b1; end
            12'h305: begin rdata = mtvec; writable = 1'b1; end
            12'h3a0: begin rdata = pmpcfg0; writable = 1'b1; end
            12'h3b0: begin rdata = pmpaddr0; writable = 1'b1; end
            12'h341: begin rdata = mepc; writable = 1'b1; end
            12'h342: begin rdata = mcause; writable = 1'b1; end
            12'h343: begin rdata = mtval; writable = 1'b1; end
            12'h344: begin rdata = 32'b0; writable = 1'b1; end
            12'h744: begin rdata = mnstatus; writable = 1'b1; end
            12'hf14: rdata = 32'b0;
            12'hb00: begin rdata = cycle_count[31:0]; writable = 1'b1; end
            12'hb80: begin rdata = cycle_count[63:32]; writable = 1'b1; end
            12'hb02: begin rdata = instret_count[31:0]; writable = 1'b1; end
            12'hb82: begin rdata = instret_count[63:32]; writable = 1'b1; end
            12'hc00: rdata = cycle_count[31:0];
            12'hc80: rdata = cycle_count[63:32];
            12'hc02: rdata = instret_count[31:0];
            12'hc82: rdata = instret_count[63:32];
            default: valid = 1'b0;
        endcase
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            cycle_count <= 64'b0;
            instret_count <= 64'b0;
            mtvec <= 32'h00000100;
            mepc <= 32'b0;
            mcause <= 32'b0;
            mtval <= 32'b0;
            mstatus <= 32'b0;
            mie <= 32'b0;
            medeleg <= 32'b0;
            mideleg <= 32'b0;
            pmpaddr0 <= 32'b0;
            pmpcfg0 <= 32'b0;
            mnstatus <= 32'b0;
        end else begin
            cycle_count <= cycle_count + 1'b1;
            if (retire) instret_count <= instret_count + 1'b1;
            if (write_en) begin
                case (addr)
                    12'h300: mstatus <= wdata;
                    12'h302: medeleg <= wdata;
                    12'h303: mideleg <= wdata;
                    12'h304: mie <= wdata;
                    12'h305: mtvec <= {wdata[31:2], 2'b00};
                    12'h3a0: pmpcfg0 <= wdata;
                    12'h3b0: pmpaddr0 <= wdata;
                    12'h341: mepc <= {wdata[31:2], 2'b00};
                    12'h342: mcause <= wdata;
                    12'h343: mtval <= wdata;
                    12'h744: mnstatus <= wdata;
                    12'hb00: cycle_count[31:0] <= wdata;
                    12'hb80: cycle_count[63:32] <= wdata;
                    12'hb02: instret_count[31:0] <= wdata;
                    12'hb82: instret_count[63:32] <= wdata;
                    default: begin end
                endcase
            end
            if (trap_en) begin
                mepc <= {trap_pc[31:2], 2'b00};
                mcause <= trap_cause;
                mtval <= trap_tval;
            end
        end
    end
endmodule
