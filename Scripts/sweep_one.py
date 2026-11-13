#!/usr/bin/env python3
"""One probe of the PTY sweep (roadmap 0211): runs PROBE against BINARY within LIMIT seconds, in a process group of its own so a
timeout kills the ask it started too; its output goes to OUT/logs/NAME.log and one line to OUT/summary.txt: PASS, FAIL, TIME, or SKIP
when Scripts/sweep-skip.txt lists it (with why).

Scripts/sweep_one.py OUT BINARY LIMIT PROBE
"""
import os
import signal
import subprocess
import sys
import time
from pathlib import Path


def skip_reason(name):
    path = Path("Scripts/sweep-skip.txt")
    if not path.exists():
        return None
    for line in path.read_text().splitlines():
        parts = line.split(maxsplit=1)
        if parts and not line.startswith("#") and parts[0] == name:
            return parts[1] if len(parts) > 1 else "listed"
    return None


def main():
    out, binary, limit, probe = Path(sys.argv[1]), sys.argv[2], int(sys.argv[3]), sys.argv[4]
    name = Path(probe).stem
    reason = skip_reason(name)
    if reason:
        line = f"SKIP    - {name}: {reason}"
    else:
        start = time.time()
        with open(out / "logs" / f"{name}.log", "wb") as log:
            process = subprocess.Popen(
                [sys.executable, probe, binary], stdout=log, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL, start_new_session=True
            )
            try:
                status = process.wait(timeout=limit)
                verdict = "PASS" if status == 0 else "FAIL"
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
                status, verdict = "timeout", "TIME"
        line = f"{verdict} {int(time.time() - start):4d} {name} (exit {status})"
    with open(out / "summary.txt", "a") as summary:
        summary.write(line + "\n")


if __name__ == "__main__":
    main()
