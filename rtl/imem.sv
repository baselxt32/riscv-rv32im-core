module imem #(
    parameter int WORDS = 1024,
    parameter logic [31:0] BASE_ADDR = 32'b0,
    parameter INIT_FILE = "",
    parameter int INIT_WORDS = 0
) (
    input  logic [31:0] addr,
    output logic [31:0] instr
);
    logic [31:0] words [0:WORDS-1];
    logic [31:0] word_addr;
    initial begin
        for (int i = 0; i < WORDS; i++) words[i] = 32'h00000013; // addi x0,x0,0
        if (INIT_FILE != "") begin
            if (INIT_WORDS > 0)
                $readmemh(INIT_FILE, words, 0, INIT_WORDS - 1);
            else
                $readmemh(INIT_FILE, words);
        end
    end
    assign word_addr = (addr - BASE_ADDR) >> 2;
`ifdef RISCV_FORMAL
    (* anyseq *) logic [31:0] formal_instr;
    assign instr = formal_instr;
`else
    assign instr = (addr >= BASE_ADDR && word_addr < WORDS) ?
                   words[word_addr] : 32'h00000013;
`endif
endmodule
