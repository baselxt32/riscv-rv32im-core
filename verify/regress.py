#!/usr/bin/env python3
"""Generate legal RV32I programs and compare each retirement with a C model."""
from __future__ import annotations

import argparse
from collections import Counter
import json
import os
from pathlib import Path
import random
import shutil
import subprocess

from tool_env import load_oss_cad

ROOT = Path(__file__).resolve().parents[1]
LOCAL_TOOLS = ROOT.parents[1] / "work" / "iverilog-install" / "bin"


def r(f7: int, rs2: int, rs1: int, f3: int, rd: int) -> int:
    return (f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | 0x33


def i(imm: int, rs1: int, f3: int, rd: int, opcode: int = 0x13) -> int:
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | opcode


def s(imm: int, rs2: int, rs1: int, f3: int) -> int:
    imm &= 0xFFF
    return ((imm >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | ((imm & 31) << 7) | 0x23


def b(imm: int, rs2: int, rs1: int, f3: int) -> int:
    imm &= 0x1FFF
    return (((imm >> 12) & 1) << 31) | (((imm >> 5) & 63) << 25) | \
           (rs2 << 20) | (rs1 << 15) | (f3 << 12) | \
           (((imm >> 1) & 15) << 8) | (((imm >> 11) & 1) << 7) | 0x63


def j(imm: int, rd: int) -> int:
    imm &= 0x1FFFFF
    return (((imm >> 20) & 1) << 31) | (((imm >> 1) & 1023) << 21) | \
           (((imm >> 11) & 1) << 20) | (((imm >> 12) & 255) << 12) | \
           (rd << 7) | 0x6F


def directed_program() -> list[int]:
    """Control flow plus EX forwarding, store forwarding, and a load-use stall."""
    return [
        i(5, 0, 0, 1), i(7, 1, 0, 2), i(1, 2, 0, 3),
        s(0, 3, 0, 2), i(0, 0, 2, 4, 0x03), i(2, 4, 0, 5),
        b(8, 3, 5, 1), i(99, 0, 0, 6), i(1, 5, 0, 7),
        j(8, 8), i(99, 0, 0, 9), i(1, 8, 0, 10),
        b(8, 10, 10, 1), j(0, 0),
    ]


def instruction_program() -> list[int]:
    """Exercise upper immediates, signed shifts, byte/halfword memory, and JALR."""
    return [
        i(-1, 0, 0, 1), i(1, 0, 0, 2),
        r(0, 2, 1, 2, 3), r(0, 2, 1, 3, 4),
        i(0x401, 1, 5, 5), i(1, 1, 5, 6), i(5, 2, 1, 7),
        r(0x20, 1, 2, 0, 8), r(0, 7, 1, 7, 9),
        r(0, 7, 2, 6, 10), r(0, 7, 10, 4, 11),
        (0x12345 << 12) | (12 << 7) | 0x37,
        (13 << 7) | 0x17,
        i(128, 0, 0, 14), s(0, 1, 14, 0),
        i(0, 14, 4, 15, 0x03), i(0, 14, 0, 16, 0x03),
        s(2, 7, 14, 1), i(2, 14, 5, 17, 0x03),
        i(2, 14, 1, 18, 0x03), i(88, 0, 0, 19, 0x67),
        i(99, 0, 0, 20), b(8, 2, 1, 1),
        i(99, 0, 0, 21), i(7, 0, 0, 22), j(0, 0),
    ]


def m_program() -> list[int]:
    return [
        i(-20, 0, 0, 1), i(3, 0, 0, 2),
        *[r(1, 2, 1, f3, f3 + 3) for f3 in range(8)],
        r(1, 0, 1, 4, 11), r(1, 0, 1, 6, 12),
        (0x80000 << 12) | (13 << 7) | 0x37,
        i(-1, 0, 0, 14),
        r(1, 14, 13, 4, 15), r(1, 14, 13, 6, 16),
        s(0, 2, 0, 2), i(0, 0, 2, 19, 0x03),
        r(1, 19, 1, 0, 20), i(1, 20, 0, 21),
    ]


def branch_operands(f3: int, taken: bool) -> tuple[int, int]:
    """Register choices for x1=-1 and x2=1, in rs1/rs2 order."""
    taken_operands = {
        0: (1, 1), 1: (1, 2), 4: (1, 2),
        5: (2, 1), 6: (2, 1), 7: (1, 2),
    }
    not_taken_operands = {
        0: (1, 2), 1: (1, 1), 4: (2, 1),
        5: (1, 2), 6: (1, 2), 7: (2, 1),
    }
    return (taken_operands if taken else not_taken_operands)[f3]


def branch_case_program(f3: int, taken: bool) -> list[int]:
    """One branch outcome with signed and unsigned edge-value operands."""
    rs1, rs2 = branch_operands(f3, taken)
    return [i(-1, 0, 0, 1), i(1, 0, 0, 2), b(8, rs2, rs1, f3),
            i(99, 0, 0, 3), j(0, 0)]


def backward_branch_program() -> list[int]:
    return [i(3, 0, 0, 1), i(-1, 1, 0, 1), b(-4, 0, 1, 1), j(0, 0)]


def jalr_odd_program() -> list[int]:
    return [i(17, 0, 0, 1), i(0, 1, 0, 2, 0x67),
            i(99, 0, 0, 3), i(99, 0, 0, 3),
            i(1, 2, 0, 4), j(0, 0)]


def backward_jal_program() -> list[int]:
    return [i(2, 0, 0, 1), i(-1, 1, 0, 1), b(8, 0, 1, 0),
            j(-8, 0), j(0, 0)]


def matrix_program() -> list[int]:
    words = []
    for index in range(16):
        words += [i(index + 1, 0, 0, 1), s(256 + 4 * index, 1, 0, 2),
                  i((index % 7) + 1, 0, 0, 1), s(512 + 4 * index, 1, 0, 2)]
    for row in range(4):
        for col in range(4):
            words.append(i(0, 0, 0, 3))
            for inner in range(4):
                words += [i(256 + 4 * (row * 4 + inner), 0, 2, 4, 0x03),
                          i(512 + 4 * (inner * 4 + col), 0, 2, 5, 0x03),
                          r(1, 5, 4, 0, 6), r(0, 6, 3, 0, 3)]
            words.append(s(768 + 4 * (row * 4 + col), 3, 0, 2))
    return words


def stride_program() -> list[int]:
    words = []
    for index in range(128):
        words += [i((index % 31) + 1, 0, 0, 1),
                  s(256 + 4 * index, 1, 0, 2)]
    words.append(i(0, 0, 0, 3))
    for index in range(0, 128, 2):
        words += [i(256 + 4 * index, 0, 2, 4, 0x03),
                  r(0, 4, 3, 0, 3)]
    words.append(s(800, 3, 0, 2))
    return words


def list_program() -> tuple[list[int], int]:
    words = []
    for index in range(64):
        next_addr = 512 + 8 * (index + 1) if index < 63 else 0
        words += [i(next_addr, 0, 0, 1), s(512 + 8 * index, 1, 0, 2),
                  i(index + 1, 0, 0, 1), s(516 + 8 * index, 1, 0, 2)]
    words += [i(512, 0, 0, 1), i(64, 0, 0, 2), i(0, 0, 0, 4),
              i(4, 1, 2, 3, 0x03), r(0, 3, 4, 0, 4),
              i(0, 1, 2, 1, 0x03), i(-1, 2, 0, 2), b(-16, 0, 2, 1),
              s(1024, 4, 0, 2)]
    return words, 256 + 3 + 5 * 64 + 1


def program(seed: int, blocks: int) -> tuple[list[int], int]:
    rng = random.Random(seed)
    words = [i(256, 0, 0, 31), i(1, 0, 0, 22)]
    # x31 is the data-memory base; x21=-1 and x22=1 are branch operands.
    retired = len(words)
    last_rd = 1
    for _ in range(blocks):
        kind = rng.randrange(7)
        rd = rng.randint(1, 20)
        rs1 = last_rd if rng.random() < 0.65 else rng.randint(0, 20)
        before = len(words)
        if kind == 0:
            f3, f7 = rng.choice([(0, 0), (0, 0x20), (1, 0), (2, 0),
                                  (3, 0), (4, 0), (5, 0), (5, 0x20),
                                  (6, 0), (7, 0)])
            words.append(r(f7, rng.randint(0, 20), rs1, f3, rd))
        elif kind == 1:
            f3 = rng.choice([0, 2, 3, 4, 6, 7])
            words.append(i(rng.randint(-64, 63), rs1, f3, rd))
        elif kind == 2:
            f3 = rng.choice([1, 5])
            shamt = rng.randrange(32)
            f7 = 0x20 if f3 == 5 and rng.choice([False, True]) else 0
            words.append(i((f7 << 5) | shamt, rs1, f3, rd))
        elif kind == 3:
            offset = 4 * rng.randrange(4)
            words.append(s(offset, rs1, 31, 2))
            words.append(i(offset, 31, 2, rd, 0x03))
            words.append(i(1, rd, 0, rd))  # Force a load-use dependency.
        elif kind == 4:
            store_f3 = rng.choice([0, 1])
            load_f3 = store_f3 + (4 if rng.choice([False, True]) else 0)
            offset = rng.randrange(16)
            if store_f3 == 1:
                offset &= ~1  # Halfword accesses must be aligned.
            words.append(s(offset, rs1, 31, store_f3))
            words.append(i(offset, 31, load_f3, rd, 0x03))
            words.append(i(1, rd, 0, rd))
        elif kind == 5:
            f3 = rng.choice([0, 1, 4, 5, 6, 7])
            taken = rng.choice([False, True])
            source1, source2 = branch_operands(f3, taken)
            source1 = 21 if source1 == 1 else 22
            source2 = 21 if source2 == 1 else 22
            words.append(i(-1, 0, 0, 21))  # Forward this value into the branch.
            words.append(b(8, source2, source1, f3))
            words.append(i(99, 0, 0, 30))  # Skipped only when taken.
            retired += 2 if taken else 3
            last_rd = 21
            continue
        else:
            words.append(r(1, rng.randint(0, 20), rs1, rng.randrange(8), rd))
        retired += len(words) - before
        last_rd = rd
    if len(words) > 1024:
        raise ValueError(f"seed {seed} produced {len(words)} instructions; ROM holds 1024")
    return words, retired


def run(cmd: list[str], *, input_text: str | None = None) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(cmd, cwd=ROOT, input=input_text, text=True,
                            capture_output=True, check=False)
    if result.returncode:
        raise RuntimeError(f"{' '.join(cmd)} failed:\n{result.stdout}\n{result.stderr}")
    return result


def coverage_from_trace(lines: list[str]) -> Counter[str]:
    bins: Counter[str] = Counter()
    prior_rd = 0
    prior_load = False
    prior_mnemonic = None
    register_ops = {(0, 0): "add", (0x20, 0): "sub", (0, 1): "sll",
                    (0, 2): "slt", (0, 3): "sltu", (0, 4): "xor",
                    (0, 5): "srl", (0x20, 5): "sra", (0, 6): "or",
                    (0, 7): "and", (1, 0): "mul", (1, 1): "mulh",
                    (1, 2): "mulhsu", (1, 3): "mulhu", (1, 4): "div",
                    (1, 5): "divu", (1, 6): "rem", (1, 7): "remu"}
    immediate_ops = {0: "addi", 2: "slti", 3: "sltiu", 4: "xori",
                     6: "ori", 7: "andi"}
    load_ops = {0: "lb", 1: "lh", 2: "lw", 4: "lbu", 5: "lhu"}
    store_ops = {0: "sb", 1: "sh", 2: "sw"}
    branch_ops = {0: "beq", 1: "bne", 4: "blt", 5: "bge",
                  6: "bltu", 7: "bgeu"}
    for index, line in enumerate(lines):
        _, pc_hex, instr_hex, rd_hex, *_ = line.split()
        pc, instr, rd = int(pc_hex, 16), int(instr_hex, 16), int(rd_hex, 16)
        opcode = instr & 0x7F
        funct3 = (instr >> 12) & 7
        funct7 = (instr >> 25) & 0x7F
        kind = {0x33: "register_alu", 0x13: "immediate_alu", 0x03: "load",
                0x23: "store", 0x63: "branch", 0x6F: "jal", 0x67: "jalr",
                0x37: "lui", 0x17: "auipc", 0x0F: "fence"}.get(opcode, "other")
        bins[kind] += 1
        mnemonic = None
        if opcode == 0x33:
            mnemonic = register_ops.get((funct7, funct3))
        elif opcode == 0x13:
            mnemonic = immediate_ops.get(funct3)
            if funct3 == 1:
                mnemonic = "slli"
            elif funct3 == 5:
                mnemonic = "srai" if funct7 == 0x20 else "srli"
        elif opcode == 0x03:
            mnemonic = load_ops.get(funct3)
        elif opcode == 0x23:
            mnemonic = store_ops.get(funct3)
        elif opcode == 0x63:
            mnemonic = branch_ops.get(funct3)
        else:
            mnemonic = {0x6F: "jal", 0x67: "jalr", 0x37: "lui",
                        0x17: "auipc", 0x0F: "fence"}.get(opcode)
        if mnemonic:
            bins[f"instr_{mnemonic}"] += 1
        rs1 = (instr >> 15) & 31
        rs2 = (instr >> 20) & 31
        uses1 = opcode in (0x33, 0x13, 0x03, 0x23, 0x63, 0x67)
        uses2 = opcode in (0x33, 0x23, 0x63)
        dependency = prior_rd and ((uses1 and rs1 == prior_rd) or
                                   (uses2 and rs2 == prior_rd))
        if dependency:
            bins["adjacent_dependency"] += 1
            if uses1 and rs1 == prior_rd:
                bins["adjacent_rs1_dependency"] += 1
            if uses2 and rs2 == prior_rd:
                bins["adjacent_rs2_dependency"] += 1
                if opcode == 0x23:
                    bins["store_after_producer"] += 1
            if prior_load:
                bins["load_use_pair"] += 1
                if prior_mnemonic:
                    bins[f"load_use_after_{prior_mnemonic}"] += 1
                bins[f"load_use_into_{kind}"] += 1
        if opcode == 0x63 and index + 1 < len(lines):
            next_pc = int(lines[index + 1].split()[1], 16)
            outcome = "taken" if next_pc != pc + 4 else "not_taken"
            bins[f"branch_{outcome}"] += 1
            if mnemonic:
                bins[f"branch_{mnemonic}_{outcome}"] += 1
            if dependency:
                bins[f"branch_after_producer_{outcome}"] += 1
        prior_rd = rd
        prior_load = opcode == 0x03
        prior_mnemonic = mnemonic
    return bins


def main() -> None:
    load_oss_cad()
    parser = argparse.ArgumentParser()
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--seeds", type=int, default=3)
    parser.add_argument("--blocks", type=int, default=100)
    parser.add_argument("--simulator", choices=("icarus", "verilator"), default="icarus")
    parser.add_argument("--output-dir", type=Path, default=ROOT / "build" / "regression")
    parser.add_argument("--memory-traces", type=Path)
    args = parser.parse_args()
    if args.memory_traces and args.simulator != "verilator":
        parser.error("--memory-traces requires --simulator verilator")
    if args.memory_traces:
        args.memory_traces = args.memory_traces.resolve()
        args.memory_traces.mkdir(parents=True, exist_ok=True)
    build = args.output_dir.resolve()
    build.mkdir(parents=True, exist_ok=True)
    if args.seeds < 0 or args.blocks < 1:
        parser.error("--seeds must be nonnegative and --blocks must be positive")
    rtl = sorted(str(p) for p in (ROOT / "rtl").glob("*.sv"))
    if args.simulator == "icarus":
        tool_dir = str(LOCAL_TOOLS) if (LOCAL_TOOLS / "iverilog").exists() else None
        env_path = os.pathsep.join(filter(None, [tool_dir, os.environ.get("PATH", "")]))
        iverilog = shutil.which("iverilog", path=env_path)
        vvp = shutil.which("vvp", path=env_path)
        if not iverilog or not vvp:
            raise SystemExit("Install Icarus Verilog, then rerun this script.")
        simulator = [vvp, str(build / "trace.vvp")]
        run([iverilog, "-g2012", "-gassertions", "-s", "trace_tb", "-o", simulator[1],
             *rtl, str(ROOT / "tests" / "trace_tb.sv")])
    else:
        verilator = shutil.which("verilator")
        if not verilator:
            raise SystemExit("Verilator is not installed. See the Verilator setup instructions in README.md.")
        model_dir = build / "verilator"
        run([verilator, "--binary", "--timing", "--assert", "-Wno-fatal",
             "--top-module", "trace_tb", "--Mdir", str(model_dir),
             *rtl, str(ROOT / "tests" / "trace_tb.sv")])
        simulator = [str(model_dir / "Vtrace_tb")]
    compiler = shutil.which("cc")
    if not compiler:
        raise SystemExit("A C compiler is required for the reference model.")
    run([compiler, "-std=c11", "-O2", "-Wall", "-Wextra", "-o", str(build / "ref_model"),
         str(ROOT / "verify" / "ref_model.c")])

    cases = [("directed", directed_program(), 12),
             ("instruction families", instruction_program(), 24),
             ("rv32m", m_program(), None)]
    for f3, mnemonic in [(0, "beq"), (1, "bne"), (4, "blt"),
                         (5, "bge"), (6, "bltu"), (7, "bgeu")]:
        for taken in (True, False):
            label = f"{mnemonic} {'taken' if taken else 'not taken'}"
            cases.append((label, branch_case_program(f3, taken), 4 if taken else 5))
    cases.extend([("backward bne", backward_branch_program(), 8),
                  ("odd-target jalr", jalr_odd_program(), 4),
                  ("backward jal", backward_jal_program(), 7)])
    cases += [(f"seed={seed}", words, count)
              for seed in range(args.seed, args.seed + args.seeds)
              for words, count in [program(seed, args.blocks)]]
    list_words, list_count = list_program()
    cases.extend([("matrix multiply", matrix_program(), None),
                  ("array sum strides", stride_program(), None),
                  ("linked list walk", list_words, list_count)])
    total = 0
    total_cycles = 0
    coverage: Counter[str] = Counter()
    for label, words, retire_count in cases:
        count = retire_count or len(words)
        program_path = build / "program.hex"
        program_path.write_text("".join(f"{word:08x}\n" for word in words))
        trace_name = label.replace(" ", "_").replace("=", "_")
        mem_path = args.memory_traces / f"{trace_name}.trace" if args.memory_traces else None
        sim_args = [*simulator, f"+program={program_path}", f"+max_retire={count}"]
        if mem_path:
            sim_args.append(f"+mem_trace={mem_path}")
        sim = run(sim_args)
        trace_lines = [line for line in sim.stdout.splitlines() if line.startswith("TRACE ")]
        traces = "\n".join(trace_lines) + "\n"
        check = run([str(build / "ref_model"), str(program_path), str(count)],
                    input_text=traces)
        cycle_count = 0
        for line in sim.stdout.splitlines():
            if line.startswith("COVERAGE "):
                for item in line.split()[1:]:
                    key, value = item.split("=")
                    coverage[key] += int(value)
                    if key == "cycles":
                        cycle_count = int(value)
        if label == "rv32m" and coverage["m_stalls"] == 0:
            raise RuntimeError("rv32m program retired without an M pipeline stall")
        print(f"{check.stdout.strip()} ({label}, {cycle_count / count:.3f} CPI)")
        total += count
        total_cycles += cycle_count
        if mem_path:
            (args.memory_traces / f"{trace_name}.json").write_text(
                json.dumps({"name": label, "instructions": count,
                            "base_cycles": cycle_count,
                            "base_cpi": cycle_count / count}, indent=2) + "\n")
        coverage.update(coverage_from_trace(trace_lines))
    coverage_path = build / "coverage.json"
    previous = json.loads(coverage_path.read_text()) if coverage_path.exists() else {}
    coverage_path.write_text(json.dumps(dict(sorted(coverage.items())), indent=2) + "\n")
    print("Coverage: " + ", ".join(f"{key}={value}" for key, value in sorted(coverage.items())))
    changes = {key: coverage[key] - previous.get(key, 0) for key in coverage
               if coverage[key] != previous.get(key, 0)}
    if changes:
        print("Coverage delta: " + ", ".join(f"{key}={value:+d}" for key, value in sorted(changes.items())))
    else:
        print("Coverage delta: no change")
    print(f"PASS regression: {len(cases)} programs, {total} retirements, "
          f"{total_cycles / total:.3f} aggregate CPI")


if __name__ == "__main__":
    main()
