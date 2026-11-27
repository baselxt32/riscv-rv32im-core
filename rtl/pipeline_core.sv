module pipeline_core #(
    parameter int UART_CLOCKS_PER_BIT = 16,
    parameter PROGRAM_HEX = "",
    parameter int PROGRAM_WORDS = 0,
    parameter logic [31:0] RESET_PC = 32'b0,
    parameter logic [31:0] IMEM_BASE = 32'b0,
    parameter int IMEM_WORDS = 1024,
    parameter logic [31:0] DMEM_BASE = 32'b0,
    parameter int DMEM_BYTES = 4096,
    parameter bit ALLOW_MISALIGNED = 1'b0
) (
    input  logic        clk,
    input  logic        rst,
    output logic        trace_valid,
    output logic [31:0] trace_pc,
    output logic [31:0] trace_instr,
    output logic [4:0]  trace_rd,
    output logic [31:0] trace_rd_value,
    output logic        trace_mem_write,
    output logic [31:0] trace_mem_addr,
    output logic [31:0] trace_mem_wdata,
    output logic        debug_load_use_stall,
    output logic        debug_control_flush,
    output logic        debug_uart_stall,
    output logic        debug_m_stall,
    output logic        uart_tx_pin,
    output logic        fault,
    output logic        rvfi_valid,
    output logic [63:0] rvfi_order,
    output logic [31:0] rvfi_insn,
    output logic        rvfi_trap,
    output logic        rvfi_halt,
    output logic        rvfi_intr,
    output logic [1:0]  rvfi_mode,
    output logic [1:0]  rvfi_ixl,
    output logic [4:0]  rvfi_rs1_addr,
    output logic [4:0]  rvfi_rs2_addr,
    output logic [31:0] rvfi_rs1_rdata,
    output logic [31:0] rvfi_rs2_rdata,
    output logic [4:0]  rvfi_rd_addr,
    output logic [31:0] rvfi_rd_wdata,
    output logic [31:0] rvfi_pc_rdata,
    output logic [31:0] rvfi_pc_wdata,
    output logic [31:0] rvfi_mem_addr,
    output logic [3:0]  rvfi_mem_rmask,
    output logic [3:0]  rvfi_mem_wmask,
    output logic [31:0] rvfi_mem_rdata,
    output logic [31:0] rvfi_mem_wdata
);
    // Pipeline state is declared before use for Icarus Verilog compatibility.
    logic idex_valid;
    logic [31:0] idex_pc, idex_instr, idex_rs1_value, idex_rs2_value;
    logic [31:0] idex_imm, idex_imm_b, idex_imm_j, idex_imm_u, idex_imm_i;
    logic [4:0] idex_rs1, idex_rs2, idex_rd;
    logic [2:0] idex_funct3, idex_branch_type;
    logic [3:0] idex_alu_op;
    logic [1:0] idex_wb_sel;
    logic idex_reg_write, idex_mem_write, idex_mem_read;
    logic idex_alu_src_imm, idex_alu_src_pc, idex_branch_enable;
    logic idex_jal, idex_jalr;
    logic idex_is_m;
    logic idex_is_csr;
    logic [31:0] idex_csr_value;
    logic [4:0] idex_rvfi_rs1, idex_rvfi_rs2;
    logic [31:0] idex_pc_next;

    logic exmem_valid, exmem_reg_write, exmem_mem_write, exmem_mem_read, exmem_trap;
    logic [31:0] exmem_pc, exmem_instr, exmem_alu_result;
    logic [31:0] exmem_store_data, exmem_imm_u, exmem_pc4;
    logic [4:0] exmem_rd;
    logic [2:0] exmem_funct3;
    logic [1:0] exmem_wb_sel;
    logic [4:0] exmem_rvfi_rs1, exmem_rvfi_rs2;
    logic [31:0] exmem_rvfi_rs1_data, exmem_rvfi_rs2_data, exmem_pc_next;

    logic memwb_valid, memwb_reg_write, memwb_mem_write, memwb_trap;
    logic [31:0] memwb_pc, memwb_instr, memwb_wb_value;
    logic [31:0] memwb_mem_addr, memwb_mem_wdata;
    logic [4:0] memwb_rd;
    logic [4:0] memwb_rvfi_rs1, memwb_rvfi_rs2;
    logic [31:0] memwb_rvfi_rs1_data, memwb_rvfi_rs2_data, memwb_pc_next;
    logic [31:0] memwb_mem_rdata;
    logic [3:0] memwb_mem_mask;
    logic memwb_mem_read;
    logic fault_q;

    // Fetch and decode
    logic [31:0] pc, fetched_instr;
