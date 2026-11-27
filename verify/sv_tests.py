#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
from pathlib import Path
import shutil
import subprocess

from tool_env import load_oss_cad

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build" / "directed-verilator"
TESTS = (
    "smoke", "alu_imm", "muldiv", "muldiv_random", "instructions", "pipeline",
    "pipeline_forward", "pipeline_system", "misaligned_target", "csr_ops", "uart_tx",
    "cpu_uart", "demo_top",
)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--simulator", choices=("verilator",), default="verilator")
    args = parser.parse_args()
    load_oss_cad()
    verilator = shutil.which("verilator")
    if not verilator:
        raise SystemExit("Verilator is required")
    BUILD.mkdir(parents=True, exist_ok=True)
    subprocess.run(["python3", "software/build_hello.py"], cwd=ROOT, check=True)
    rtl = sorted(str(path) for path in (ROOT / "rtl").glob("*.sv"))
    for name in TESTS:
        top = f"{name}_tb"
        model_dir = BUILD / name
        build = subprocess.run(
            [verilator, "--binary", "--timing", "--assert", "-Wno-fatal",
             "--top-module", top, "--Mdir", str(model_dir),
             *rtl, str(ROOT / "tests" / f"{top}.sv")],
            cwd=ROOT, text=True, capture_output=True)
        if build.returncode:
            raise SystemExit(f"{top} build failed:\n{build.stdout}\n{build.stderr}")
        sim = subprocess.run([str(model_dir / f"V{top}")], cwd=ROOT,
                             text=True, capture_output=True)
        if sim.returncode or "PASS " not in sim.stdout:
            raise SystemExit(f"{top} failed:\n{sim.stdout}\n{sim.stderr}")
        print(next(line for line in sim.stdout.splitlines() if line.startswith("PASS ")))
    print(f"PASS directed Verilator suite: {len(TESTS)} testbenches")


if __name__ == "__main__":
    main()
