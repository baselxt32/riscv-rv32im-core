RTL := $(wildcard rtl/*.sv)
BUILD := build
SIM ?= icarus

.PHONY: smoke smoke-iverilog unit-iverilog muldiv-iverilog muldiv-random-iverilog instructions-iverilog pipeline-iverilog pipeline-forward-iverilog pipeline-system-iverilog misaligned-target-iverilog csr-iverilog uart-iverilog cpu-uart-iverilog demo-iverilog hello-hex test-iverilog test-verilator regress regress-verilator compare-budgets official formal test clean
smoke:
	verilator --binary --timing --top-module smoke_tb -Wno-fatal --Mdir $(BUILD)/smoke $(RTL) tests/smoke_tb.sv
	$(BUILD)/smoke/Vsmoke_tb

smoke-iverilog:
	mkdir -p $(BUILD)
	iverilog -g2012 -gassertions -s smoke_tb -o $(BUILD)/smoke.vvp $(RTL) tests/smoke_tb.sv
	vvp $(BUILD)/smoke.vvp

unit-iverilog:
	mkdir -p $(BUILD)
	iverilog -g2012 -gassertions -s alu_imm_tb -o $(BUILD)/alu_imm.vvp rtl/alu.sv rtl/imm_gen.sv tests/alu_imm_tb.sv
	vvp $(BUILD)/alu_imm.vvp

muldiv-iverilog:
	mkdir -p $(BUILD)
	iverilog -g2012 -gassertions -s muldiv_tb -o $(BUILD)/muldiv.vvp rtl/muldiv.sv tests/muldiv_tb.sv
	vvp $(BUILD)/muldiv.vvp

muldiv-random-iverilog:
	mkdir -p $(BUILD)
	iverilog -g2012 -gassertions -s muldiv_random_tb -o $(BUILD)/muldiv_random.vvp rtl/muldiv.sv tests/muldiv_random_tb.sv
	vvp $(BUILD)/muldiv_random.vvp

instructions-iverilog:
	mkdir -p $(BUILD)
	iverilog -g2012 -gassertions -s instructions_tb -o $(BUILD)/instructions.vvp $(RTL) tests/instructions_tb.sv
	vvp $(BUILD)/instructions.vvp

pipeline-iverilog:
	mkdir -p $(BUILD)
	iverilog -g2012 -gassertions -s pipeline_tb -o $(BUILD)/pipeline.vvp $(RTL) tests/pipeline_tb.sv
	vvp $(BUILD)/pipeline.vvp

pipeline-forward-iverilog:
	mkdir -p $(BUILD)
	iverilog -g2012 -gassertions -s pipeline_forward_tb -o $(BUILD)/pipeline_forward.vvp $(RTL) tests/pipeline_forward_tb.sv
	vvp $(BUILD)/pipeline_forward.vvp

pipeline-system-iverilog:
	mkdir -p $(BUILD)
	iverilog -g2012 -gassertions -s pipeline_system_tb -o $(BUILD)/pipeline_system.vvp $(RTL) tests/pipeline_system_tb.sv
	vvp $(BUILD)/pipeline_system.vvp

misaligned-target-iverilog:
	mkdir -p $(BUILD)
	iverilog -g2012 -gassertions -s misaligned_target_tb -o $(BUILD)/misaligned_target.vvp $(RTL) tests/misaligned_target_tb.sv
	vvp $(BUILD)/misaligned_target.vvp

csr-iverilog:
	mkdir -p $(BUILD)
	iverilog -g2012 -gassertions -s csr_ops_tb -o $(BUILD)/csr_ops.vvp $(RTL) tests/csr_ops_tb.sv
	vvp $(BUILD)/csr_ops.vvp

uart-iverilog:
	mkdir -p $(BUILD)
	iverilog -g2012 -gassertions -s uart_tx_tb -o $(BUILD)/uart_tx.vvp rtl/uart_tx.sv tests/uart_tx_tb.sv
	vvp $(BUILD)/uart_tx.vvp

cpu-uart-iverilog:
	mkdir -p $(BUILD)
	iverilog -g2012 -gassertions -s cpu_uart_tb -o $(BUILD)/cpu_uart.vvp $(RTL) tests/cpu_uart_tb.sv
	vvp $(BUILD)/cpu_uart.vvp

hello-hex:
	python3 software/build_hello.py

demo-iverilog: hello-hex
	mkdir -p $(BUILD)
	iverilog -g2012 -gassertions -s demo_top_tb -o $(BUILD)/demo.vvp $(RTL) tests/demo_top_tb.sv
	vvp $(BUILD)/demo.vvp

test-iverilog: smoke-iverilog unit-iverilog muldiv-iverilog muldiv-random-iverilog instructions-iverilog pipeline-iverilog pipeline-forward-iverilog pipeline-system-iverilog misaligned-target-iverilog csr-iverilog uart-iverilog cpu-uart-iverilog demo-iverilog

test-verilator:
	python3 verify/sv_tests.py

regress:
	python3 verify/regress.py --simulator $(SIM) --output-dir build/regression-$(SIM)

regress-verilator:
	python3 verify/regress.py --simulator verilator --output-dir build/regression-verilator

compare-budgets:
	python3 verify/compare_budgets.py

official:
	python3 verify/official.py --simulator $(SIM)

formal:
	python3 formal/run.py

ifeq ($(SIM),verilator)
test: test-verilator regress official
else
test: test-iverilog regress official
endif

clean:
	rm -rf $(BUILD)