`ifdef VERILATOR
    integer mem_trace_fd;
    string mem_trace_path;
    initial begin
        mem_trace_fd = 0;
        if ($value$plusargs("mem_trace=%s", mem_trace_path)) begin
            mem_trace_fd = $fopen(mem_trace_path, "w");
            if (!mem_trace_fd) $fatal(1, "cannot open memory trace %s", mem_trace_path);
        end
    end

    always @(posedge clk) begin
        if (mem_trace_fd && !rst && !fault && !uart_stall) begin
            if (!m_stall && !ex_redirect && !trap_event && !mret_event &&
                !load_use_stall && !serial_wait)
                $fdisplay(mem_trace_fd, "I %08x 4", pc);
            if (exmem_valid && !mem_access_fault && !mem_misaligned) begin
                if (exmem_mem_read)
                    $fdisplay(mem_trace_fd, "L %08x %0d", exmem_alu_result,
                              exmem_funct3[1:0] == 0 ? 1 :
                              exmem_funct3[1:0] == 1 ? 2 : 4);
                if (exmem_mem_write)
                    $fdisplay(mem_trace_fd, "S %08x %0d", exmem_alu_result,
                              exmem_funct3[1:0] == 0 ? 1 :
                              exmem_funct3[1:0] == 1 ? 2 : 4);
            end
        end
    end
`endif
    logic ifid_valid;
    logic [31:0] ifid_pc, ifid_instr;
    logic [31:0] rf_rs1, rf_rs2, dec_rs1, dec_rs2;
    logic [31:0] imm_i, imm_s, imm_b, imm_u, imm_j, dec_imm;
    logic dec_reg_write, dec_mem_write, dec_mem_read;
    logic dec_alu_src_imm, dec_alu_src_pc, dec_branch_enable;
    logic [1:0] dec_wb_sel;
    logic [2:0] dec_branch_type;
    logic dec_jal, dec_jalr, dec_illegal;
    logic [3:0] dec_alu_op;
    logic load_use_stall;
    logic dec_is_system, dec_is_csr, dec_ecall, dec_ebreak, dec_mret;
    logic dec_csr_write, dec_csr_bad, serial_wait, trap_event, mret_event;
    logic csr_valid, csr_writable, csr_write_en;
    logic [31:0] csr_rdata, csr_operand, csr_wdata, csr_trap_vector, csr_epc;
    logic [31:0] trap_cause;
    logic ex_redirect, ex_misaligned, m_stall, uart_stall;
    logic [31:0] ex_target;

    imem #(.WORDS(IMEM_WORDS), .BASE_ADDR(IMEM_BASE),
           .INIT_FILE(PROGRAM_HEX), .INIT_WORDS(PROGRAM_WORDS)) imem0 (
        .addr(pc), .instr(fetched_instr)
    );
    regfile rf (
        .clk(clk), .rst(rst), .rs1(ifid_instr[19:15]),
        .rs2(ifid_instr[24:20]), .rd(memwb_rd),
        .write_data(memwb_wb_value),
        .write_enable(memwb_valid && memwb_reg_write && !fault),
        .read1(rf_rs1), .read2(rf_rs2)
    );
    imm_gen ig (
        .instr(ifid_instr), .imm_i(imm_i), .imm_s(imm_s),
        .imm_b(imm_b), .imm_u(imm_u), .imm_j(imm_j)
    );
    control #(.SUPPORT_M(1'b1), .SUPPORT_SYSTEM(1'b1)) ctl (
        .instr(ifid_instr), .reg_write(dec_reg_write),
        .mem_write(dec_mem_write), .mem_read(dec_mem_read),
        .alu_src_imm(dec_alu_src_imm), .alu_src_pc(dec_alu_src_pc),
        .wb_sel(dec_wb_sel), .branch_enable(dec_branch_enable),
        .branch_type(dec_branch_type), .jal(dec_jal), .jalr(dec_jalr),
        .alu_op(dec_alu_op), .illegal(dec_illegal)
    );

    assign dec_is_system = ifid_instr[6:0] == 7'b1110011;
    assign dec_is_csr = dec_is_system && ifid_instr[14:12] != 3'b000;
    assign dec_ecall = ifid_instr == 32'h00000073;
    assign dec_ebreak = ifid_instr == 32'h00100073;
    assign dec_mret = ifid_instr == 32'h30200073;
    assign dec_csr_write = ifid_instr[13:12] == 2'b01 ||
                           ifid_instr[19:15] != 5'd0;
    assign dec_csr_bad = dec_is_csr &&
                         (!csr_valid || (dec_csr_write && !csr_writable));
    assign serial_wait = ifid_valid && dec_is_system &&
                         (idex_valid || exmem_valid || memwb_valid);
    assign csr_operand = ifid_instr[14] ? {27'b0, ifid_instr[19:15]} : dec_rs1;
    assign csr_wdata = ifid_instr[13:12] == 2'b01 ? csr_operand :
                       ifid_instr[13:12] == 2'b10 ? csr_rdata | csr_operand :
                       csr_rdata & ~csr_operand;
    assign trap_cause = dec_ecall ? 32'd11 : dec_ebreak ? 32'd3 : 32'd2;
    assign trap_event = ifid_valid && !serial_wait && !ex_redirect &&
                        !m_stall && !uart_stall && !fault &&
                        (dec_illegal || dec_csr_bad || dec_ecall || dec_ebreak);
    assign mret_event = ifid_valid && dec_mret && !serial_wait &&
                        !ex_redirect && !m_stall && !uart_stall && !fault;
    assign csr_write_en = ifid_valid && dec_is_csr && dec_csr_write &&
                          !dec_illegal && !dec_csr_bad && !serial_wait &&
                          !ex_redirect && !m_stall && !uart_stall && !fault;
    csr_file csrs (
        .clk(clk), .rst(rst), .addr(ifid_instr[31:20]),
        .rdata(csr_rdata), .valid(csr_valid), .writable(csr_writable),
        .write_en(csr_write_en), .wdata(csr_wdata),
        .trap_en((ex_misaligned && !uart_stall && !fault) || trap_event),
        .trap_pc(ex_misaligned ? idex_pc : ifid_pc),
        .trap_cause(ex_misaligned ? 32'd0 : trap_cause),
        .trap_tval(ex_misaligned ? ex_target : 32'b0),
        .retire(memwb_valid && !fault),
        .trap_vector(csr_trap_vector), .epc(csr_epc)
    );

    hazard_unit hazards (
        .ifid_valid(ifid_valid), .ifid_instr(ifid_instr),
        .idex_valid(idex_valid), .idex_mem_read(idex_mem_read),
        .idex_rd(idex_rd), .load_use_stall(load_use_stall)
    );
    assign dec_imm = ifid_instr[6:0] == 7'b0010111 ? imm_u :
                     ifid_instr[6:0] == 7'b0100011 ? imm_s : imm_i;

    // Execute: newest non-load result has priority over the older WB result.
    logic [31:0] ex_rs1, ex_rs2, ex_alu_a, ex_alu_b, ex_alu_result;
    logic [31:0] ex_base_result, m_result;
    logic [31:0] ex_forward_value;
    logic ex_branch_taken;
    logic m_start, m_busy, m_done;
    logic [31:0] m_rs1_data, m_rs2_data;
    logic uart_access, uart_write, uart_ready;
    forwarding_unit forward (
        .ifid_rs1(ifid_instr[19:15]), .ifid_rs2(ifid_instr[24:20]),
        .rf_rs1(rf_rs1), .rf_rs2(rf_rs2),
        .idex_rs1(idex_rs1), .idex_rs2(idex_rs2),
        .idex_rs1_data(idex_rs1_value), .idex_rs2_data(idex_rs2_value),
        .exmem_valid(exmem_valid), .exmem_reg_write(exmem_reg_write),
        .exmem_mem_read(exmem_mem_read), .exmem_rd(exmem_rd),
        .exmem_value(ex_forward_value),
        .memwb_valid(memwb_valid), .memwb_reg_write(memwb_reg_write),
        .memwb_rd(memwb_rd), .memwb_value(memwb_wb_value),
        .dec_rs1(dec_rs1), .dec_rs2(dec_rs2),
        .ex_rs1(ex_rs1), .ex_rs2(ex_rs2)
    );
    always_comb begin
        ex_alu_a = idex_alu_src_pc ? idex_pc : ex_rs1;
        ex_alu_b = idex_alu_src_imm ? idex_imm : ex_rs2;
        ex_branch_taken = 1'b0;
        if (idex_valid && idex_branch_enable) begin
            case (idex_branch_type)
                3'b000: ex_branch_taken = (ex_rs1 == ex_rs2);
                3'b001: ex_branch_taken = (ex_rs1 != ex_rs2);
                3'b100: ex_branch_taken = ($signed(ex_rs1) < $signed(ex_rs2));
                3'b101: ex_branch_taken = ($signed(ex_rs1) >= $signed(ex_rs2));
                3'b110: ex_branch_taken = (ex_rs1 < ex_rs2);
                3'b111: ex_branch_taken = (ex_rs1 >= ex_rs2);
                default: ex_branch_taken = 1'b0;
            endcase
        end
        ex_redirect = idex_valid && (ex_branch_taken || idex_jal || idex_jalr);
        ex_target = idex_pc + idex_imm_b;
        if (idex_jal) ex_target = idex_pc + idex_imm_j;
        if (idex_jalr) ex_target = (ex_rs1 + idex_imm_i) & 32'hfffffffe;
    end
    assign ex_misaligned = ex_redirect && |ex_target[1:0];
    alu alu0 (.a(ex_alu_a), .b(ex_alu_b), .op(idex_alu_op), .result(ex_base_result));
    assign m_start = idex_valid && idex_is_m && !m_busy && !m_done &&
                     !fault && !uart_stall;
    assign m_stall = idex_valid && idex_is_m && !m_done;
    assign ex_alu_result = idex_is_csr ? idex_csr_value :
                           idex_is_m ? m_result : ex_base_result;
    muldiv m_unit (
        .clk(clk), .rst(rst), .start(m_start), .funct3(idex_funct3),
        .a(ex_rs1), .b(ex_rs2), .busy(m_busy), .done(m_done), .result(m_result)
    );
    always_ff @(posedge clk) begin
        if (rst) begin
            m_rs1_data <= 32'b0;
            m_rs2_data <= 32'b0;
        end else if (m_start) begin
            m_rs1_data <= ex_rs1;
            m_rs2_data <= ex_rs2;
        end
    end

    // Execute/memory forwarding value
    always_comb begin
        case (exmem_wb_sel)
            2'd2: ex_forward_value = exmem_pc4;
            2'd3: ex_forward_value = exmem_imm_u;
            default: ex_forward_value = exmem_alu_result;
        endcase
    end

    logic [31:0] mem_load_data;
    logic mem_access_fault, mem_misaligned;
    assign uart_access = exmem_alu_result == 32'h10000000;
    assign uart_write = exmem_valid && exmem_mem_write && uart_access && !fault_q;
    assign uart_stall = uart_write && !uart_ready;
    uart_tx #(.CLOCKS_PER_BIT(UART_CLOCKS_PER_BIT)) uart0 (
        .clk(clk), .rst(rst), .valid(uart_write),
        .data(exmem_store_data[7:0]), .ready(uart_ready), .tx(uart_tx_pin)
    );
    dmem #(.BYTES(DMEM_BYTES), .BASE_ADDR(DMEM_BASE),
           .ALLOW_MISALIGNED(ALLOW_MISALIGNED)) dmem0 (
        .clk(clk), .rst(rst),
        .read_enable(exmem_valid && exmem_mem_read && !uart_access),
        .write_enable(exmem_valid && exmem_mem_write && !fault_q && !uart_access),
        .funct3(exmem_funct3), .addr(exmem_alu_result),
        .write_data(exmem_store_data), .read_data(mem_load_data),
        .access_fault(mem_access_fault), .misaligned(mem_misaligned)
    );

    // Memory/writeback and trace
    assign fault = fault_q || mem_access_fault || mem_misaligned;
    assign rvfi_valid = memwb_valid && !fault;
    assign rvfi_insn = memwb_instr;
    assign rvfi_trap = memwb_trap;
    assign rvfi_halt = 1'b0;
    assign rvfi_intr = 1'b0;
    assign rvfi_mode = 2'b11;
    assign rvfi_ixl = 2'b01;
    assign rvfi_rs1_addr = memwb_rvfi_rs1;
    assign rvfi_rs2_addr = memwb_rvfi_rs2;
    assign rvfi_rs1_rdata = memwb_rvfi_rs1_data;
    assign rvfi_rs2_rdata = memwb_rvfi_rs2_data;
    assign rvfi_rd_addr = memwb_reg_write && !memwb_trap ? memwb_rd : 5'b0;
    assign rvfi_rd_wdata = rvfi_rd_addr != 5'b0 ? memwb_wb_value : 32'b0;
    assign rvfi_pc_rdata = memwb_pc;
    assign rvfi_pc_wdata = memwb_pc_next;
    assign rvfi_mem_addr = memwb_mem_addr;
    assign rvfi_mem_rmask = memwb_mem_read ? memwb_mem_mask : 4'b0;
    assign rvfi_mem_wmask = memwb_mem_write ? memwb_mem_mask : 4'b0;
    assign rvfi_mem_rdata = memwb_mem_rdata;
    assign rvfi_mem_wdata = memwb_mem_wdata;
    assign debug_load_use_stall = load_use_stall && !ex_redirect && !fault && !uart_stall;
    assign debug_control_flush = ex_redirect && !fault && !uart_stall;
    assign debug_uart_stall = uart_stall;
    assign debug_m_stall = m_stall && !uart_stall && !fault;

`ifndef SYNTHESIS
    // Simulation invariants for the hazard paths and architectural x0.
    always @(posedge clk) begin
        if (!rst && !fault_q) begin
            assert (rf.regs[0] == 32'b0) else $fatal(1, "x0 changed");
            assert (!(exmem_valid && exmem_mem_read && exmem_mem_write))
                else $fatal(1, "memory stage reads and writes together");
            assert (!(debug_load_use_stall && debug_control_flush))
                else $fatal(1, "stall and flush asserted together");
            if (debug_load_use_stall)
                assert (idex_valid && idex_mem_read && idex_rd != 5'd0)
                    else $fatal(1, "illegal load-use stall");
            if (debug_control_flush)
                assert (idex_valid && (ex_branch_taken || idex_jal || idex_jalr))
                    else $fatal(1, "illegal control flush");
            if (idex_valid && exmem_valid && exmem_reg_write &&
                !exmem_mem_read && exmem_rd != 5'd0) begin
                if (idex_rs1 == exmem_rd)
                    assert (ex_rs1 == ex_forward_value)
                        else $fatal(1, "EX rs1 forwarding failed");
                if (idex_rs2 == exmem_rd)
                    assert (ex_rs2 == ex_forward_value)
                        else $fatal(1, "EX rs2 forwarding failed");
            end
        end
    end
`endif

    always_ff @(posedge clk) begin
        if (rst) begin
            rvfi_order <= 64'b0;
            pc <= RESET_PC;
            ifid_valid <= 1'b0;
            ifid_pc <= 32'b0;
            ifid_instr <= 32'b0;
            idex_valid <= 1'b0;
            exmem_valid <= 1'b0;
            memwb_valid <= 1'b0;
            exmem_trap <= 1'b0;
            memwb_trap <= 1'b0;
            trace_valid <= 1'b0;
            trace_pc <= 32'b0;
            trace_instr <= 32'b0;
            trace_rd <= 5'b0;
            trace_rd_value <= 32'b0;
            trace_mem_write <= 1'b0;
            trace_mem_addr <= 32'b0;
            trace_mem_wdata <= 32'b0;
            fault_q <= 1'b0;
        end else if (uart_stall) begin
            // Keep the UART store in MEM until accepted. Retire the older WB
            // instruction once, then leave a WB bubble while waiting.
            memwb_valid <= 1'b0;
            trace_valid <= memwb_valid;
            trace_pc <= memwb_pc;
            trace_instr <= memwb_instr;
            trace_rd <= memwb_reg_write ? memwb_rd : 5'd0;
            trace_rd_value <= memwb_wb_value;
            trace_mem_write <= memwb_valid && memwb_mem_write;
            trace_mem_addr <= memwb_mem_addr;
            trace_mem_wdata <= memwb_mem_wdata;
            if (rvfi_valid) rvfi_order <= rvfi_order + 64'd1;
        end else if (!fault && m_stall) begin
            // Drain older instructions while the M operation holds EX.
            exmem_valid <= 1'b0;
            memwb_valid <= exmem_valid;
            memwb_trap <= exmem_trap;
            memwb_pc <= exmem_pc;
            memwb_instr <= exmem_instr;
            memwb_rd <= exmem_rd;
            memwb_reg_write <= exmem_reg_write;
            memwb_mem_write <= exmem_mem_write;
            memwb_mem_addr <= exmem_alu_result;
            memwb_mem_wdata <= exmem_store_data;
            memwb_wb_value <= exmem_mem_read ?
                              (uart_access ? {31'b0, uart_ready} : mem_load_data) :
                              ex_forward_value;
            memwb_rvfi_rs1 <= exmem_rvfi_rs1;
            memwb_rvfi_rs2 <= exmem_rvfi_rs2;
            memwb_rvfi_rs1_data <= exmem_rvfi_rs1_data;
            memwb_rvfi_rs2_data <= exmem_rvfi_rs2_data;
            memwb_pc_next <= exmem_pc_next;
            memwb_mem_read <= exmem_mem_read;
            memwb_mem_rdata <= uart_access ? {31'b0, uart_ready} : mem_load_data;
            memwb_mem_mask <= exmem_funct3[1:0] == 2'b00 ? 4'b0001 :
                              exmem_funct3[1:0] == 2'b01 ? 4'b0011 : 4'b1111;
            trace_valid <= memwb_valid;
            trace_pc <= memwb_pc;
            trace_instr <= memwb_instr;
            trace_rd <= memwb_reg_write ? memwb_rd : 5'd0;
            trace_rd_value <= memwb_wb_value;
            trace_mem_write <= memwb_valid && memwb_mem_write;
            trace_mem_addr <= memwb_mem_addr;
            trace_mem_wdata <= memwb_mem_wdata;
            if (rvfi_valid) rvfi_order <= rvfi_order + 64'd1;
        end else if (!fault) begin
            if (rvfi_valid) rvfi_order <= rvfi_order + 64'd1;
            if (ex_redirect) begin
                pc <= ex_misaligned ? csr_trap_vector : ex_target;
                ifid_valid <= 1'b0;
            end else if (trap_event || mret_event) begin
                pc <= trap_event ? csr_trap_vector : csr_epc;
                ifid_valid <= 1'b0;
            end else if (!load_use_stall && !serial_wait) begin
                pc <= pc + 32'd4;
                ifid_valid <= 1'b1;
                ifid_pc <= pc;
                ifid_instr <= fetched_instr;
            end

            if (ex_redirect || trap_event || load_use_stall || serial_wait) begin
                idex_valid <= 1'b0;
            end else begin
                idex_valid <= ifid_valid && !dec_illegal && !dec_csr_bad;
                idex_pc <= ifid_pc;
                idex_instr <= ifid_instr;
                idex_rs1_value <= dec_rs1;
                idex_rs2_value <= dec_rs2;
                idex_rs1 <= ifid_instr[19:15];
                idex_rs2 <= ifid_instr[24:20];
                idex_rd <= ifid_instr[11:7];
                idex_imm <= dec_imm;
                idex_imm_i <= imm_i;
                idex_imm_b <= imm_b;
                idex_imm_j <= imm_j;
                idex_imm_u <= imm_u;
                idex_funct3 <= ifid_instr[14:12];
                idex_branch_type <= dec_branch_type;
                idex_alu_op <= dec_alu_op;
                idex_wb_sel <= dec_wb_sel;
                idex_reg_write <= dec_reg_write;
                idex_mem_write <= dec_mem_write;
                idex_mem_read <= dec_mem_read;
                idex_alu_src_imm <= dec_alu_src_imm;
                idex_alu_src_pc <= dec_alu_src_pc;
                idex_branch_enable <= dec_branch_enable;
                idex_jal <= dec_jal;
                idex_jalr <= dec_jalr;
                idex_is_m <= ifid_instr[6:0] == 7'b0110011 &&
                             ifid_instr[31:25] == 7'b0000001;
                idex_is_csr <= dec_is_csr;
                idex_csr_value <= csr_rdata;
                idex_rvfi_rs1 <= (ifid_instr[6:0] == 7'h33 ||
                                   ifid_instr[6:0] == 7'h13 ||
                                   ifid_instr[6:0] == 7'h03 ||
                                   ifid_instr[6:0] == 7'h23 ||
                                   ifid_instr[6:0] == 7'h63 ||
                                   ifid_instr[6:0] == 7'h67 ||
                                   (dec_is_csr && !ifid_instr[14])) ?
                                  ifid_instr[19:15] : 5'b0;
                idex_rvfi_rs2 <= (ifid_instr[6:0] == 7'h33 ||
                                   ifid_instr[6:0] == 7'h23 ||
                                   ifid_instr[6:0] == 7'h63) ?
                                  ifid_instr[24:20] : 5'b0;
                idex_pc_next <= dec_mret ? csr_epc : ifid_pc + 32'd4;
            end

            exmem_valid <= idex_valid;
            exmem_trap <= ex_misaligned;
            exmem_pc <= idex_pc;
            exmem_instr <= idex_instr;
            exmem_alu_result <= ex_alu_result;
            exmem_store_data <= ex_rs2;
            exmem_imm_u <= idex_imm_u;
            exmem_pc4 <= idex_pc + 32'd4;
            exmem_rd <= idex_rd;
            exmem_funct3 <= idex_funct3;
            exmem_wb_sel <= idex_wb_sel;
            exmem_reg_write <= idex_reg_write && !ex_misaligned;
            exmem_mem_write <= idex_mem_write;
            exmem_mem_read <= idex_mem_read;
            exmem_rvfi_rs1 <= idex_rvfi_rs1;
            exmem_rvfi_rs2 <= idex_rvfi_rs2;
            exmem_rvfi_rs1_data <= idex_rvfi_rs1 != 5'b0 ?
                                   (idex_is_m ? m_rs1_data : ex_rs1) : 32'b0;
            exmem_rvfi_rs2_data <= idex_rvfi_rs2 != 5'b0 ?
                                   (idex_is_m ? m_rs2_data : ex_rs2) : 32'b0;
            exmem_pc_next <= ex_misaligned ? csr_trap_vector :
                             ex_redirect ? ex_target : idex_pc_next;

            memwb_valid <= exmem_valid;
            memwb_trap <= exmem_trap;
            memwb_pc <= exmem_pc;
            memwb_instr <= exmem_instr;
            memwb_rd <= exmem_rd;
            memwb_reg_write <= exmem_reg_write;
            memwb_mem_write <= exmem_mem_write;
            memwb_mem_addr <= exmem_alu_result;
            memwb_mem_wdata <= exmem_store_data;
            memwb_wb_value <= exmem_mem_read ?
                              (uart_access ? {31'b0, uart_ready} : mem_load_data) :
                              ex_forward_value;
            memwb_rvfi_rs1 <= exmem_rvfi_rs1;
            memwb_rvfi_rs2 <= exmem_rvfi_rs2;
            memwb_rvfi_rs1_data <= exmem_rvfi_rs1_data;
            memwb_rvfi_rs2_data <= exmem_rvfi_rs2_data;
            memwb_pc_next <= exmem_pc_next;
            memwb_mem_read <= exmem_mem_read;
            memwb_mem_rdata <= uart_access ? {31'b0, uart_ready} : mem_load_data;
            memwb_mem_mask <= exmem_funct3[1:0] == 2'b00 ? 4'b0001 :
                              exmem_funct3[1:0] == 2'b01 ? 4'b0011 : 4'b1111;

            trace_valid <= memwb_valid;
            trace_pc <= memwb_pc;
            trace_instr <= memwb_instr;
            trace_rd <= memwb_reg_write ? memwb_rd : 5'd0;
            trace_rd_value <= memwb_wb_value;
            trace_mem_write <= memwb_valid && memwb_mem_write;
            trace_mem_addr <= memwb_mem_addr;
            trace_mem_wdata <= memwb_mem_wdata;
        end else begin
            trace_valid <= 1'b0;
            trace_mem_write <= 1'b0;
            fault_q <= 1'b1;
        end
    end
endmodule
