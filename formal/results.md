# RV32IM formal results

SymbiYosys bounded model checks using riscv-formal instruction and register checkers.
Depth 15 and a 120-second timeout per check.
M instruction checks use RISCV_FORMAL_ALTOPS in both the core and the instruction model.
ALTOPS checks pipeline and register behavior, not real arithmetic; the separate random M test checks arithmetic.
A timeout is unproven, not a passing or failing assertion.

| Check | Result | Model |
| --- | --- | --- |
| `add` | PASS | ISA |
| `addi` | PASS | ISA |
| `and` | PASS | ISA |
| `andi` | PASS | ISA |
| `auipc` | PASS | ISA |
| `beq` | PASS | ISA |
| `bge` | PASS | ISA |
| `bgeu` | PASS | ISA |
| `blt` | PASS | ISA |
| `bltu` | PASS | ISA |
| `bne` | PASS | ISA |
| `div` | PASS | ALTOPS |
| `divu` | PASS | ALTOPS |
| `jal` | PASS | ISA |
| `jalr` | PASS | ISA |
| `lb` | PASS | ISA |
| `lbu` | PASS | ISA |
| `lh` | PASS | ISA |
| `lhu` | PASS | ISA |
| `lui` | PASS | ISA |
| `lw` | PASS | ISA |
| `mul` | PASS | ALTOPS |
| `mulh` | PASS | ALTOPS |
| `mulhsu` | PASS | ALTOPS |
| `mulhu` | PASS | ALTOPS |
| `or` | PASS | ISA |
| `ori` | PASS | ISA |
| `rem` | PASS | ALTOPS |
| `remu` | PASS | ALTOPS |
| `sb` | PASS | ISA |
| `sh` | PASS | ISA |
| `sll` | PASS | ISA |
| `slli` | PASS | ISA |
| `slt` | PASS | ISA |
| `slti` | PASS | ISA |
| `sltiu` | PASS | ISA |
| `sltu` | PASS | ISA |
| `sra` | PASS | ISA |
| `srai` | PASS | ISA |
| `srl` | PASS | ISA |
| `srli` | PASS | ISA |
| `sub` | PASS | ISA |
| `sw` | PASS | ISA |
| `xor` | PASS | ISA |
| `xori` | PASS | ISA |
| `reg` | PASS | ISA |

Logs and counterexamples are in `build/formal/<check>/`.
