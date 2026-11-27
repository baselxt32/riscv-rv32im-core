#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_FORMAL = ROOT.parents[1] / "work" / "riscv-formal"
BUILD = ROOT / "build" / "formal"
M_CHECKS = ("mul", "mulh", "mulhsu", "mulhu", "div", "divu", "rem", "remu")


def main() -> None:
    parser = argparse.ArgumentParser()
    upstream = Path(os.environ.get("RISCV_FORMAL_DIR", DEFAULT_FORMAL)).resolve()
    insn_file = upstream / "insns" / "isa_rv32im.txt"
    if not insn_file.is_file():
        raise SystemExit(f"Clone https://github.com/YosysHQ/riscv-formal to {upstream} or set RISCV_FORMAL_DIR")
    insn_checks = tuple(line.strip() for line in insn_file.read_text().splitlines()
                        if line.strip() and not line.startswith("#"))
    parser.add_argument("--check", choices=("all", *insn_checks, "reg"), default="all")
    args = parser.parse_args()
    script = Path.home() / "oss-cad-suite" / "environment"
    if script.is_file():
        result = subprocess.run(
            ["bash", "-c", 'source "$1" >/dev/null && env -0', "bash", str(script)],
            capture_output=True, check=True)
        for entry in result.stdout.split(b"\0"):
            if b"=" in entry:
                name, value = entry.split(b"=", 1)
                os.environ[os.fsdecode(name)] = os.fsdecode(value)
    sby = shutil.which("sby")
    if not sby:
        raise SystemExit("SymbiYosys (sby) is required")
    macros = upstream / "checks" / "rvfi_macros.vh"
    if not macros.is_file():
        raise SystemExit(f"Clone https://github.com/YosysHQ/riscv-formal to {upstream} or set RISCV_FORMAL_DIR")
    BUILD.mkdir(parents=True, exist_ok=True)
    checks = (*insn_checks, "reg") if args.check == "all" else (args.check,)
    rtl = sorted((ROOT / "rtl").glob("*.sv"))
    results = []
    for check in checks:
        sources = [ROOT / "formal" / "check_top.sv", ROOT / "formal" / "wrapper.sv",
                   upstream / "checks" / f"rvfi_{'reg' if check == 'reg' else 'insn'}_check.sv",
                   *rtl]
        if check != "reg":
            sources.append(upstream / "insns" / f"insn_{check}.v")
        defines = ["-D", "RISCV_FORMAL", "-D", "RISCV_FORMAL_ALTOPS",
                   "-D", "RISCV_FORMAL_NRET=1",
                   "-D", "RISCV_FORMAL_XLEN=32", "-D", "RISCV_FORMAL_ILEN=32",
                   "-D", "RISCV_FORMAL_CHANNEL_IDX=0"]
        if check != "reg":
            defines += ["-D", f"RISCV_FORMAL_INSN_MODEL=rvfi_insn_{check}"]
        else:
            defines += ["-D", "FORMAL_REG_CHECK"]
        read = "read -sv " + " ".join(defines) + f" -I{upstream / 'checks'} " + \
               " ".join(str(path) for path in sources)
        depth = 15
        config = f"""[options]
mode bmc
depth {depth}

[engines]
smtbmc boolector

[script]
{read}
prep -flatten -top rvfi_testbench
chformal -early

[files]
{chr(10).join(str(path) for path in [macros, *sources])}
"""
        job = BUILD / f"{check}.sby"
        job.write_text(config)
        timeout = 120
        process = subprocess.Popen([sby, "-f", str(job)], cwd=ROOT, text=True,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   start_new_session=True)
        try:
            stdout, stderr = process.communicate(timeout=timeout)
            output = stdout + stderr
            status = "PASS" if process.returncode == 0 else \
                     "FAIL" if "DONE (FAIL" in output else "ERROR"
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            stdout, stderr = process.communicate()
            output = stdout + stderr
            status = "TIMEOUT"
        log = BUILD / f"{check}.log"
        log.write_text(output)
        detail = next((line.strip() for line in output.splitlines()
                       if "failed assertion" in line), "")
        results.append({"check": check, "status": status,
                        "model": "ALTOPS" if check in M_CHECKS else "ISA",
                        "detail": detail,
                        "log": str(log)})
        print(f"{check}: {status}" + (f" ({detail})" if detail else ""), flush=True)
        (BUILD / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    counts = {status: sum(row["status"] == status for row in results)
              for status in ("PASS", "FAIL", "ERROR", "TIMEOUT")}
    report = ["# RV32IM formal results", "",
              "SymbiYosys bounded model checks using riscv-formal instruction and register checkers.",
              "Depth 15 and a 120-second timeout per check.",
              "M instruction checks use RISCV_FORMAL_ALTOPS in both the core and the instruction model.",
              "ALTOPS checks pipeline and register behavior, not real arithmetic; the separate random M test checks arithmetic.",
              "A timeout is unproven, not a passing or failing assertion.", "",
              "| Check | Result | Model |", "| --- | --- | --- |"]
    report += [f"| `{row['check']}` | {row['status']} | {row['model']} |" for row in results]
    report += ["", "Logs and counterexamples are in `build/formal/<check>/`.", ""]
    (BUILD / "results.md").write_text("\n".join(report))
    if args.check == "all":
        (ROOT / "formal" / "results.md").write_text("\n".join(report))
    print("Formal: " + ", ".join(f"{count} {status.lower()}" for status, count in counts.items()))
    if counts["FAIL"] or counts["ERROR"] or counts["TIMEOUT"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
