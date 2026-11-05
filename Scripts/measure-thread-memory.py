#!/usr/bin/env python3
"""Measure ask's resident memory with several threads at work (roadmaps 0194, 0195: the measure `threads.max` owes).

ASK_PYTE=/tmp/ask-pty/lib Scripts/measure-thread-memory.py .build/release/ask [THREADS]

Starts the real binary on a PTY against a local fake provider, then one thread at a time (each running a quiet `sleep`, so it stays
at work), up to THREADS (8 by default; `threads.max` is raised to allow it). After each, once the thread's job is listed and memory has
settled, it reads the process's resident size. Prints one line per count, then the first thread's cost (paid once) and each further one's. Hermetic.
"""
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
spec = importlib.util.spec_from_file_location("fold_probe", os.path.join(HERE, "probe-folding.py"))
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


def resident_kib(pid):
    return int(subprocess.run(["ps", "-o", "rss=", "-p", str(pid)], capture_output=True, text=True).stdout.strip())


def settled(pid, seconds=3.0):
    """The resident size once two readings a second apart differ by under 1%, or after `seconds`."""
    last = resident_kib(pid)
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        time.sleep(1)
        now = resident_kib(pid)
        if abs(now - last) < last * 0.01:
            return now
        last = now
    return last


def main():
    count = int(sys.argv[2]) if len(sys.argv) > 2 else 8
    with tempfile.TemporaryDirectory() as root:
        project, config, state = root + "/project", root + "/config", root + "/state"
        os.makedirs(project)
        os.makedirs(config + "/ask")
        with open(config + "/ask/config.json", "w") as file:
            json.dump({"ui": {"inputPrefix": "ask> "}, "threads": {"names": "numbered", "max": 16}}, file)
        turn = probe.agent.turn
        server = probe.agent.Server(
            [turn([("text", "MAIN ONE")], "end_turn")]
            + [turn([("tool", f"c{i}", "sleep 300")], "tool_use") for i in range(count)]
        )
        environment = probe.agent.environment(state, server.url, config=config)
        environment.update(TERM="xterm-256color", TERM_PROGRAM="ghostty")
        for key in ("SSH_TTY", "SSH_CONNECTION", "TMUX", "KITTY_WINDOW_ID"):
            environment.pop(key, None)
        terminal = probe.Terminal(project, environment, rows=40)
        try:
            terminal.until(lambda: "ask>" in terminal.text())
            terminal.send(b"hello\r")
            terminal.until(lambda: "MAIN ONE" in terminal.text())
            readings = [settled(terminal.pid)]
            print(f"threads 0: {readings[0] / 1024:.1f} MiB")
            for n in range(1, count + 1):
                terminal.send(f"/thread task {n}\r".encode())
                terminal.until(lambda: len(server.requests) >= n + 1 and f"{n} job" in terminal.text().replace("jobs", "job"))
                readings.append(settled(terminal.pid))
                print(f"threads {n}: {readings[-1] / 1024:.1f} MiB")
            first = (readings[1] - readings[0]) / 1024
            more = (readings[-1] - readings[1]) / max(count - 1, 1) / 1024
            print(f"the first thread: {first:.2f} MiB (once: the machinery threads share); each one more: {more:.2f} MiB; "
                  f"{readings[-1] / 1024:.1f} MiB in all with {count}")
        finally:
            terminal.close()
            server.httpd.shutdown()


if __name__ == "__main__":
    main()
