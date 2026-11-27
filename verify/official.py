#!/usr/bin/env python3
"""Run precompiled rv32ui-p and rv32um-p riscv-tests ELFs."""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tarfile
import urllib.request

from tool_env import load_oss_cad

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build" / "official"
TESTS = BUILD / "tests"
URL = "https://github.com/riscv-software-src/sail-riscv-tests/releases/download/2026-08-20/riscv-tests.tar.gz"
SHA256 = "eb24265e83ca0b68a24a513dff7e4535975e724fe07d71f3cf75fef87fd75bec"
BASE = 0x80000000
IMEM_BYTES = 8192
DMEM_BYTES = 16384
LOCAL_TOOLS = ROOT.parents[1] / "work" / "iverilog-install" / "bin"


def get_tests() -> None:
    TESTS.mkdir(parents=True, exist_ok=True)
    archive = BUILD / "riscv-tests.tar.gz"
    if not archive.exists():
        print("Downloading pinned riscv-tests binaries...")
        with urllib.request.urlopen(URL, timeout=60) as response:
            archive.write_bytes(response.read())
    data = archive.read_bytes()
    if hashlib.sha256(data).hexdigest() != SHA256:
        raise SystemExit("riscv-tests archive checksum mismatch")
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as tar:
        for member in tar:
            name = Path(member.name).name
            if not member.isfile() or not name.startswith(("rv32ui-p-", "rv32um-p-")):
                continue
            source = tar.extractfile(member)
            if source is None:
                raise ValueError(f"missing archive member {name}")
            (TESTS / name).write_bytes(source.read())


def load_elf(path: Path) -> tuple[bytearray, bytearray, int]:
    data = path.read_bytes()
    if data[:6] != b"\x7fELF\x01\x01" or struct.unpack_from("<H", data, 18)[0] != 243:
        raise ValueError(f"{path.name} is not a little-endian RV32 ELF")
    phoff = struct.unpack_from("<I", data, 28)[0]
    phentsize, phnum = struct.unpack_from("<HH", data, 42)
    imem = bytearray(b"\x13\x00\x00\x00" * (IMEM_BYTES // 4))
    dmem = bytearray(DMEM_BYTES)
    for index in range(phnum):
        kind, offset, vaddr, _, size, memsize, _, _ = struct.unpack_from(
            "<IIIIIIII", data, phoff + index * phentsize)
        if kind != 1:
            continue
        start = vaddr - BASE
        if start < 0 or start + memsize > DMEM_BYTES or offset + size > len(data):
            raise ValueError(f"{path.name} has a segment outside the test memory")
        dmem[start:start + size] = data[offset:offset + size]
        if start < IMEM_BYTES:
            copied = min(size, IMEM_BYTES - start)
            imem[start:start + copied] = data[offset:offset + copied]

    shoff = struct.unpack_from("<I", data, 32)[0]
    shentsize, shnum = struct.unpack_from("<HH", data, 46)
    sections = [struct.unpack_from("<IIIIIIIIII", data, shoff + i * shentsize)
                for i in range(shnum)]
    tohost = None
    for section in sections:
        _, kind, _, _, offset, size, link, _, _, entsize = section
        if kind != 2 or entsize == 0:
            continue
        strings = sections[link]
        table = data[strings[4]:strings[4] + strings[5]]
        for pos in range(offset, offset + size, entsize):
            name_offset, value, _, _, _, _ = struct.unpack_from("<IIIBBH", data, pos)
            name = table[name_offset:].split(b"\x00", 1)[0]
            if name == b"tohost":
                tohost = value
                break
    if tohost is None:
        raise ValueError(f"{path.name} has no tohost symbol")
    return imem, dmem, tohost


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--suite", choices=("all", "rv32ui", "rv32um"), default="all")
    parser.add_argument("--test", help="run one exact test name")
    parser.add_argument("--simulator", choices=("icarus", "verilator"), default="icarus")
    args = parser.parse_args()
    load_oss_cad()
    get_tests()
    path = os.pathsep.join((str(LOCAL_TOOLS), os.environ.get("PATH", "")))
    iverilog = shutil.which("iverilog", path=path)
    vvp = shutil.which("vvp", path=path)
    rtl = sorted(str(path) for path in (ROOT / "rtl").glob("*.sv"))
    if args.simulator == "icarus":
        if not iverilog or not vvp:
            raise SystemExit("Icarus Verilog is required for the official-test runner")
        binary = BUILD / "official.vvp"
        command = [iverilog, "-g2012", "-gassertions", "-s", "official_tb",
                   "-o", str(binary), *rtl, str(ROOT / "tests" / "official_tb.sv")]
        simulator = [vvp, str(binary)]
    else:
        verilator = shutil.which("verilator")
        if not verilator:
            raise SystemExit("Verilator is required for the official-test runner")
        model_dir = BUILD / "verilator"
        command = [verilator, "--binary", "--timing", "--assert", "-Wno-fatal",
                   "--top-module", "official_tb", "--Mdir", str(model_dir),
                   *rtl, str(ROOT / "tests" / "official_tb.sv")]
        simulator = [str(model_dir / "Vofficial_tb")]
    compile_result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True)
    if compile_result.returncode:
        raise SystemExit(compile_result.stderr)

    names = sorted(path.name for path in TESTS.iterdir() if path.is_file())
    names = [name for name in names if
             (args.suite == "all" or name.startswith(args.suite + "-")) and
             (args.test is None or name == args.test)]
    if not names:
        raise SystemExit("No matching official tests")
    results = []
    for name in names:
        if name == "rv32ui-p-fence_i":
            results.append({"test": name, "status": "SKIP", "reason": "Zifencei is outside RV32IM"})
            print(f"SKIP {name}: Zifencei is outside RV32IM")
            continue
        try:
            imem, dmem, tohost = load_elf(TESTS / name)
            imem_path = BUILD / "imem.hex"
            dmem_path = BUILD / "dmem.hex"
            imem_path.write_text("".join(
                f"{struct.unpack_from('<I', imem, pos)[0]:08x}\n"
                for pos in range(0, IMEM_BYTES, 4)))
            dmem_path.write_text("".join(f"{byte:02x}\n" for byte in dmem))
            sim = subprocess.run(
                [*simulator, f"+imem={imem_path}", f"+dmem={dmem_path}",
                 f"+tohost={tohost:08x}"],
                cwd=ROOT, text=True, capture_output=True, timeout=30)
            passed = sim.returncode == 0 and "OFFICIAL PASS" in sim.stdout
            if passed:
                detail = next(line for line in sim.stdout.splitlines()
                              if line.startswith("OFFICIAL PASS"))
                results.append({"test": name, "status": "PASS", "detail": detail})
                print(f"PASS {name}: {detail}")
            else:
                lines = (sim.stdout + sim.stderr).splitlines()
                detail = next((line for line in reversed(lines) if "FATAL" in line),
                              lines[-1] if lines else "simulation failed")
                results.append({"test": name, "status": "FAIL", "detail": detail})
                print(f"FAIL {name}: {detail}")
        except (ValueError, subprocess.TimeoutExpired) as error:
            results.append({"test": name, "status": "FAIL", "detail": str(error)})
            print(f"FAIL {name}: {error}")
    (BUILD / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    passed = sum(row["status"] == "PASS" for row in results)
    failed = sum(row["status"] == "FAIL" for row in results)
    skipped = sum(row["status"] == "SKIP" for row in results)
    print(f"Official tests: {passed} pass, {failed} fail, {skipped} skip")
    print(f"Report: {BUILD / 'results.json'}")
    if failed:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
