# RV32IM processor

This is a five-stage RISC-V processor written in SystemVerilog, built from an earlier single-cycle core in this repository. It executes RV32I and RV32M instructions, forwards results between stages, stalls for load-use and multi-cycle divide dependencies, and flushes wrong-path instructions after branches and jumps. Taken branches and jumps to addresses that are not 4-byte aligned trap with `mcause=0`, `mepc` at the branch or jump, and `mtval` at the target. The pipeline has a memory-mapped UART transmitter at `0x10000000`. Instruction and data memory are separate behavioral arrays.

```text
       PC -> instruction ROM -> IF/ID -> register file -> ID/EX -> ALU, branch, M unit
                                                               |             |
                                                        forwarding      redirect/flush
                                                               |             |
                                          register write <- MEM/WB <- EX/MEM <- data memory
```

The decoder, ALU, register file, immediate generator, forwarding unit, hazard unit, M unit, CSR file, and memories are separate modules under `rtl/`. `rtl/core.sv` is the original single-cycle RV32I core; `rtl/pipeline_core.sv` is the tested RV32IM pipeline. `rtl/demo_top.sv` connects the pipeline to a ROM program and UART TX pin for simulation.

## Run

Install Icarus Verilog, Python 3, and a host C compiler. In this workspace, `./run_tests.sh` finds the local Icarus build and sources `~/oss-cad-suite/environment` when present. Run either simulator with:

```sh
./run_tests.sh --simulator icarus
./run_tests.sh --simulator verilator
```

Each command runs 13 directed SystemVerilog testbenches, the C-model retirement regression, and the precompiled official `rv32ui-p` and `rv32um-p` tests. The official runner downloads a pinned [riscv-tests release](https://github.com/riscv-software-src/sail-riscv-tests/releases/tag/2026-08-20) on its first run, checks its SHA-256 digest, and writes individual results to `build/official/results.json`. An internet connection is needed only for that first download. `make official` runs just the official suite; `python3 verify/official.py --test rv32ui-p-add` runs one binary.

`python3 verify/regress.py --seed 42 --seeds 3 --blocks 100` runs the generated-program regression with chosen seeds. `make compare-budgets` compares three regression sizes. `make demo-iverilog` runs a ROM-loaded program that prints `Hi` through the UART pin. `make clean` removes generated files.

To run formal checks, install SymbiYosys and Boolector, clone [riscv-formal](https://github.com/YosysHQ/riscv-formal) into `../../work/riscv-formal` from this directory or set `RISCV_FORMAL_DIR` to another checkout, then run `make formal`. The runner sources OSS CAD Suite if present and writes per-check logs and JSON under `build/formal/`, plus a Markdown table at `formal/results.md`. It exits nonzero while any check fails or times out.

## Verification results

- Both Icarus and Verilator pass on this computer: 13 directed testbenches, 21 C-model-checked programs with 651 retired instructions, and 49 official ISA binaries. The one skipped official binary is `rv32ui-p-fence_i`, which tests the separate Zifencei extension.
- The C model compares each retired PC, instruction, register write, and data-memory store in order. It stops at the first mismatch. Its 21 programs include directed hazard cases and three seeded random programs. Coverage counters report instruction classes, branch outcomes, load-use pairs, forwarding dependencies, flushes, and M-unit stalls.
- Directed tests cover CSR operations, illegal-instruction, ECALL, EBREAK, and misaligned-target traps, MRET, FENCE, UART framing, and pipeline hazards. The M-unit test checks 512 edge-case and 8,000 seeded-random operations against a separate arithmetic model under both simulators. The official binaries run through their own startup and report pass/fail through `tohost`.
- The riscv-formal instruction and register checks pass 46 of 46 bounded checks at depth 15. All eight M instruction checks use `RISCV_FORMAL_ALTOPS` in the formal build; they check pipeline and register behavior with substituted arithmetic, not the real multiplier or divider. The real arithmetic is checked by the random M-unit test and the official `rv32um-p` binaries. These are bounded checks, not unbounded proofs. The full per-check table is in `formal/results.md`.
- The C regression measured 2.186 aggregate cycles per retired instruction for these short synthetic programs. This is a test-suite figure, not a CoreMark or Dhrystone score. `make compare-budgets` records wall time and coverage at three random-program sizes.

## Current limits

- The CSR implementation has `cycle`, `instret`, `mcause`, `mepc`, `mtval`, and `mtvec`, plus the machine-mode startup CSRs used by the official test harness. It does not implement a complete privilege system, interrupts, page translation, or PMP enforcement. `FENCE` is a no-op with the current ordered memory model.
- The official test configuration enables misaligned byte-array memory accesses. The normal pipeline configuration faults on misaligned halfword and word accesses. The memory arrays are asynchronous simulation models, not FPGA block RAM.
- The C model checks RV32IM data-path programs. System instructions and traps are covered by directed RTL tests and the official suite. RVFI instruction and register checks are bounded; Spike lockstep has not been run.
- No branch predictor, caches, C cross-toolchain flow, standard software benchmark, FPGA implementation, or timing report has been completed. The UART top has been simulated, not placed on a board.

## Next work

Build Spike and compare its retirement trace against RVFI, then compile and run a small C program with a RISC-V cross-toolchain. Increase the formal bounds. After that, add measured cache and branch-prediction changes and synthesize the design.
