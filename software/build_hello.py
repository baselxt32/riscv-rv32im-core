#!/usr/bin/env python3
"""Build hello.hex without requiring a RISC-V cross-toolchain."""
from pathlib import Path


def addi(imm: int, rs1: int, rd: int) -> int:
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (rd << 7) | 0x13


def sb(rs2: int, rs1: int) -> int:
    return (rs2 << 20) | (rs1 << 15) | 0x23


words = [(0x10000 << 12) | (1 << 7) | 0x37]
for char in b"Hi\n":
    words.extend([addi(char, 0, 2), sb(2, 1)])
words.append(0x0000006F)  # jal x0, 0
output = Path(__file__).with_name("hello.hex")
output.write_text("".join(f"{word:08x}\n" for word in words))
print(f"Wrote {output} ({len(words)} instructions)")
