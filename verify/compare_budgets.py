#!/usr/bin/env python3
"""Measure three deterministic verification budgets against the same RTL."""
from __future__ import annotations

import json
from pathlib import Path
import re
import subprocess
import sys
from time import perf_counter

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "build" / "budget-comparison"
BUDGETS = (("fast", 0, 100), ("normal", 3, 100), ("extended", 10, 400))
SUMMARY = re.compile(r"PASS regression: (\d+) programs, (\d+) retirements, ([\d.]+) aggregate CPI")


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    results = []
    for name, seeds, blocks in BUDGETS:
        directory = OUTPUT / name
        command = [sys.executable, "verify/regress.py", "--seed", "1",
                   "--seeds", str(seeds), "--blocks", str(blocks),
                   "--output-dir", str(directory)]
        start = perf_counter()
        result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True)
        elapsed = perf_counter() - start
        if result.returncode:
            sys.stderr.write(result.stdout + result.stderr)
            raise SystemExit(f"{name} budget failed in {elapsed:.2f}s")
        match = SUMMARY.search(result.stdout)
        if not match:
            raise SystemExit(f"{name} budget produced no summary:\n{result.stdout}")
        coverage = json.loads((directory / "coverage.json").read_text())
        results.append({"budget": name, "seeds": seeds, "blocks_per_seed": blocks,
                        "seconds": round(elapsed, 3), "programs": int(match[1]),
                        "retirements": int(match[2]), "cpi": float(match[3]),
                        "covered_bins": sorted(k for k, v in coverage.items() if v > 0),
                        "coverage": coverage})
    (OUTPUT / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    print("budget    seconds  programs  retired  bins  stalls  flushes")
    for row in results:
        coverage = row["coverage"]
        print(f"{row['budget']:<9} {row['seconds']:>7.2f} {row['programs']:>9} "
              f"{row['retirements']:>8} {len(row['covered_bins']):>5} "
              f"{coverage.get('stalls', 0):>7} {coverage.get('flushes', 0):>8}")
    for earlier, later in zip(results, results[1:]):
        added = sorted(set(later["covered_bins"]) - set(earlier["covered_bins"]))
        print(f"{later['budget']} added bins: {', '.join(added) if added else 'none'}")
    print(f"Detailed counts: {OUTPUT / 'results.json'}")


if __name__ == "__main__":
    main()
