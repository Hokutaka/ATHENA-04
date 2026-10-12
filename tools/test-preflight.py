#!/usr/bin/env python3
"""Regression test: the preflight scanner must detect tracked ignored secrets.

Only dummy names and dummy content are used. Requires git and Python 3.
"""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

source = Path(__file__).with_name("preflight-public.py")
with tempfile.TemporaryDirectory(prefix="athena-preflight-") as tmp:
    root = Path(tmp)
    (root / "tools").mkdir()
    shutil.copy2(source, root / "tools" / "preflight-public.py")
    subprocess.run(["git", "init", "-q", str(root)], check=True)

    # An .ssh directory should be ignored by the walk but caught via the Git index.
    (root / ".gitignore").write_text(".ssh/\n", encoding="utf-8")
    (root / ".ssh").mkdir()
    (root / ".ssh" / "id_ed25519").write_text(
        "DUMMY CONTENT ONLY - NOT AN SSH KEY\n", encoding="utf-8"
    )
    subprocess.run(
        ["git", "-C", str(root), "add", "-f", ".ssh/id_ed25519"], check=True
    )
    scan = subprocess.run(
        [sys.executable, str(root / "tools" / "preflight-public.py")],
        cwd=root, capture_output=True, text=True, check=False,
    )
    if scan.returncode != 1 or "sensitive runtime/environment file is tracked" not in scan.stdout:
        raise SystemExit(
            f"FAIL: tracked ignored dummy SSH key name was not flagged\n"
            f"exit={scan.returncode}\nstdout={scan.stdout}\nstderr={scan.stderr}"
        )
    # Once removed from the Git index, the dummy file should not trigger a warning.
    subprocess.run(
        ["git", "-C", str(root), "rm", "-q", "--cached", ".ssh/id_ed25519"],
        check=True,
    )
    rescanned = subprocess.run(
        [sys.executable, str(root / "tools" / "preflight-public.py")],
        cwd=root, capture_output=True, text=True, check=False,
    )
    if rescanned.returncode != 0:
        raise SystemExit(
            f"FAIL: clean index was not accepted\n"
            f"stdout={rescanned.stdout}\nstderr={rescanned.stderr}"
        )
print("PASS: preflight detects tracked ignored SSH file names.")
