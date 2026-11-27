from __future__ import annotations

import os
from pathlib import Path
import subprocess


def load_oss_cad() -> None:
    script = Path.home() / "oss-cad-suite" / "environment"
    if not script.is_file():
        return
    result = subprocess.run(
        ["bash", "-c", 'source "$1" >/dev/null && env -0', "bash", str(script)],
        capture_output=True, check=True)
    for entry in result.stdout.split(b"\0"):
        if b"=" in entry:
            name, value = entry.split(b"=", 1)
            os.environ[os.fsdecode(name)] = os.fsdecode(value)
